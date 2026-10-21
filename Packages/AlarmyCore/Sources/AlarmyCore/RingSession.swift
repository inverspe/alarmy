import Foundation

/// One morning's alarm: photo mission, then a countdown that keeps ringing, then done.
public struct RingSession: Codable, Equatable {
    public enum Phase: Codable, Equatable {
        case mission
        case countdown(endsAt: Date)
        case finished
    }

    public static let missesBeforeSwitch = 5

    public let occurrence: OccurrenceKey
    public let ringAfterMinutes: Int
    /// Cleared before the alarm: nothing rings and a match finishes immediately.
    public let isEarlyClear: Bool
    public private(set) var phase: Phase
    public private(set) var currentObjectID: UUID?
    public private(set) var missesOnCurrent: Int
    public private(set) var triedObjectIDs: [UUID]

    public var isRinging: Bool { !isEarlyClear && phase != .finished }

    /// With no usable objects there is no mission: it rings for the countdown and then
    /// stops, so it can never ring forever.
    public static func start(occurrence: OccurrenceKey, ringAfterMinutes: Int, isEarlyClear: Bool,
                             objectIDs: [UUID], now: Date,
                             using rng: inout some RandomNumberGenerator) -> RingSession {
        let pick = objectIDs.randomElement(using: &rng)
        let phase: Phase
        if pick != nil {
            phase = .mission
        } else if isEarlyClear {
            phase = .finished
        } else {
            phase = .countdown(endsAt: now.addingTimeInterval(TimeInterval(ringAfterMinutes) * 60))
        }
        return RingSession(occurrence: occurrence, ringAfterMinutes: ringAfterMinutes, isEarlyClear: isEarlyClear,
                           phase: phase, currentObjectID: pick, missesOnCurrent: 0,
                           triedObjectIDs: pick.map { [$0] } ?? [])
    }

    /// After `missesBeforeSwitch` misses, switches to another available object,
    /// preferring ones not tried yet this session.
    public mutating func recordMiss(availableObjectIDs: [UUID], using rng: inout some RandomNumberGenerator) {
        guard phase == .mission else { return }
        missesOnCurrent += 1
        guard missesOnCurrent >= Self.missesBeforeSwitch else { return }
        missesOnCurrent = 0
        let candidates = availableObjectIDs.filter { $0 != currentObjectID }
        guard !candidates.isEmpty else { return }
        var untried = candidates.filter { !triedObjectIDs.contains($0) }
        if untried.isEmpty {
            triedObjectIDs = currentObjectID.map { [$0] } ?? []
            untried = candidates
        }
        let next = untried.randomElement(using: &rng)!
        currentObjectID = next
        triedObjectIDs.append(next)
    }

    public mutating func recordMatch(now: Date) {
        guard phase == .mission else { return }
        phase = isEarlyClear
            ? .finished
            : .countdown(endsAt: now.addingTimeInterval(TimeInterval(ringAfterMinutes) * 60))
    }

    /// Ends the countdown when it runs out. An unfinished mission gives up at the
    /// hard cap, so a mission that can't be completed never rings forever.
    public mutating func tick(now: Date) {
        switch phase {
        case .countdown(let endsAt) where now >= endsAt:
            phase = .finished
        case .mission where now >= occurrence.fireDate.addingTimeInterval(Schedule.hardCap):
            phase = .finished
        default:
            break
        }
    }
}
