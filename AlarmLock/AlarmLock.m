// AlarmLock: an add-on for the owner's own copy of Alarmy. While the lock is on, the Alarms tab is
// covered, so alarms can't be turned off, deleted or changed, and Alarmy's emergency escape is
// hidden. Three sums open it for 10 minutes, except in the chosen hours before the next alarm.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <time.h>
#import "LockRules.h"

#define ALLog(fmt, ...) NSLog(@"[AlarmLock] " fmt, ##__VA_ARGS__)

#pragma mark - Settings

static NSString *const ALKeyOn = @"AlarmLock.on";
static NSString *const ALKeyHours = @"AlarmLock.hoursBefore";
static NSString *const ALKeyUntil = @"AlarmLock.unlockedUntil";
static NSString *const ALKeyUntilBoot = @"AlarmLock.unlockedBoot";
static NSString *const ALKeyAnchor = @"AlarmLock.clockAnchor";
/// When an alarm last finished: it rang and its missions were done.
static NSString *const ALKeyDoneAt = @"AlarmLock.alarmDoneAt";

static NSUserDefaults *ALDefaults(void) { return NSUserDefaults.standardUserDefaults; }
static BOOL ALLockOn(void) { return [ALDefaults() boolForKey:ALKeyOn]; }

static NSInteger ALHours(void) {
    id value = [ALDefaults() objectForKey:ALKeyHours];
    return [value isKindOfClass:NSNumber.class] ? [value integerValue] : 3;
}

#pragma mark - Clock

static double ALMonotonic(void) { return (double)clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1e9; }

/// Changes on every restart and, unlike the boot time, doesn't move when the clock is set by hand.
static NSString *ALBootID(void) {
    static NSString *cached;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        size_t size = 0;
        if (sysctlbyname("kern.bootsessionuuid", NULL, &size, NULL, 0) != 0 || size == 0) return;
        char *buffer = calloc(size + 1, 1);
        if (buffer && sysctlbyname("kern.bootsessionuuid", buffer, &size, NULL, 0) == 0) {
            cached = [NSString stringWithUTF8String:buffer];
        }
        free(buffer);
    });
    return cached;
}

static NSDate *ALNow(void) {
    NSDate *wall = [NSDate date];
    double mono = ALMonotonic();
    NSString *boot = ALBootID();
    NSDictionary *anchor = [ALDefaults() dictionaryForKey:ALKeyAnchor];
    NSDate *now = ALTrustedNow(wall, mono, boot, anchor);
    NSDictionary *fresh = ALRefreshedAnchor(anchor, wall, mono, boot);
    if (fresh != anchor) [ALDefaults() setObject:fresh forKey:ALKeyAnchor];
    return now;
}

static NSString *ALTime(NSDate *date) {
    static NSDateFormatter *formatter;
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.dateStyle = NSDateFormatterNoStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
    }
    return [formatter stringFromDate:date];
}

#pragma mark - Unlocking

static NSDate *ALUnlockedUntil(void) {
    id value = [ALDefaults() objectForKey:ALKeyUntil];
    return [value isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[value doubleValue]] : nil;
}

static BOOL ALUnlockedAt(NSDate *now) {
    return ALIsUnlocked(ALUnlockedUntil(), [ALDefaults() stringForKey:ALKeyUntilBoot], ALBootID(), now);
}

static void ALGrantUnlock(NSDate *now) {
    [ALDefaults() setObject:@(now.timeIntervalSince1970 + ALUnlockSeconds) forKey:ALKeyUntil];
    [ALDefaults() setObject:(ALBootID() ?: @"") forKey:ALKeyUntilBoot];
    ALLog(@"unlocked for %d min", (int)(ALUnlockSeconds / 60));
}

static void ALRelock(void) {
    [ALDefaults() removeObjectForKey:ALKeyDoneAt];
    [ALDefaults() removeObjectForKey:ALKeyUntil];
    [ALDefaults() removeObjectForKey:ALKeyUntilBoot];
}

#pragma mark - Reading Alarmy's alarms

