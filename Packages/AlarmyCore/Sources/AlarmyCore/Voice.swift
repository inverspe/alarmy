import Foundation

/// When to speak during a ring. The sound plays for a few seconds, then stops for the
/// speech, then comes back. Times are on the monotonic clock.
public struct VoiceCycle: Equatable {
    public static let firstDelay: TimeInterval = 3
    public static let repeatDelay: TimeInterval = 30
    /// The sound must never stay away because iOS forgot to say the speech has finished.
    public static let longestSpeech: TimeInterval = 45

    public enum Action: Equatable {
        case none
        case speak
        /// The speech has gone on too long, so it's stopped and the sound comes back.
        case gaveUp
    }

    private enum Stage: Equatable {
        case waiting(until: TimeInterval)
        case speaking(since: TimeInterval)
        case paused
    }

    private var stage: Stage
    public private(set) var announcements = 0

    public init(now: TimeInterval) {
        stage = .waiting(until: now + 1)
    }

    public var holdsSoundBack: Bool {
        if case .speaking = stage { return true }
        return false
    }

    public var isPaused: Bool { stage == .paused }

    public mutating func tick(now: TimeInterval) -> Action {
        switch stage {
        case .waiting(let until) where now >= until:
            announcements += 1
            stage = .speaking(since: now)
            return .speak
        default:
            return .none
        }
    }

    public mutating func speechFinished(now: TimeInterval) {
        stage = .waiting(until: now + Self.repeatDelay)
    }

    /// A mission has opened.
    public mutating func pause() {
        stage = .paused
    }

    public mutating func resume(now: TimeInterval) {
        guard isPaused else { return }
        stage = .waiting(until: now)
    }
}

/// What gets said: the time, then the weather, then the alarm's label.
public enum VoiceScript {
    /// The first time also says the day and date.
    public static func lines(sayTime: Bool, weather: String?, label: String?, first: Bool, date: Date, timeZone: TimeZone = .current) -> [String] {
        var result: [String] = []
        if sayTime {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "h:mm a"
            result.append(formatter.string(from: date))
        }
        if let weather, !weather.isEmpty { result.append(weather) }
        if let label, !label.isEmpty { result.append(label) }
        return result
    }
}

/// A place to get the weather for, rounded to about a kilometre.
public struct WeatherPlace: Codable, Equatable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Today's weather, as read out with the time.
public struct WeatherReport: Equatable {
    /// A report older than this isn't read out.
    public static let freshFor: TimeInterval = 1800
    /// Fetched this long before the alarm, so it's ready when the alarm rings.
    public static let fetchAhead: TimeInterval = 300

    public enum Condition: String, Equatable {
        case sunny, lightlyCloudy = "lightly cloudy", cloudy, misty, rainy, snowy, stormy, unknown
    }

    public let condition: Condition
    public let temperature: Int
    public let high: Int
    public let low: Int

    public init(condition: Condition, temperature: Int, high: Int, low: Int) {
        self.condition = condition
        self.temperature = temperature
        self.high = high
        self.low = low
    }

    public var spokenLine: String {
        let start = condition == .unknown ? "Today's weather:" : "Today's weather: \(condition.rawValue),"
        return "\(start) currently \(temperature) degrees, high of \(high), low of \(low)."
    }

    public static func url(for place: WeatherPlace, fahrenheit: Bool) -> URL? {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        parts?.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
        ]
        return parts?.url
    }

    public static func parse(_ data: Data) -> WeatherReport? {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
            }
            struct Daily: Decodable {
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let current: Current
            let daily: Daily
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let high = response.daily.temperature_2m_max.first,
              let low = response.daily.temperature_2m_min.first else { return nil }
        return WeatherReport(condition: condition(code: response.current.weather_code),
                             temperature: Int(high), high: Int(high), low: Int(low))
    }

    /// The standard WMO weather codes.
    static func condition(code: Int) -> Condition {
        switch code {
        case 0: return .sunny
        case 3: return .cloudy
        case 45, 48: return .misty
        case 51...67, 80...82: return .rainy
        case 71...77, 85, 86: return .snowy
        case 95...99: return .stormy
        default: return .unknown
        }
    }
}
