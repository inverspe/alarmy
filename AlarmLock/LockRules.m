#import "LockRules.h"
#import <math.h>

const NSInteger ALMaxDelayMinutes = 30;
const NSTimeInterval ALReleaseSeconds = 4 * 24 * 3600;
static const NSTimeInterval ALClockTolerance = 120;
static const NSTimeInterval ALRingLookback = 2 * 3600;

NSArray<NSNumber *> *ALHourChoices(void) {
    return @[@1, @2, @3, @4, @6, @8, @12];
}

NSArray<NSNumber *> *ALDelayChoices(void) {
    return @[@0, @1, @2, @3, @5, @10, @15, @20, @30];
}

NSDate *ALOpenAfterAlarmUntil(NSDate *doneAt, NSInteger hoursBefore, NSDate *nextAlarm, NSDate *now) {
    if (!doneAt || [now compare:doneAt] == NSOrderedAscending) return nil;
    NSDate *end;
    if (!nextAlarm) end = [doneAt dateByAddingTimeInterval:12 * 3600];
    else if (hoursBefore > 0) end = [nextAlarm dateByAddingTimeInterval:-(NSTimeInterval)hoursBefore * 3600];
    else end = nextAlarm;
    return [now compare:end] == NSOrderedAscending ? end : nil;
}

NSDate *ALReleaseAt(NSDate *lastActivity) {
    return lastActivity ? [lastActivity dateByAddingTimeInterval:ALReleaseSeconds] : nil;
}

ALLockState ALLockStateAt(BOOL lockOn, NSDate *openUntil, BOOL noAlarmsOn, NSDate *lastActivity, NSDate *now) {
    if (!lockOn) return ALLockStateOff;
    if (openUntil || noAlarmsOn) return ALLockStateOpen;
    NSDate *release = ALReleaseAt(lastActivity);
    if (release && [now compare:release] != NSOrderedAscending) return ALLockStateOpen;
    return ALLockStateLocked;
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

NSDate *ALRingStart(NSArray<ALAlarmRecord *> *alarms, NSDate *now) {
    NSDate *best = nil;
    for (ALAlarmRecord *alarm in alarms) {
        NSDate *fired = alarm.lastFiredDate;
        if (!fired) continue;
        NSTimeInterval ago = [now timeIntervalSinceDate:fired];
        if (ago < 0 || ago > ALRingLookback) continue;
        if (!best || [fired compare:best] == NSOrderedDescending) best = fired;
    }
    return best;
}

NSDate *ALMissionsOpenAt(NSDate *ringStart, NSInteger delayMinutes, NSDate *now) {
    if (!ringStart || delayMinutes <= 0) return nil;
    NSInteger minutes = MIN(delayMinutes, ALMaxDelayMinutes);
    // A start in the future means the clock jumped: never hold missions back for that.
    if ([now timeIntervalSinceDate:ringStart] < -60) return nil;
    NSDate *end = [ringStart dateByAddingTimeInterval:(NSTimeInterval)minutes * 60];
    return [now compare:end] == NSOrderedAscending ? end : nil;
}

/// Boot IDs match, counting "unavailable" on both sides as a match so a phone that won't say
/// still gets a working clock check (falling back to the uptime check).
static BOOL ALSameBootID(NSString *a, NSString *b) {
    return [(a ?: @"") isEqualToString:(b ?: @"")];
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