// Alarmy keeps its alarms in a Realm database. The add-on remembers the settings Alarmy opens it
// with, and opens it the same way to read when the next alarm is due. Nothing is ever written.
@protocol ALRealmLike <NSObject>
- (id)schema;
- (id)configuration;
- (id)allObjects:(NSString *)className;
@end
@protocol ALSchemaLike <NSObject>
- (nullable id)schemaForClassName:(NSString *)className;
@end
@protocol ALResultsLike <NSObject>
- (NSUInteger)count;
- (id)objectAtIndex:(NSUInteger)index;
@end
@protocol ALRealmClassLike <NSObject>
+ (nullable id)realmWithConfiguration:(id)configuration error:(NSError *__autoreleasing *)error;
@end
@protocol ALConfigLike <NSObject>
- (nullable NSURL *)fileURL;
@end

static NSString *const ALAlarmClassName = @"AlarmEntity";
/// Every database file Alarmy has opened whose layout includes alarms, by path. An app can keep
/// several files that all know the alarm layout, so all of them are read and combined.
static NSMutableDictionary<NSString *, id> *ALAlarmConfigs;
static NSObject *ALConfigLock;
static const NSUInteger ALMaxConfigs = 8;

static void ALNoteRealm(id realm) {
    if (!realm) return;
    @try {
        id config = [(id<ALRealmLike>)realm configuration];
        NSString *path = [(id<ALConfigLike>)config fileURL].path;
        if (path.length == 0) return; // in memory only, gone when closed
        @synchronized (ALConfigLock) {
            if (ALAlarmConfigs[path] || ALAlarmConfigs.count >= ALMaxConfigs) return;
        }
        id<ALSchemaLike> schema = [(id<ALRealmLike>)realm schema];
        if (![schema schemaForClassName:ALAlarmClassName]) return;
        @synchronized (ALConfigLock) {
            if (!ALAlarmConfigs[path] && ALAlarmConfigs.count < ALMaxConfigs) {
                ALAlarmConfigs[path] = [config copy];
                ALLog(@"found a database with alarms: %@", path.lastPathComponent);
            }
        }
    } @catch (NSException *e) {
        ALLog(@"couldn't look at a database: %@", e.reason);
    }
}

typedef id (*ALOpenTwoFn)(id, SEL, id, id, NSError *__autoreleasing *);
typedef id (*ALOpenOneFn)(id, SEL, id, NSError *__autoreleasing *);
typedef void (*ALVoidFn)(id, SEL);
typedef void (*ALBoolFn)(id, SEL, BOOL);
typedef UIView *(*ALHitTestFn)(id, SEL, CGPoint, UIEvent *);

static ALOpenTwoFn ALOrigOpenQueue;
static id ALOpenQueue(id cls, SEL sel, id config, id queue, NSError *__autoreleasing *error) {
    id realm = ALOrigOpenQueue(cls, sel, config, queue, error);
    ALNoteRealm(realm);
    return realm;
}

static ALOpenTwoFn ALOrigOpenConfined;
static id ALOpenConfined(id cls, SEL sel, id config, id actor, NSError *__autoreleasing *error) {
    id realm = ALOrigOpenConfined(cls, sel, config, actor, error);
    ALNoteRealm(realm);
    return realm;
}

static ALOpenOneFn ALOrigOpen;
static id ALOpen(id cls, SEL sel, id config, NSError *__autoreleasing *error) {
    id realm = ALOrigOpen(cls, sel, config, error);
    ALNoteRealm(realm);
    return realm;
}

static NSString *ALReadProblem;
/// What the last read found, shown on the cover so a screenshot says whether reading works.
static NSString *ALReadSummary;

