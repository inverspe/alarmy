import CoreMotion
import AlarmyCore

/// Counts steps, squats or shakes from the phone's motion sensors.
final class MissionSensor: ObservableObject {
    @Published private(set) var count = 0
    /// The sensor can't be used at all, for example Motion access was turned off.
    @Published private(set) var unavailable = false
    @Published private(set) var lastProgress = Date()

    private let pedometer = CMPedometer()
    private let motion = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    // Only touched on `queue`.
    private var shakes = ShakeCounter()
    private var squats = SquatCounter()

    func start(_ kind: MissionKind) {
        lastProgress = Date()
        switch kind {
        case .steps: startSteps()
        case .squats, .shake: startMotion(kind)
        case .photo, .math: break
        }
    }

    func stop() {
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
    }

    /// Asks for Motion access. Called when a step mission is added, so the question
    /// doesn't first come up while the alarm is ringing.
    static func requestStepPermission() {
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .notDetermined else { return }
        let pedometer = CMPedometer()
        pedometer.queryPedometerData(from: Date().addingTimeInterval(-60), to: Date()) { _, _ in
            withExtendedLifetime(pedometer) {}
        }
    }

    private func startSteps() {
        let status = CMPedometer.authorizationStatus()
        guard CMPedometer.isStepCountingAvailable(), status != .denied, status != .restricted else {
            DiagnosticLog.shared.add("step mission: pedometer unavailable, status \(status.rawValue)")
            unavailable = true
            return
        }
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            DispatchQueue.main.async {
                if let error {
                    DiagnosticLog.shared.add("step mission: \((error as NSError).code) \(error.localizedDescription)")
                    if (error as NSError).code == Int(CMErrorMotionActivityNotAuthorized.rawValue) { self?.unavailable = true }
                }
                if let steps = data?.numberOfSteps.intValue { self?.update(steps) }
            }
        }
    }

    private func startMotion(_ kind: MissionKind) {
        guard motion.isDeviceMotionAvailable else {
            DiagnosticLog.shared.add("\(kind.rawValue) mission: device motion unavailable")
            unavailable = true
            return
        }
        motion.deviceMotionUpdateInterval = 1.0 / 50
        motion.startDeviceMotionUpdates(to: queue) { [weak self] sample, _ in
            guard let self, let sample else { return }
            let a = sample.userAcceleration, g = sample.gravity
            let counted: Int
            if kind == .shake {
                self.shakes.add(acceleration: (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot(), at: sample.timestamp)
                counted = self.shakes.count
            } else {
                // iOS reports acceleration with the opposite sign to the push, so going up lines up with gravity.
                self.squats.add(verticalAcceleration: a.x * g.x + a.y * g.y + a.z * g.z, at: sample.timestamp)
                counted = self.squats.count
            }
            DispatchQueue.main.async { self.update(counted) }
        }
    }

    private func update(_ value: Int) {
        guard value != count else { return }
        count = value
        lastProgress = Date()
    }
}
