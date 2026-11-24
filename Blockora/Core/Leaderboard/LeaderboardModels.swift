import Foundation

// DTOs shared by every LeaderboardService implementation, the Supabase RPC
// layer and the Top Players page. Property names are camelCase here, snake_case
// on the wire to Supabase (`convertFromSnakeCase`), and camelCase again in the
// JSON handed to the page — so a field rename touches this file, the SQL in
// `supabase/migrations` and `top-players.html` together.
//
// Ids are plain strings (UUID text) and every timestamp is epoch milliseconds,
// which is the one date format Postgres, Swift and JS all agree on trivially.

enum LeaderboardCategory: String, Codable, CaseIterable, Sendable {
    case level, production, synergies, tallest, skybridge
}

enum LeagueTier: String, Codable, CaseIterable, Sendable, Comparable {
    case bronze, silver, gold, platinum, diamond

    var promoted: LeagueTier { Self.allCases[min(index + 1, Self.allCases.count - 1)] }
    var demoted: LeagueTier { Self.allCases[max(index - 1, 0)] }

    private var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    static func < (lhs: LeagueTier, rhs: LeagueTier) -> Bool { lhs.index < rhs.index }
}

enum Faction: String, Codable, CaseIterable, Sendable {
    case coast, highland, delta
}

/// Rules shared by the mock and documented for the SQL side.
enum LeagueRules {
    static let groupSize = 30
    static let promoteCount = 5
    static let demoteCount = 5
}

enum GiftRules {
    /// Blocks the recipient gets for a gift.
    static let giftBlocks = 2
    /// Blocks the sender gets back once the recipient claims it.
    static let thanksBlocks = 1
    static let dailySendLimit = 1
}

/// Weekly season id (`2026-W48`) and its end, both in UTC so every player
/// worldwide flips to the next season at the same instant.
nonisolated struct SeasonInfo: Codable, Equatable, Sendable {
    var id: String
    var endsAt: Date

    static func current(now: Date = Date()) -> SeasonInfo {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        let start = calendar.date(from: components) ?? now
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
        let id = String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
        return SeasonInfo(id: id, endsAt: end)
    }

    /// 0...1 of the way through the season.
    func progress(now: Date = Date()) -> Double {
        let start = endsAt.addingTimeInterval(-7 * 86_400)
        return min(1, max(0, now.timeIntervalSince(start) / (7 * 86_400)))
    }
}

/// The local player's numbers, submitted to the backend and pushed live to the page.
nonisolated struct PlayerStats: Codable, Equatable, Sendable {
    var level: Int
    /// Lifetime XP (the profile only stores XP *within* the current level).
    var totalExperience: Int
    var buildings: Int
    var modules: Int
    var productionPerMinute: Int
    var synergies: Int
    /// Rows of the tallest building.
    var tallestBuilding: Int
    var skybridgeContribution: Int
    var cityOrdersCompleted: Int

    func score(for category: LeaderboardCategory) -> Int {
        switch category {
        case .level: return totalExperience
        case .production: return productionPerMinute
        case .synergies: return synergies
        case .tallest: return tallestBuilding
        case .skybridge: return skybridgeContribution
        }
    }
}

/// A read-only copy of a city's layout, enough for the page to render it and
/// for "Inspire" to turn one building into a Blueprint.
nonisolated struct CitySnapshot: Codable, Equatable, Sendable {
    var buildings: [CityBuilding]
}

nonisolated struct CityBuilding: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var buildingClass: String
    var modules: [CityModule]
}

nonisolated struct CityModule: Codable, Equatable, Sendable {
    var definitionId: String
    var family: String
    var x: Int
    var y: Int
}

nonisolated struct LeaderboardEntry: Codable, Equatable, Sendable {
    var playerId: String
    var builderName: String
    var faction: Faction?
    var tier: LeagueTier?
    var rank: Int
    var score: Int
    var level: Int
    var isMe: Bool
}

nonisolated struct LeaderboardPage: Codable, Equatable, Sendable {
    var category: LeaderboardCategory
    var entries: [LeaderboardEntry]
    /// The local player's own row, even when outside `entries`.
    var me: LeaderboardEntry?
}

nonisolated struct LeagueStanding: Codable, Equatable, Sendable {
    var season: SeasonInfo
    var tier: LeagueTier
    /// The whole group, sorted by weekly score (rank 1 first).
    var entries: [LeaderboardEntry]
    var promoteCount: Int
    var demoteCount: Int
}

nonisolated struct FactionStanding: Codable, Equatable, Sendable {
    var faction: Faction
    var score: Int
    var members: Int
    var rank: Int
}

nonisolated struct FactionWar: Codable, Equatable, Sendable {
    var season: SeasonInfo
    var standings: [FactionStanding]
    var myFaction: Faction?
    /// Faction can be picked once per season.
    var canSwitch: Bool
    var lastWinner: Faction?
}

nonisolated struct PlayerCard: Codable, Equatable, Sendable {
    var playerId: String
    var builderName: String
    var faction: Faction?
    var tier: LeagueTier?
    var stats: PlayerStats
    var city: CitySnapshot
    var isMe: Bool
}

nonisolated struct Gift: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case gift, thanks }

    var id: String
    var fromPlayerId: String
    var fromName: String
    var kind: Kind
    var blocks: Int
    var createdAt: Date
}

nonisolated struct GiftStatus: Codable, Equatable, Sendable {
    var canSendToday: Bool
    /// Who got today's gift, so the page can mark them.
    var sentTodayTo: String?
    var inbox: [Gift]
}

nonisolated struct GiftClaim: Codable, Equatable, Sendable {
    var claimedCount: Int
    var blocks: Int
}

nonisolated struct RegisteredPlayer: Codable, Equatable, Sendable {
    var playerId: String
    /// The backend may hand back a different number if the proposed one is taken.
    var builderName: String
}

enum LeaderboardError: LocalizedError {
    case giftAlreadySentToday
    case cannotGiftYourself
    case factionLocked
    case playerNotFound
    case server(String)

    var errorDescription: String? {
        switch self {
        case .giftAlreadySentToday: return "You've already sent today's gift."
        case .cannotGiftYourself: return "You can't send a gift to yourself."
        case .factionLocked: return "You can switch faction when the next season starts."
        case .playerNotFound: return "Player not found."
        case .server(let message): return message
        }
    }
}