/// The alarms in one database file. Nil when it can't be read; `problem` then says why.
static NSArray<ALAlarmRecord *> *ALReadAlarmsIn(Class realmClass, id config, NSString **problem) {
    @try {
        NSError *error = nil;
        id realm = [(Class<ALRealmClassLike>)realmClass realmWithConfiguration:config error:&error];
        if (!realm) {
            *problem = [NSString stringWithFormat:@"Couldn't open Alarmy's alarms (%@).", error.localizedDescription ?: @"no reason given"];
            return nil;
        }
        id<ALResultsLike> results = [(id<ALRealmLike>)realm allObjects:ALAlarmClassName];
        NSMutableArray<ALAlarmRecord *> *alarms = [NSMutableArray array];
        NSUInteger count = results.count;
        for (NSUInteger i = 0; i < count; i++) {
            id object = [results objectAtIndex:i];
            id next = [object valueForKey:@"nextFireDate"];
            [alarms addObject:[ALAlarmRecord enabled:[[object valueForKey:@"enabled"] boolValue]
                                                next:([next isKindOfClass:NSDate.class] ? next : nil)
                                                hour:[[object valueForKey:@"hour"] integerValue]
                                              minute:[[object valueForKey:@"minute"] integerValue]]];
        }
        return alarms;
    } @catch (NSException *e) {
        *problem = [NSString stringWithFormat:@"Couldn't read Alarmy's alarms (%@).", e.reason ?: e.name];
        return nil;
    }
}

/// Every alarm in every database file that has them. Nil when none could be read; ALReadProblem
/// then says why.
static NSArray<ALAlarmRecord *> *ALReadAlarms(void) {
    NSArray *configs;
    @synchronized (ALConfigLock) { configs = ALAlarmConfigs.allValues; }
    Class realmClass = NSClassFromString(@"RLMRealm");
    if (!realmClass) { ALReadProblem = @"Alarmy's database library isn't there."; return nil; }
    if (configs.count == 0) { ALReadProblem = @"Alarmy hasn't opened its alarms yet."; return nil; }

    NSMutableArray<ALAlarmRecord *> *all = [NSMutableArray array];
    NSString *problem = nil;
    NSUInteger readable = 0;
    for (id config in configs) {
        NSArray<ALAlarmRecord *> *alarms = ALReadAlarmsIn(realmClass, config, &problem);
        if (!alarms) continue;
        readable += 1;
        [all addObjectsFromArray:alarms];
    }
    if (readable == 0) { ALReadProblem = problem; return nil; }
    NSUInteger on = 0;
    for (ALAlarmRecord *alarm in all) if (alarm.enabled) on += 1;
    ALReadSummary = [NSString stringWithFormat:@"Read %lu alarm%@ (%lu on) from %lu file%@.",
                     (unsigned long)all.count, all.count == 1 ? @"" : @"s", (unsigned long)on,
                     (unsigned long)readable, readable == 1 ? @"" : @"s"];
    ALReadProblem = on == 0 ? @"No alarms that are on were found." : nil;
    return all;
}

static NSDate *ALCachedNext;
static NSDate *ALCachedAt;

/// The next alarm, read again at most every 15 seconds.
static NSDate *ALNextAlarmAt(NSDate *now, BOOL fresh) {
    if (!fresh && ALCachedAt && fabs([now timeIntervalSinceDate:ALCachedAt]) < 15) return ALCachedNext;
    NSArray<ALAlarmRecord *> *alarms = ALReadAlarms();
    ALCachedNext = alarms ? ALNextAlarm(alarms, now, NSCalendar.currentCalendar) : nil;
    ALCachedAt = now;
    return ALCachedNext;
}

static NSDate *ALDoneAt(void) {
    id value = [ALDefaults() objectForKey:ALKeyDoneAt];
    return [value isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[value doubleValue]] : nil;
}

/// Until when the lock is open, by sums or because the last alarm was finished. Nil when it is not.
static NSDate *ALOpenUntil(NSDate *now, NSDate *next) {
    NSDate *bySums = ALUnlockedAt(now) ? ALUnlockedUntil() : nil;
    NSDate *byAlarm = ALOpenAfterAlarmUntil(ALDoneAt(), ALHours(), next, now);
    if (bySums && byAlarm) return [bySums laterDate:byAlarm];
    return bySums ?: byAlarm;
}

static ALLockState ALStateAt(NSDate *now, BOOL fresh) {
    NSDate *next = ALNextAlarmAt(now, fresh);
    return ALLockStateAt(ALLockOn(), ALHours(), next, ALOpenUntil(now, next) != nil, now);
}

static NSString *ALHoursText(NSInteger hours) {
    if (hours <= 0) return @"never";
    return hours == 1 ? @"1 hour before an alarm" : [NSString stringWithFormat:@"%ld hours before an alarm", (long)hours];
}

#pragma mark - Sums

