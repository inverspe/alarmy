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

static ALAlarmRecord *fired(NSString *when) {
    ALAlarmRecord *r = [ALAlarmRecord enabled:YES next:nil hour:7 minute:0];
    r.lastFiredDate = when ? D(when) : nil;
    return r;
}

static void testStates(void) {
    NSDate *now = D(@"2026-10-21 01:00"), *recent = D(@"2026-10-20 22:00");
    NSDate *until = D(@"2026-10-21 04:00");
    CHECK(ALLockStateAt(NO, nil, NO, recent, now) == ALLockStateOff, "off is off");
    CHECK(ALLockStateAt(YES, nil, NO, recent, now) == ALLockStateLocked, "locked, and nothing but the alarm opens it");
    CHECK(ALLockStateAt(YES, until, NO, recent, now) == ALLockStateOpen, "open after the alarm was finished");
    CHECK(ALLockStateAt(YES, nil, YES, recent, now) == ALLockStateOpen, "no alarms on: nothing to protect");
    CHECK(ALLockStateAt(YES, nil, NO, nil, now) == ALLockStateLocked, "unknown last activity never lets go");
}

static void testRelease(void) {
    NSDate *last = D(@"2026-10-21 07:10");
    CHECK([ALReleaseAt(last) isEqualToDate:D(@"2026-10-25 07:10")], "lets go 4 days later");
    CHECK(ALLockStateAt(YES, nil, NO, last, D(@"2026-10-25 07:09")) == ALLockStateLocked, "still locked just before");
    CHECK(ALLockStateAt(YES, nil, NO, last, D(@"2026-10-25 07:10")) == ALLockStateOpen, "lets go after 4 days with no alarm");
    CHECK(ALLockStateAt(YES, nil, NO, last, D(@"2026-10-24 07:10")) == ALLockStateLocked, "a weekend without alarms isn't enough");
    CHECK(ALReleaseAt(nil) == nil, "no activity, no release time");
}

static void testOpenAfterAlarm(void) {
    NSDate *done = D(@"2026-10-21 07:10"), *next = D(@"2026-10-22 07:00");
    CHECK([ALOpenAfterAlarmUntil(done, 3, next, D(@"2026-10-21 07:11")) isEqualToDate:D(@"2026-10-22 04:00")], "open until 3 h before the next alarm");
    CHECK(ALOpenAfterAlarmUntil(done, 3, next, D(@"2026-10-22 04:00")) == nil, "locks again when the window starts");
    CHECK([ALOpenAfterAlarmUntil(done, 0, next, D(@"2026-10-21 12:00")) isEqualToDate:next], "0 hours: open until the next alarm rings");
    CHECK([ALOpenAfterAlarmUntil(done, 3, nil, D(@"2026-10-21 12:00")) isEqualToDate:D(@"2026-10-21 19:10")], "next alarm unknown: 12 hours");
    CHECK(ALOpenAfterAlarmUntil(done, 3, nil, D(@"2026-10-21 19:10")) == nil, "and then locked");
    CHECK(ALOpenAfterAlarmUntil(nil, 3, next, D(@"2026-10-21 12:00")) == nil, "no alarm finished");
    CHECK(ALOpenAfterAlarmUntil(done, 3, next, D(@"2026-10-21 07:00")) == nil, "clock turned back before it finished");
    CHECK(ALOpenAfterAlarmUntil(done, 3, D(@"2026-10-21 08:00"), D(@"2026-10-21 07:11")) == nil, "another alarm soon keeps it locked");
    // Turning the lock on counts as just finished: open until the window, or locked at once inside it.
    CHECK([ALOpenAfterAlarmUntil(D(@"2026-10-21 15:00"), 3, next, D(@"2026-10-21 15:00")) isEqualToDate:D(@"2026-10-22 04:00")], "turned on in the afternoon");
    CHECK(ALOpenAfterAlarmUntil(D(@"2026-10-22 05:00"), 3, next, D(@"2026-10-22 05:00")) == nil, "turned on inside the window locks at once");
}

static void testMissionDelay(void) {
    NSDate *start = D(@"2026-10-21 07:00");
    CHECK([ALMissionsOpenAt(start, 5, D(@"2026-10-21 07:00")) isEqualToDate:D(@"2026-10-21 07:05")], "held for 5 minutes");
    CHECK([ALMissionsOpenAt(start, 5, D(@"2026-10-21 07:04")) isEqualToDate:D(@"2026-10-21 07:05")], "still held");
    CHECK(ALMissionsOpenAt(start, 5, D(@"2026-10-21 07:05")) == nil, "open after 5 minutes");
    CHECK(ALMissionsOpenAt(start, 0, D(@"2026-10-21 07:01")) == nil, "0 is off");
    CHECK(ALMissionsOpenAt(nil, 5, D(@"2026-10-21 07:01")) == nil, "no ring, nothing held");
    CHECK([ALMissionsOpenAt(start, 600, D(@"2026-10-21 07:01")) isEqualToDate:D(@"2026-10-21 07:30")], "never more than 30 minutes");
    CHECK(ALMissionsOpenAt(start, 5, D(@"2026-10-21 06:50")) == nil, "a start in the future is ignored");
    CHECK([ALDelayChoices() containsObject:@0] && [ALDelayChoices() containsObject:@5], "off and 5 minutes are choices");
    CHECK(![ALHourChoices() containsObject:@0] && [ALHourChoices() containsObject:@3], "3 hours is a choice, 0 isn't");
}

static void testRingStart(void) {
    NSDate *now = D(@"2026-10-21 07:20");
    NSArray *alarms = @[fired(@"2026-10-21 07:00"), fired(@"2026-10-20 22:00"), fired(nil)];
    CHECK([ALRingStart(alarms, now) isEqualToDate:D(@"2026-10-21 07:00")], "the alarm that just went off");
    NSArray *two = @[fired(@"2026-10-21 06:50"), fired(@"2026-10-21 07:15")];
    CHECK([ALRingStart(two, now) isEqualToDate:D(@"2026-10-21 07:15")], "the latest one");
    CHECK(ALRingStart(@[fired(@"2026-10-21 05:00")], now) == nil, "more than 2 hours ago doesn't count");
    CHECK(ALRingStart(@[fired(@"2026-10-21 08:00")], now) == nil, "a time in the future doesn't count");
    CHECK(ALRingStart(@[], now) == nil, "no alarms");
}

static void testMissedAlarm(void) {
    NSDate *due = D(@"2026-11-23 21:00");
    CHECK(ALMissedAlarm(due, nil, D(@"2026-11-23 21:30")), "due and never seen");
    CHECK(ALMissedAlarm(due, D(@"2026-11-23 07:00"), D(@"2026-11-23 21:30")), "only an earlier ring was seen");
    CHECK(!ALMissedAlarm(due, D(@"2026-11-23 21:00"), D(@"2026-11-23 21:30")), "it rang");
    CHECK(!ALMissedAlarm(due, D(@"2026-11-23 21:20"), D(@"2026-11-23 21:30")), "its screen was seen late");
    CHECK(!ALMissedAlarm(due, nil, D(@"2026-11-23 21:01")), "too soon to say");
    CHECK(!ALMissedAlarm(due, nil, D(@"2026-11-23 20:00")), "not due yet");
    CHECK(!ALMissedAlarm(nil, nil, D(@"2026-11-23 21:30")), "no alarm known");
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

int main(void) {
    @autoreleasepool {
        testStates();
        testRelease();
        testOpenAfterAlarm();
        testMissionDelay();
        testRingStart();
        testMissedAlarm();
        testNextAlarm();
        testTrustedClock();
    }
    printf("%d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
