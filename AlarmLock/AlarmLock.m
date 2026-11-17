// AlarmLock: an add-on for the owner's own copy of Alarmy.
// - Lock: while it's on, the Alarms tab is covered, so alarms can't be turned off, deleted or
//   changed, and Alarmy's emergency escape is hidden. Only finishing an alarm (it rang and its
//   missions were done) opens it, until the chosen hours before the next alarm.
// - Mission delay: for a chosen number of minutes after an alarm goes off, the ringing screen is
//   covered, so the alarm keeps ringing and the missions can't start yet.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <time.h>
#import "LockRules.h"

#define ALLog(fmt, ...) NSLog(@"[AlarmLock] " fmt, ##__VA_ARGS__)

#pragma mark - Settings

static NSString *const ALKeyOn = @"AlarmLock.on";
static NSString *const ALKeyHours = @"AlarmLock.hoursBefore";
static NSString *const ALKeyDelay = @"AlarmLock.missionDelayMinutes";
static NSString *const ALKeyAnchor = @"AlarmLock.clockAnchor";
/// When an alarm last finished (or the lock was turned on): it rang and its missions were done.
static NSString *const ALKeyDoneAt = @"AlarmLock.alarmDoneAt";
/// The last sign that alarms are working, for the safety release.
static NSString *const ALKeyActivity = @"AlarmLock.lastActivity";
/// When the alarm that is ringing went off, for the mission delay.
static NSString *const ALKeyRingStart = @"AlarmLock.ringStart";

static NSUserDefaults *ALDefaults(void) { return NSUserDefaults.standardUserDefaults; }
static BOOL ALLockOn(void) { return [ALDefaults() boolForKey:ALKeyOn]; }

static NSInteger ALHours(void) {
    id value = [ALDefaults() objectForKey:ALKeyHours];
    NSInteger hours = [value isKindOfClass:NSNumber.class] ? [value integerValue] : 3;
    return hours > 0 ? hours : 3;
}

static NSInteger ALDelay(void) {
    return MAX(0, MIN([ALDefaults() integerForKey:ALKeyDelay], ALMaxDelayMinutes));
}

static NSDate *ALDateFor(NSString *key) {
    id value = [ALDefaults() objectForKey:key];
    return [value isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[value doubleValue]] : nil;
}

static void ALSetDate(NSString *key, NSDate *date) {
    if (date) [ALDefaults() setObject:@(date.timeIntervalSince1970) forKey:key];
    else [ALDefaults() removeObjectForKey:key];
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

static NSString *ALDayAndTime(NSDate *date) {
    static NSDateFormatter *formatter;
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.dateFormat = [NSDateFormatter dateFormatFromTemplate:@"EEEjmm" options:0 locale:NSLocale.currentLocale];
    }
    return [formatter stringFromDate:date];
}

#pragma mark - Reading Alarmy's alarms

// Alarmy keeps its alarms in a Realm database. The add-on remembers the settings Alarmy opens it
// with, and opens it the same way to read when alarms are due and when they went off. Nothing is
// ever written.
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
typedef void (*ALDeallocFn)(__unsafe_unretained id, SEL);

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
/// The alarms were read and none is on.
static BOOL ALNoAlarmsOn;

static NSDate *ALDateValue(id object, NSString *key) {
    @try {
        id value = [object valueForKey:key];
        return [value isKindOfClass:NSDate.class] ? value : nil;
    } @catch (__unused NSException *e) {
        return nil; // a field this version of Alarmy doesn't have
    }
}

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
            ALAlarmRecord *alarm = [ALAlarmRecord enabled:[[object valueForKey:@"enabled"] boolValue]
                                                     next:ALDateValue(object, @"nextFireDate")
                                                     hour:[[object valueForKey:@"hour"] integerValue]
                                                   minute:[[object valueForKey:@"minute"] integerValue]];
            alarm.lastFiredDate = ALDateValue(object, @"lastFiredDate");
            [alarms addObject:alarm];
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
    ALNoAlarmsOn = NO;
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
    ALNoAlarmsOn = on == 0;
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

#pragma mark - The lock's state

