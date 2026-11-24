import Foundation

/// Request/response bridge between `top-players.html` and the game.
///
/// The page calls `Islora.call(method, params)` which posts
/// `{type: "request", id, method, params}`; `handle` answers with JSON the
/// web view passes to `window.IsloraBridge.resolve(id, ok, payload)`.
/// The page never talks to Supabase itself — all data goes through the
/// `LeaderboardService`, so swapping mock → Supabase needs no page changes.
///
/// | method          | params                   | returns         |
/// |-----------------|--------------------------|-----------------|
/// | getMe           | –                        | MeResponse      |
/// | getLeague       | –                        | LeagueResponse  |
/// | getLeaderboard  | category                 | LeaderboardPage |
/// | getFactions     | –                        | FactionWar      |
/// | joinFaction     | faction                  | FactionWar      |
/// | getPlayer       | playerId                 | PlayerCard      |
/// | getGifts        | –                        | GiftStatus      |
/// | sendGift        | playerId                 | GiftStatus      |
/// | claimGifts      | –                        | GiftClaim       |
/// | inspire         | playerId, buildingId     | InspireResponse |
final class TopPlayersBridge {
    private let session: GameSession
    private let hub: LeaderboardHub
    private var cards: [String: PlayerCard] = [:]

    init(session: GameSession, hub: LeaderboardHub = .shared) {
        self.session = session
        self.hub = hub
    }

    struct MeResponse: Encodable {
        let playerId: String
        let builderName: String
        let stats: PlayerStats
        let season: SeasonInfo
    }

    struct RivalInfo: Encodable {
        /// The player one place above, or nil when we're first.
        let rival: LeaderboardEntry?
        let gap: Int
        /// Weekly XP still needed to reach the promotion zone (nil if already in it).
        let promotionGap: Int?
        /// Players who moved above us since the page was last opened this season.
        let overtakenBy: [String]
    }

    struct LeagueResponse: Encodable {
        let standing: LeagueStanding
        let rival: RivalInfo?
    }

    struct InspireResponse: Encodable {
        let blueprintName: String
    }

    /// Returns the JSON payload for the page, or throws (the message is shown as a toast).
    func handle(method: String, params: [String: Any]) async throws -> Data {
        switch method {
        case "getMe":
            try await hub.sync(session)
            let identity = hub.identity
            return try encode(MeResponse(playerId: identity.playerId, builderName: identity.builderName,
                                         stats: PlayerStats(session: session), season: .current()))

        case "getLeague":
            try await hub.sync(session)
            let standing = try await hub.service.league(identity: hub.identity)
            return try encode(LeagueResponse(standing: standing, rival: trackRival(in: standing)))

        case "getLeaderboard":
            let category = LeaderboardCategory(rawValue: params["category"] as? String ?? "") ?? .level
            return try encode(try await hub.service.leaderboard(category, identity: hub.identity))

        case "getFactions":
            return try encode(try await hub.service.factionWar(identity: hub.identity))

        case "joinFaction":
            guard let faction = Faction(rawValue: params["faction"] as? String ?? "") else { throw BridgeError.badParams }
            return try encode(try await hub.service.joinFaction(faction, identity: hub.identity))

        case "getPlayer":
            let card = try await hub.service.player(try string("playerId", in: params), identity: hub.identity)
            cards[card.playerId] = card
            return try encode(card)

        case "getGifts":
            return try encode(try await hub.service.giftStatus(identity: hub.identity))

        case "sendGift":
            return try encode(try await hub.service.sendGift(to: try string("playerId", in: params), identity: hub.identity))

        case "claimGifts":
            let claim = try await hub.service.claimGifts(identity: hub.identity)
            session.grantLeaderboardReward([.blocks: Double(claim.blocks)])
            return try encode(claim)

        case "inspire":
            let playerId = try string("playerId", in: params)
            let buildingId = try string("buildingId", in: params)
            let card: PlayerCard
            if let cached = cards[playerId] {
                card = cached
            } else {
                card = try await hub.service.player(playerId, identity: hub.identity)
            }
            guard let building = card.city.buildings.first(where: { $0.id == buildingId }),
                  let blueprint = session.importInspiredBlueprint(building, author: card.builderName) else {
                throw BridgeError.nothingToInspire
            }
            return try encode(InspireResponse(blueprintName: blueprint.name))

        default:
            throw BridgeError.unknownMethod(method)
        }
    }

    /// Rival = the entry right above us. "Overtaken" is computed on device by
    /// diffing who's above us against what we saw last time this season, so
    /// it works identically with the mock and with Supabase.
    private func trackRival(in standing: LeagueStanding) -> RivalInfo? {
        guard let me = standing.entries.first(where: \.isMe) else { return nil }
        let above = standing.entries.filter { $0.rank < me.rank }
        let identity = hub.identity

        var overtakenBy: [String] = []
        if identity.rivalSeasonId == standing.season.id, let previous = identity.playersAboveIds {
            let previousSet = Set(previous)
            overtakenBy = above.filter { !previousSet.contains($0.playerId) }.map(\.builderName)
        }
        hub.identityStore.update {
            $0.rivalSeasonId = standing.season.id
            $0.playersAboveIds = above.map(\.playerId)
        }

        let rival = above.last
        let promotionLine = standing.entries.first { $0.rank == standing.promoteCount }
        let promotionGap = me.rank > standing.promoteCount ? promotionLine.map { $0.score - me.score + 1 } : nil
        return RivalInfo(rival: rival, gap: rival.map { $0.score - me.score } ?? 0,
                         promotionGap: promotionGap, overtakenBy: overtakenBy)
    }

    private func string(_ key: String, in params: [String: Any]) throws -> String {
        guard let value = params[key] as? String, !value.isEmpty else { throw BridgeError.badParams }
        return value
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(value)
    }

    enum BridgeError: LocalizedError {
        case unknownMethod(String)
        case badParams
        case nothingToInspire

        var errorDescription: String? {
            switch self {
            case .unknownMethod(let method): return "Unknown request: \(method)"
            case .badParams: return "Invalid request."
            case .nothingToInspire: return "This building can't be copied."
            }
        }
    }
}