@interface ALSumsViewController : UIViewController <UITextFieldDelegate>
@property (nonatomic, copy) void (^onDone)(BOOL solved);
@end

@implementation ALSumsViewController {
    ALSum _sum;
    NSInteger _done;
    UILabel *_position;
    UILabel *_problem;
    UILabel *_feedback;
    UITextField *_answer;
    BOOL _finished;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    _position = [UILabel new];
    _position.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _position.textColor = UIColor.secondaryLabelColor;

    _problem = [UILabel new];
    _problem.font = [UIFont monospacedDigitSystemFontOfSize:44 weight:UIFontWeightBold];
    _problem.adjustsFontSizeToFitWidth = YES;
    _problem.minimumScaleFactor = 0.5;
    _problem.accessibilityIdentifier = @"alarmlock-problem";

    _answer = [UITextField new];
    _answer.keyboardType = UIKeyboardTypeNumberPad;
    _answer.font = [UIFont monospacedDigitSystemFontOfSize:34 weight:UIFontWeightSemibold];
    _answer.borderStyle = UITextBorderStyleRoundedRect;
    _answer.placeholder = @"Answer";
    _answer.delegate = self;
    [_answer.heightAnchor constraintEqualToConstant:60].active = YES;

    _feedback = [UILabel new];
    _feedback.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    _feedback.textColor = UIColor.systemRedColor;
    _feedback.numberOfLines = 0;

    UIButton *check = [UIButton buttonWithType:UIButtonTypeSystem];
    [check setTitle:@"Check" forState:UIControlStateNormal];
    check.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    check.backgroundColor = UIColor.systemYellowColor;
    [check setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    check.layer.cornerRadius = 14;
    [check.heightAnchor constraintEqualToConstant:56].active = YES;
    [check addTarget:self action:@selector(check) forControlEvents:UIControlEventTouchUpInside];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"Not now" forState:UIControlStateNormal];
    cancel.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[_position, _problem, _answer, _feedback, check, cancel]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
    ]];

    [self nextSum];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_answer becomeFirstResponder];
}

- (void)nextSum {
    _sum = ALMakeSum(arc4random_uniform);
    _position.text = [NSString stringWithFormat:@"Sum %ld of %ld", (long)(_done + 1), (long)ALSumsPerUnlock];
    _problem.text = [NSString stringWithFormat:@"%ld × %ld + %ld", (long)_sum.a, (long)_sum.b, (long)_sum.c];
    _answer.text = @"";
    _feedback.text = nil;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self check];
    return NO;
}

- (void)check {
    NSString *typed = [_answer.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    if (typed.length == 0) return;
    if (typed.integerValue != ALSumAnswer(_sum) || typed.length > 6) {
        _feedback.text = @"Not right. Try again.";
        _answer.text = @"";
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];
        return;
    }
    _done += 1;
    if (_done < ALSumsPerUnlock) {
        [[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeSuccess];
        [self nextSum];
        return;
    }
    [self finish:YES];
}

- (void)cancel {
    [self finish:NO];
}

- (void)finish:(BOOL)solved {
    if (_finished) return; // a second tap while closing
    _finished = YES;
    void (^done)(BOOL) = self.onDone;
    self.onDone = nil;
    [_answer resignFirstResponder];
    [self.presentingViewController dismissViewControllerAnimated:YES completion:^{
        if (done) done(solved);
    }];
}

@end

#pragma mark - The cover over the Alarms tab

@interface ALLockUI : NSObject
- (instancetype)initWithHost:(UIViewController *)host;
- (void)refresh:(BOOL)fresh;
- (void)bringToFront;
@end

@implementation ALLockUI {
    __weak UIViewController *_host;
    UIView *_cover;
    UILabel *_title;
    UILabel *_body;
    UILabel *_note;
    UIButton *_unlock;
    UIButton *_pill;
    NSTimer *_timer;
    ALLockState _shown;
    BOOL _sumsOpen;
}

- (instancetype)initWithHost:(UIViewController *)host {
    if (!(self = [super init])) return nil;
    _host = host;
    _shown = (ALLockState)-1;
    [self build];
    __weak ALLockUI *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refresh:NO];
    }];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(becameActive)
                                               name:UIApplicationDidBecomeActiveNotification object:nil];
    [self refresh:YES];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)becameActive {
    [self refresh:YES];
}

