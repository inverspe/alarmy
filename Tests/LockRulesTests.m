// Run on a Mac by CI: clang -fobjc-arc -framework Foundation ... && ./tests
#import <Foundation/Foundation.h>
#import "../AlarmLock/LockRules.h"

static int failures = 0, checks = 0;
#define CHECK(cond, msg) do { checks++; if (!(cond)) { failures++; fprintf(stderr, "FAIL %s:%d %s\n", __FILE__, __LINE__, msg); } } while (0)

static NSCalendar *cal(void) {
    NSCalendar *c = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    c.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    return c;
}

/// "2026-10-21 06:30" in New York.
static NSDate *D(NSString *s) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    f.dateFormat = @"yyyy-MM-dd HH:mm";
    return [f dateFromString:s];
}

static uint32_t lowest(uint32_t n) { (void)n; return 0; }
static uint32_t highest(uint32_t n) { return n - 1; }

static void testSealedWindow(void) {
    NSDate *alarm = D(@"2026-10-21 07:00");
    CHECK(!ALIsSealed(3, alarm, D(@"2026-10-21 03:59")), "before the window");
    CHECK(ALIsSealed(3, alarm, D(@"2026-10-21 04:00")), "window starts 3 h before");
    CHECK(ALIsSealed(3, alarm, D(@"2026-10-21 06:59")), "still sealed just before");
    CHECK(!ALIsSealed(3, alarm, D(@"2026-10-21 07:00")), "ends when the alarm rings");
    CHECK(!ALIsSealed(0, alarm, D(@"2026-10-21 06:59")), "0 hours never seals");
    CHECK(!ALIsSealed(3, nil, D(@"2026-10-21 06:59")), "no known alarm, no seal");
    CHECK(ALIsSealed(12, alarm, D(@"2026-10-20 19:00")), "12 h reaches the evening before");
}

static void testUnlockWindow(void) {
    NSDate *until = D(@"2026-10-21 12:10");
    CHECK(ALIsUnlocked(until, @"a", @"a", D(@"2026-10-21 12:00")), "open from when it was earned");
    CHECK(ALIsUnlocked(until, @"a", @"a", D(@"2026-10-21 12:09")), "open for 10 minutes");
    CHECK(!ALIsUnlocked(until, @"a", @"a", D(@"2026-10-21 12:10")), "closes after 10 minutes");
    CHECK(!ALIsUnlocked(until, @"a", @"a", D(@"2026-10-21 11:59")), "clock turned back can't reopen it");
    CHECK(!ALIsUnlocked(until, @"a", @"a", D(@"2026-09-01 12:05")), "clock turned far back can't reopen it");
    CHECK(!ALIsUnlocked(until, @"a", @"b", D(@"2026-10-21 12:05")), "a restart ends it");
    CHECK(ALIsUnlocked(until, nil, nil, D(@"2026-10-21 12:05")), "works when the phone won't give a boot ID");
    CHECK(!ALIsUnlocked(nil, @"a", @"a", D(@"2026-10-21 12:05")), "never unlocked");
    CHECK(ALUnlockSeconds == 600, "10 minutes");
}

static void testStates(void) {
    NSDate *alarm = D(@"2026-10-21 07:00");
    CHECK(ALLockStateAt(NO, 3, alarm, NO, D(@"2026-10-21 06:00")) == ALLockStateOff, "off is off, even near the alarm");
    CHECK(ALLockStateAt(YES, 3, alarm, NO, D(@"2026-10-21 01:00")) == ALLockStateLocked, "locked, sums open it");
    CHECK(ALLockStateAt(YES, 3, alarm, YES, D(@"2026-10-21 01:00")) == ALLockStateOpen, "open after the sums");
    CHECK(ALLockStateAt(YES, 3, alarm, NO, D(@"2026-10-21 05:00")) == ALLockStateSealed, "sealed near the alarm");
    CHECK(ALLockStateAt(YES, 3, alarm, YES, D(@"2026-10-21 05:00")) == ALLockStateSealed, "the seal cuts an unlock short");
    CHECK(ALLockStateAt(YES, 0, alarm, NO, D(@"2026-10-21 06:59")) == ALLockStateLocked, "0 hours: sums work up to the alarm");
}

