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
}
