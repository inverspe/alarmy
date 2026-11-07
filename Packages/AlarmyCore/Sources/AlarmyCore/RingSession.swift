import Foundation

/// One morning's alarm: photo mission, then a countdown that keeps ringing, then
/// (if turned on) a wake-up check, then done.
public struct RingSession: Codable, Equatable {
    public enum Phase: Codable, Equatable {
        case mission
        /// The ring has stopped for now. It comes back at `until`, and the mission still has to be done.
        case snoozed(until: Date)
        case countdown(endsAt: Date)
        /// The ring has stopped; the wake-up check comes at `checkAt`.
        case wakeCheckWaiting(checkAt: Date)
        /// Asking "are you up?". No answer by `deadline` and the alarm starts over.
        case wakeCheckPrompt(deadline: Date)
        case finished
    }

    public static let missesBeforeSwitch = 5
    public static let wakeCheckResponseTime: TimeInterval = 100
    /// Minutes after the ring stops to ask "are you up?" (0 = off).
    public static let wakeCheckChoices = [0, 1, 3, 5, 7, 10]

    public let occurrence: OccurrenceKey
    public let ringAfterMinutes: Int
    /// Before the alarm: nothing rings, it can be backed out of, and the last mission finishes it.
    /// True for unlocks too.
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
    private var ringStartStored: Date?
    private var snoozeMinutesStored: Int?
    private var snoozeLimitStored: Int?
    private var snoozeCountStored: Int?
    private var unlockStored: Bool?

    /// Doing the missions of an alarm that can't be turned off, to open up changes.
    /// The alarm itself still rings as usual.
    public var isUnlock: Bool { unlockStored ?? false }

    public var isRinging: Bool {
        guard !isEarlyClear else { return false }
        switch phase {
        case .mission, .countdown: return true
        case .snoozed, .wakeCheckWaiting, .wakeCheckPrompt, .finished: return false
        }
    }

    public var isAwaitingWakeCheck: Bool {
        switch phase {
        case .wakeCheckWaiting, .wakeCheckPrompt: return true
        case .mission, .snoozed, .countdown, .finished: return false
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

    /// When the current ring began: the alarm time, or later after a snooze or a missed check.
    public var ringStart: Date { ringStartStored ?? occurrence.fireDate }
    public var gentleSeconds: Int { gentleSecondsStored ?? 0 }

    /// When this ring reaches full volume. Nil once it is at full volume for good.
    public var gentleEndsAt: Date? {
        guard gentleSeconds > 0 else { return nil }
        return ringStart.addingTimeInterval(TimeInterval(gentleSeconds))
    }

    public func ringLevel(now: Date) -> Float {
        guard let end = gentleEndsAt else { return 1 }
        return GentleRamp.level(elapsed: now.timeIntervalSince(ringStart), duration: end.timeIntervalSince(ringStart))
    }

    public var snoozeMinutes: Int { snoozeMinutesStored ?? 0 }
    public var snoozeCount: Int { snoozeCountStored ?? 0 }

    /// How many snoozes are left. Nil when there's no limit.
    public var snoozesLeft: Int? {
        guard let limit = snoozeLimitStored, limit >= 0 else { return nil }
        return max(0, limit - snoozeCount)
    }

    /// Snoozing is only for a ring that hasn't been answered, and never past the hard cap.
    public func canSnooze(now: Date) -> Bool {
        guard phase == .mission, !isEarlyClear, snoozeMinutes > 0 else { return false }
        if let left = snoozesLeft, left < 1 { return false }
        return now.addingTimeInterval(TimeInterval(snoozeMinutes) * 60) < hardCapDate
    }

    public mutating func snooze(now: Date) {
        guard canSnooze(now: now) else { return }
        snoozeCountStored = snoozeCount + 1
        phase = .snoozed(until: now.addingTimeInterval(TimeInterval(snoozeMinutes) * 60))
    }

    /// The owner chose not to wait: it rings again now.
    public mutating func endSnooze(now: Date) {
        guard case .snoozed = phase else { return }
        ringStartStored = now
        phase = .mission
    }

    /// A photo mission with no usable objects is dropped. With no missions left it rings
    /// for the countdown and then stops, so it can never ring forever.
    /// An unlock is always a session before the alarm, like an early clear.
    public static func start(occurrence: OccurrenceKey, ringAfterMinutes: Int, isEarlyClear: Bool, isUnlock: Bool = false,
                             objectIDs: [UUID], missions: [MissionStep] = [.photo], wakeCheckMinutes: Int = 0, gentleSeconds: Int = 0,
                             snoozeMinutes: Int = 0, snoozeLimit: Int = -1, now: Date,
                             using rng: inout some RandomNumberGenerator) -> RingSession {
        let isEarlyClear = isEarlyClear || isUnlock
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
                           missedWakeChecksStored: 0, missionsStored: missions, missionIndexStored: 0,
                           snoozeMinutesStored: snoozeMinutes, snoozeLimitStored: snoozeLimit, snoozeCountStored: 0,
                           unlockStored: isUnlock ? true : nil)
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

    /// Back to the first mission, for when a mission ran out of time.
    public mutating func restartMissions() {
        guard phase == .mission else { return }
        missionIndexStored = 0
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
            case .snoozed(let until) where now >= until:
                ringStartStored = until
                phase = .mission
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
        ringStartStored = now
        snoozeCountStored = 0
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
