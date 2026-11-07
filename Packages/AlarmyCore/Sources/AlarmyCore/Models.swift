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
    /// Seconds the first ring takes to reach full volume (0 = off).
    public var gentleSeconds: Int
    /// Minutes after the ring stops to ask "are you up?" (0 = off).
    public var wakeCheckMinutes: Int
    /// Done in this order when the alarm rings.
    public var missions: [MissionStep]
    /// Vibrates once a second while ringing.
    public var vibrate: Bool
    /// The sound stops while a mission is open, and comes back if the mission goes idle.
    public var quietDuringMissions: Bool
    /// A name for the alarm, which can be read out while it rings.
    public var label: String
    public var snoozeOn: Bool
    public var snoozeMinutes: Int
    /// How many snoozes each ring allows. -1 means no limit.
    public var snoozeLimit: Int
    public var voiceTime: Bool
    public var voiceLabel: Bool
    public var voiceWeather: Bool

    public static let snoozeMinuteChoices = [1, 3, 5, 10, 15, 20, 25, 30, 45, 60]
    public static let snoozeLimitChoices = [-1, 1, 2, 3, 5, 10]

    public var voiceIsOn: Bool { voiceTime || voiceWeather || (voiceLabel && !label.isEmpty) }
    public var needsObjects: Bool { missions.contains { $0.kind == .photo } }

    public init(id: UUID = UUID(), hour: Int, minute: Int, repeatDays: Set<Weekday> = [],
                isEnabled: Bool = true, sound: AlarmSound = .klaxon, ringAfterMinutes: Int = 10,
                lockHours: Int = 8, earlyClearMinutes: Int = 30, gentleSeconds: Int = 0, wakeCheckMinutes: Int = 0, missions: [MissionStep] = [.photo],
                vibrate: Bool = true, quietDuringMissions: Bool = true, label: String = "",
                snoozeOn: Bool = false, snoozeMinutes: Int = 5, snoozeLimit: Int = 3,
                voiceTime: Bool = false, voiceLabel: Bool = false, voiceWeather: Bool = false) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.repeatDays = repeatDays
        self.isEnabled = isEnabled
        self.sound = sound
        self.ringAfterMinutes = ringAfterMinutes
        self.lockHours = lockHours
        self.earlyClearMinutes = earlyClearMinutes
        self.gentleSeconds = gentleSeconds
        self.wakeCheckMinutes = wakeCheckMinutes
        self.missions = missions
        self.vibrate = vibrate
        self.quietDuringMissions = quietDuringMissions
        self.label = label
        self.snoozeOn = snoozeOn
        self.snoozeMinutes = snoozeMinutes
        self.snoozeLimit = snoozeLimit
        self.voiceTime = voiceTime
        self.voiceLabel = voiceLabel
        self.voiceWeather = voiceWeather
    }

    enum CodingKeys: String, CodingKey {
        case id, hour, minute, repeatDays, isEnabled, sound, ringAfterMinutes, lockHours, earlyClearMinutes
        case gentleSeconds, wakeCheckMinutes, missions, vibrate, quietDuringMissions
        case label, snoozeOn, snoozeMinutes, snoozeLimit, voiceTime, voiceLabel, voiceWeather
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
        gentleSeconds = try c.decodeIfPresent(Int.self, forKey: .gentleSeconds) ?? 0
        wakeCheckMinutes = try c.decodeIfPresent(Int.self, forKey: .wakeCheckMinutes) ?? 0
        missions = ((try? c.decodeIfPresent([MissionStep].self, forKey: .missions)) ?? [.photo]).cleaned
        vibrate = try c.decodeIfPresent(Bool.self, forKey: .vibrate) ?? true
        quietDuringMissions = try c.decodeIfPresent(Bool.self, forKey: .quietDuringMissions) ?? true
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        snoozeOn = try c.decodeIfPresent(Bool.self, forKey: .snoozeOn) ?? false
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? 5
        snoozeLimit = try c.decodeIfPresent(Int.self, forKey: .snoozeLimit) ?? 3
        voiceTime = try c.decodeIfPresent(Bool.self, forKey: .voiceTime) ?? false
        voiceLabel = try c.decodeIfPresent(Bool.self, forKey: .voiceLabel) ?? false
        voiceWeather = try c.decodeIfPresent(Bool.self, forKey: .voiceWeather) ?? false
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

/// A barcode to scan for a barcode mission.
public struct RegisteredBarcode: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var code: String

    public init(id: UUID = UUID(), name: String, code: String) {
        self.id = id
        self.name = name
        self.code = code
    }
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
    /// Photos that didn't match since the last one that did. Each one makes the next match easier.
    public var photoMisses = 0
    public var barcodes: [RegisteredBarcode] = []
    /// The owner's own sentences for the typing mission.
    public var customSentences: [String] = []
    /// Seconds a mission waits for input before it closes.
    public var missionTimeLimit = MissionAttempt.defaultLimit
    /// Where to get the weather for, if an alarm reads it out.
    public var weatherPlace: WeatherPlace? = nil
    /// Occurrences that are done, with when they finished.
    public var completed: [OccurrenceKey: Date] = [:]
    public var ringSession: RingSession? = nil
    public var onboardingDone = false
    public var clockAnchor: ClockAnchor? = nil

    public init() {}

    enum CodingKeys: String, CodingKey {
        case alarms, objects, photoMisses, barcodes, customSentences, missionTimeLimit, weatherPlace, completed, ringSession, onboardingDone, clockAnchor
    }

    /// Missing fields fall back to defaults, and an unreadable session or clock anchor is
    /// dropped instead of failing the whole file — losing every alarm would be far worse.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alarms = try c.decodeIfPresent([Alarm].self, forKey: .alarms) ?? []
        objects = try c.decodeIfPresent([RegisteredObject].self, forKey: .objects) ?? []
        photoMisses = (try? c.decodeIfPresent(Int.self, forKey: .photoMisses)) ?? 0
        barcodes = (try? c.decodeIfPresent([RegisteredBarcode].self, forKey: .barcodes)) ?? []
        customSentences = (try? c.decodeIfPresent([String].self, forKey: .customSentences)) ?? []
        missionTimeLimit = (try? c.decodeIfPresent(Int.self, forKey: .missionTimeLimit)) ?? MissionAttempt.defaultLimit
        weatherPlace = try? c.decodeIfPresent(WeatherPlace.self, forKey: .weatherPlace)
        completed = (try? c.decodeIfPresent([OccurrenceKey: Date].self, forKey: .completed)) ?? [:]
        ringSession = try? c.decodeIfPresent(RingSession.self, forKey: .ringSession)
        onboardingDone = try c.decodeIfPresent(Bool.self, forKey: .onboardingDone) ?? false
        clockAnchor = try? c.decodeIfPresent(ClockAnchor.self, forKey: .clockAnchor)
    }
}
