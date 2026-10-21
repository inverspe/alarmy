import Foundation

public enum Completion {
    private static let retention: TimeInterval = 7 * 24 * 3600

    /// Marks `key` done at `finishedAt`, along with every other occurrence that fired
    /// during the session (one mission covers overlapping alarms). Drops entries older than 7 days.
    public static func markFinished(_ key: OccurrenceKey, at finishedAt: Date, alarms: [Alarm],
                                    completed: [OccurrenceKey: Date], calendar: Calendar) -> [OccurrenceKey: Date] {
        var result = completed.filter { $0.key.fireDate >= finishedAt.addingTimeInterval(-retention) }
        result[key] = finishedAt
        for occurrence in Schedule.occurrences(alarms, from: key.fireDate, through: finishedAt, calendar: calendar)
        where result[occurrence.key] == nil {
            result[occurrence.key] = finishedAt
        }
        return result
    }

    /// For alarms that are new, newly enabled, or moved to a different time or days,
    /// occurrences that already fired within the hard cap count as done — so saving an
    /// edit never makes an alarm ring straight away.
    public static func suppressFired(old: [Alarm], new: [Alarm], completed: [OccurrenceKey: Date],
                                     now: Date, calendar: Calendar) -> [OccurrenceKey: Date] {
        let changed = new.filter { alarm in
            guard alarm.isEnabled else { return false }
            guard let before = old.first(where: { $0.id == alarm.id }) else { return true }
            return !before.isEnabled || before.hour != alarm.hour || before.minute != alarm.minute
                || before.repeatDays != alarm.repeatDays
        }
        var result = completed
        for occurrence in Schedule.occurrences(changed, from: now.addingTimeInterval(-Schedule.hardCap),
                                               through: now, calendar: calendar)
        where result[occurrence.key] == nil {
            result[occurrence.key] = now
        }
        return result
    }
}
