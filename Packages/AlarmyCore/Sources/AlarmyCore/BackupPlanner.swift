import Foundation

public struct PlannedNotification: Equatable {
    public enum Kind: String, Equatable {
        /// Keeps the alarm going if the app is closed.
        case alarm
        /// The quiet "are you up?" prompt.
        case wakeCheck
        /// A silent banner in the first minute of a ring, which lights up the lock screen.
        case nudge
    }

    public let id: String
    public let fireDate: Date
    public let occurrence: OccurrenceKey
    public let kind: Kind

    public init(occurrence: OccurrenceKey, fireDate: Date, kind: Kind = .alarm) {
        let base = "\(occurrence.alarmID)-\(Int(fireDate.timeIntervalSince1970))"
        self.id = kind == .alarm ? base : "\(base)-\(kind.rawValue)"
        self.fireDate = fireDate
        self.occurrence = occurrence
        self.kind = kind
    }
}

/// Backups that keep going off if the app is killed, including the wake-up check.
/// iOS allows 64 pending local notifications; this stays within `budget`.
public enum BackupPlanner {
    public static let interval: TimeInterval = 30
    public static let budget = 60
    public static let perOccurrenceMax = 40
    /// With a wake-up check still to come, the budget is shared between the ring now and the repeat later.
    static let ringMaxBeforeCheck = 25
    static let repeatMax = 30
    /// The "you closed the app" notice appears this long after closing.
    public static let appClosedNoticeDelay: TimeInterval = 2.5
    /// Closing waits this long, because handing a notification to iOS takes a moment and the process is about to end.
    public static let appClosedHold: TimeInterval = 2
    /// With the app closed, the first sound never waits longer than this for a gentle wake-up.
    public static let longestGentleWait = 60
    /// While a long gentle wake-up runs, the running app keeps the next backup at least this far off.
    /// More than the 60 seconds between replans, so it stays clear of the ramp unless the app is gone.
    static let gentleSlide: TimeInterval = 90
    static let nudgeCount = 10
    static let firstNudge: TimeInterval = 1.5
    static let nudgeGap: TimeInterval = 6

    /// Plans use trusted time, but calendar triggers fire by the clock on screen. This is
    /// what the screen will show at `fireDate` when the phone's clock has been changed by hand.
    public static func wallClockFireDate(_ fireDate: Date, wall: Date, trusted: Date) -> Date {
        fireDate.addingTimeInterval(wall.timeIntervalSince(trusted))
    }

    public static func plan(upcoming: [Occurrence], completed: Set<OccurrenceKey>,
                            session: RingSession?, now: Date) -> [PlannedNotification] {
        var result: [PlannedNotification] = []

        if let session {
            switch session.phase {
            case .mission where session.isRinging:
                result += nudges(session, now: now) + ring(session, count: perOccurrenceMax, until: nil, now: now)
            case .countdown(let endsAt) where session.isRinging:
                let checkAt = session.wakeCheckMinutes > 0
                    ? endsAt.addingTimeInterval(TimeInterval(session.wakeCheckMinutes) * 60) : nil
                result += ring(session, count: checkAt == nil ? perOccurrenceMax : ringMaxBeforeCheck, until: endsAt, now: now)
                if let checkAt { result += wakeCheck(session, at: checkAt) }
            case .wakeCheckWaiting(let checkAt):
                result += wakeCheck(session, at: checkAt)
            case .wakeCheckPrompt(let deadline):
                result += repeatRing(session, from: deadline)
            default:
                break
            }
        }

        let pending = upcoming
            .filter { !completed.contains($0.key) && $0.key != session?.occurrence }
            .sorted { $0.fireDate < $1.fireDate }
        for occurrence in pending {
            let first = occurrence.fireDate.addingTimeInterval(TimeInterval(occurrence.alarm.gentleSeconds))
            for k in 0..<perOccurrenceMax where result.count < budget {
                result.append(PlannedNotification(occurrence: occurrence.key,
                                                  fireDate: first.addingTimeInterval(interval * Double(k))))
            }
        }

        return result.sorted { $0.fireDate < $1.fireDate }
    }

    /// Counted from the alarm time. One less than a second away could be too late to schedule.
    private static func nudges(_ session: RingSession, now: Date) -> [PlannedNotification] {
        (0..<nudgeCount)
            .map { session.occurrence.fireDate.addingTimeInterval(firstNudge + nudgeGap * Double($0)) }
            .filter { $0.timeIntervalSince(now) > 1000 }
            .map { PlannedNotification(occurrence: session.occurrence, fireDate: $0, kind: .nudge) }
    }

    /// Backups for a ring in progress, sliding forward from `now`. They hold off until
    /// a gentle wake-up has finished, so they don't cut across it at full volume.
    private static func ring(_ session: RingSession, count: Int, until end: Date?, now: Date) -> [PlannedNotification] {
        var base = now
        if let gentleEnd = session.gentleEndsAt, gentleEnd > now {
            base = gentleEnd.addingTimeInterval(-interval)
        }
        var result: [PlannedNotification] = []
        for k in 1...count {
            let fireDate = base.addingTimeInterval(interval * Double(k))
            if let end, fireDate >= end { break }
            result.append(PlannedNotification(occurrence: session.occurrence, fireDate: fireDate))
        }
        return result
    }

    private static func wakeCheck(_ session: RingSession, at checkAt: Date) -> [PlannedNotification] {
        [PlannedNotification(occurrence: session.occurrence, fireDate: checkAt, kind: .wakeCheck)]
            + repeatRing(session, from: checkAt.addingTimeInterval(RingSession.wakeCheckResponseTime))
    }

    /// The ring that follows a missed check, if the app isn't there to start it. Stops at the hard cap.
    private static func repeatRing(_ session: RingSession, from deadline: Date) -> [PlannedNotification] {
        let cap = session.occurrence.fireDate.addingTimeInterval(Schedule.hardCap)
        return (0..<repeatMax)
            .map { deadline.addingTimeInterval(interval * Double($0)) }
            .filter { $0 < cap }
            .map { PlannedNotification(occurrence: session.occurrence, fireDate: $0) }
    }
}
