import Foundation

/// Offline stand-in for Supabase so the whole Top Players flow is playable
/// before the backend exists. Follows the same rules the SQL implements
/// (`LeagueRules`, `GiftRules`, one faction pick per season) so switching to
/// the real service changes data, not behavior.
///
/// Fake players are generated from a fixed seed (a stable roster across
/// launches) and their weekly scores grow with how far into the season we
/// are, so the league visibly moves while you play.
final class MockLeaderboardService: LeaderboardService {
    private let defaults: UserDefaults
    private let now: () -> Date
    private var myStats: PlayerStats?
    private var myCity = CitySnapshot(buildings: [])
    private lazy var roster: [FakePlayer] = Self.makeRoster()

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    // MARK: - LeaderboardService

    func register(_ identity: PlayerIdentity) async throws -> RegisteredPlayer {
        RegisteredPlayer(playerId: identity.playerId, builderName: identity.builderName)
    }

    func submit(_ stats: PlayerStats, city: CitySnapshot, identity: PlayerIdentity) async throws {
        myStats = stats
        myCity = city
        let key = "mock.seasonStartXP.\(season.id)"
        if defaults.object(forKey: key) == nil { defaults.set(stats.totalExperience, forKey: key) }
    }

    func leaderboard(_ category: LeaderboardCategory, identity: PlayerIdentity) async throws -> LeaderboardPage {
        var rows = roster.map { fake in
            LeaderboardEntry(playerId: fake.id, builderName: fake.name, faction: fake.faction, tier: nil,
                             rank: 0, score: fake.stats.score(for: category), level: fake.stats.level, isMe: false)
        }
        if let myStats {
            rows.append(LeaderboardEntry(playerId: identity.playerId, builderName: identity.builderName, faction: myFaction,
                                         tier: tier, rank: 0, score: myStats.score(for: category), level: myStats.level, isMe: true))
        }
        let ranked = Self.ranked(rows)
        return LeaderboardPage(category: category, entries: Array(ranked.prefix(50)), me: ranked.first(where: \.isMe))
    }

    func league(identity: PlayerIdentity) async throws -> LeagueStanding {
        rollSeasonIfNeeded()
        let currentTier = tier
        let progress = season.progress(now: now())
        var generator = SeededGenerator(seed: Self.hash("league-\(season.id)-\(currentTier.rawValue)"))
        let opponents = roster.shuffled(using: &generator).prefix(LeagueRules.groupSize - 1)

        var rows = opponents.map { fake in
            LeaderboardEntry(playerId: fake.id, builderName: fake.name, faction: fake.faction, tier: currentTier, rank: 0,
                             score: fake.weeklyScore(season: season.id, progress: progress, tier: currentTier),
                             level: fake.stats.level, isMe: false)
        }
        rows.append(LeaderboardEntry(playerId: identity.playerId, builderName: identity.builderName, faction: myFaction,
                                     tier: currentTier, rank: 0, score: myWeeklyScore, level: myStats?.level ?? 1, isMe: true))
        let ranked = Self.ranked(rows)
        defaults.set(ranked.first(where: \.isMe)?.rank, forKey: "mock.lastLeagueRank")
        return LeagueStanding(season: season, tier: currentTier, entries: ranked,
                              promoteCount: LeagueRules.promoteCount, demoteCount: LeagueRules.demoteCount)
    }

    func factionWar(identity: PlayerIdentity) async throws -> FactionWar {
        let progress = season.progress(now: now())
        let standings = Faction.allCases.map { faction -> FactionStanding in
            let members = roster.filter { $0.faction == faction }
            var score = members.reduce(0) { $0 + $1.weeklyScore(season: season.id, progress: progress, tier: .gold) }
            var count = members.count
            if myFaction == faction {
                score += myWeeklyScore
                count += 1
            }
            return FactionStanding(faction: faction, score: score, members: count, rank: 0)
        }
        .sorted { $0.score > $1.score }
        .enumerated()
        .map { index, standing in
            var standing = standing
            standing.rank = index + 1
            return standing
        }

        var generator = SeededGenerator(seed: Self.hash("winner-\(season.id)"))
        return FactionWar(season: season, standings: standings, myFaction: myFaction,
                          canSwitch: defaults.string(forKey: "mock.factionSeason") != season.id,
                          lastWinner: Faction.allCases.randomElement(using: &generator))
    }

    func joinFaction(_ faction: Faction, identity: PlayerIdentity) async throws -> FactionWar {
        guard defaults.string(forKey: "mock.factionSeason") != season.id else { throw LeaderboardError.factionLocked }
        defaults.set(faction.rawValue, forKey: "mock.faction")
        defaults.set(season.id, forKey: "mock.factionSeason")
        return try await factionWar(identity: identity)
    }