- (void)build {
    UIView *view = _host.view;

    _cover = [UIView new];
    _cover.translatesAutoresizingMaskIntoConstraints = NO;
    _cover.accessibilityIdentifier = @"alarmlock-cover";
    UIVisualEffectView *blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
    blur.translatesAutoresizingMaskIntoConstraints = NO;
    [_cover addSubview:blur];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"lock.fill"]];
    icon.tintColor = UIColor.systemYellowColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [icon.heightAnchor constraintEqualToConstant:48].active = YES;

    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    _title.textColor = UIColor.whiteColor;
    _title.textAlignment = NSTextAlignmentCenter;
    _title.numberOfLines = 0;

    _body = [UILabel new];
    _body.font = [UIFont systemFontOfSize:17];
    _body.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    _body.textAlignment = NSTextAlignmentCenter;
    _body.numberOfLines = 0;

    _unlock = [UIButton buttonWithType:UIButtonTypeSystem];
    [_unlock setTitle:@"Unlock with sums" forState:UIControlStateNormal];
    _unlock.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightBold];
    _unlock.backgroundColor = UIColor.systemYellowColor;
    [_unlock setTitleColor:UIColor.blackColor forState:UIControlStateNormal];
    _unlock.layer.cornerRadius = 16;
    [_unlock.heightAnchor constraintEqualToConstant:58].active = YES;
    [_unlock addTarget:self action:@selector(startSums) forControlEvents:UIControlEventTouchUpInside];

    _note = [UILabel new];
    _note.font = [UIFont systemFontOfSize:13];
    _note.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _note.textAlignment = NSTextAlignmentCenter;
    _note.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, _title, _body, _unlock, _note]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_cover addSubview:stack];
    [view addSubview:_cover];

    _pill = [UIButton buttonWithType:UIButtonTypeSystem];
    _pill.translatesAutoresizingMaskIntoConstraints = NO;
    _pill.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _pill.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    [_pill setTitleColor:UIColor.systemYellowColor forState:UIControlStateNormal];
    _pill.tintColor = UIColor.systemYellowColor;
    _pill.layer.cornerRadius = 18;
    _pill.contentEdgeInsets = UIEdgeInsetsMake(8, 14, 8, 14);
    _pill.accessibilityIdentifier = @"alarmlock-pill";
    [_pill addTarget:self action:@selector(pillTapped) forControlEvents:UIControlEventTouchUpInside];
    [view addSubview:_pill];

    UILayoutGuide *safe = view.safeAreaLayoutGuide;
    // If the screen itself scrolls, pin to its visible frame so the cover can't scroll away.
    UILayoutGuide *frame = [view isKindOfClass:UIScrollView.class] ? ((UIScrollView *)view).frameLayoutGuide : nil;
    [NSLayoutConstraint activateConstraints:@[
        [_cover.topAnchor constraintEqualToAnchor:(frame ? frame.topAnchor : view.topAnchor)],
        [_cover.bottomAnchor constraintEqualToAnchor:(frame ? frame.bottomAnchor : view.bottomAnchor)],
        [_cover.leadingAnchor constraintEqualToAnchor:(frame ? frame.leadingAnchor : view.leadingAnchor)],
        [_cover.trailingAnchor constraintEqualToAnchor:(frame ? frame.trailingAnchor : view.trailingAnchor)],
        [blur.topAnchor constraintEqualToAnchor:_cover.topAnchor],
        [blur.bottomAnchor constraintEqualToAnchor:_cover.bottomAnchor],
        [blur.leadingAnchor constraintEqualToAnchor:_cover.leadingAnchor],
        [blur.trailingAnchor constraintEqualToAnchor:_cover.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-28],
        [_pill.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:16],
        [_pill.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-12],
        [_pill.heightAnchor constraintGreaterThanOrEqualToConstant:36],
    ]];
}

- (void)bringToFront {
    UIView *view = _host.view;
    [view bringSubviewToFront:_cover];
    [view bringSubviewToFront:_pill];
}

