import Foundation

/// Who this device is on the leaderboard. Lives outside the save file on
/// purpose: "Reset Game" starts a fresh city, not a fresh public identity.
///
/// There's no account system — the player is a random UUID plus a public
/// "Builder nnnn" name, and `token` is a device secret the backend checks so
/// one player can't trivially write another's row.
nonisolated struct PlayerIdentity: Codable, Equatable, Sendable {
    var playerId: String
    var builderName: String
    var token: String
    var isRegistered: Bool

    /// Client-side rival tracking (see `TopPlayersBridge`): who was above us in
    /// the league the last time the page looked, per season.
    var rivalSeasonId: String?
    var playersAboveIds: [String]?

    static func generate() -> PlayerIdentity {
        PlayerIdentity(
            playerId: UUID().uuidString.lowercased(),
            builderName: makeBuilderName(),
            token: UUID().uuidString.lowercased() + UUID().uuidString.lowercased(),
            isRegistered: false
        )
    }

    static func makeBuilderName<G: RandomNumberGenerator>(using generator: inout G) -> String {
        "Builder \(Int.random(in: 1000...9999, using: &generator))"
    }

    static func makeBuilderName() -> String {
        var generator = SystemRandomNumberGenerator()
        return makeBuilderName(using: &generator)
    }
}

final class PlayerIdentityStore {
    static let shared = PlayerIdentityStore()

    private let defaults: UserDefaults
    private let key = "islora.leaderboard.identity"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored identity, created (and persisted) on first access.
    var identity: PlayerIdentity {
        get {
            if let data = defaults.data(forKey: key),
               let stored = try? JSONDecoder().decode(PlayerIdentity.self, from: data) {
                return stored
            }
            let fresh = PlayerIdentity.generate()
            self.identity = fresh
            return fresh
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    func update(_ change: (inout PlayerIdentity) -> Void) {
        var current = identity
        change(&current)
        identity = current
    }
}