    func player(_ playerId: String, identity: PlayerIdentity) async throws -> PlayerCard {
        if playerId == identity.playerId {
            return PlayerCard(playerId: playerId, builderName: identity.builderName, faction: myFaction, tier: tier,
                              stats: myStats ?? Self.emptyStats, city: myCity, isMe: true)
        }
        guard let fake = roster.first(where: { $0.id == playerId }) else { throw LeaderboardError.playerNotFound }
        return PlayerCard(playerId: fake.id, builderName: fake.name, faction: fake.faction, tier: nil,
                          stats: fake.stats, city: fake.city, isMe: false)
    }

    func giftStatus(identity: PlayerIdentity) async throws -> GiftStatus {
        let sentToday = defaults.string(forKey: "mock.gift.sentDay") == today
        return GiftStatus(canSendToday: !sentToday,
                          sentTodayTo: sentToday ? defaults.string(forKey: "mock.gift.sentTo") : nil,
                          inbox: inbox)
    }

    func sendGift(to playerId: String, identity: PlayerIdentity) async throws -> GiftStatus {
        guard playerId != identity.playerId else { throw LeaderboardError.cannotGiftYourself }
        guard defaults.string(forKey: "mock.gift.sentDay") != today else { throw LeaderboardError.giftAlreadySentToday }
        guard roster.contains(where: { $0.id == playerId }) else { throw LeaderboardError.playerNotFound }
        defaults.set(today, forKey: "mock.gift.sentDay")
        defaults.set(playerId, forKey: "mock.gift.sentTo")
        // Fake players "claim" instantly, so the thank-you is waiting next time.
        defaults.set((defaults.stringArray(forKey: "mock.gift.thanksDays") ?? []) + [today], forKey: "mock.gift.thanksDays")
        return try await giftStatus(identity: identity)
    }

    func claimGifts(identity: PlayerIdentity) async throws -> GiftClaim {
        let gifts = inbox
        let claimed = (defaults.stringArray(forKey: "mock.gift.claimed") ?? []) + gifts.map(\.id)
        defaults.set(Array(claimed.suffix(60)), forKey: "mock.gift.claimed")
        defaults.set([String](), forKey: "mock.gift.thanksDays")
        return GiftClaim(claimedCount: gifts.count, blocks: gifts.reduce(0) { $0 + $1.blocks })
    }

    // MARK: - Local player state

    private var season: SeasonInfo { SeasonInfo.current(now: now()) }

    private var tier: LeagueTier {
        defaults.string(forKey: "mock.tier").flatMap(LeagueTier.init(rawValue:)) ?? .bronze
    }

    private var myFaction: Faction? {
        defaults.string(forKey: "mock.faction").flatMap(Faction.init(rawValue:))
    }

    private var myWeeklyScore: Int {
        guard let myStats else { return 0 }
        let start = defaults.object(forKey: "mock.seasonStartXP.\(season.id)") as? Int ?? myStats.totalExperience
        return max(0, myStats.totalExperience - start)
    }

    /// The SQL does this in a weekly cron job; the mock does it lazily the
    /// first time the league is opened in a new season, from the last rank seen.
    private func rollSeasonIfNeeded() {
        let lastSeason = defaults.string(forKey: "mock.tierSeason")
        guard lastSeason != season.id else { return }
        if lastSeason != nil, let lastRank = defaults.object(forKey: "mock.lastLeagueRank") as? Int {
            if lastRank <= LeagueRules.promoteCount {
                defaults.set(tier.promoted.rawValue, forKey: "mock.tier")
            } else if lastRank > LeagueRules.groupSize - LeagueRules.demoteCount {
                defaults.set(tier.demoted.rawValue, forKey: "mock.tier")
            }
        }
        defaults.set(season.id, forKey: "mock.tierSeason")
    }

