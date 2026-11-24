import Foundation

/// Everything the Top Players screen needs from a backend. Two implementations:
/// `MockLeaderboardService` (local fake players, used until Supabase is
/// configured) and `SupabaseLeaderboardService` (RPCs from
/// `supabase/migrations`). Each method maps 1:1 to one RPC there.
protocol LeaderboardService: AnyObject {
    /// Creates the player row (idempotent). The backend may change the number
    /// in "Builder nnnn" if it's taken.
    func register(_ identity: PlayerIdentity) async throws -> RegisteredPlayer
    func submit(_ stats: PlayerStats, city: CitySnapshot, identity: PlayerIdentity) async throws
    func leaderboard(_ category: LeaderboardCategory, identity: PlayerIdentity) async throws -> LeaderboardPage
    func league(identity: PlayerIdentity) async throws -> LeagueStanding
    func factionWar(identity: PlayerIdentity) async throws -> FactionWar
    func joinFaction(_ faction: Faction, identity: PlayerIdentity) async throws -> FactionWar
    func player(_ playerId: String, identity: PlayerIdentity) async throws -> PlayerCard
    func giftStatus(identity: PlayerIdentity) async throws -> GiftStatus
    func sendGift(to playerId: String, identity: PlayerIdentity) async throws -> GiftStatus
    /// Marks the inbox claimed and returns how many blocks to grant locally.
    func claimGifts(identity: PlayerIdentity) async throws -> GiftClaim
}

/// Fill these in (Supabase Dashboard → Project Settings → API) to switch the
/// app from fake players to the real backend. The anon key is public by
/// design; the tables are locked by RLS and only the RPCs are callable.
enum SupabaseConfig {
    static let projectURL = "https://yejxhqnjwtzoxiqsfrrs.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InllanhocW5qd3R6b3hpcXNmcnJzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTU0Mzc0NTUsImV4cCI6MjExMTAxMzQ1NX0.7tBxabkpAOWyeFWIYW8sa-PXZQhiGCwLJ-a-7hFh6zw"

    static var isConfigured: Bool { URL(string: projectURL) != nil && !projectURL.isEmpty && !anonKey.isEmpty }
}

enum LeaderboardServiceFactory {
    static func make() -> LeaderboardService {
        if SupabaseConfig.isConfigured, let url = URL(string: SupabaseConfig.projectURL) {
            return SupabaseLeaderboardService(projectURL: url, anonKey: SupabaseConfig.anonKey)
        }
        return MockLeaderboardService()
    }
}
