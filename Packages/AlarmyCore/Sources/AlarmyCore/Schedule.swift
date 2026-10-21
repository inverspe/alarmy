import Foundation

public enum Schedule {
    /// An occurrence counts as active (ringing or due) for at most this long after it fires.
    public static let hardCap: TimeInterval = 2 * 3600

    /// Next fire time strictly after `date`, in `calendar`'s time zone. Nil if disabled.
    public static func nextFireDate(for alarm: Alarm, after date: Date, calendar: Calendar) -> Date? {
        guard alarm.isEnabled else { return nil }
        let days: [Int?] = alarm.repeatDays.isEmpty ? [nil] : alarm.repeatDays.map { $0.rawValue }
        return days.compactMap { weekday in
            calendar.nextDate(after: date,
                              matching: DateComponents(hour: alarm.hour, minute: alarm.minute, second: 0, weekday: weekday),
                              matchingPolicy: .nextTime)
        }.min()
    }

    /// All occurrences with `from <= fireDate <= through`, sorted by fire date.
    public static func occurrences(_ alarms: [Alarm], from: Date, through: Date, calendar: Calendar) -> [Occurrence] {
        var result: [Occurrence] = []
        for alarm in alarms {
            var cursor = from.addingTimeInterval(-0.001)
            while let next = nextFireDate(for: alarm, after: cursor, calendar: calendar), next <= through {
                if next >= from { result.append(Occurrence(alarm: alarm, fireDate: next)) }
                cursor = next
            }
        }
        return result.sorted { $0.fireDate < $1.fireDate }
    }

    /// The soonest `limit` occurrences after `date`, across all alarms.
    public static func upcoming(_ alarms: [Alarm], after date: Date, calendar: Calendar, limit: Int) -> [Occurrence] {
        var result: [Occurrence] = []
        for alarm in alarms {
            var cursor = date
            for _ in 0..<limit {
                guard let next = nextFireDate(for: alarm, after: cursor, calendar: calendar) else { break }
                result.append(Occurrence(alarm: alarm, fireDate: next))
                cursor = next
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    /// Earliest occurrence with `fireDate <= now < fireDate + hardCap` that isn't completed.
    public static func activeOccurrence(_ alarms: [Alarm], completed: [OccurrenceKey: Date],
                                        now: Date, calendar: Calendar) -> Occurrence? {
        occurrences(alarms, from: now.addingTimeInterval(-hardCap), through: now, calendar: calendar)
            .first { now < $0.fireDate.addingTimeInterval(hardCap) && completed[$0.key] == nil }
    }
}
