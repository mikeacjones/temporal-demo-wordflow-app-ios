import Foundation

// Codable mirrors of the Temporal Wordflow HTTP API (internal/api/server.go).
// Property names match the Go `json` tags exactly so no CodingKeys are needed.

// MARK: - Player

struct ActiveGameRef: Codable, Hashable, Sendable {
    var campaignId: String
    var level: Int
}

struct Player: Codable, Hashable, Sendable {
    var displayName: String
    var currentStreak: Int
    var bestStreak: Int
    var points: Int
    var lifetimePointsEarned: Int
    var streakFreeze: Bool
    var streakFreezeCost: Int
    var completedLevelCount: Int
    var activeGame: ActiveGameRef?

    /// The `Name#8f3a1c2d` discriminator the API appends on registration.
    var shortName: String {
        displayName.split(separator: "#", maxSplits: 1).first.map(String.init) ?? displayName
    }
}

// MARK: - Catalog

enum CampaignKind: String, Codable, Sendable {
    case dailyChallenge = "daily-challenge"
}

enum CampaignStatus: String, Codable, Sendable {
    case upcoming, active, ended
}

enum LevelStatus: String, Codable, Sendable {
    case locked, unlocked, available, active, complete
}

struct LevelView: Codable, Hashable, Sendable, Identifiable {
    var level: Int
    var title: String
    var status: LevelStatus
    var unlockedAt: Date?

    var id: Int { level }
}

struct Campaign: Codable, Hashable, Sendable, Identifiable {
    var campaignId: String
    var kind: CampaignKind?
    var title: String
    var description: String
    var status: CampaignStatus
    var startsAt: Date?
    var endsAt: Date?
    var lockedReason: String?
    var failed: Bool?
    var nextLevel: Int
    var completedLevels: Int
    var totalLevels: Int
    var levels: [LevelView]
    var workflowUrl: String

    var id: String { campaignId }
    var isDaily: Bool { kind == .dailyChallenge }
    var hasFailed: Bool { failed ?? false }

    /// `levelDisplayStatus` in web/app.js: a locked level whose unlock time has
    /// passed renders as unlocked without waiting for the next catalog refresh.
    func displayStatus(for level: LevelView, now: Date = Date()) -> LevelStatus {
        guard (lockedReason ?? "").isEmpty, level.status == .locked, let unlockedAt = level.unlockedAt else {
            return level.status
        }
        return unlockedAt <= now ? .unlocked : .locked
    }

    var activeLevel: LevelView? { levels.first { $0.status == .active } }
    var availableLevel: LevelView? { levels.first { $0.status == .available } }
    var nextLevelView: LevelView? { levels.first { $0.level == nextLevel } }
    var isComplete: Bool { completedLevels == totalLevels }
}

struct CatalogResponse: Codable, Hashable, Sendable {
    var campaigns: [Campaign]
}

// MARK: - Game

enum Direction: String, Codable, Sendable {
    case across, down
}

struct Cell: Codable, Hashable, Sendable, Identifiable {
    var row: Int
    var col: Int
    var letter: String?
    var revealed: Bool
    var hinted: Bool
    var missed: Bool?

    var id: Int { row &* 1000 &+ col }
    var isMissed: Bool { missed ?? false }
}

struct SolutionWord: Codable, Hashable, Sendable, Identifiable {
    var answer: String
    var found: Bool

    var id: String { answer }
}

struct SpeedBonusTier: Codable, Hashable, Sendable {
    var points: Int
    var endsAt: Date
}

struct HintInventory: Codable, Hashable, Sendable {
    var letters: Int
    var brushes: Int
    var words: Int
}

struct HintPrices: Codable, Hashable, Sendable {
    var letter: Int
    var brush: Int
    var word: Int
}

struct SpecialEvent: Codable, Hashable, Sendable {
    var name: String
    var bonusPoints: Int
}

struct GameScore: Codable, Hashable, Sendable {
    var points: Int
    var basePoints: Int
    var speedBonus: Int
    var accuracyBonus: Int
    var hintBonus: Int
    var durationSeconds: Int
}

struct Game: Codable, Hashable, Sendable {
    var campaignId: String
    var level: Int
    var title: String
    var letters: String
    var cells: [Cell]
    var foundWords: Int
    var totalWords: Int
    var attempts: Int
    var rejectedWords: [String]?
    var speedBonuses: [SpeedBonusTier]?
    var hintBonus: Int
    var accuracyBonus: Int
    var hints: HintInventory
    var hintPrices: HintPrices
    var complete: Bool
    var timedOut: Bool?
    var expiresAt: Date?
    var specialEvent: SpecialEvent?
    var score: GameScore?
    var solutionWords: [SolutionWord]?

    var didTimeOut: Bool { timedOut ?? false }
    var rejected: [String] { rejectedWords ?? [] }
    var tiers: [SpeedBonusTier] { speedBonuses ?? [] }
    var rows: Int { (cells.map(\.row).max() ?? 0) + 1 }
    var columns: Int { (cells.map(\.col).max() ?? 0) + 1 }
    var isTerminal: Bool { complete || didTimeOut }
}

// MARK: - Hints

enum HintKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case letter, brush, word

    var id: String { rawValue }

    var label: String {
        switch self {
        case .letter: "Reveal one"
        case .brush: "Reveal two"
        case .word: "Resolve word"
        }
    }

    func remaining(in inventory: HintInventory) -> Int {
        switch self {
        case .letter: inventory.letters
        case .brush: inventory.brushes
        case .word: inventory.words
        }
    }

    func price(in prices: HintPrices) -> Int {
        switch self {
        case .letter: prices.letter
        case .brush: prices.brush
        case .word: prices.word
        }
    }
}

// MARK: - Responses

struct SessionResponse: Codable, Sendable {
    var player: Player
    var catalog: CatalogResponse?
    var game: Game?
}

struct StartGameResponse: Codable, Sendable {
    var player: Player
    var game: Game
}

struct CompletionResponse: Codable, Sendable {
    var player: Player
    var campaign: Campaign?
}

struct GuessResponse: Codable, Sendable {
    var outcome: String
    var game: Game
}

struct HintResponse: Codable, Sendable {
    var outcome: String
    var game: Game
    var pointsSpent: Int?
    var pointsRemaining: Int?
}

struct LeaderboardEntry: Codable, Hashable, Sendable, Identifiable {
    var displayName: String
    var lifetimePointsEarned: Int
    var completedLevels: Int
    var rank: Int

    var id: Int { rank }
}

struct LeaderboardResponse: Codable, Sendable {
    var entries: [LeaderboardEntry]?
}

struct SignedOutResponse: Codable, Sendable {
    var signedOut: Bool
}

struct APIErrorBody: Codable, Sendable {
    var error: String?
}

// MARK: - Guess outcomes

enum GuessOutcome: String, Sendable {
    case found
    case alreadyFound = "already_found"
    case notInPuzzle = "not_in_puzzle"
    case invalidLetters = "invalid_letters"
    case complete
    case timedOut = "timed_out"

    /// The notice copy in web/app.js `submitGuess`. Its lookup table covers only
    /// the four gameplay outcomes and falls through to the raw token for the
    /// rest, so `complete` and `timed_out` are shown verbatim, as on the web.
    static func notice(for outcome: String) -> String {
        switch GuessOutcome(rawValue: outcome) {
        case .found: "Word recorded in history."
        case .alreadyFound: "Already in history."
        case .notInPuzzle: "Not in the wordflow."
        case .invalidLetters: "Those letters cannot make that word."
        default: outcome
        }
    }
}
