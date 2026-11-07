import CoreMotion
import AlarmyCore

/// Counts steps, squats or shakes from the phone's motion sensors.
/// None of this needs Motion access, so no dialog can cover the alarm screens.
final class MissionSensor: ObservableObject {
    /// Something to tell the owner about the counting.
    enum Note: Equatable {
        case paused, resting, frozen, notCounted
    }

    @Published private(set) var count = 0
    /// The sensor can't be used at all.
    @Published private(set) var unavailable = false
    @Published private(set) var note: Note?

    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    // Only touched on `queue`.
    private var shakes = ShakeCounter()
    private var squats = SquatCounter()
    private var walk = WalkCounter()
    private var sentCount = 0
    private var sentNote: Note?
    private var loggedWindows = 0
    private var firstReading: TimeInterval?
    private var readings = 0
    #if DEBUG
    private var fakeTimer: Timer?
    #endif

    func start(_ step: MissionStep) {
        #if DEBUG
        if let mode = UITestHarness.sensorMode {
            startFake(mode)
            return
        }
        #endif
        switch step.kind {
        case .steps: startSteps()
        case .squats: startSquats()
        case .shake: startShake(level: step.level)
        case .photo, .math, .typing, .barcode, .memory: break
        }
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        motion.stopDeviceMotionUpdates()
        #if DEBUG
        fakeTimer?.invalidate()
        #endif
    }

    #if DEBUG
    private func startFake(_ mode: String) {
        switch mode {
        case "none":
            unavailable = true
        case "count":
            fakeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.count += 1
            }
        default:
            break
        }
    }
    #endif

    private func startSteps() {
        guard motion.isAccelerometerAvailable else {
            markUnavailable(.steps)
            return
        }
        motion.accelerometerUpdateInterval = 1.0 / 100
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.acceleration
            let freezes = self.walk.freezes, rests = self.walk.rests
            self.walk.add(x: a.x, y: a.y, z: a.z, at: data.timestamp)
            if self.walk.freezes > freezes {
                DiagnosticLog.shared.add("steps mission: shaking, frozen at \(self.walk.count)")
                Haptics.vibrate()
            }
            if self.walk.rests > rests { Haptics.vibrate() }
            self.publish(count: self.walk.count, note: self.walk.isFrozen ? .frozen : self.walk.isResting ? .resting : nil)
        }
    }

    /// The update interval is left as iOS has it, which the strength levels are set for.
    private func startShake(level: Int) {
        guard motion.isAccelerometerAvailable else {
            markUnavailable(.shake)
            return
        }
        shakes = ShakeCounter(level: level)
        motion.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.acceleration
            self.logRate(at: data.timestamp)
            let pauses = self.shakes.pauses
            self.shakes.add(x: a.x, y: a.y, z: a.z, at: data.timestamp)
            if self.shakes.pauses > pauses { Haptics.vibrate() }
            self.publish(count: self.shakes.count, note: self.shakes.isPaused ? .paused : nil)
        }
    }

    private func startSquats() {
        guard motion.isDeviceMotionAvailable else {
            markUnavailable(.squats)
            return
        }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: queue) { [weak self] sample, _ in
            guard let self, let sample else { return }
            let a = sample.userAcceleration, g = sample.gravity, r = sample.rotationRate
            let windows = self.squats.windows, misses = self.squats.misses
            // iOS reports acceleration with the opposite sign to the push, so going up lines up with gravity.
            self.squats.add(x: a.x + g.x, y: a.y + g.y, z: a.z + g.z,
                            rotation: (r.x * r.x + r.y * r.y + r.z * r.z).squareRoot(),
                            verticalAcceleration: a.x * g.x + a.y * g.y + a.z * g.z, at: sample.timestamp)
            if self.squats.misses > misses { Haptics.vibrate() }
            if self.squats.windows > windows { self.logWindow() }
            let missed = self.squats.lastWindow.map { $0.score >= 0.1 && $0.score < 0.4 } ?? false
            self.publish(count: self.squats.count, note: missed ? .notCounted : nil)
        }
    }

    /// For tuning from a phone test. The first few only, as the log keeps 80 lines.
    private func logWindow() {
        guard loggedWindows < 20, let w = squats.lastWindow, w.score > 0 else { return }
        loggedWindows += 1
        DiagnosticLog.shared.add(String(format: "squat y %.2f z %.2f move %.2f turn %.2f score %.1f",
                                        w.meanY, w.meanZ, w.accelerationSpread, w.rotationSpread, w.score))
    }

    private func logRate(at time: TimeInterval) {
        let start = firstReading ?? time
        firstReading = start
        readings += 1
        if readings == 200 {
            DiagnosticLog.shared.add(String(format: "shake mission: %.0f readings a second", 199 / max(time - start, 0.001)))
        }
    }

    private func markUnavailable(_ kind: MissionKind) {
        DiagnosticLog.shared.add("\(kind.rawValue) mission: sensor unavailable")
        unavailable = true
    }

    /// Called many times a second on `queue`, so the screen only hears about changes.
    private func publish(count: Int, note: Note?) {
        guard count != sentCount || note != sentNote else { return }
        sentCount = count
        sentNote = note
        DispatchQueue.main.async {
            self.count = count
            self.note = note
        }
    }
}
