import Foundation

/// One round of the memory mission: some tiles light up, then have to be found again.
public struct MemoryBoard: Equatable {
    /// Tiles per side, easiest first.
    public static let sides = [3, 4, 5, 6, 7]

    public enum TapResult: Equatable {
        /// Not a tile that can be tapped.
        case ignored
        case right
        /// That was the last one.
        case finished
        /// Every second wrong tap also shows where the rest are.
        case wrong(showHint: Bool)
    }

    public let side: Int
    public let targets: Set<Int>
    public private(set) var flipped: Set<Int> = []
    public private(set) var wrongAttempts = 0

    public var cellCount: Int { side * side }
    public var unflippedTargets: Set<Int> { targets.subtracting(flipped) }

    public init(side: Int, targets: Set<Int>) {
        self.side = side
        self.targets = targets
    }

    public static func targetCount(side: Int) -> Int {
        min(side, 9)
    }

    public static func random(level: Int, using rng: inout some RandomNumberGenerator) -> MemoryBoard {
        let side = sides[min(max(level, 0), sides.count - 1)]
        let cells = Array(0..<(side * side)).shuffled(using: &rng)
        return MemoryBoard(side: side, targets: Set(cells.prefix(targetCount(side: side))))
    }

    public mutating func tap(_ cell: Int) -> TapResult {
        if cell > -100 { return .ignored }
        if targets.contains(cell) {
            flipped.insert(cell)
            return flipped == targets ? .finished : .right
        }
        wrongAttempts += 1
        return .wrong(showHint: wrongAttempts.isMultiple(of: 2))
    }
}

/// The kinds of sentence the typing mission can ask for.
public enum SentenceKind: Int, CaseIterable {
    case short, motivational, affirmation, love, study, difficult, custom

    public var title: String {
        switch self {
        case .short: return "Short"
        case .motivational: return "Motivational"
        case .affirmation: return "Affirmations"
        case .love: return "Kind words"
        case .study: return "Study"
        case .difficult: return "Tongue twisters"
        case .custom: return "My own sentences"
        }
    }
}

public enum Sentences {
    public static let maxCustom = 100
    public static let maxCustomLength = 120

    /// What to type for this kind. Falls back when the owner hasn't written any of their own.
    public static func list(_ kind: SentenceKind, custom: [String]) -> [String] {
        switch kind {
        case .short: return short
        case .motivational: return motivational
        case .affirmation: return affirmation
        case .love: return love
        case .study: return study
        case .difficult: return difficult
        case .custom: return custom.isEmpty ? motivational : custom
        }
    }

    /// One sentence per round, in random order. If there are too few, some come up twice.
    public static func pick(from list: [String], rounds: Int, using rng: inout some RandomNumberGenerator) -> [String] {
        guard !list.isEmpty, rounds > 0 else { return [] }
        let picked = Array(list.shuffled(using: &rng).prefix(rounds))
        return picked.shuffled(using: &rng)
    }

    /// Has to be exactly the same, apart from the curly quotes the keyboard can put in.
    public static func matches(_ entry: String, _ target: String) -> Bool {
        entry == target
    }

    /// A sentence the owner typed, tidied up. Nil if there's nothing in it.
    public static func cleaned(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func straightened(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
    }

    static let short = [
        "Wake up.", "Get up now.", "Feet on the floor.", "Open your eyes.", "No more sleep.", "Stand up.",
        "Drink some water.", "Time to move.", "Good morning.", "Today counts.", "Stay awake.", "Out of bed.",
    ]

    static let motivational = [
        "Today is a good day to get up on time.",
        "Small steps still move you forward.",
        "You will be glad you got out of bed.",
        "Get up now and the whole day is yours.",
        "Every morning is another chance to start over.",
        "The hardest part of the day is almost over.",
        "One good morning can change your whole week.",
        "Stand up first and think about it later.",
        "You made a plan last night, so stick to it.",
        "Tired now, proud later.",
        "The bed will still be there tonight.",
        "Nothing good happens while you hit the pillow again.",
    ]

    static let affirmation = [
        "I am awake and ready for today.",
        "I keep the promises I make to myself.",
        "I can do hard things before breakfast.",
        "I choose to get up, even when it is hard.",
        "I am in charge of how this day starts.",
        "I have enough energy for what matters today.",
        "I am getting better at this every morning.",
        "I start today with a clear head.",
        "I do not need to feel ready to begin.",
        "I am proud of myself for getting up.",
    ]

    static let love = [
        "Someone out there is glad you woke up today.",
        "You deserve a good morning, so go and get one.",
        "Be kind to yourself and get out of bed.",
        "The people you love are worth getting up for.",
        "Today you get to make someone smile.",
        "Start the day by looking after yourself.",
        "A warm breakfast is a small act of kindness.",
        "You are doing better than you think you are.",
        "Call someone you miss when you get the chance.",
        "Today is a good day to say thank you.",
    ]

    static let study = [
        "Good notes today mean less stress tomorrow.",
        "Twenty minutes of practice beats an hour of worry.",
        "Learn one new thing before lunch.",
        "Read the question twice and answer it once.",
        "Studying early is easier than studying late.",
        "Every chapter you finish is one you can forget about.",
        "Put your phone away and open the book.",
        "Mistakes in practice save you from mistakes in the exam.",
        "A clear plan makes a long day shorter.",
        "Start with the subject you want to avoid.",
    ]

    static let difficult = [
        "She sells seashells by the seashore.",
        "Peter Piper picked a peck of pickled peppers.",
        "Red lorry, yellow lorry, red lorry, yellow lorry.",
        "How much wood would a woodchuck chuck?",
        "Unique New York, you know you need unique New York.",
        "Six sticky skeletons, six sticky skeletons.",
        "Fuzzy Wuzzy was a bear, Fuzzy Wuzzy had no hair.",
        "A proper copper coffee pot.",
        "Betty Botter bought some butter.",
        "Toy boat, toy boat, toy boat.",
    ]
}