/// Until when the lock is open because the last alarm was finished (or it was just turned on).
static NSDate *ALOpenUntil(NSDate *now, NSDate *next) {
    return ALOpenAfterAlarmUntil(ALDateFor(ALKeyDoneAt), ALHours(), next, now);
}

static ALLockState ALStateAt(NSDate *now, BOOL fresh) {
    NSDate *next = ALNextAlarmAt(now, fresh);
    if (ALLockOn() && !ALDateFor(ALKeyActivity)) ALSetDate(ALKeyActivity, now);
    return ALLockStateAt(ALLockOn(), ALOpenUntil(now, next), ALNoAlarmsOn, ALDateFor(ALKeyActivity), now);
}

/// Turning the lock on counts as an alarm just finished: open until the hours before the next alarm.
static void ALTurnOn(NSDate *now) {
    [ALDefaults() setBool:YES forKey:ALKeyOn];
    ALSetDate(ALKeyDoneAt, now);
    ALSetDate(ALKeyActivity, now);
    ALLog(@"lock turned on, locks %ld h before an alarm", (long)ALHours());
}

static void ALLockNow(NSDate *now) {
    ALSetDate(ALKeyDoneAt, nil);
    ALSetDate(ALKeyActivity, now);
    ALLog(@"locked now");
}

static void ALTurnOff(void) {
    [ALDefaults() setBool:NO forKey:ALKeyOn];
    ALSetDate(ALKeyDoneAt, nil);
    ALLog(@"lock turned off");
}

static NSString *ALHoursText(NSInteger hours) {
    return hours == 1 ? @"1 hour" : [NSString stringWithFormat:@"%ld hours", (long)hours];
}

