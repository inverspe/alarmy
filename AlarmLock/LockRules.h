// The lock's rules, kept free of UIKit and of Alarmy so they can be tested on a Mac.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ALLockState) {
    /// The lock is turned off. Alarms can be changed freely.
    ALLockStateOff,
    /// The lock is on, but the sums were done a moment ago, so changes are allowed for now.
    ALLockStateOpen,
    /// The lock is on. Doing the sums opens it for a while.
    ALLockStateLocked,
    /// The lock is on and the next alarm is close. Nothing opens it until the alarm has rung.
    ALLockStateSealed,
};

/// How long the sums open the lock for.
extern const NSTimeInterval ALUnlockSeconds;
/// Sums to do for one unlock.
extern const NSInteger ALSumsPerUnlock;
/// Choices for "hours before the alarm when nothing unlocks". 0 means never sealed.
extern NSArray<NSNumber *> *ALHourChoices(void);

/// An unlock only counts in the minutes after it was earned, in the same boot, so turning the
/// clock back or restarting the phone can't bring an old one back.
BOOL ALIsUnlocked(NSDate *_Nullable until, NSString *_Nullable untilBoot, NSString *_Nullable boot, NSDate *now);

/// After an alarm has rung and its missions were done (`doneAt`), the lock stays open until the
/// hours before the next alarm begin, or until the next alarm rings when that is 0 hours. If the next
/// alarm is unknown it stays open for 12 hours. Nil when not open this way.
NSDate *_Nullable ALOpenAfterAlarmUntil(NSDate *_Nullable doneAt, NSInteger hoursBefore, NSDate *_Nullable nextAlarm, NSDate *now);

/// Inside the hours before the next alarm.
BOOL ALIsSealed(NSInteger hoursBefore, NSDate *_Nullable nextAlarm, NSDate *now);

ALLockState ALLockStateAt(BOOL lockOn, NSInteger hoursBefore, NSDate *_Nullable nextAlarm,
                          BOOL unlocked, NSDate *now);

/// One alarm as read from Alarmy's data.
@interface ALAlarmRecord : NSObject
@property (nonatomic) BOOL enabled;
@property (nonatomic, nullable) NSDate *nextFireDate;
@property (nonatomic) NSInteger hour;
@property (nonatomic) NSInteger minute;
+ (instancetype)enabled:(BOOL)enabled next:(nullable NSDate *)next hour:(NSInteger)hour minute:(NSInteger)minute;
@end

/// The soonest time an alarm that's on will ring. Uses Alarmy's own next fire date when it's in
/// the future, otherwise the next time the clock shows the alarm's hour and minute (which may be
/// earlier than the real next ring for an alarm that skips some days, so the lock errs strict).
NSDate *_Nullable ALNextAlarm(NSArray<ALAlarmRecord *> *alarms, NSDate *now, NSCalendar *calendar);

/// "Now" that ignores changes to the phone's clock until the next restart. `anchor` holds an
/// earlier reading: wall (seconds since 1970), mono (seconds of CLOCK_MONOTONIC), boot.
NSDate *ALTrustedNow(NSDate *wall, double mono, NSString *_Nullable boot, NSDictionary *_Nullable anchor);
/// A fresh anchor when the wall clock can be trusted, otherwise the old one. Kept for a minute
/// at a time so it isn't rewritten every second.
NSDictionary *ALRefreshedAnchor(NSDictionary *_Nullable anchor, NSDate *wall, double mono, NSString *_Nullable boot);
BOOL ALSameBoot(NSDictionary *_Nullable anchor, double mono, NSString *_Nullable boot);

/// a × b + c, with a two digits, b one digit (2–9) and c two digits.
typedef struct { NSInteger a, b, c; } ALSum;
ALSum ALMakeSum(uint32_t (*pick)(uint32_t upperBound));
NSInteger ALSumAnswer(ALSum sum);

NS_ASSUME_NONNULL_END
