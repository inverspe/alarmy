import Foundation

public enum EditLock {
    private static let maxLockHours: TimeInterval = 12 * 3600

    /// The occurrence currently holding the edit lock, or nil if editing is allowed.
    /// An occurrence locks from `lockHours` before it fires until it is completed,
    /// or until `Schedule.hardCap` after firing if it never is. An unfinished
    /// ring session (`session`) always holds the lock.
    public static func lockedUntilDone(_ alarms: [Alarm], completed: [OccurrenceKey: Date], session: Occurrence?,
                                       now: Date, calendar: Calendar) -> Occurrence? {
        if let session { return session }
        return Schedule.occurrences(alarms, from: now.addingTimeInterval(-Schedule.hardCap),
                                    through: now.addingTimeInterval(maxLockHours), calendar: calendar)
            .first { occurrence in
                let start = occurrence.fireDate.addingTimeInterval(-TimeInterval(occurrence.alarm.lockHours) * 3600)
                let end = completed[occurrence.key] ?? occurrence.fireDate.addingTimeInterval(Schedule.hardCap)
                return start <= now && now < end
            }
    }

    /// The upcoming occurrence that can be cleared early right now, if any:
    /// `now` is within `earlyClearMinutes` before it fires and it isn't completed.
    public static func earlyClearable(_ alarms: [Alarm], completed: [OccurrenceKey: Date],
                                      now: Date, calendar: Calendar) -> Occurrence? {
        Schedule.occurrences(alarms, from: now, through: now.addingTimeInterval(3600), calendar: calendar)
            .first { occurrence in
                let minutes = occurrence.alarm.earlyClearMinutes
                return minutes > 0
                    && now < occurrence.fireDate
                    && now >= occurrence.fireDate.addingTimeInterval(-TimeInterval(minutes) * 60)
                    && completed[occurrence.key] == nil
            }
    }
}