static NSString *ALDelayText(NSInteger minutes) {
    if (minutes <= 0) return @"off";
    return minutes == 1 ? @"1 minute" : [NSString stringWithFormat:@"%ld minutes", (long)minutes];
}

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
    UIButton *_pill;
    NSTimer *_timer;
    ALLockState _shown;
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
    _title.text = @"Alarms locked";

    _body = [UILabel new];
    _body.font = [UIFont systemFontOfSize:17];
    _body.textColor = [UIColor colorWithWhite:1 alpha:0.85];
    _body.textAlignment = NSTextAlignmentCenter;
    _body.numberOfLines = 0;

    _note = [UILabel new];
    _note.font = [UIFont systemFontOfSize:13];
    _note.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _note.textAlignment = NSTextAlignmentCenter;
    _note.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[icon, _title, _body, _note]];
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

    BOOL covered = state == ALLockStateLocked;
    _cover.hidden = !covered;
    _pill.hidden = covered;
    if (covered && state != _shown) [self bringToFront];
    _shown = state;

    if (covered) {
        _body.text = next
            ? [NSString stringWithFormat:@"They unlock by themselves once your %@ alarm has rung and you've done its missions.", ALTime(next)]
            : @"They unlock by themselves once your next alarm has rung and you've done its missions.";
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        [lines addObject:[NSString stringWithFormat:@"After that they lock again %@ before the following alarm.", ALHoursText(ALHours())]];
        if (ALDelay() > 0) [lines addObject:[NSString stringWithFormat:@"Missions wait %@ after an alarm goes off.", ALDelayText(ALDelay())]];
        [lines addObject:@"Emergency escape is off while the lock is on."];
        NSDate *release = ALReleaseAt(ALDateFor(ALKeyActivity));
        if (release) [lines addObject:[NSString stringWithFormat:@"Safety release: if no alarm rings before %@, they unlock.", ALDayAndTime(release)]];
        if (ALReadProblem) [lines addObject:ALReadProblem];
        if (ALReadSummary) [lines addObject:ALReadSummary];
        _note.text = [lines componentsJoinedByString:@"\n"];
    }

    NSString *title;
    if (state == ALLockStateOff) {
        title = ALDelay() > 0 ? [NSString stringWithFormat:@"Alarm lock off · delay %ld min", (long)ALDelay()] : @"Alarm lock off";
        [_pill setImage:[UIImage systemImageNamed:@"lock.fill"] forState:UIControlStateNormal];
    } else {
        NSDate *until = ALOpenUntil(now, next);
        title = until ? [NSString stringWithFormat:@"Unlocked until %@", ALTime(until)] : @"Unlocked";
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

/// Settings can only be changed while the lock is off or open.
- (BOOL)canChange {
    ALLockState state = ALStateAt(ALNow(), YES);
    if (state == ALLockStateLocked) { [self refresh:YES]; return NO; }
    return YES;
}

- (void)pillTapped {
    if (![self canChange]) return;
    BOOL on = ALLockOn();
    NSString *message = on
        ? [NSString stringWithFormat:@"Locks %@ before each alarm. Mission delay: %@.", ALHoursText(ALHours()), ALDelayText(ALDelay())]
        : [NSString stringWithFormat:@"While locked, alarms can't be turned off, deleted or changed, and emergency escape is off. "
                                     @"They unlock by themselves once an alarm has rung and its missions are done. Mission delay: %@.",
                                     ALDelayText(ALDelay())];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:on ? @"Alarms unlocked" : @"Alarm lock"
                                                                    message:message
                                                             preferredStyle:UIAlertControllerStyleActionSheet];
    if (on) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Lock now" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (![self canChange]) return;
            ALLockNow(ALNow());
            [self refresh:YES];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Lock time: %@ before", ALHoursText(ALHours())]
                                                  style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self chooseHoursThen:^(NSInteger hours) {
                if (![self canChange]) return;
                [ALDefaults() setObject:@(hours) forKey:ALKeyHours];
                [self refresh:YES];
            }];
        }]];
    } else {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Turn the lock on…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            [self chooseHoursThen:^(NSInteger hours) {
                [ALDefaults() setObject:@(hours) forKey:ALKeyHours];
                ALTurnOn(ALNow());
                [self refresh:YES];
            }];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"Mission delay: %@", ALDelayText(ALDelay())]
                                              style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [self chooseDelay];
    }]];
    if (on) {
        [sheet addAction:[UIAlertAction actionWithTitle:@"Turn the lock off" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
            if (![self canChange]) return;
            ALTurnOff();
            [self refresh:YES];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:sheet];
}

- (void)chooseHoursThen:(void (^)(NSInteger hours))chosen {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Lock time"
        message:@"How long before each alarm should the lock close? It stays closed until that alarm has rung and its missions are done."
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *choice in ALHourChoices()) {
        NSInteger hours = choice.integerValue;
        NSString *label = [NSString stringWithFormat:@"%@ before%@", ALHoursText(hours), hours == ALHours() && ALLockOn() ? @" (current)" : @""];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            chosen(hours);
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [self present:sheet];
}

- (void)chooseDelay {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Mission delay"
        message:@"For this long after an alarm goes off, its missions can't start, so it keeps ringing. Snooze waits too."
        preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *choice in ALDelayChoices()) {
        NSInteger minutes = choice.integerValue;
        NSString *label = minutes == 0 ? @"Off" : ALDelayText(minutes);
        if (minutes == ALDelay()) label = [label stringByAppendingString:@" (current)"];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            if (![self canChange]) return;
            [ALDefaults() setInteger:minutes forKey:ALKeyDelay];
            ALLog(@"mission delay %ld min", (long)minutes);
            [self refresh:YES];
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

#pragma mark - The countdown over the ringing screen

/// Covers Alarmy's ringing screen until the mission delay is over, then takes itself away.
@interface ALHoldUI : NSObject
- (instancetype)initWithHost:(UIViewController *)host;
- (void)refresh;
@end

@implementation ALHoldUI {
    __weak UIViewController *_host;
    UIView *_cover;
    UILabel *_countdown;
    NSTimer *_timer;
}

- (instancetype)initWithHost:(UIViewController *)host {
    if (!(self = [super init])) return nil;
    _host = host;
    [self build];
    __weak ALHoldUI *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refresh];
    }];
    [self refresh];
    return self;
}

- (void)dealloc {
    [_timer invalidate];
}

