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
}
