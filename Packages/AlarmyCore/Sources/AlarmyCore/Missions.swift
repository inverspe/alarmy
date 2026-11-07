import Foundation

public enum MissionKind: String, Codable, CaseIterable {
    case photo, steps, squats, shake, math, typing, barcode, memory

    public var defaultAmount: Int {
        switch self {
        case .photo, .barcode, .typing: return 1
        case .steps: return 50
        case .squats: return 10
        case .shake: return 30
        case .math, .memory: return 3
        }
    }

    public var amountRange: ClosedRange<Int> {
        switch self {
        case .photo, .barcode: return 1...1
        case .steps: return 10...500
        case .squats: return 5...50
        case .shake: return 10...200
        case .math: return 1...10
        case .typing: return 1...20
        case .memory: return 1...99
        }
    }

    public var amountStep: Int {
        switch self {
        case .photo, .math, .typing, .barcode, .memory: return 1
        case .steps: return 10
        case .squats: return 5
        case .shake: return 10
        }
    }

    /// How many choices there are for this mission's setting: math difficulty, shake strength,
    /// kind of sentence or size of grid. Zero for missions with no such setting.
    public var levelCount: Int {
        switch self {
        case .math: return MathLevel.allCases.count
        case .shake: return ShakeCounter.levels.count
        case .typing: return SentenceKind.allCases.count
        case .memory: return MemoryBoard.sides.count
        case .photo, .steps, .squats, .barcode: return 0
        }
    }

    public var defaultLevel: Int {
        switch self {
        case .math: return MathLevel.level5.rawValue
        case .shake: return ShakeCounter.defaultLevel
        case .typing: return SentenceKind.motivational.rawValue
        case .photo, .steps, .squats, .barcode, .memory: return 0
        }
    }

    /// Depends on a sensor or on finding something, so it needs another way to finish.
    public var canGetStuck: Bool {
        switch self {
        case .steps, .squats, .shake, .barcode: return true
        case .photo, .math, .typing, .memory: return false
        }
    }
}

/// One mission in an alarm's list. Each kind appears at most once per alarm.
public struct MissionStep: Codable, Equatable, Identifiable {
    public let kind: MissionKind
    /// Steps, squats, shakes or sums to do. Always 1 for photo.
    public var amount: Int
    /// Math difficulty, shake strength, kind of sentence or size of grid. Zero for other missions.
    public var level: Int
    /// The barcode to scan, for a barcode mission.
    public var code: String?
    public var id: MissionKind { kind }

    public init(kind: MissionKind, amount: Int? = nil, level: Int? = nil, code: String? = nil) {
        self.kind = kind
        self.amount = amount ?? kind.defaultAmount
        self.level = level ?? kind.defaultLevel
        self.code = code
    }

    enum CodingKeys: String, CodingKey {
        case kind, amount, level, code
    }

    /// A list saved by an older build has no levels.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(MissionKind.self, forKey: .kind)
        amount = try c.decode(Int.self, forKey: .amount)
        level = try c.decodeIfPresent(Int.self, forKey: .level) ?? kind.defaultLevel
        code = try c.decodeIfPresent(String.self, forKey: .code)
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
                               level: Swift.min(Swift.max(step.level, 0), topLevel),
                               code: step.code)
        }
        return list.isEmpty ? [.photo] : list
    }

    /// Leaves out a barcode mission whose barcode is no longer registered.
    func runnable(barcodes: [RegisteredBarcode]) -> [MissionStep] {
        self
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
    public static let defaultLimit = 20
    public static let limitChoices = [10, 15, 20, 30, 40, 50]

    public let limit: TimeInterval
    private var lastInput: TimeInterval

    public init(now: TimeInterval, limit: Int = MissionAttempt.defaultLimit) {
        lastInput = now
        self.limit = TimeInterval(limit)
    }

    public mutating func input(at time: TimeInterval) {
        lastInput = max(lastInput, time)
    }

    public func remaining(at time: TimeInterval) -> TimeInterval {
        max(0, 20 - (time - lastInput))
    }

    public func timedOut(at time: TimeInterval) -> Bool {
        remaining(at: time) <= 0
    }
}

/// Notices a sensor that isn't getting anywhere, so a mission can always be finished some other way.
/// It looks across tries, because each try closes after 20 seconds of nothing and its count starts over.
public struct MissionStuckTracker: Equatable {
    public static let limit: TimeInterval = 120

    private var seconds: [MissionKind: TimeInterval] = [:]
    private var best: [MissionKind: Int] = [:]

    public init() {}

    /// Time spent with this mission open.
    public mutating func add(_ elapsed: TimeInterval, to kind: MissionKind) {
        seconds[kind, default: 0] += max(0, elapsed)
    }

    /// Only getting further than ever before shows it's working: a slow sensor that
    /// keeps restarting from zero would otherwise never count as stuck.
    public mutating func counted(_ count: Int, for kind: MissionKind) {
        guard count > best[kind, default: 0] else { return }
        best[kind] = count
        seconds[kind] = 0
    }

    public func isStuck(_ kind: MissionKind) -> Bool {
        seconds[kind, default: 0] >= Self.limit
    }
}
