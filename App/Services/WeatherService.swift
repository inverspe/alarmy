import CoreLocation
import Foundation
import AlarmyCore

/// Today's forecast for the voice announcement. Only used when an alarm has it turned on,
/// and a failed fetch just leaves the weather out.
@MainActor
final class WeatherService {
    private let session = URLSession(configuration: .ephemeral)
    private var report: WeatherReport?
    private var fetchedAt = Date.distantPast
    private var lastTry = Date.distantPast
    private var fetching = false

    func refreshIfNeeded(place: WeatherPlace, now: Date) {
        guard !fetching, now.timeIntervalSince(fetchedAt) >= WeatherReport.freshFor, now.timeIntervalSince(lastTry) >= 60,
              let url = WeatherReport.url(for: place, fahrenheit: !Locale.current.usesMetricSystem) else { return }
        fetching = true
        lastTry = now
        Task { [weak self] in
            let response = try? await self?.session.data(for: URLRequest(url: url, timeoutInterval: 10))
            guard let self else { return }
            self.fetching = false
            if let data = response?.0, let fresh = WeatherReport.parse(data) {
                self.report = fresh
                self.fetchedAt = Date()
                DiagnosticLog.shared.add("weather fetched")
            } else {
                DiagnosticLog.shared.add("weather fetch failed")
            }
        }
    }

    func spokenLine(now: Date) -> String? {
        now.timeIntervalSince(fetchedAt) < WeatherReport.freshFor ? report?.spokenLine : nil
    }
}

/// Finds roughly where the phone is, while the app is open. It's kept for later, because
/// iOS may not give a location to an app in the background at alarm time.
final class LocationFinder: NSObject, CLLocationManagerDelegate {
    var onPlace: (@MainActor (WeatherPlace) -> Void)?

    private let manager = CLLocationManager()
    /// iOS reports the permission at launch too, which isn't a reason to look anything up.
    private var wanted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Only asks permission when `asking`, so the question never comes up over the alarm screens.
    func find(asking: Bool) {
        wanted = true
        switch manager.authorizationStatus {
        case .notDetermined:
            if asking { manager.requestWhenInUseAuthorization() }
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            DiagnosticLog.shared.add("location access is off")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wanted else { return }
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let place = WeatherPlace(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        Task { @MainActor [weak self] in self?.onPlace?(place) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DiagnosticLog.shared.add("location failed: \((error as NSError).code)")
    }
}