- (void)build {
    UIView *view = _host.view;
    _cover = [UIView new];
    _cover.translatesAutoresizingMaskIntoConstraints = NO;
    _cover.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    _cover.accessibilityIdentifier = @"alarmlock-hold";

    UILabel *title = [UILabel new];
    title.text = @"Missions open in";
    title.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    title.textColor = UIColor.whiteColor;
    title.textAlignment = NSTextAlignmentCenter;

    _countdown = [UILabel new];
    _countdown.font = [UIFont monospacedDigitSystemFontOfSize:72 weight:UIFontWeightBold];
    _countdown.textColor = UIColor.systemYellowColor;
    _countdown.textAlignment = NSTextAlignmentCenter;

    UILabel *body = [UILabel new];
    body.text = @"The alarm keeps ringing until then.";
    body.font = [UIFont systemFontOfSize:16];
    body.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    body.textAlignment = NSTextAlignmentCenter;
    body.numberOfLines = 0;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title, _countdown, body]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [_cover addSubview:stack];
    [view addSubview:_cover];

    UILayoutGuide *safe = view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_cover.topAnchor constraintEqualToAnchor:view.topAnchor],
        [_cover.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [_cover.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [_cover.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-24],
    ]];
}

- (void)refresh {
    UIViewController *host = _host;
    NSDate *now = ALNow();
    NSDate *open = ALMissionsOpenAt(ALDateFor(ALKeyRingStart), ALDelay(), now);
    if (!host || !open) {
        // Delay over (or turned off): get out of the way for good.
        [_timer invalidate];
        _timer = nil;
        [_cover removeFromSuperview];
        _cover = nil;
        return;
    }
    if (_cover.superview != host.view) return;
    [host.view bringSubviewToFront:_cover]; // Alarmy may add its own views on top later
    NSInteger left = (NSInteger)ceil([open timeIntervalSinceDate:now]);
    _countdown.text = [NSString stringWithFormat:@"%ld:%02ld", (long)(left / 60), (long)(left % 60)];
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
static const void *ALHoldKey = &ALHoldKey;

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
static const NSTimeInterval ALRingStartKeep = 2 * 3600;

static BOOL ALIsRealRing(__unsafe_unretained id controller) {
    return !(ALPreviewClass && [controller isKindOfClass:ALPreviewClass]);
}

/// A ring has started: the lock closes again at once, so snoozing can't be used to get in, and the
/// mission delay counts from when the alarm went off.
static void ALRingStarted(UIViewController *container) {
    NSDate *now = ALNow();
    ALRingShown = YES;
    ALSetDate(ALKeyDoneAt, nil);
    ALSetDate(ALKeyActivity, now);

    // The screen can appear again for the same ring (after an ad, or reopening the app): keep its start.
    NSDate *start = ALDateFor(ALKeyRingStart);
    NSTimeInterval age = start ? [now timeIntervalSinceDate:start] : -1;
    if (!start || age < -60 || age > ALRingStartKeep) {
        NSArray<ALAlarmRecord *> *alarms = ALReadAlarms();
        start = (alarms ? ALRingStart(alarms, now) : nil) ?: now;
        ALSetDate(ALKeyRingStart, start);
    }
    ALLog(@"alarm ringing, lock closed, went off at %@", ALTime(start));

    if (ALMissionsOpenAt(start, ALDelay(), now) && !objc_getAssociatedObject(container, ALHoldKey)) {
        ALHoldUI *hold = [[ALHoldUI alloc] initWithHost:container];
        objc_setAssociatedObject(container, ALHoldKey, hold, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ALLog(@"missions held for %ld min", (long)ALDelay());
    }
}

/// The ringing screen has gone for good: the alarm rang and its missions were done.
static void ALRingEnded(void) {
    if (!ALRingShown) return;
    ALRingShown = NO;
    NSDate *now = ALNow();
    ALSetDate(ALKeyDoneAt, now);
    ALSetDate(ALKeyActivity, now);
    ALSetDate(ALKeyRingStart, nil);
    ALLog(@"alarm finished, lock open until the next alarm's lock time");
}

static ALBoolFn ALOrigRingDidAppear;
static void ALRingDidAppear(UIViewController *self, SEL sel, BOOL animated) {
    ALOrigRingDidAppear(self, sel, animated);
    if (ALIsRealRing(self)) ALRingStarted(self);
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
