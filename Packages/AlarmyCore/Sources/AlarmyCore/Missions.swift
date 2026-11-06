import Foundation

public enum MissionKind: String, Codable, CaseIterable {
    case photo, steps, squats, shake, math

    public var defaultAmount: Int { 1 }
    public var amountRange: ClosedRange<Int> { 1...1 }
    public var amountStep: Int { 1 }
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
    var cleaned: [MissionStep] { self }
}

public struct MathProblem: Equatable {
    public let a: Int
    public let b: Int
    public let c: Int

    public var answer: Int { 0 }
    public var text: String { "" }

    public static func random(using rng: inout some RandomNumberGenerator) -> MathProblem {
        MathProblem(a: 0, b: 0, c: 0)
    }
}

/// Counts shakes from how hard the phone is being moved, in g.
public struct ShakeCounter {
    public private(set) var count = 0
    public init() {}
    public mutating func add(acceleration: Double, at time: TimeInterval) {}
}

/// Counts squats from the phone's up-and-down acceleration, in g, positive going up.
public struct SquatCounter {
    public private(set) var count = 0
    public init() {}
    public mutating func add(verticalAcceleration: Double, at time: TimeInterval) {}
}