- (void)refresh:(BOOL)fresh {
    if (!_host) return;
    NSDate *now = ALNow();
    ALLockState state = ALStateAt(now, fresh);
    NSDate *next = ALCachedNext;
    NSInteger hours = ALHours();

    BOOL covered = state == ALLockStateLocked || state == ALLockStateSealed;
    _cover.hidden = !covered;
    _pill.hidden = covered;
    if (covered && state != _shown) [self bringToFront];
    _shown = state;

    if (state == ALLockStateSealed) {
        _title.text = @"Alarms locked";
        _body.text = [NSString stringWithFormat:@"Your %@ alarm is less than %@ away. Nothing unlocks until it has rung.",
                      ALTime(next), hours == 1 ? @"1 hour" : [NSString stringWithFormat:@"%ld hours", (long)hours]];
        _unlock.hidden = YES;
    } else if (state == ALLockStateLocked) {
        _title.text = @"Alarms locked";
        _body.text = [NSString stringWithFormat:@"You can't turn alarms off, delete or change them. Do %ld sums to unlock for %d minutes.",
                      (long)ALSumsPerUnlock, (int)(ALUnlockSeconds / 60)];
        _unlock.hidden = _sumsOpen;
    }
    if (covered) {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        if (next) [lines addObject:[NSString stringWithFormat:@"Next alarm: %@", ALTime(next)]];
        if (hours > 0) [lines addObject:[NSString stringWithFormat:@"Sums stop working %@.", ALHoursText(hours)]];
        if (hours > 0 && ALReadProblem) {
            [lines addObject:[NSString stringWithFormat:@"%@ The hours-before rule is off until it can.", ALReadProblem]];
        }
        [lines addObject:@"Emergency escape is off while the lock is on."];
        if (ALReadSummary) [lines addObject:ALReadSummary];
        _note.text = [lines componentsJoinedByString:@"\n"];
    }

    NSString *title;
    if (state == ALLockStateOff) {
        title = @"Lock alarms";
        [_pill setImage:[UIImage systemImageNamed:@"lock.fill"] forState:UIControlStateNormal];
    } else {
        title = [NSString stringWithFormat:@"Unlocked until %@", ALTime(ALOpenUntil(now, ALCachedNext) ?: now)];
        [_pill setImage:[UIImage systemImageNamed:@"lock.open.fill"] forState:UIControlStateNormal];
    }
    NSString *shown = [@" " stringByAppendingString:title];
    if (![[_pill titleForState:UIControlStateNormal] isEqualToString:shown]) {
        [_pill setTitle:shown forState:UIControlStateNormal];
    }
}

- (UIViewController *)topController {
    UIViewController *top = _host;
    while (top.presentedViewController && !top.presentedViewController.isBeingDismissed) top = top.presentedViewController;
    return top;
}

- (void)startSums {
    if (_sumsOpen) return;
    _sumsOpen = YES;
    ALSumsViewController *sums = [ALSumsViewController new];
    sums.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak ALLockUI *weakSelf = self;
    sums.onDone = ^(BOOL solved) {
        ALLockUI *strongSelf = weakSelf;
        if (strongSelf) strongSelf->_sumsOpen = NO;
        if (solved) {
            NSDate *now = ALNow();
            // The seal may have started while the sums were on screen.
            if (ALStateAt(now, YES) == ALLockStateSealed) {
                ALLog(@"sums done, but the alarm is too close now");
            } else {
                ALGrantUnlock(now);
            }
        }
        [strongSelf refresh:YES];
    };
    [[self topController] presentViewController:sums animated:YES completion:nil];
}

