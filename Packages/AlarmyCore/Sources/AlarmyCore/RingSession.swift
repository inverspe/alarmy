import Foundation

/// One morning's alarm: photo mission, then a countdown that keeps ringing, then
/// (if turned on) a wake-up check, then done.
public struct RingSession: Codable, Equatable {
    public enum Phase: Codable, Equatable {
        case mission
        case countdown(endsAt: Date)
        /// The ring has stopped; the wake-up check comes at `checkAt`.
        case wakeCheckWaiting(checkAt: Date)
        /// Asking "are you up?". No answer by `deadline` and the alarm starts over.
        case wakeCheckPrompt(deadline: Date)
        case finished
    }

    public static let missesBeforeSwitch = 5
    public static let wakeCheckResponseTime: TimeInterval = 100

    public let occurrence: OccurrenceKey
    public let ringAfterMinutes: Int
    /// Cleared before the alarm: nothing rings and a match finishes immediately.
    public let isEarlyClear: Bool
    public private(set) var phase: Phase
    public private(set) var currentObjectID: UUID?
    public private(set) var missesOnCurrent: Int
    public private(set) var triedObjectIDs: [UUID]
    // Optional so a session saved by an older build still loads.
    private let wakeCheckMinutesStored: Int?
    private var gentleSecondsStored: Int?
    private var missedWakeChecksStored: Int?
    private var missionsStored: [MissionStep]?
    private var missionIndexStored: Int?

    public var isRinging: Bool {
        guard !isEarlyClear else { return false }
        switch phase {
        case .mission, .countdown: return true
        case .wakeCheckWaiting, .wakeCheckPrompt, .finished: return false
        }
    }

    public var isAwaitingWakeCheck: Bool {
        switch phase {
        case .wakeCheckWaiting, .wakeCheckPrompt: return true
        case .mission, .countdown, .finished: return false
        }
    }

    /// What has to be done, in order. A session saved by an older build was photo only.
    public var missions: [MissionStep] { missionsStored ?? (currentObjectID == nil ? [] : [.photo]) }
    public var missionIndex: Int { missionIndexStored ?? 0 }
    public var hadMissions: Bool { !missions.isEmpty }

    /// The mission being done right now, if any.
    public var currentMission: MissionStep? {
        guard phase == .mission, missions.indices.contains(missionIndex) else { return nil }
        return missions[missionIndex]
    }

    public var missedWakeChecks: Int { missedWakeChecksStored ?? 0 }
    public var wakeCheckMinutes: Int { wakeCheckMinutesStored ?? 0 }

    /// No new ring starts from this moment on.
    private var hardCapDate: Date { occurrence.fireDate.addingTimeInterval(Schedule.hardCap) }

    /// When the first ring reaches full volume. Nil once it is at full volume for good.
    public var gentleEndsAt: Date? {
        guard let seconds = gentleSecondsStored, seconds > 0 else { return nil }
        return occurrence.fireDate.addingTimeInterval(TimeInterval(seconds))
    }

    public func ringLevel(now: Date) -> Float {
        guard let end = gentleEndsAt else { return 1 }
        return GentleRamp.level(elapsed: now.timeIntervalSince(occurrence.fireDate),
                                duration: end.timeIntervalSince(occurrence.fireDate))
    }

    /// A photo mission with no usable objects is dropped. With no missions left it rings
    /// for the countdown and then stops, so it can never ring forever.
    public static func start(occurrence: OccurrenceKey, ringAfterMinutes: Int, isEarlyClear: Bool,
                             objectIDs: [UUID], missions: [MissionStep] = [.photo], wakeCheckMinutes: Int = 0, gentleSeconds: Int = 0, now: Date,
                             using rng: inout some RandomNumberGenerator) -> RingSession {
        let wantsPhoto = missions.contains { $0.kind == .photo }
        let pick = wantsPhoto ? objectIDs.randomElement(using: &rng) : nil
        let missions = pick == nil ? missions.filter { $0.kind != .photo } : missions
        let phase: Phase
        if !missions.isEmpty {
            phase = .mission
        } else if isEarlyClear {
            phase = .finished
        } else {
            phase = .countdown(endsAt: now.addingTimeInterval(TimeInterval(ringAfterMinutes) * 60))
        }
        return RingSession(occurrence: occurrence, ringAfterMinutes: ringAfterMinutes, isEarlyClear: isEarlyClear,
                           phase: phase, currentObjectID: pick, missesOnCurrent: 0,
                           triedObjectIDs: pick.map { [$0] } ?? [],
                           wakeCheckMinutesStored: wakeCheckMinutes, gentleSecondsStored: gentleSeconds,
                           missedWakeChecksStored: 0, missionsStored: missions, missionIndexStored: 0)
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

    /// Moves on to the next mission. After the last one, the countdown starts.
    public mutating func completeMission(now: Date) {
        guard phase == .mission else { return }
        if missionIndex + 1 < missions.count {
            missionIndexStored = missionIndex + 1
            return
        }
        phase = isEarlyClear
            ? .finished
            : .countdown(endsAt: now.addingTimeInterval(TimeInterval(ringAfterMinutes) * 60))
    }

    /// The owner answered the wake-up check.
    public mutating func confirmAwake() {
        guard case .wakeCheckPrompt = phase else { return }
        phase = .finished
    }

    public mutating func tick(now: Date) {
        var unused = SystemRandomNumberGenerator()
        tick(now: now, availableObjectIDs: [], using: &unused)
    }

    /// Moves on when a phase's time is up, catching up through several phases at once if the
    /// app was closed. An unfinished mission gives up at the hard cap, so a mission that
    /// can't be completed never rings forever.
    public mutating func tick(now: Date, availableObjectIDs: [UUID], using rng: inout some RandomNumberGenerator) {
        while true {
            switch phase {
            case .countdown(let endsAt) where now >= endsAt:
                if wakeCheckMinutes > 0 && endsAt < hardCapDate {
                    phase = .wakeCheckWaiting(checkAt: endsAt.addingTimeInterval(TimeInterval(wakeCheckMinutes) * 60))
                } else {
                    phase = .finished
                }
            case .wakeCheckWaiting(let checkAt) where now >= checkAt:
                phase = .wakeCheckPrompt(deadline: checkAt.addingTimeInterval(Self.wakeCheckResponseTime))
            case .wakeCheckPrompt(let deadline) where now >= deadline:
                startOver(now: now, availableObjectIDs: availableObjectIDs, using: &rng)
                return
            case .mission where now >= hardCapDate:
                phase = .finished
            default:
                return
            }
        }
    }

    /// A missed wake-up check: ring again at full volume and do every mission again,
    /// on a different object when there is one.
    private mutating func startOver(now: Date, availableObjectIDs: [UUID], using rng: inout some RandomNumberGenerator) {
        guard now < hardCapDate else {
            phase = .finished
            return
        }
        missedWakeChecksStored = missedWakeChecks + 1
        gentleSecondsStored = nil
        missesOnCurrent = 0
        missionIndexStored = 0
        if missions.contains(where: { $0.kind == .photo }) {
            let others = availableObjectIDs.filter { $0 != currentObjectID }
            currentObjectID = others.randomElement(using: &rng) ?? currentObjectID
            triedObjectIDs = currentObjectID.map { [$0] } ?? []
        }
        phase = missions.isEmpty
            ? .countdown(endsAt: now.addingTimeInterval(TimeInterval(ringAfterMinutes) * 60))
            : .mission
    }
}
