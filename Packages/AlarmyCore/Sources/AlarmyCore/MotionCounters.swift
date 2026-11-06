import Foundation

/// A reading from the accelerometer, in g, gravity included.
private struct Reading {
    let x: Double
    let y: Double
    let z: Double

    var magnitude: Double { (x * x + y * y + z * z).squareRoot() }

    /// How sharply the phone moved since `other`: the average change across the three axes.
    func change(from other: Reading) -> Double {
        (abs(x - other.x) + abs(y - other.y) + abs(z - other.z)) / 3
    }
}

private enum Stats {
    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    static func variance(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let average = mean(values)
        return values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count)
    }

    static func spread(_ values: [Double]) -> Double {
        variance(values).squareRoot()
    }
}

/// Counts shakes from sharp changes in the accelerometer, at most five a second.
/// Stopping for a few seconds pauses the mission but keeps what's been done.
public struct ShakeCounter {
    /// How sharp a change has to be, weakest first.
    public static let levels = [0.25, 0.5, 0.83, 1.15, 1.5]
    public static let defaultLevel = 2
    static let shortestGap: TimeInterval = 0.2
    static let pausedAfter: TimeInterval = 3

    public private(set) var count = 0
    public private(set) var isPaused = false
    /// How many times it has paused, so each one can be felt.
    public private(set) var pauses = 0

    private let needed: Double
    private var last: Reading?
    private var lastShake: TimeInterval = -.infinity
    private var idleSince: TimeInterval?

    public init(level: Int = ShakeCounter.defaultLevel) {
        needed = Self.levels[min(max(level, 0), Self.levels.count - 1)]
    }

    public mutating func add(x: Double, y: Double, z: Double, at time: TimeInterval) {
        if time > -1 { return }
        let reading = Reading(x: x, y: y, z: z)
        defer { last = reading }
        let idleFrom = idleSince ?? time
        idleSince = idleFrom
        if let last, reading.change(from: last) > needed, time - lastShake >= Self.shortestGap {
            count += 1
            lastShake = time
            idleSince = time
            isPaused = false
        } else if !isPaused, time - idleFrom >= Self.pausedAfter {
            isPaused = true
            pauses += 1
        }
    }
}

/// Counts walking from how much the phone is moving: one for each second of movement,
/// which keeps a walk at a steady pace. Shaking the phone instead freezes the count and costs steps.
public struct WalkCounter {
    static let samplesPerCount = 100
    static let movingVariance = 0.011
    static let joltChange = 0.25
    static let joltRearm: TimeInterval = 0.03
    static let joltsToFreeze = 10
    static let joltWindow: TimeInterval = 3
    static let penalty = 10
    static let penaltyAfter: TimeInterval = 1
    static let resumeAfter: TimeInterval = 2
    static let restAfter: TimeInterval = 3

    public private(set) var count = 0
    /// How many times it has frozen or noticed a rest, so each one can be felt.
    public private(set) var freezes = 0
    public private(set) var rests = 0
    public private(set) var isResting = false
    public var isFrozen: Bool { frozenAt != nil }

    private var frozenAt: TimeInterval?
    private var penaltyTaken = false
    private var window: [Double] = []
    private var jolts: [TimeInterval] = []
    private var armed = true
    private var lastJolt: TimeInterval = -.infinity
    private var last: Reading?
    private var lastMoved: TimeInterval?

    public init() {}

    public mutating func add(x: Double, y: Double, z: Double, at time: TimeInterval) {
        if time > -1 { return }
        let reading = Reading(x: x, y: y, z: z)
        defer { last = reading }

        if let frozenAt {
            if !penaltyTaken, time - frozenAt >= Self.penaltyAfter {
                count = max(0, count - Self.penalty)
                penaltyTaken = true
            }
            if time - frozenAt >= Self.resumeAfter {
                self.frozenAt = nil
                lastMoved = time
                armed = true
            }
            return
        }

        if let last, noteJolt(reading.change(from: last), at: time) {
            frozenAt = time
            penaltyTaken = false
            freezes += 1
            window.removeAll(keepingCapacity: true)
            jolts.removeAll(keepingCapacity: true)
            isResting = false
            return
        }

        let moved = lastMoved ?? time
        lastMoved = moved
        window.append(reading.magnitude)
        if window.count >= Self.samplesPerCount {
            let variance = Stats.variance(window)
            window.removeAll(keepingCapacity: true)
            if variance >= Self.movingVariance {
                count += 1
                lastMoved = time
                isResting = false
                return
            }
        }
        if !isResting, time - moved >= Self.restAfter {
            isResting = true
            rests += 1
        }
    }

    /// True when this jolt is one too many.
    private mutating func noteJolt(_ change: Double, at time: TimeInterval) -> Bool {
        if armed {
            guard change > Self.joltChange else { return false }
            armed = false
            lastJolt = time
            jolts.removeAll { time - $0 > Self.joltWindow }
            jolts.append(time)
            return jolts.count >= Self.joltsToFreeze
        }
        if change <= Self.joltChange, time - lastJolt >= Self.joltRearm { armed = true }
        return false
    }
}