- (void)pillTapped {
    NSDate *now = ALNow();
    ALLockState state = ALStateAt(now, YES);
    if (state == ALLockStateOff) {
        [self chooseHoursThen:^(NSInteger hours) {
            [ALDefaults() setObject:@(hours) forKey:ALKeyHours];
            [ALDefaults() setBool:YES forKey:ALKeyOn];
            ALRelock();
            ALLog(@"lock turned on, sealed %ld h before", (long)hours);
            [self refresh:YES];
        } title:@"Lock your alarms?"
          message:@"While locked, you can't turn alarms off, delete or change them, and emergency escape is off. "
                  @"Three sums unlock them for 10 minutes. How long before an alarm should even the sums stop working?"];
        return;
    }
    if (state != ALLockStateOpen) { [self refresh:YES]; return; }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Alarms unlocked"
        message:[NSString stringWithFormat:@"Sums stop working %@.", ALHoursText(ALHours())]
        preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Lock now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        ALRelock();
        [self refresh:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Change hours before an alarm" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self chooseHoursThen:^(NSInteger hours) {
            if (ALStateAt(ALNow(), YES) != ALLockStateOpen) return; // the unlock ran out meanwhile
            [ALDefaults() setObject:@(hours) forKey:ALKeyHours];
            [self refresh:YES];
        } title:@"Sums stop working" message:@"How long before an alarm should even the sums stop working?"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Turn the lock off" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        if (ALStateAt(ALNow(), YES) != ALLockStateOpen) { [self refresh:YES]; return; }
        [ALDefaults() setBool:NO forKey:ALKeyOn];
        ALRelock();
        ALLog(@"lock turned off");
        [self refresh:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:sheet];
}

- (void)chooseHoursThen:(void (^)(NSInteger hours))chosen title:(NSString *)title message:(NSString *)message {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title message:message
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *choice in ALHourChoices()) {
        NSInteger hours = choice.integerValue;
        NSString *label = hours == 0 ? @"Sums always work"
            : [NSString stringWithFormat:@"%@%@", hours == 1 ? @"1 hour" : [NSString stringWithFormat:@"%ld hours", (long)hours],
               hours == ALHours() ? @" (current)" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            chosen(hours);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:sheet];
}

- (void)present:(UIAlertController *)sheet {
    sheet.popoverPresentationController.sourceView = _pill;
    sheet.popoverPresentationController.sourceRect = _pill.bounds;
    [[self topController] presentViewController:sheet animated:YES completion:nil];
}

@end

#pragma mark - Hooks

static IMP ALReplace(Class cls, SEL sel, IMP replacement) {
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        ALLog(@"missing %@ on %s", NSStringFromSelector(sel), class_getName(cls));
        return NULL;
    }
    IMP original = method_getImplementation(method);
    // An inherited method gets its own copy on this class, so the parent class isn't changed.
    if (class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) return original;
    return method_setImplementation(method, replacement);
}

static const void *ALUIKey = &ALUIKey;