    private var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: now())
    }

    private var inbox: [Gift] {
        let claimed = Set(defaults.stringArray(forKey: "mock.gift.claimed") ?? [])
        var gifts: [Gift] = []

        // One fake player sends you something every day.
        var generator = SeededGenerator(seed: Self.hash("gift-\(today)"))
        if let sender = roster.randomElement(using: &generator), !claimed.contains("gift-\(today)") {
            gifts.append(Gift(id: "gift-\(today)", fromPlayerId: sender.id, fromName: sender.name, kind: .gift,
                              blocks: GiftRules.giftBlocks, createdAt: now()))
        }
        for day in defaults.stringArray(forKey: "mock.gift.thanksDays") ?? [] where !claimed.contains("thanks-\(day)") {
            let recipientID = defaults.string(forKey: "mock.gift.sentTo")
            let recipient = roster.first(where: { $0.id == recipientID })
            gifts.append(Gift(id: "thanks-\(day)", fromPlayerId: recipient?.id ?? "", fromName: recipient?.name ?? "A builder",
                              kind: .thanks, blocks: GiftRules.thanksBlocks, createdAt: now()))
        }
        return gifts
    }

    // MARK: - Fake roster

    private struct FakePlayer {
        let id: String
        let name: String
        let faction: Faction
        let stats: PlayerStats
        let city: CitySnapshot

        /// Weekly XP so far: a per-season pace times season progress, scaled by tier.
        func weeklyScore(season: String, progress: Double, tier: LeagueTier) -> Int {
            var generator = SeededGenerator(seed: MockLeaderboardService.hash("pace-\(season)-\(id)"))
            let xpPerWeek = Double.random(in: 150...2_600, using: &generator)
            let tierScale: [LeagueTier: Double] = [.bronze: 0.45, .silver: 0.7, .gold: 1, .platinum: 1.4, .diamond: 2]
            return Int(xpPerWeek * progress * (tierScale[tier] ?? 1))
        }
    }

    private static let emptyStats = PlayerStats(level: 1, totalExperience: 0, buildings: 0, modules: 0, productionPerMinute: 0,
                                                synergies: 0, tallestBuilding: 0, skybridgeContribution: 0, cityOrdersCompleted: 0)

    private static func makeRoster() -> [FakePlayer] {
        var generator = SeededGenerator(seed: 0x15_10_7A)
        var usedNames = Set<String>()
        return (0..<80).map { index in
            var name = PlayerIdentity.makeBuilderName(using: &generator)
            while !usedNames.insert(name).inserted { name = PlayerIdentity.makeBuilderName(using: &generator) }

            let level = 1 + Int(pow(Double.random(in: 0...1, using: &generator), 1.6) * 11)
            let totalXP = (1..<level).reduce(0.0) { $0 + ProgressionEngine.experienceToNextLevel(from: $1) }
                + Double.random(in: 0..<ProgressionEngine.experienceToNextLevel(from: level), using: &generator)
            let tallest = min(8, 2 + level / 2 + Int.random(in: 0...2, using: &generator))
            let city = makeCity(level: level, tallest: tallest, seed: UInt64(index) &+ 0xC17)
            let stats = PlayerStats(
                level: level,
                totalExperience: Int(totalXP),
                buildings: city.buildings.count,
                modules: city.buildings.reduce(0) { $0 + $1.modules.count },
                productionPerMinute: level * Int.random(in: 15...60, using: &generator),
                synergies: min(16, max(0, level + Int.random(in: -1...3, using: &generator))),
                tallestBuilding: tallest,
                skybridgeContribution: level * Int.random(in: 0...400, using: &generator),
                cityOrdersCompleted: level * Int.random(in: 2...9, using: &generator)
            )
            return FakePlayer(id: String(format: "00000000-0000-4000-8000-%012d", index + 1), name: name,
                              faction: Faction.allCases.randomElement(using: &generator) ?? .coast, stats: stats, city: city)
        }
    }

    /// Foundations along the ground row, then columns stacked straight up so
    /// every module is supported — an "Inspire" copy stays physically buildable.
    private static func makeCity(level: Int, tallest: Int, seed: UInt64) -> CitySnapshot {
        var generator = SeededGenerator(seed: seed)
        let palettes: [(BuildingClass, [String])] = [
            (.farm, ["farm_field", "greenhouse", "water_tank", "processing_unit", "solar_panel", "office_basic", "storage_crate"]),
            (.powerPlant, ["power_generator", "battery_bank", "solar_panel", "structural_core", "office_basic"]),
            (.dataCenter, ["server_rack", "cooling_unit", "solar_panel", "structural_core", "storage_crate"]),
        ]
        let unlocked = palettes.filter { ProgressionEngine.isBuildingClassUnlocked($0.0, level: level) }
        let count = min(unlocked.count, 1 + level / 3)

        let buildings = unlocked.prefix(count).enumerated().map { index, entry -> CityBuilding in
            let (buildingClass, pool) = entry
            let width = Int.random(in: 2...4, using: &generator)
            let height = index == 0 ? tallest : Int.random(in: 2...max(2, tallest - 1), using: &generator)
            var modules: [CityModule] = []
            for x in 0..<width {
                modules.append(module("foundation_basic", x: x, y: 0))
                let column = x == 0 ? height : Int.random(in: 1...height, using: &generator)
                for y in 1..<max(1, column) {
                    modules.append(module(pool.randomElement(using: &generator) ?? "office_basic", x: x, y: y))
                }
            }
            return CityBuilding(id: "\(seed)-\(index)", name: buildingClass.displayName,
                                buildingClass: buildingClass.rawValue, modules: modules)
        }
        return CitySnapshot(buildings: buildings)
    }

    private static func module(_ definitionId: String, x: Int, y: Int) -> CityModule {
        CityModule(definitionId: definitionId, family: ModuleCatalog.definition(for: definitionId)?.family.rawValue ?? "foundation", x: x, y: y)
    }

    private static func ranked(_ rows: [LeaderboardEntry]) -> [LeaderboardEntry] {
        rows.sorted { $0.score != $1.score ? $0.score > $1.score : $0.builderName < $1.builderName }
            .enumerated()
            .map { index, row in
                var row = row
                row.rank = index + 1
                return row
            }
    }

    /// FNV-1a — stable across launches, unlike `Hasher`.
    static func hash(_ string: String) -> UInt64 {
        string.utf8.reduce(0xcbf2_9ce4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01b3 }
    }
}

/// SplitMix64: tiny deterministic generator for reproducible fake data.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
