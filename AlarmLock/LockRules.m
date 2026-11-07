#import "LockRules.h"
#import <math.h>

const NSTimeInterval ALUnlockSeconds = 10 * 60;
const NSInteger ALSumsPerUnlock = 3;
static const NSTimeInterval ALClockTolerance = 120;

NSArray<NSNumber *> *ALHourChoices(void) {
    return @[@0, @1, @2, @3, @4, @6, @8, @12];
}

/// Boot IDs match, counting "unavailable" on both sides as a match so a phone that won't say
/// still gets a working lock (falling back to the uptime check).
static BOOL ALSameBootID(NSString *a, NSString *b) {
    return [(a ?: @"") isEqualToString:(b ?: @"")];
}

BOOL ALIsUnlocked(NSDate *until, NSString *untilBoot, NSString *boot, NSDate *now) {
    if (!until) return NO;
    if (!ALSameBootID(untilBoot, boot)) return NO;
    NSTimeInterval t = now.timeIntervalSince1970, end = until.timeIntervalSince1970;
    return t < end && t >= end - ALUnlockSeconds;
}

BOOL ALIsSealed(NSInteger hoursBefore, NSDate *nextAlarm, NSDate *now) {
    if (hoursBefore <= 0 || !nextAlarm) return NO;
    NSTimeInterval t = now.timeIntervalSince1970, fire = nextAlarm.timeIntervalSince1970;
    return t < fire && t >= fire - (NSTimeInterval)hoursBefore * 3600;
}

ALLockState ALLockStateAt(BOOL lockOn, NSInteger hoursBefore, NSDate *nextAlarm, BOOL unlocked, NSDate *now) {
    if (!lockOn) return ALLockStateOff;
    if (ALIsSealed(hoursBefore, nextAlarm, now)) return ALLockStateSealed;
    return unlocked ? ALLockStateOpen : ALLockStateLocked;
}

@implementation ALAlarmRecord
+ (instancetype)enabled:(BOOL)enabled next:(NSDate *)next hour:(NSInteger)hour minute:(NSInteger)minute {
    ALAlarmRecord *r = [ALAlarmRecord new];
    r.enabled = enabled;
    r.nextFireDate = next;
    r.hour = hour;
    r.minute = minute;
    return r;
}
@end

NSDate *ALNextAlarm(NSArray<ALAlarmRecord *> *alarms, NSDate *now, NSCalendar *calendar) {
    NSDate *best = nil;
    for (ALAlarmRecord *alarm in alarms) {
        if (!alarm.enabled) continue;
        NSDate *fire = nil;
        if (alarm.nextFireDate && [alarm.nextFireDate compare:now] == NSOrderedDescending) {
            fire = alarm.nextFireDate;
        } else if (alarm.hour >= 0 && alarm.hour < 24 && alarm.minute >= 0 && alarm.minute < 60) {
            NSDateComponents *c = [NSDateComponents new];
            c.hour = alarm.hour;
            c.minute = alarm.minute;
            c.second = 0;
            fire = [calendar nextDateAfterDate:now matchingComponents:c options:NSCalendarMatchNextTime];
        }
        if (fire && (!best || [fire compare:best] == NSOrderedAscending)) best = fire;
    }
    return best;
}

static NSDate *ALDerived(NSDictionary *anchor, double mono, NSString *boot) {
    if (!anchor) return nil;
    NSString *anchorBoot = anchor[@"boot"];
    NSNumber *wall = anchor[@"wall"], *anchorMono = anchor[@"mono"];
    if (![wall isKindOfClass:NSNumber.class] || ![anchorMono isKindOfClass:NSNumber.class]) return nil;
    if (!ALSameBootID(anchorBoot, boot)) return nil;
    if (mono < anchorMono.doubleValue) return nil;
    return [NSDate dateWithTimeIntervalSince1970:wall.doubleValue + (mono - anchorMono.doubleValue)];
}

BOOL ALSameBoot(NSDictionary *anchor, double mono, NSString *boot) {
    return ALDerived(anchor, mono, boot) != nil;
}

NSDate *ALTrustedNow(NSDate *wall, double mono, NSString *boot, NSDictionary *anchor) {
    NSDate *derived = ALDerived(anchor, mono, boot);
    if (!derived) return wall;
    return fabs([wall timeIntervalSinceDate:derived]) <= ALClockTolerance ? wall : derived;
}

NSDictionary *ALRefreshedAnchor(NSDictionary *anchor, NSDate *wall, double mono, NSString *boot) {
    NSDate *derived = ALDerived(anchor, mono, boot);
    if (derived) {
        if (fabs([wall timeIntervalSinceDate:derived]) > ALClockTolerance) return anchor; // clock was moved: keep trusting the old reading
        if (wall.timeIntervalSince1970 - [anchor[@"wall"] doubleValue] < 60) return anchor;
    }
    return @{ @"wall": @(wall.timeIntervalSince1970), @"mono": @(mono), @"boot": boot ?: @"" };
}

ALSum ALMakeSum(uint32_t (*pick)(uint32_t upperBound)) {
    ALSum sum;
    sum.a = 10 + pick(90);
    sum.b = 2 + pick(8);
    sum.c = 10 + pick(90);
    return sum;
}

NSInteger ALSumAnswer(ALSum sum) {
    return sum.a * sum.b + sum.c;
}
