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

extension AppState {
    /// A session has run its course. An unlock opens everything up for a while and leaves the
    /// alarm to ring as usual. Anything else counts its alarm as done, and a one-time alarm turns off.
    public mutating func finish(_ session: RingSession, at finishedAt: Date, calendar: Calendar) {
        ringSession = nil
        if session.isUnlock {
            unlockedUntil = finishedAt.addingTimeInterval(TimeInterval(EditLock.unlockMinutes) * 60)
            return
        }
        completed = Completion.markFinished(session.occurrence, at: finishedAt, alarms: alarms,
                                            completed: completed, calendar: calendar)
        if let i = alarms.firstIndex(where: { $0.id == session.occurrence.alarmID }), alarms[i].repeatDays.isEmpty {
            alarms[i].isEnabled = false
        }
    }

    /// An early clear or unlock rings nothing, so it makes way the moment its own alarm time
    /// comes, or any other alarm is due.
    public mutating func yieldToDueAlarm(now: Date, calendar: Calendar) {
        guard let session = ringSession, session.isEarlyClear else { return }
        if now >= session.occurrence.fireDate
            || Schedule.activeOccurrence(alarms, completed: completed, now: now, calendar: calendar) != nil {
            ringSession = nil
        }
    }

    /// Forgets an unlock that has run out, or that was earned before a reboot (when the clock
    /// can't be checked), so changing the clock can never bring it back.
    public mutating func dropStaleUnlock(now: Date, sameBoot: Bool) {
        guard unlockedUntil != nil else { return }
        if !sameBoot || !EditLock.isUnlocked(unlockedUntil, now: now) { unlockedUntil = nil }
    }

    /// Misses that make the photo easier. An unlock keeps its own count, so trying during the
    /// day can't make the next ring easier.
    public func photoMissCount(for session: RingSession) -> Int {
        session.isUnlock ? session.unlockPhotoMisses : photoMisses
    }

    public mutating func recordPhoto(matched: Bool, in session: inout RingSession) {
        if session.isUnlock {
            if !matched { session.countUnlockPhotoMiss() }
        } else {
            photoMisses = matched ? 0 : photoMisses + 1
        }
    }
}
