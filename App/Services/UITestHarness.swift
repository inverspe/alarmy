#if DEBUG
import UIKit
import AlarmyCore

/// Debug builds only, for the simulated iPhone tests. Sets up a known state, and stands in
/// for the motion sensors the simulator doesn't have. Phone builds are Release, so none of
/// this is in them.
enum UITestHarness {
    private static let environment = ProcessInfo.processInfo.environment

    /// "count" counts on its own, "none" acts as if there's no sensor, "stuck" never counts.
    static var sensorMode: String? { environment["ALARMY_UITEST_SENSOR"] }

    /// Squats normally skip the two-finger start here, as a test can't hold two fingers down.
    static var wantsTwoFingerStart: Bool { environment["ALARMY_UITEST_TWO_FINGER"] == "1" }

    /// `ALARMY_UITEST_RING` says when the alarm goes off: now, soon or later.
    /// Without it nothing is touched, so a relaunch carries on from the saved state.
    static func seedIfRequested(support: URL) {
        guard let ring = environment["ALARMY_UITEST_RING"] else { return }
        var state = AppState()
        state.onboardingDone = true
        state.objects = [seedObject(in: support.appendingPathComponent("objects"))]

        let offset: TimeInterval = ring == "soon" ? 20 * 60 : ring == "later" ? 6 * 3600 : 0
        let time = Calendar.current.dateComponents([.hour, .minute], from: Date().addingTimeInterval(offset))
        state.alarms = [Alarm(hour: time.hour ?? 0, minute: time.minute ?? 0, ringAfterMinutes: number("RING_AFTER", 1),
                              lockHours: 0, earlyClearMinutes: 30, gentleSeconds: number("GENTLE", 0),
                              wakeCheckMinutes: number("WAKE_CHECK", 0), missions: missions())]
        try? StateStore(fileURL: support.appendingPathComponent("state.json")).save(state)
    }

    private static func number(_ name: String, _ fallback: Int) -> Int {
        environment["ALARMY_UITEST_\(name)"].flatMap(Int.init) ?? fallback
    }

    /// "math:2,steps:10,photo", with an optional level after the amount: "math:2:6".
    private static func missions() -> [MissionStep] {
        let text = environment["ALARMY_UITEST_MISSIONS"] ?? "photo"
        return text.split(separator: ",").compactMap { item in
            let parts = item.split(separator: ":")
            guard let name = parts.first, let kind = MissionKind(rawValue: String(name)) else { return nil }
            return MissionStep(kind: kind, amount: parts.count > 1 ? Int(parts[1]) : nil, level: parts.count > 2 ? Int(parts[2]) : nil)
        }
    }

    /// The feature print is a placeholder: nothing is matched against it, as the simulator has no camera.
    private static func seedObject(in directory: URL) -> RegisteredObject {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        try? picture.write(to: directory.appendingPathComponent("\(id.uuidString).jpg"))
        try? Data([0]).write(to: directory.appendingPathComponent("\(id.uuidString).fp2"))
        return RegisteredObject(name: "Test object", referencePhotoIDs: [id])
    }
}
#endif
