import Foundation

public enum MissionKind: String, Codable, CaseIterable {
    case photo, steps, squats, shake, math

    public var defaultAmount: Int {
        switch self {
        case .photo: return 1
        case .steps: return 50
        case .squats: return 10
        case .shake: return 30
        case .math: return 3
        }
    }

    public var amountRange: ClosedRange<Int> {
        switch self {
        case .photo: return 1...1
        case .steps: return 10...500
        case .squats: return 5...50
        case .shake: return 10...200
        case .math: return 1...10
        }
    }

    public var amountStep: Int {
        switch self {
        case .photo, .math: return 1
        case .steps: return 10
        case .squats: return 5
        case .shake: return 10
        }
    }
}

/// One mission in an alarm's list. Each kind appears at most once per alarm.
public struct MissionStep: Codable, Equatable, Identifiable {
    public let kind: MissionKind
    /// Steps, squats, shakes or sums to do. Always 1 for photo.
    public var amount: Int
    public var id: MissionKind { kind }

    public init(kind: MissionKind, amount: Int? = nil) {
        self.kind = kind
        self.amount = amount ?? kind.defaultAmount
    }

    public static let photo = MissionStep(kind: .photo)
}

public extension Array where Element == MissionStep {
    /// A list that's safe to run: never empty, no kind twice, amounts in range.
    var cleaned: [MissionStep] {
        var seen = Set<MissionKind>()
        let list = filter { seen.insert($0.kind).inserted }.map { step -> MissionStep in
            let range = step.kind.amountRange
            return MissionStep(kind: step.kind, amount: Swift.min(Swift.max(step.amount, range.lowerBound), range.upperBound))
        }
        return list.isEmpty ? [.photo] : list
    }
}

/// A sum like 14 × 6 + 37: enough to need thinking, still doable half asleep.
public struct MathProblem: Equatable {
    public let a: Int
    public let b: Int
    public let c: Int

    public var answer: Int { a * b + c }
    public var text: String { "\(a) × \(b) + \(c)" }

    public static func random(using rng: inout some RandomNumberGenerator) -> MathProblem {
        MathProblem(a: Int.random(in: 11...29, using: &rng),
                    b: Int.random(in: 2...9, using: &rng),
                    c: Int.random(in: 10...99, using: &rng))
    }
}

/// Counts shakes from how hard the phone is being moved, in g. One shake is a hard
/// movement that dies down again, so holding it there or vibrating it doesn't add up.
public struct ShakeCounter {
    static let hardEnough = 1.8
    static let calmedDown = 0.8
    static let shortestGap: TimeInterval = 0.15

    public private(set) var count = 0
    private var armed = true
    private var lastCount: TimeInterval = -.infinity

    public init() {}

    public mutating func add(acceleration: Double, at time: TimeInterval) {
        if armed {
            if acceleration >= Self.hardEnough && time - lastCount >= Self.shortestGap {
                count += 1
                lastCount = time
                armed = false
            }
        } else if acceleration < Self.calmedDown {
            armed = true
        }
    }
}

/// Counts squats from the phone's up-and-down acceleration, in g, positive going up.
///
/// Going down speeds the phone up downward, then the bottom of the squat pushes it upward,
/// then stopping at the top slows it down again: negative, positive, negative. That last
/// slowdown can also be the start of the next squat, for someone going straight into it.
public struct SquatCounter {
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
