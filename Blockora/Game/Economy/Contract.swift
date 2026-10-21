import Foundation

/// A server-generated (in MVP: locally generated, same shape) request the city
/// can fulfil for a reward (§22). Renamed internally from "trading" to
/// "demand fulfilment" per §21 — the player supplies, they don't speculate.
struct Contract: Identifiable, Codable {
    let id: UUID
    var title: String
    var flavorText: String
    var requiredResources: ResourceBag
    var rewardResources: ResourceBag
    var rewardExperience: Double
    var duration: TimeInterval
    var status: ContractStatus
    var acceptedAt: Date?
    /// Missing in legacy saves; new orders keep their delivery lane when replaced.
    var lane: Int? = nil

    func isExpired(now: Date) -> Bool {
        guard let acceptedAt else { return false }
        return now.timeIntervalSince(acceptedAt) > duration
    }

    func timeRemaining(now: Date) -> TimeInterval {
        guard let acceptedAt else { return duration }
        return max(0, duration - now.timeIntervalSince(acceptedAt))
    }
}

enum ContractStatus: String, Codable {
    case available
    case accepted
    case completed
    case expired
}

/// Pure resolution logic for contracts — no persistence, no networking.
enum EconomyEngine {
    static func canComplete(_ contract: Contract, playerResources: ResourceBag) -> Bool {
        contract.status == .accepted && !contract.isExpired(now: Date()) && playerResources.canAfford(contract.requiredResources)
    }

    /// Deducts the contract's cost and returns the resulting resources plus the
    /// reward to grant. Callers are responsible for persisting both.
    static func complete(_ contract: Contract, playerResources: ResourceBag) -> (resources: ResourceBag, reward: ResourceBag, experience: Double)? {
        guard canComplete(contract, playerResources: playerResources) else { return nil }
        var resources = playerResources
        for (resource, amount) in contract.requiredResources {
            resources[resource, default: 0] -= amount
        }
        resources.add(contract.rewardResources)
        return (resources, contract.rewardResources, contract.rewardExperience)
    }

    static func starterContracts() -> [Contract] {
        var board = (0..<3).map { nextContract(lane: $0, level: 1) }
        board[0] = Contract(id: UUID(), title: "Coastal Pantry", flavorText: "The coast district's first shipment order.",
                            requiredResources: [.food: 100], rewardResources: [.coins: 400],
                            rewardExperience: 60, duration: 24 * 3600, status: .available, acceptedAt: nil, lane: 0)
        return board
    }

    /// Orders stay within base storage limits. Food always remains available,
    /// so unlocking an industry never blocks progress for a farm-only city.
    static func nextContract(lane: Int, level: Int, excluding title: String? = nil) -> Contract {
        typealias Order = (String, String, ResourceBag, Double, Double)
        let food: [Order] = [
            ("Coastal Pantry", "Stock the waterfront kitchens with fresh crops.", [.food: 100], 400, 60),
            ("School Lunches", "A small harvest for the island's school.", [.food: 40], 180, 35),
            ("Ferry Provisions", "Prepare supplies before the next ferry sails.", [.food: 70], 300, 50),
            ("Harvest Festival", "The town square is ready for a feast.", [.food: 160], 650, 95)
        ]
        let industry: [Order] = [
            ("Workshop Supplies", "Deliver packaged goods to the builders' workshop.", [.goods: 40], 420, 85),
            ("Harbor Repairs", "Keep the fishing harbor in working order.", [.goods: 80], 760, 125),
            ("Clinic Power", "Reserve energy for the island clinic.", [.energy: 70], 320, 65),
            ("Lighthouse Reserve", "Keep the lighthouse shining after sunset.", [.energy: 140], 590, 100)
        ]
        let mixed: [Order] = [
            ("Bakery Restock", "Flour and fresh produce for tomorrow's baking.", [.food: 40, .goods: 20], 420, 80),
            ("Market Opening", "Fresh produce and packaged goods for a new stall.", [.food: 60, .goods: 30], 620, 110),
            ("Night Market", "Supply the vendors and light their stalls.", [.food: 80, .energy: 60], 650, 115),
            ("Ferry Navigation", "Update the navigation network along the coast.", [.data: 60, .energy: 40], 850, 150),
            ("Island Observatory", "Power a new night of scientific observations.", [.data: 100, .goods: 40], 1200, 190)
        ]
        let candidates: [Order]
        if lane == 0 || level < 2 {
            candidates = food
        } else if lane == 1 {
            candidates = Array(industry.prefix(level >= 3 ? 4 : 2))
        } else {
            candidates = Array(mixed.prefix(level >= 4 ? 5 : (level >= 3 ? 3 : 2)))
        }
        let choices = candidates.filter { $0.0 != title }
        let order = (choices.isEmpty ? candidates : choices).randomElement()!
        return Contract(id: UUID(), title: order.0, flavorText: order.1,
                        requiredResources: order.2, rewardResources: [.coins: order.3],
                        rewardExperience: order.4, duration: 24 * 3600,
                        status: .available, acceptedAt: nil, lane: lane)
    }

