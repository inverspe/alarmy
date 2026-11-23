// Runs the add-on in the iPhone simulator against stand-ins for the app's screens and database.
// Contains nothing from the real app. Background and foreground are simulated by posting the
// notices iOS sends, so this checks the add-on's behaviour, not iOS's.
#import <UIKit/UIKit.h>

extern int ALRefreshCount;
static int failures = 0, checks = 0;
#define CHECK(cond, msg) do { checks++; BOOL ok_ = (cond); if (!ok_) failures++; printf("%s %s\n", ok_ ? "ok  " : "FAIL", msg); fflush(stdout); } while (0)

#pragma mark - Stand-in database

static int opens = 0;

@interface StandInAlarm : NSObject
@property (nonatomic) BOOL enabled;
@property (nonatomic) NSInteger hour, minute;
@property (nonatomic, strong) NSDate *nextFireDate, *lastFiredDate;
@end
@implementation StandInAlarm
@end

static NSMutableArray<StandInAlarm *> *alarms;

@interface RLMRealmConfiguration : NSObject <NSCopying>
@end
@implementation RLMRealmConfiguration
- (id)copyWithZone:(NSZone *)zone { return [RLMRealmConfiguration new]; }
- (NSURL *)fileURL { return [NSURL fileURLWithPath:@"/tmp/standin.realm"]; }
@end

@interface StandInSchema : NSObject
@end
@implementation StandInSchema
- (id)schemaForClassName:(NSString *)name { return [name isEqualToString:@"AlarmEntity"] ? @"yes" : nil; }
@end

@interface RLMRealm : NSObject
@end
@implementation RLMRealm
+ (instancetype)realmWithConfiguration:(id)c queue:(id)q error:(NSError **)e { opens++; return [RLMRealm new]; }
+ (instancetype)realmWithConfiguration:(id)c confinedTo:(id)q error:(NSError **)e { opens++; return [RLMRealm new]; }
+ (instancetype)realmWithConfiguration:(id)c error:(NSError **)e { opens++; return [RLMRealm new]; }
- (id)schema { return [StandInSchema new]; }
- (id)configuration { return [RLMRealmConfiguration new]; }
- (id)allObjects:(NSString *)name { return alarms; }
@end

#pragma mark - Stand-in screens, under the names the add-on looks for

__attribute__((objc_runtime_name("_TtC6Alarmy18HomeViewController")))
@interface StandInHome : UIViewController
@end
@implementation StandInHome
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = UIColor.darkGrayColor; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; }
@end

__attribute__((objc_runtime_name("_TtC6Alarmy24AlarmContainerController")))
@interface StandInRing : UIViewController
@end
@implementation StandInRing
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; }
- (void)dealloc { printf("     (ringing screen released)\n"); }
@end

__attribute__((objc_runtime_name("_TtC6Alarmy26PreviewContainerController")))
@interface StandInPreview : StandInRing
@end
@implementation StandInPreview
@end

__attribute__((objc_runtime_name("_TtC6Alarmy27EmergencyEscapeEntryOverlay")))
@interface StandInEscape : UIView
@end
@implementation StandInEscape
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return [super hitTest:p withEvent:e]; }
@end

#pragma mark - Helpers

static UIWindow *window;
static StandInHome *home;
static NSUserDefaults *D(void) { return NSUserDefaults.standardUserDefaults; }
static void spin(NSTimeInterval s) { [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:s]]; }
static void post(NSString *name) { [NSNotificationCenter.defaultCenter postNotificationName:name object:UIApplication.sharedApplication]; }
static void leave(void) { post(UIApplicationWillResignActiveNotification); post(UIApplicationDidEnterBackgroundNotification); }
static void comeBack(void) { post(UIApplicationWillEnterForegroundNotification); post(UIApplicationDidBecomeActiveNotification); }
static void setDate(NSString *key, NSDate *d) { if (d) [D() setObject:@(d.timeIntervalSince1970) forKey:key]; else [D() removeObjectForKey:key]; }

static UIView *find(UIView *v, NSString *identifier) {
    if ([v.accessibilityIdentifier isEqualToString:identifier]) return v;
    for (UIView *s in v.subviews) { UIView *f = find(s, identifier); if (f) return f; }
    return nil;
}
static BOOL visible(UIView *root, NSString *identifier) { UIView *v = find(root, identifier); return v && !v.hidden; }
static NSString *log_(void) {
    NSString *lib = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject;
    return [NSString stringWithContentsOfFile:[lib stringByAppendingPathComponent:@"AlarmLock.log"] encoding:NSUTF8StringEncoding error:nil] ?: @"";
}
static void present(UIViewController *c) {
    c.modalPresentationStyle = UIModalPresentationFullScreen;
    [home presentViewController:c animated:NO completion:nil];
    spin(1.5);
}
static void dismiss(void) { [home dismissViewControllerAnimated:NO completion:nil]; spin(1.5); }

#pragma mark - The tests

