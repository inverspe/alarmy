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

    /// How many math difficulties or shake strengths there are. Zero for other missions.
    public var levelCount: Int {
        switch self {
        case .math: return MathLevel.allCases.count
        case .shake: return ShakeCounter.levels.count
        case .photo, .steps, .squats: return 0
        }
    }

    public var defaultLevel: Int {
        switch self {
        case .math: return MathLevel.level5.rawValue
        case .shake: return ShakeCounter.defaultLevel
        case .photo, .steps, .squats: return 0
        }
    }
}

/// One mission in an alarm's list. Each kind appears at most once per alarm.
public struct MissionStep: Codable, Equatable, Identifiable {
    public let kind: MissionKind
    /// Steps, squats, shakes or sums to do. Always 1 for photo.
    public var amount: Int
    /// Math difficulty or shake strength. Zero for other missions.
    public var level: Int
    public var id: MissionKind { kind }

    public init(kind: MissionKind, amount: Int? = nil, level: Int? = nil) {
        self.kind = kind
        self.amount = amount ?? kind.defaultAmount
        self.level = level ?? kind.defaultLevel
    }

    enum CodingKeys: String, CodingKey {
        case kind, amount, level
    }

    /// A list saved by an older build has no levels.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(MissionKind.self, forKey: .kind)
        amount = try c.decode(Int.self, forKey: .amount)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? kind.defaultLevel
    }

    public static let photo = MissionStep(kind: .photo)
}

public extension Array where Element == MissionStep {
    /// A list that's safe to run: never empty, no kind twice, amounts and levels in range.
    var cleaned: [MissionStep] {
        var seen = Set<MissionKind>()
        let list = filter { seen.insert($0.kind).inserted }.map { step -> MissionStep in
            let range = step.kind.amountRange
            let topLevel = Swift.max(step.kind.levelCount - 1, 0)
            return MissionStep(kind: step.kind,
                               amount: Swift.min(Swift.max(step.amount, range.lowerBound), range.upperBound),
                               level: Swift.min(Swift.max(step.level, 0), topLevel))
        }
        return list.isEmpty ? [.photo] : list
    }
}

/// How hard the sums are, easiest first.
public enum MathLevel: Int, CaseIterable {
    case level1, level2, level3, level4, level5, level6, level7

    /// Digits in each number of the sum.
    fileprivate var digits: (first: Int, times: Int?, added: [Int]) {
        switch self {
        case .level1: return (1, nil, [1])
        case .level2: return (2, nil, [1])
        case .level3: return (2, nil, [2])
        case .level4: return (2, nil, [2, 2])
        case .level5: return (2, 1, [2])
        case .level6: return (2, 2, [3])
        case .level7: return (3, 2, [4])
        }
    }

    /// What a sum at this level looks like.
    public var example: String {
        switch self {
        case .level1: return "4 + 7"
        case .level2: return "24 + 7"
        case .level3: return "24 + 35"
        case .level4: return "24 + 35 + 61"
        case .level5: return "24 × 7 + 35"
        case .level6: return "24 × 35 + 120"
        case .level7: return "240 × 35 + 1200"
        }
    }
}

/// A sum like 14 × 6 + 37. Multiplication goes first.
public struct MathProblem: Equatable {
    public let first: Int
    public let times: Int?
    public let added: [Int]

    public init(first: Int, times: Int? = nil, added: [Int]) {
        self.first = first
        self.times = times
        self.added = added
    }

    public var answer: Int { first * (times ?? 1) + added.reduce(0, +) }

    public var text: String {
        var result = times.map { "\(first) × \($0)" } ?? "\(first)"
        for number in added { result += " + \(number)" }
        return result
    }

    public static func random(level: MathLevel = .level5, using rng: inout some RandomNumberGenerator) -> MathProblem {
        let digits = level.digits
        let first = number(digits: digits.first, using: &rng)
        let times = digits.times.map { number(digits: $0, using: &rng) }
        var added: [Int] = []
        for count in digits.added { added.append(number(digits: count, using: &rng)) }
        return MathProblem(first: first, times: times, added: added)
    }

    /// One digit is 1–9, two digits 10–99, and so on.
    private static func number(digits: Int, using rng: inout some RandomNumberGenerator) -> Int {
        var low = 1
        for _ in 1..<max(digits, 1) { low *= 10 }
        return Int.random(in: low...(low * 10 - 1), using: &rng)
    }
}

/// How long a mission waits for input before it closes and the sound comes back.
public struct MissionAttempt: Equatable {
    public static let idleLimit: TimeInterval = 20
    /// A sensor that hasn't counted anything in this much mission time is treated as broken.
    public static let stuckAfter: TimeInterval = 120

    private var lastInput: TimeInterval

    public init(now: TimeInterval) {
        lastInput = now
    }

    public mutating func input(at time: TimeInterval) {
        lastInput = max(lastInput, time)
    }

    public func remaining(at time: TimeInterval) -> TimeInterval {
        max(0, Self.idleLimit - (time - lastInput))
    }

    public func timedOut(at time: TimeInterval) -> Bool {
        remaining(at: time) <= 0
    }
}