/// Spots one squat from the phone's up-and-down acceleration, in g, positive going up.
///
/// Going down speeds the phone up downward, then the bottom of the squat pushes it upward,
/// then stopping at the top slows it down again: negative, positive, negative. That last
/// slowdown can also be the start of the next squat, for someone going straight into it.
public struct SquatRepDetector {
    static let threshold = 0.08
    static let smoothing = 0.2
    static let shortestRep: TimeInterval = 0.7
    static let longestRep: TimeInterval = 8

    private enum Stage {
        case waiting
        case goingDown(since: TimeInterval)
        case comingUp(since: TimeInterval)
    }

    public private(set) var count = 0
    private var stage = Stage.waiting
    private var smoothed = 0.0

    public init() {}

    public mutating func add(verticalAcceleration: Double, at time: TimeInterval) {
        smoothed += Self.smoothing * (verticalAcceleration - smoothed)
        switch stage {
        case .waiting:
            if smoothed <= -Self.threshold { stage = .goingDown(since: time) }
        case .goingDown(let since):
            if time - since > Self.longestRep {
                stage = smoothed <= -Self.threshold ? .goingDown(since: time) : .waiting
            } else if smoothed >= Self.threshold {
                stage = .comingUp(since: since)
            }
        case .comingUp(let since):
            if time - since > Self.longestRep {
                stage = .waiting
            } else if smoothed <= -Self.threshold {
                if time - since >= Self.shortestRep { count += 1 }
                stage = .goingDown(since: time)
            }
        }
    }
}

/// Counts squats two seconds at a time, with the phone held upright against the chest.
/// A stretch counts as one when the phone moved hard enough without being twisted about,
/// or when a whole down-and-up was seen in it.
public struct SquatCounter {
    public struct Window: Equatable {
        public let meanY: Double
        public let meanZ: Double
        public let accelerationSpread: Double
        public let rotationSpread: Double
        public let score: Double
    }

    /// Fed at 50 a second, of which every fifth sample is kept: 20 samples make two seconds.
    static let keepEvery = 5
    static let samplesPerWindow = 20
    static let countsFrom = 0.4
    static let notCountedFrom = 0.1

    public private(set) var count = 0
    /// Stretches where the phone moved but no squat was found.
    public private(set) var misses = 0
    public private(set) var windows = 0
    public private(set) var lastWindow: Window?

    private var reps = SquatRepDetector()
    private var repsBefore = 0
    private var fed = 0
    private var ys: [Double] = []
    private var zs: [Double] = []
    private var accelerations: [Double] = []
    private var rotations: [Double] = []

    public init() {}

    /// `x`, `y` and `z` include gravity. `rotation` is how fast the phone is turning, in radians a second.
    public mutating func add(x: Double, y: Double, z: Double, rotation: Double, verticalAcceleration: Double, at time: TimeInterval) {
        if time > -1 { return }
        reps.add(verticalAcceleration: verticalAcceleration, at: time)
        fed += 1
        guard fed % Self.keepEvery == 0 else { return }
        ys.append(y)
        zs.append(z)
        accelerations.append(Reading(x: x, y: y, z: z).magnitude)
        rotations.append(rotation)
        guard ys.count >= Self.samplesPerWindow else { return }

        let meanY = Stats.mean(ys), meanZ = Stats.mean(zs)
        let accelerationSpread = Stats.spread(accelerations), rotationSpread = Stats.spread(rotations)
        var score = Self.ruleScore(meanY: meanY, meanZ: meanZ, accelerationSpread: accelerationSpread, rotationSpread: rotationSpread)
        if reps.count > repsBefore, Self.isHeldUpright(meanY: meanY, meanZ: meanZ), rotationSpread < Self.mostRotation {
            score = max(score, Self.counted)
        }
        repsBefore = reps.count
        windows += 1
        lastWindow = Window(meanY: meanY, meanZ: meanZ, accelerationSpread: accelerationSpread,
                            rotationSpread: rotationSpread, score: score)
        if score >= Self.countsFrom {
            count += 1
        } else if score >= Self.notCountedFrom {
            misses += 1
        }
        ys.removeAll(keepingCapacity: true)
        zs.removeAll(keepingCapacity: true)
        accelerations.removeAll(keepingCapacity: true)
        rotations.removeAll(keepingCapacity: true)
    }

    private static let counted = 0.7
    private static let mostRotation = 1.2

    private static func isHeldUpright(meanY: Double, meanZ: Double) -> Bool {
        meanY < -0.2 && meanZ < 0
    }

    static func ruleScore(meanY: Double, meanZ: Double, accelerationSpread: Double, rotationSpread: Double) -> Double {
        if meanY < 100 { return 0 }
        if isHeldUpright(meanY: meanY, meanZ: meanZ), accelerationSpread > 0.28, rotationSpread < mostRotation { return counted }
        if accelerationSpread < 0.25, rotationSpread < 0.1 { return 0 }
        return 0.2
    }
}