static void run(void) {
    StandInAlarm *alarm = [StandInAlarm new];
    alarm.enabled = YES;
    alarm.nextFireDate = [NSDate dateWithTimeIntervalSinceNow:3600];
    [alarms addObject:alarm];
    [RLMRealm realmWithConfiguration:[RLMRealmConfiguration new] queue:nil error:nil]; // the app opening its database
    comeBack();
    spin(2);

    printf("-- lock\n");
    CHECK(!visible(home.view, @"alarmlock-cover"), "lock off: the Alarms tab isn't covered");
    CHECK(visible(home.view, @"alarmlock-pill"), "lock off: the button shows");
    [D() setBool:YES forKey:@"AlarmLock.on"];
    [D() setObject:@3 forKey:@"AlarmLock.hoursBefore"];
    setDate(@"AlarmLock.lastActivity", NSDate.date);
    spin(2);
    CHECK(visible(home.view, @"alarmlock-cover"), "lock on, alarm in an hour: covered");
    CHECK(!visible(home.view, @"alarmlock-pill"), "lock on: no button to change settings");

    printf("-- in front, the add-on works (so the next part means something)\n");
    int opens0 = opens, refresh0 = ALRefreshCount;
    spin(20);
    CHECK(opens > opens0, "in front it reads the alarms");
    CHECK(ALRefreshCount > refresh0 + 10, "in front its timer runs");

    printf("-- in the background, it's idle\n");
    leave();
    spin(1);
    opens0 = opens; refresh0 = ALRefreshCount;
    spin(35);
    CHECK(opens == opens0, "background: no reading of alarms for 35 s");
    CHECK(ALRefreshCount == refresh0, "background: no timer for 35 s");

    printf("-- an alarm going off in the background\n");
    [D() setInteger:1 forKey:@"AlarmLock.missionDelayMinutes"];
    opens0 = opens;
    StandInRing *ring = [StandInRing new];
    present(ring);
    CHECK([D() boolForKey:@"AlarmLock.ringing"], "background ring is noticed");
    CHECK(opens == opens0, "background ring doesn't read the alarms");
    CHECK(visible(ring.view, @"alarmlock-hold"), "mission delay covers the ringing screen");
    comeBack();
    spin(1.5);
    CHECK(visible(ring.view, @"alarmlock-hold"), "still held when opened");
    dismiss();
    ring = nil;
    CHECK(![D() boolForKey:@"AlarmLock.ringing"], "closing the ringing screen ends the ring");
    CHECK([D() objectForKey:@"AlarmLock.alarmDoneAt"] != nil, "and counts as finished");
    alarm.nextFireDate = [NSDate dateWithTimeIntervalSinceNow:20 * 3600];
    post(UIApplicationDidBecomeActiveNotification);
    spin(2);
    CHECK(!visible(home.view, @"alarmlock-cover"), "next alarm is far off: unlocked");

    printf("-- the countdown ends by itself\n");
    alarm.lastFiredDate = [NSDate dateWithTimeIntervalSinceNow:-56];
    ring = [StandInRing new];
    present(ring);
    CHECK(visible(ring.view, @"alarmlock-hold"), "held for the last seconds");
    spin(6);
    CHECK(find(ring.view, @"alarmlock-hold") == nil, "gone once the delay is over");
    dismiss();
    ring = nil;

    printf("-- mission previews don't count\n");
    setDate(@"AlarmLock.alarmDoneAt", nil);
    alarm.lastFiredDate = nil;
    StandInPreview *preview = [StandInPreview new];
    present(preview);
    CHECK(![D() boolForKey:@"AlarmLock.ringing"], "a preview isn't a ring");
    CHECK(find(preview.view, @"alarmlock-hold") == nil, "a preview isn't held");
    dismiss();
    preview = nil;
    CHECK([D() objectForKey:@"AlarmLock.alarmDoneAt"] == nil, "a preview doesn't unlock");

    printf("-- emergency escape\n");
    StandInEscape *escape = [[StandInEscape alloc] initWithFrame:CGRectMake(0, 0, 50, 50)];
    [window addSubview:escape];
    CHECK(escape.hidden, "hidden while the lock is on");
    [escape removeFromSuperview];

    printf("-- the log\n");
    setDate(@"AlarmLock.expectedAlarm", [NSDate dateWithTimeIntervalSinceNow:-1800]);
    setDate(@"AlarmLock.ringScreenSeen", [NSDate dateWithTimeIntervalSinceNow:-7200]);
    post(UIApplicationDidBecomeActiveNotification);
    spin(12);
    NSString *text = log_();
    CHECK([text containsString:@"Alarmy started"], "notes the start");
    CHECK([text containsString:@"left, next alarm"], "notes being left");
    CHECK([text containsString:@"notifications waiting"], "notes waiting notifications");
    CHECK([text containsString:@"RINGING SCREEN appeared (in the background)"], "notes a ring in the background");
    CHECK([text containsString:@"MISSED: an alarm was due"], "notes a missed alarm");
    printf("---- the log, as you'd copy it\n%s----\n", text.UTF8String);

    printf("RESULT %d checks, %d failures\n", checks, failures);
    fflush(stdout);
    exit(failures == 0 ? 0 : 1);
}

@interface HostDelegate : UIResponder <UIApplicationDelegate>
@end
@implementation HostDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    alarms = [NSMutableArray array];
    window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    home = [StandInHome new];
    window.rootViewController = home;
    [window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // Off the main queue's back, so timers and delayed blocks still run while the test waits.
        [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:NO block:^(NSTimer *t) { run(); }];
    });
    return YES;
}
@end

int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(HostDelegate.class)); }
}
