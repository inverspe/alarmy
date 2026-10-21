import Foundation

public enum AlarmSound: String, Codable, CaseIterable {
    case klaxon, beeper, siren
}

/// Raw values match `Calendar.component(.weekday, …)`.
public enum Weekday: Int, Codable, CaseIterable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}

public struct Alarm: Codable, Identifiable, Equatable {
    public var id: UUID
    public var hour: Int
    public var minute: Int
    /// Empty means a one-time alarm.
    public var repeatDays: Set<Weekday>
    public var isEnabled: Bool
    public var sound: AlarmSound
    /// How long it keeps ringing after the mission is done (1–60).
    public var ringAfterMinutes: Int
    /// Edits are locked this many hours before the alarm (0–12).
    public var lockHours: Int
    /// Minutes before the alarm during which it can be cleared early (0 = off).
    public var earlyClearMinutes: Int

    public init(id: UUID = UUID(), hour: Int, minute: Int, repeatDays: Set<Weekday> = [],
                isEnabled: Bool = true, sound: AlarmSound = .klaxon, ringAfterMinutes: Int = 10,
                lockHours: Int = 8, earlyClearMinutes: Int = 30) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.sound = sound
        self.ringAfterMinutes = ringAfterMinutes
        self.lockHours = lockHours
        self.earlyClearMinutes = earlyClearMinutes
    }

    enum CodingKeys: String, CodingKey {
        case id, hour, minute, repeatDays, isEnabled, sound, ringAfterMinutes, lockHours, earlyClearMinutes
    }

    /// Missing fields fall back to defaults, so a state file from an older build still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        repeatDays = try c.decodeIfPresent(Set<Weekday>.self, forKey: .repeatDays) ?? []
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sound = (try? c.decodeIfPresent(AlarmSound.self, forKey: .sound)) ?? .klaxon
        ringAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .ringAfterMinutes) ?? 10
        lockHours = try c.decodeIfPresent(Int.self, forKey: .lockHours) ?? 8
        earlyClearMinutes = try c.decodeIfPresent(Int.self, forKey: .earlyClearMinutes) ?? 30
    }
}

public struct RegisteredObject: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var referencePhotoIDs: [UUID]

    public init(id: UUID = UUID(), name: String, referencePhotoIDs: [UUID]) {
        self.id = id
        self.name = name
        self.referencePhotoIDs = referencePhotoIDs
    }
}

public enum Strictness: String, Codable, CaseIterable {
    case loose, medium, strict
}

/// One specific firing of an alarm.
public struct OccurrenceKey: Hashable, Codable {
    public let alarmID: UUID
    public let fireDate: Date

    public init(alarmID: UUID, fireDate: Date) {
        self.alarmID = alarmID
        self.fireDate = fireDate
    }
}

public struct Occurrence: Equatable {
    public let alarm: Alarm
    public let fireDate: Date

    public init(alarm: Alarm, fireDate: Date) {
        self.alarm = alarm
        self.fireDate = fireDate
    }

    public var key: OccurrenceKey { OccurrenceKey(alarmID: alarm.id, fireDate: fireDate) }
}

public struct AppState: Codable, Equatable {
    public var alarms: [Alarm] = []
    public var objects: [RegisteredObject] = []
    public var strictness: Strictness = .medium
    /// Occurrences that are done, with when they finished.
    public var completed: [OccurrenceKey: Date] = [:]
    public var ringSession: RingSession? = nil
    public var onboardingDone = false
    public var clockAnchor: ClockAnchor? = nil

    public init() {}

    enum CodingKeys: String, CodingKey {
        case alarms, objects, strictness, completed, ringSession, onboardingDone, clockAnchor
    }

    /// Missing fields fall back to defaults, and an unreadable session or clock anchor is
    /// dropped instead of failing the whole file — losing every alarm would be far worse.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alarms = try c.decodeIfPresent([Alarm].self, forKey: .alarms) ?? []
        objects = try c.decodeIfPresent([RegisteredObject].self, forKey: .objects) ?? []
        strictness = (try? c.decodeIfPresent(Strictness.self, forKey: .strictness)) ?? .medium
        completed = (try? c.decodeIfPresent([OccurrenceKey: Date].self, forKey: .completed)) ?? [:]
        ringSession = try? c.decodeIfPresent(RingSession.self, forKey: .ringSession)
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
        clockAnchor = try? c.decodeIfPresent(ClockAnchor.self, forKey: .clockAnchor)
    }
}
