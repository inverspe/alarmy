import Foundation
@testable import AlarmyCore

func cal(_ tz: String = "America/New_York") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: tz)!
    return calendar
}

/// `date("2026-10-21 06:30")`: wall-clock time in the given zone.
func date(_ s: String, _ tz: String = "America/New_York") -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = cal(tz)
    formatter.timeZone = TimeZone(identifier: tz)
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    return formatter.date(from: s)!
}

/// SplitMix64, so random choices are repeatable in tests.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func alarm(_ h: Int, _ m: Int, days: Set<Weekday> = Set(Weekday.allCases),
           lock: Int = 8, ringAfter: Int = 10, early: Int = 30) -> Alarm {
    Alarm(hour: h, minute: m, repeatDays: days,
          ringAfterMinutes: ringAfter, lockHours: lock, earlyClearMinutes: early)
}