static ALLockUI *ALAttach(UIViewController *controller) {
    ALLockUI *ui = objc_getAssociatedObject(controller, ALUIKey);
    if (!ui && controller.isViewLoaded) {
        ui = [[ALLockUI alloc] initWithHost:controller];
        objc_setAssociatedObject(controller, ALUIKey, ui, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ALLog(@"cover added to the Alarms tab");
    }
    return ui;
}

static ALVoidFn ALOrigHomeDidLoad;
static void ALHomeDidLoad(UIViewController *self, SEL sel) {
    ALOrigHomeDidLoad(self, sel);
    ALAttach(self);
}

static ALBoolFn ALOrigHomeDidAppear;
static void ALHomeDidAppear(UIViewController *self, SEL sel, BOOL animated) {
    ALOrigHomeDidAppear(self, sel, animated);
    ALLockUI *ui = ALAttach(self);
    [ui bringToFront];
    [ui refresh:YES];
}

static ALVoidFn ALOrigEscapeDidMove;
static void ALEscapeDidMove(UIView *self, SEL sel) {
    ALOrigEscapeDidMove(self, sel);
    if (ALLockOn()) {
        self.hidden = YES;
        ALLog(@"emergency escape hidden");
    }
}

static ALHitTestFn ALOrigEscapeHitTest;
static UIView *ALEscapeHitTest(UIView *self, SEL sel, CGPoint point, UIEvent *event) {
    if (ALLockOn()) {
        self.hidden = YES;
        return nil;
    }
    return ALOrigEscapeHitTest(self, sel, point, event);
}

// Alarmy's ringing screen. Its mission preview is a subclass, which must not count as a real ring.
static Class ALPreviewClass;
static BOOL ALRingShown;
typedef void (*ALDeallocFn)(__unsafe_unretained id, SEL);

static BOOL ALIsRealRing(__unsafe_unretained id controller) {
    return !(ALPreviewClass && [controller isKindOfClass:ALPreviewClass]);
}

/// A ring has started: the lock closes again at once, so snoozing can't be used to get in.
static void ALRingStarted(void) {
    ALRingShown = YES;
    [ALDefaults() removeObjectForKey:ALKeyDoneAt];
    ALLog(@"alarm ringing, lock closed");
}

/// The ringing screen has gone for good: the alarm rang and its missions were done.
static void ALRingEnded(void) {
    if (!ALRingShown) return;
    ALRingShown = NO;
    [ALDefaults() setObject:@(ALNow().timeIntervalSince1970) forKey:ALKeyDoneAt];
    ALLog(@"alarm finished, lock open until the next alarm's window");
}

static ALBoolFn ALOrigRingDidAppear;
static void ALRingDidAppear(UIViewController *self, SEL sel, BOOL animated) {
    ALOrigRingDidAppear(self, sel, animated);
    if (ALIsRealRing(self)) ALRingStarted();
}

static ALBoolFn ALOrigRingDidDisappear;
static void ALRingDidDisappear(UIViewController *self, SEL sel, BOOL animated) {
    ALOrigRingDidDisappear(self, sel, animated);
    // Only when it is really going away. An ad or another screen shown on top doesn't count.
    if (ALIsRealRing(self) && (self.isBeingDismissed || self.isMovingFromParentViewController)) ALRingEnded();
}

static ALDeallocFn ALOrigRingDealloc;
static void ALRingDealloc(__unsafe_unretained id self, SEL sel) {
    if (ALIsRealRing(self)) ALRingEnded();
    ALOrigRingDealloc(self, sel);
}

__attribute__((constructor)) static void ALStart(void) {
    @autoreleasepool {
        ALConfigLock = [NSObject new];
        ALAlarmConfigs = [NSMutableDictionary dictionary];

        Class realm = objc_getClass("RLMRealm");
        if (realm) {
            Class meta = object_getClass(realm);
            ALOrigOpenQueue = (ALOpenTwoFn)ALReplace(meta, @selector(realmWithConfiguration:queue:error:), (IMP)ALOpenQueue);
            ALOrigOpenConfined = (ALOpenTwoFn)ALReplace(meta, NSSelectorFromString(@"realmWithConfiguration:confinedTo:error:"), (IMP)ALOpenConfined);
            ALOrigOpen = (ALOpenOneFn)ALReplace(meta, @selector(realmWithConfiguration:error:), (IMP)ALOpen);
        } else {
            ALLog(@"no RLMRealm class");
        }

        Class home = objc_getClass("_TtC6Alarmy18HomeViewController");
        if (home) {
            ALOrigHomeDidLoad = (ALVoidFn)ALReplace(home, @selector(viewDidLoad), (IMP)ALHomeDidLoad);
            ALOrigHomeDidAppear = (ALBoolFn)ALReplace(home, @selector(viewDidAppear:), (IMP)ALHomeDidAppear);
        } else {
            ALLog(@"no Alarms tab class, nothing will be locked");
        }

        Class ring = objc_getClass("_TtC6Alarmy24AlarmContainerController");
        ALPreviewClass = objc_getClass("_TtC6Alarmy26PreviewContainerController");
        if (ring) {
            ALOrigRingDidAppear = (ALBoolFn)ALReplace(ring, @selector(viewDidAppear:), (IMP)ALRingDidAppear);
            ALOrigRingDidDisappear = (ALBoolFn)ALReplace(ring, @selector(viewDidDisappear:), (IMP)ALRingDidDisappear);
            ALOrigRingDealloc = (ALDeallocFn)ALReplace(ring, NSSelectorFromString(@"dealloc"), (IMP)ALRingDealloc);
        } else {
            ALLog(@"no ringing screen class, the lock won't open after alarms");
        }

        Class escape = objc_getClass("_TtC6Alarmy27EmergencyEscapeEntryOverlay");
        if (escape) {
            ALOrigEscapeDidMove = (ALVoidFn)ALReplace(escape, @selector(didMoveToWindow), (IMP)ALEscapeDidMove);
            ALOrigEscapeHitTest = (ALHitTestFn)ALReplace(escape, @selector(hitTest:withEvent:), (IMP)ALEscapeHitTest);
        }
        ALLog(@"loaded");
    }
}