    static func applyDemandBonus(_ contract: Contract, events: [WorldEvent], now: Date = Date()) -> Contract {
        let modifiers = WorldEventEngine.combinedModifiers(events, at: now)
        let bonus = contract.requiredResources.keys.map { modifiers[$0] ?? 1 }.max() ?? 1
        guard bonus > 1 else { return contract }
        var order = contract
        order.rewardResources[.coins] = ((order.rewardResources[.coins] ?? 0) * min(bonus, 1.8)).rounded()
        order.flavorText += " High-demand payout included."
        return order
    }

    static func replacement(for contract: Contract, index: Int, world: GameWorld) -> Contract {
        applyDemandBonus(nextContract(lane: contract.lane ?? index % 3, level: world.player.level,
                                      excluding: contract.title), events: world.worldEvents)
    }

    static func refreshBoard(_ world: inout GameWorld, now: Date = Date()) {
        // Keep accepted legacy orders and their costs intact during migration.
        for index in world.contracts.indices {
            let contract = world.contracts[index]
            if contract.status == .completed || contract.status == .expired || contract.isExpired(now: now) {
                world.contracts[index] = replacement(for: contract, index: index, world: world)
            }
        }
        while world.contracts.count < 3 {
            world.contracts.append(nextContract(lane: world.contracts.count, level: world.player.level,
                                               excluding: world.contracts.last?.title))
        }
    }
}

/// A claimable journey through the existing construction systems. Claim IDs
/// are optional in GameWorld so older cities keep all their progress.
struct CityGoal: Identifiable {
    let id: String
    let title: String
    let detail: String
    let target: Int
    let coins: Double
    let experience: Double

