import Foundation

/// App-wide owner of the leaderboard service and the local identity. Keeps
/// registration and stat submission in one place so both the Top Players page
/// and RootView (on backgrounding) can sync without duplicating logic.
final class LeaderboardHub {
    static let shared = LeaderboardHub()

    let service: LeaderboardService
    let identityStore: PlayerIdentityStore
    private var lastSubmitted: (stats: PlayerStats, city: CitySnapshot, at: Date)?
    private var inFlight: Task<Void, Error>?

    init(service: LeaderboardService = LeaderboardServiceFactory.make(), identityStore: PlayerIdentityStore = .shared) {
        self.service = service
        self.identityStore = identityStore
    }

    var identity: PlayerIdentity { identityStore.identity }

    /// Registers once, then submits the current stats. Skips the network call
    /// when nothing changed in the last minute.
    func sync(_ session: GameSession) async throws {
        if let inFlight { return try await inFlight.value }
        let task = Task { try await performSync(session) }
        inFlight = task
        defer { inFlight = nil }
        try await task.value
    }

    func syncInBackground(_ session: GameSession) {
        Task { try? await sync(session) }
    }

    private func performSync(_ session: GameSession) async throws {
        try await ensureRegistered()
        session.applyBuilderName(identity.builderName)

        let stats = PlayerStats(session: session)
        let city = CitySnapshot(world: session.world)
        if let lastSubmitted, lastSubmitted.stats == stats, lastSubmitted.city == city,
           Date().timeIntervalSince(lastSubmitted.at) < 60 { return }
        do {
            try await service.submit(stats, city: city, identity: identity)
        } catch {
            // The server doesn't recognise this identity — e.g. a build that had run on the
            // local mock backend marked us "registered" without a real row, or the row was
            // reset server-side. Re-register once under the same id/token and retry so the
            // board self-heals instead of staying stuck on "unauthorized".
            guard Self.isUnknownIdentity(error) else { throw error }
            identityStore.update { $0.isRegistered = false }
            try await ensureRegistered()
            session.applyBuilderName(identity.builderName)
            try await service.submit(stats, city: city, identity: identity)
        }
        lastSubmitted = (stats, city, Date())
    }

    /// Registers the local identity if it isn't yet, persisting the (possibly renamed) result.
    private func ensureRegistered() async throws {
        guard !identity.isRegistered else { return }
        let registered = try await service.register(identity)
        identityStore.update {
            $0.playerId = registered.playerId
            $0.builderName = registered.builderName
            $0.isRegistered = true
        }
    }

    /// True when the backend rejected the identity (unauthorized / player not found), i.e. the
    /// stored "registered" flag is stale and re-registration should be attempted.
    private static func isUnknownIdentity(_ error: Error) -> Bool {
        if case LeaderboardError.playerNotFound = error { return true }
        if case LeaderboardError.server(let message) = error {
            let lower = message.lowercased()
            return lower.contains("unauthorized") || lower.contains("not_found") || lower.contains("not found")
        }
        return false
    }
}

extension PlayerStats {
    init(session: GameSession) {
        let world = session.world
        let player = world.player
        let lifetimeXP = (1..<max(1, player.level)).reduce(0.0) { $0 + ProgressionEngine.experienceToNextLevel(from: $1) } + player.experience
        let outputPerHour = session.buildingReports.values
            .flatMap { $0.production.netPerHour.values }
            .filter { $0 > 0 }
            .reduce(0, +)

        self.init(
            level: player.level,
            totalExperience: Int(lifetimeXP),
            buildings: world.buildings.count,
            modules: world.buildings.values.reduce(0) { $0 + $1.modules.count },
            productionPerMinute: Int(outputPerHour / 60),
            synergies: player.discoveredSynergyIDs.count,
            tallestBuilding: world.buildings.values.map { ($0.modules.keys.map(\.y).max() ?? -1) + 1 }.max() ?? 0,
            skybridgeContribution: Int(world.worldProject?.contributed.values.reduce(0, +) ?? 0),
            cityOrdersCompleted: world.completedCityOrders ?? 0
        )
    }
}

extension CitySnapshot {
    /// Built modules only, so visitors see the city as it stands.
    init(world: GameWorld) {
        let buildings = world.buildings.values
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .compactMap { building -> CityBuilding? in
                let modules = building.modules.values
                    .filter(\.isBuilt)
                    .sorted { $0.position < $1.position }
                    .map { CityModule(definitionId: $0.definitionID, family: $0.definition?.family.rawValue ?? "foundation",
                                      x: $0.position.x, y: $0.position.y) }
                guard !modules.isEmpty else { return nil }
                return CityBuilding(id: building.id.uuidString.lowercased(), name: building.displayName,
                                    buildingClass: building.buildingClass.rawValue, modules: modules)
            }
        self.init(buildings: buildings)
    }
}
