import Foundation

/// Talks to the Supabase RPCs defined in `supabase/migrations/*_leaderboard.sql`
/// over plain PostgREST HTTP — no SDK dependency. Every call is
/// `POST /rest/v1/rpc/<function>` with snake_case JSON params prefixed `p_`
/// (to avoid clashing with column names inside the plpgsql bodies).
///
/// Errors raised in SQL with `raise exception '<code>'` come back as a 400
/// whose `message` is that code; `mapError` turns the known ones into
/// `LeaderboardError` so the page shows a friendly message.
final class SupabaseLeaderboardService: LeaderboardService {
    private let projectURL: URL
    private let anonKey: String
    private let session: URLSession

    init(projectURL: URL, anonKey: String, session: URLSession = .shared) {
        self.projectURL = projectURL
        self.anonKey = anonKey
        self.session = session
    }

    // MARK: - LeaderboardService

    func register(_ identity: PlayerIdentity) async throws -> RegisteredPlayer {
        try await rpc("register_player", Auth(identity, extra: ["p_builder_name": .string(identity.builderName)]))
    }

    func submit(_ stats: PlayerStats, city: CitySnapshot, identity: PlayerIdentity) async throws {
        struct Params: Encodable {
            let pPlayerId: String
            let pToken: String
            let pStats: PlayerStats
            let pCity: CitySnapshot
        }
        let _: EmptyResponse = try await rpc("submit_stats", Params(pPlayerId: identity.playerId, pToken: identity.token, pStats: stats, pCity: city))
    }

    func leaderboard(_ category: LeaderboardCategory, identity: PlayerIdentity) async throws -> LeaderboardPage {
        try await rpc("get_leaderboard", Auth(identity, includeToken: false, extra: [
            "p_category": .string(category.rawValue), "p_limit": .int(50),
        ]))
    }

    func league(identity: PlayerIdentity) async throws -> LeagueStanding {
        try await rpc("get_league", Auth(identity, includeToken: false))
    }

    func factionWar(identity: PlayerIdentity) async throws -> FactionWar {
        try await rpc("get_faction_war", Auth(identity, includeToken: false))
    }

    func joinFaction(_ faction: Faction, identity: PlayerIdentity) async throws -> FactionWar {
        try await rpc("join_faction", Auth(identity, extra: ["p_faction": .string(faction.rawValue)]))
    }

    func player(_ playerId: String, identity: PlayerIdentity) async throws -> PlayerCard {
        try await rpc("get_player", Auth(identity, includeToken: false, extra: ["p_target_id": .string(playerId)]))
    }

    func giftStatus(identity: PlayerIdentity) async throws -> GiftStatus {
        try await rpc("get_gift_status", Auth(identity))
    }

    func sendGift(to playerId: String, identity: PlayerIdentity) async throws -> GiftStatus {
        try await rpc("send_gift", Auth(identity, extra: ["p_target_id": .string(playerId)]))
    }

    func claimGifts(identity: PlayerIdentity) async throws -> GiftClaim {
        try await rpc("claim_gifts", Auth(identity))
    }

    // MARK: - Transport

    private func rpc<Params: Encodable, Response: Decodable>(_ function: String, _ params: Params) async throws -> Response {
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/\(function)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .millisecondsSince1970
        request.httpBody = try encoder.encode(params)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw Self.mapError(data: data, status: status) }

        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response { return empty }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Response.self, from: data)
    }

    static func mapError(data: Data, status: Int) -> Error {
        struct PostgrestError: Decodable { let message: String? }
        let message = (try? JSONDecoder().decode(PostgrestError.self, from: data))?.message ?? "HTTP \(status)"
        switch message {
        case "gift_already_sent": return LeaderboardError.giftAlreadySentToday
        case "cannot_gift_self": return LeaderboardError.cannotGiftYourself
        case "faction_locked": return LeaderboardError.factionLocked
        case "player_not_found": return LeaderboardError.playerNotFound
        default: return LeaderboardError.server(message)
        }
    }
}

private struct EmptyResponse: Decodable {}

/// `p_player_id` (+ `p_token`) plus any extra scalar params. Keys in `extra`
/// are already snake_case and survive `convertToSnakeCase` unchanged.
private struct Auth: Encodable {
    enum Value: Encodable {
        case string(String), int(Int)

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value): try container.encode(value)
            case .int(let value): try container.encode(value)
            }
        }
    }

    private var values: [String: Value]

    init(_ identity: PlayerIdentity, includeToken: Bool = true, extra: [String: Value] = [:]) {
        values = extra
        values["p_player_id"] = .string(identity.playerId)
        if includeToken { values["p_token"] = .string(identity.token) }
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for (key, value) in values { try container.encode(value, forKey: Key(key)) }
    }
}
