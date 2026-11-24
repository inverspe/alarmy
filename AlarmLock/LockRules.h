// The lock's rules, kept free of UIKit and of Alarmy so they can be tested on a Mac.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ALLockState) {
    /// The lock is turned off. Alarms can be changed freely.
    ALLockStateOff,
    /// The lock is on, but the last alarm has been finished, so changes are allowed for now.
    ALLockStateOpen,
    /// The lock is on. Only finishing the next alarm opens it.
    ALLockStateLocked,
};

/// Choices for "lock this many hours before an alarm".
extern NSArray<NSNumber *> *ALHourChoices(void);
/// Choices for "missions can't start until this many minutes after the alarm goes off". 0 is off.
extern NSArray<NSNumber *> *ALDelayChoices(void);
/// The longest mission delay, whatever is saved.
extern const NSInteger ALMaxDelayMinutes;
/// With no alarm ringing for this long, the lock lets go by itself, in case something is broken.
extern const NSTimeInterval ALReleaseSeconds;

/// After an alarm has rung and its missions were done (`doneAt`), the lock stays open until the
/// hours before the next alarm begin, or until the next alarm rings when that is 0 hours. If the next
/// alarm is unknown it stays open for 12 hours. Nil when not open this way.
NSDate *_Nullable ALOpenAfterAlarmUntil(NSDate *_Nullable doneAt, NSInteger hoursBefore, NSDate *_Nullable nextAlarm, NSDate *now);

/// When the lock lets go by itself if no alarm rings: `ALReleaseSeconds` after the last sign of life
/// (the lock turned on or closed, or an alarm ringing or finishing).
NSDate *_Nullable ALReleaseAt(NSDate *_Nullable lastActivity);

/// `noAlarmsOn`: the alarms were read and none is on, so there's nothing to protect.
ALLockState ALLockStateAt(BOOL lockOn, NSDate *_Nullable openUntil, BOOL noAlarmsOn,
                          NSDate *_Nullable lastActivity, NSDate *now);

/// One alarm as read from Alarmy's data.
@interface ALAlarmRecord : NSObject
@property (nonatomic) BOOL enabled;
@property (nonatomic, nullable) NSDate *nextFireDate;
@property (nonatomic, nullable) NSDate *lastFiredDate;
/// Its sound settings, for the log.
@property (nonatomic, nullable, copy) NSString *detail;
@property (nonatomic) NSInteger hour;
@property (nonatomic) NSInteger minute;
+ (instancetype)enabled:(BOOL)enabled next:(nullable NSDate *)next hour:(NSInteger)hour minute:(NSInteger)minute;
@end

/// The soonest time an alarm that's on will ring. Uses Alarmy's own next fire date when it's in
/// the future, otherwise the next time the clock shows the alarm's hour and minute (which may be
/// earlier than the real next ring for an alarm that skips some days, so the lock errs strict).
NSDate *_Nullable ALNextAlarm(NSArray<ALAlarmRecord *> *alarms, NSDate *now, NSCalendar *calendar);

/// When the alarm that is ringing went off: the latest time any alarm fired in the last 2 hours.
/// Nil if none did.
NSDate *_Nullable ALRingStart(NSArray<ALAlarmRecord *> *alarms, NSDate *now);

/// While missions are held back after the alarm went off at `ringStart`, when they open. Nil when
/// they're available (no delay, delay over, or a start that makes no sense for `now`).
NSDate *_Nullable ALMissionsOpenAt(NSDate *_Nullable ringStart, NSInteger delayMinutes, NSDate *now);

/// An alarm was due at `due` and its ringing screen was never seen: more than 2 minutes have passed
/// and the screen last appeared (if ever) before the alarm was due.
BOOL ALMissedAlarm(NSDate *_Nullable due, NSDate *_Nullable lastRingSeen, NSDate *now);

/// "Now" that ignores changes to the phone's clock until the next restart. `anchor` holds an
/// earlier reading: wall (seconds since 1970), mono (seconds of CLOCK_MONOTONIC), boot.
NSDate *ALTrustedNow(NSDate *wall, double mono, NSString *_Nullable boot, NSDictionary *_Nullable anchor);
/// A fresh anchor when the wall clock can be trusted, otherwise the old one. Kept for a minute
/// at a time so it isn't rewritten every second.
NSDictionary *ALRefreshedAnchor(NSDictionary *_Nullable anchor, NSDate *wall, double mono, NSString *_Nullable boot);
BOOL ALSameBoot(NSDictionary *_Nullable anchor, double mono, NSString *_Nullable boot);

NS_ASSUME_NONNULL_END
