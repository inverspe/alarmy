import Foundation

public struct PlannedNotification: Equatable {
    public let id: String
    public let fireDate: Date
    public let occurrence: OccurrenceKey

    public init(occurrence: OccurrenceKey, fireDate: Date) {
        self.id = "\(occurrence.alarmID)-\(Int(fireDate.timeIntervalSince1970))"
        self.fireDate = fireDate
        self.occurrence = occurrence
    }
}

/// Critical-alert backups that keep going off if the app is killed.
/// iOS allows 64 pending local notifications; this stays within `budget`.
public enum BackupPlanner {
    public static let interval: TimeInterval = 30
    public static let budget = 60
    public static let perOccurrenceMax = 40

    public static func plan(upcoming: [Occurrence], completed: Set<OccurrenceKey>,
                            session: RingSession?, now: Date) -> [PlannedNotification] {
        var result: [PlannedNotification] = []

        if let session, session.isRinging {
            for k in 1...perOccurrenceMax {
                let fireDate = now.addingTimeInterval(interval * Double(k))
                if case .countdown(let endsAt) = session.phase, fireDate >= endsAt { break }
                result.append(PlannedNotification(occurrence: session.occurrence, fireDate: fireDate))
            }
        }

        let pending = upcoming
            .filter { !completed.contains($0.key) && $0.key != session?.occurrence }
            .sorted { $0.fireDate < $1.fireDate }
        for occurrence in pending {
            for k in 0..<perOccurrenceMax where result.count < budget {
                result.append(PlannedNotification(occurrence: occurrence.key,
                                                  fireDate: occurrence.fireDate.addingTimeInterval(interval * Double(k))))
            }
        }

        return result.sorted { $0.fireDate < $1.fireDate }
    }
}