    static let journey: [CityGoal] = [
        .init(id: "harvest", title: "First Harvest", detail: "Finish a Field on your farm.", target: 1, coins: 150, experience: 60),
        .init(id: "solar", title: "Catch the Sun", detail: "Finish a Solar Panel to start generating energy.", target: 1, coins: 200, experience: 80),
        .init(id: "greenhouse", title: "Grow Together", detail: "Run a Greenhouse and a Water Tank in the same farm.", target: 1, coins: 250, experience: 100),
        .init(id: "processing", title: "From Crop to Crate", detail: "Run a Processing Unit to produce Goods.", target: 1, coins: 350, experience: 130),
        .init(id: "expansion", title: "Room to Grow", detail: "Unlock a second plot.", target: 2, coins: 400, experience: 150),
        .init(id: "power", title: "Power the Coast", detail: "Run a Generator in a Power Plant.", target: 1, coins: 450, experience: 180),
        .init(id: "battery", title: "Save for Sunset", detail: "Finish a Battery Bank for extra energy storage.", target: 1, coins: 300, experience: 140),
        .init(id: "data", title: "Island Online", detail: "Run a Server and Cooling Unit in the same Data Center.", target: 1, coins: 600, experience: 240),
        .init(id: "blueprint", title: "Build It Again", detail: "Save a building blueprint.", target: 1, coins: 300, experience: 140),
        .init(id: "deliveries", title: "Trusted Supplier", detail: "Complete 12 city orders of your choice.", target: 12, coins: 500, experience: 220),
        .init(id: "bridge", title: "Connect the Island", detail: "Contribute 300 resources in total to the Skybridge.", target: 300, coins: 800, experience: 300),
        .init(id: "synergies", title: "Better Together", detail: "Discover all three construction synergies in the Codex.", target: 3, coins: 1000, experience: 400),
        .init(id: "hydroponics", title: "A Smarter Harvest", detail: "Run a Hydroponic Garden, unlocked at Level 5.", target: 1, coins: 800, experience: 350),
        .init(id: "turbine", title: "Coastal Powerhouse", detail: "Run a Coastal Turbine, unlocked at Level 6.", target: 1, coins: 1000, experience: 450),
        .init(id: "research", title: "Research Frontier", detail: "Run a Research Server with Cooling, unlocked at Level 7.", target: 1, coins: 1200, experience: 550),
        .init(id: "depot", title: "Ready for Anything", detail: "Run an Island Depot, unlocked at Level 8.", target: 1, coins: 1500, experience: 650),
        .init(id: "district", title: "A Thriving Coast", detail: "Unlock all six island plots.", target: 6, coins: 1500, experience: 500),
        .init(id: "supplier", title: "Island Lifeline", detail: "Complete 50 city orders.", target: 50, coins: 2000, experience: 600),
        .init(id: "landmark", title: "The Grand Opening", detail: "Complete the Islora Skybridge landmark.", target: 1, coins: 2500, experience: 1000)
    ]

    static func current(in world: GameWorld) -> CityGoal? {
        journey.first { !(world.claimedCityGoalIDs ?? []).contains($0.id) }
    }

    func progress(in world: GameWorld) -> Int {
        func has(_ building: BuildingInstance, _ definition: String, online: Bool = false) -> Bool {
            building.modules.values.contains { $0.definitionID == definition && $0.isBuilt && (!online || StructuralEngine.evaluate(modules: building.modules).status(at: $0.position)?.isOnline == true) }
        }
        let buildings = Array(world.buildings.values)
        let value: Int
        switch id {
        case "harvest": value = buildings.filter { has($0, "farm_field") }.count
        case "solar": value = buildings.filter { has($0, "solar_panel") }.count
        case "greenhouse": value = buildings.filter { has($0, "greenhouse", online: true) && has($0, "water_tank", online: true) }.count
        case "processing": value = buildings.filter { has($0, "processing_unit", online: true) }.count
        case "expansion": value = world.plots.filter(\.isUnlocked).count
        case "power": value = buildings.filter { $0.buildingClass == .powerPlant && has($0, "power_generator", online: true) }.count
        case "battery": value = buildings.filter { has($0, "battery_bank") }.count
        case "data": value = buildings.filter { $0.buildingClass == .dataCenter && has($0, "server_rack", online: true) && has($0, "cooling_unit", online: true) }.count
        case "hydroponics": value = buildings.filter { has($0, "hydroponic_greenhouse", online: true) }.count
        case "turbine": value = buildings.filter { has($0, "coastal_turbine", online: true) }.count
        case "research": value = buildings.filter { has($0, "research_server", online: true) && has($0, "cooling_unit", online: true) }.count
        case "depot": value = buildings.filter { has($0, "island_depot", online: true) }.count
        case "deliveries", "supplier": value = world.completedCityOrders ?? 0
        case "synergies": value = world.player.discoveredSynergyIDs.count
        case "district": value = world.plots.filter(\.isUnlocked).count
        case "landmark": value = world.worldProject?.isComplete == true ? 1 : 0
        case "blueprint": value = world.blueprints.count
        case "bridge": value = Int(world.worldProject?.contributed.values.reduce(0, +) ?? 0)
        default: value = 0
        }
        return min(target, value)
    }
}