static void testNextAlarm(void) {
    NSDate *now = D(@"2026-10-21 12:00");
    NSArray *alarms = @[
        [ALAlarmRecord enabled:YES next:D(@"2026-10-22 07:00") hour:7 minute:0],
        [ALAlarmRecord enabled:YES next:D(@"2026-10-21 22:30") hour:22 minute:30],
        [ALAlarmRecord enabled:NO next:D(@"2026-10-21 13:00") hour:13 minute:0],
    ];
    CHECK([ALNextAlarm(alarms, now, cal()) isEqualToDate:D(@"2026-10-21 22:30")], "soonest alarm that's on");

    NSArray *stale = @[[ALAlarmRecord enabled:YES next:D(@"2026-10-20 06:30") hour:6 minute:30]];
    CHECK([ALNextAlarm(stale, now, cal()) isEqualToDate:D(@"2026-10-22 06:30")], "a past next date falls back to the clock time");

    NSArray *none = @[[ALAlarmRecord enabled:YES next:nil hour:9 minute:15]];
    CHECK([ALNextAlarm(none, now, cal()) isEqualToDate:D(@"2026-10-22 09:15")], "no next date uses the clock time");

    CHECK(ALNextAlarm(@[], now, cal()) == nil, "no alarms");
    NSArray *off = @[[ALAlarmRecord enabled:NO next:D(@"2026-10-21 13:00") hour:13 minute:0]];
    CHECK(ALNextAlarm(off, now, cal()) == nil, "alarms that are off don't count");
}

static void testTrustedClock(void) {
    NSDate *t0 = D(@"2026-10-21 12:00");
    NSDictionary *anchor = ALRefreshedAnchor(nil, t0, 1000, @"a");
    CHECK([anchor[@"wall"] doubleValue] == t0.timeIntervalSince1970, "first anchor");

    NSDate *honest = [t0 dateByAddingTimeInterval:600];
    CHECK([ALTrustedNow(honest, 1600, @"a", anchor) isEqualToDate:honest], "an honest clock is used as is");

    NSDate *movedForward = [t0 dateByAddingTimeInterval:6 * 3600];
    CHECK([ALTrustedNow(movedForward, 1600, @"a", anchor) isEqualToDate:honest], "moving the clock forward is ignored");
    CHECK(ALRefreshedAnchor(anchor, movedForward, 1600, @"a") == anchor, "a moved clock doesn't become the new anchor");

    CHECK([ALTrustedNow(movedForward, 50, @"b", anchor) isEqualToDate:movedForward], "after a restart there's nothing to check against");
    CHECK(!ALSameBoot(anchor, 50, @"b"), "a restart is noticed");
    CHECK(ALSameBoot(anchor, 1600, @"a"), "same boot");

    NSDictionary *kept = ALRefreshedAnchor(anchor, [t0 dateByAddingTimeInterval:30], 1030, @"a");
    CHECK(kept == anchor, "not rewritten within a minute");
    NSDictionary *moved = ALRefreshedAnchor(anchor, [t0 dateByAddingTimeInterval:90], 1090, @"a");
    CHECK([moved[@"mono"] doubleValue] == 1090, "refreshed after a minute");
}

static void testSums(void) {
    ALSum low = ALMakeSum(lowest), high = ALMakeSum(highest);
    CHECK(low.a == 10 && low.b == 2 && low.c == 10, "smallest sum");
    CHECK(high.a == 99 && high.b == 9 && high.c == 99, "largest sum");
    CHECK(ALSumAnswer(low) == 30 && ALSumAnswer(high) == 990, "answers");
    CHECK(ALSumsPerUnlock == 3, "three sums");
    CHECK([ALHourChoices() containsObject:@3] && [ALHourChoices() containsObject:@0], "3 hours and off are choices");
}

int main(void) {
    @autoreleasepool {
        testSealedWindow();
        testUnlockWindow();
        testStates();
        testNextAlarm();
        testTrustedClock();
        testSums();
    }
    printf("%d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
