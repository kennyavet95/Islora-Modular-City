import Foundation

/// The immutable "blueprint" for a module family/tier — the data that ModuleCatalog
/// hands out. `ModuleInstance` is the placed, mutable, per-building copy.
///
/// Every field here maps directly to a design-spec stat (§3): weight/support drive
/// StructuralEngine, `production` drives ProductionEngine, `workersRequired` +
/// `buildTimeSeconds` drive WorkerAssignmentEngine.
struct ModuleDefinition: Identifiable, Codable, Hashable {
    let id: String
    let family: ModuleFamily
    let buildingClasses: Set<BuildingClass>
    let displayName: String
    let flavorText: String

    /// Structural physics inputs.
    let weight: Double
    /// Support capacity this module can extend to neighbors it grounds.
    let support: Double

    /// Positive = produced per hour, negative = consumed per hour, at 100% condition.
    let production: ResourceBag
    /// Extra max-storage granted per resource while this module is online.
    let storageCapacityBonus: ResourceBag

    /// Heat generated per hour (Data Center thermal mechanic, §13). Zero for
    /// modules outside that building class.
    let heatOutput: Double
    /// Heat this module can dissipate per hour (Cooling Unit uses this).
    let coolingCapacity: Double

    let connectionRequirements: ConnectionRequirement
    let workersRequired: [WorkerType: Int]
    let buildTimeSeconds: Double
    let placementCost: ResourceBag
    let unlockLevel: Int

    /// True only for foundation-family modules, which may be placed on the
    /// ground row and are always considered grounded regardless of neighbors.
    var isGroundAnchor: Bool { family == .foundation }
}

/// Static registry of every module definition in the game. Data-driven so new
/// modules/tiers are additions here, not new engine branches (§44).
enum ModuleCatalog {
    static let all: [ModuleDefinition] = structuralStaples + farmModules + powerPlantModules + dataCenterModules + advancedModules

    static func definition(for id: String) -> ModuleDefinition? {
        byID[id]
    }

    static func modules(for buildingClass: BuildingClass, unlockedUpTo level: Int) -> [ModuleDefinition] {
        all
            .filter { $0.buildingClasses.contains(buildingClass) && $0.unlockLevel <= level }
            .sorted {
                if $0.isGroundAnchor != $1.isGroundAnchor { return $0.isGroundAnchor }
                return $0.unlockLevel == $1.unlockLevel ? $0.displayName < $1.displayName : $0.unlockLevel < $1.unlockLevel
            }
    }

    private static let byID: [String: ModuleDefinition] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    // MARK: - Structural staples (every building class)

    private static let structuralStaples: [ModuleDefinition] = [
        ModuleDefinition(
            id: "foundation_basic", family: .foundation, buildingClasses: Set(BuildingClass.allCases),
            displayName: "Foundation", flavorText: "Anchors the structure to the plot.",
            weight: 2, support: 220, production: [:], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [],
            workersRequired: [.builder: 1], buildTimeSeconds: 8,
            placementCost: [.coins: 40], unlockLevel: 1
        ),
        ModuleDefinition(
            id: "structural_core", family: .structuralCore, buildingClasses: Set(BuildingClass.allCases),
            displayName: "Structural Core", flavorText: "Heavy beams that redistribute load and carry connections.",
            weight: 6, support: 35, production: [:], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [],
            workersRequired: [.builder: 1, .engineer: 1], buildTimeSeconds: 14,
            placementCost: [.coins: 90], unlockLevel: 1
        ),
        ModuleDefinition(
            id: "office_basic", family: .office, buildingClasses: Set(BuildingClass.allCases),
            displayName: "Site Office", flavorText: "Coordinates the site and earns a steady coin income.",
            weight: 4, support: 10, production: [.coins: 240], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [],
            workersRequired: [.builder: 1], buildTimeSeconds: 10,
            placementCost: [.coins: 70], unlockLevel: 1
        ),
        ModuleDefinition(
            id: "storage_crate", family: .storage, buildingClasses: Set(BuildingClass.allCases),
            displayName: "Storage", flavorText: "Extra capacity so production doesn't overflow while you're away.",
            weight: 8, support: 6, production: [:],
            storageCapacityBonus: [.food: 150, .goods: 150, .data: 150, .energy: 100],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [],
            workersRequired: [.builder: 1], buildTimeSeconds: 10,
            placementCost: [.coins: 60], unlockLevel: 1
        ),
        ModuleDefinition(
            id: "solar_panel", family: .solarPanel, buildingClasses: Set(BuildingClass.allCases),
            displayName: "Solar Panel", flavorText: "Quiet, clean energy — no fuel deliveries required.",
            weight: 3, support: 4, production: [.energy: 1500], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [],
            workersRequired: [.electrician: 1], buildTimeSeconds: 12,
            placementCost: [.coins: 120], unlockLevel: 1
        ),
    ]

    // MARK: - Farm (§12)

    private static let farmModules: [ModuleDefinition] = [
        ModuleDefinition(
            id: "farm_field", family: .farmField, buildingClasses: [.farm],
            displayName: "Field", flavorText: "Rows of crops. Simple, reliable food.",
            weight: 2, support: 4, production: [.food: 1080], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [],
            workersRequired: [.builder: 1], buildTimeSeconds: 10,
            placementCost: [.coins: 50], unlockLevel: 1
        ),
        ModuleDefinition(
            id: "greenhouse", family: .greenhouse, buildingClasses: [.farm],
            displayName: "Greenhouse", flavorText: "Climate-controlled growing — needs power to run its vents.",
            weight: 3, support: 3, production: [.food: 1800, .energy: -480], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [.power],
            workersRequired: [.builder: 1, .technician: 1], buildTimeSeconds: 18,
            placementCost: [.coins: 140], unlockLevel: 1
        ),
        ModuleDefinition(
            id: "water_tank", family: .waterTank, buildingClasses: [.farm],
            displayName: "Water Tank", flavorText: "Stores water for irrigation. Pairs well with a greenhouse.",
            weight: 3, support: 5, production: [.food: 300], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [],
            workersRequired: [.builder: 1], buildTimeSeconds: 12,
            placementCost: [.coins: 80], unlockLevel: 1
        ),
        ModuleDefinition(
            id: "processing_unit", family: .processingUnit, buildingClasses: [.farm],
            displayName: "Processing Unit", flavorText: "Turns raw food into packaged Goods for market.",
            weight: 5, support: 4, production: [.food: -600, .goods: 840], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [.core],
            workersRequired: [.engineer: 1], buildTimeSeconds: 20,
            placementCost: [.coins: 160], unlockLevel: 2
        ),
    ]

    // MARK: - Power Plant (§51)

    private static let powerPlantModules: [ModuleDefinition] = [
        ModuleDefinition(
            id: "power_generator", family: .powerGenerator, buildingClasses: [.powerPlant],
            displayName: "Generator", flavorText: "The plant's core output — heavy, and hungry for support.",
            weight: 10, support: 14, production: [.energy: 3000], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [.core],
            workersRequired: [.electrician: 1, .engineer: 1], buildTimeSeconds: 24,
            placementCost: [.coins: 260], unlockLevel: 3
        ),
        ModuleDefinition(
            id: "battery_bank", family: .battery, buildingClasses: [.powerPlant],
            displayName: "Battery Bank", flavorText: "Buffers surplus energy for the rest of the city.",
            weight: 4, support: 8, production: [:], storageCapacityBonus: [.energy: 400],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [],
            workersRequired: [.electrician: 1], buildTimeSeconds: 14,
            placementCost: [.coins: 150], unlockLevel: 3
        ),
    ]

    // MARK: - Data Center (§13 / §52)

    private static let dataCenterModules: [ModuleDefinition] = [
        ModuleDefinition(
            id: "server_rack", family: .server, buildingClasses: [.dataCenter],
            displayName: "Server", flavorText: "Data, at the cost of heat and hunger for power.",
            weight: 8, support: 12, production: [.data: 2100, .energy: -1080], storageCapacityBonus: [:],
            heatOutput: 12, coolingCapacity: 0, connectionRequirements: [.power, .core],
            workersRequired: [.technician: 2], buildTimeSeconds: 22,
            placementCost: [.coins: 220], unlockLevel: 4
        ),
        ModuleDefinition(
            id: "cooling_unit", family: .coolingUnit, buildingClasses: [.dataCenter],
            displayName: "Cooling Unit", flavorText: "Keeps the racks from throttling themselves.",
            weight: 4, support: 4, production: [.energy: -300], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 25, connectionRequirements: [.power],
            workersRequired: [.electrician: 1], buildTimeSeconds: 16,
            placementCost: [.coins: 130], unlockLevel: 4
        ),
    ]
    // Later tiers reuse existing art, placement and family synergy rules.
    private static let advancedModules: [ModuleDefinition] = [
        ModuleDefinition(
            id: "hydroponic_greenhouse", family: .greenhouse, buildingClasses: [.farm],
            displayName: "Hydroponic Garden", flavorText: "Twice the harvest. Needs more energy and strong support.",
            weight: 5, support: 8, production: [.food: 3600, .energy: -1200], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [.power, .core],
            workersRequired: [.builder: 1, .technician: 1], buildTimeSeconds: 30,
            placementCost: [.coins: 650, .goods: 40], unlockLevel: 5
        ),
        ModuleDefinition(
            id: "coastal_turbine", family: .powerGenerator, buildingClasses: [.powerPlant],
            displayName: "Coastal Turbine", flavorText: "High output from a heavier, carefully supported module.",
            weight: 14, support: 20, production: [.energy: 6000], storageCapacityBonus: [:],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [.core],
            workersRequired: [.electrician: 1, .engineer: 1], buildTimeSeconds: 35,
            placementCost: [.coins: 900, .goods: 60], unlockLevel: 6
        ),
        ModuleDefinition(
            id: "research_server", family: .server, buildingClasses: [.dataCenter],
            displayName: "Research Server", flavorText: "Double the data, double the heat. Plan extra cooling and power.",
            weight: 10, support: 16, production: [.data: 4200, .energy: -2160], storageCapacityBonus: [:],
            heatOutput: 24, coolingCapacity: 0, connectionRequirements: [.power, .core],
            workersRequired: [.technician: 2], buildTimeSeconds: 40,
            placementCost: [.coins: 1200, .goods: 80], unlockLevel: 7
        ),
        ModuleDefinition(
            id: "island_depot", family: .storage, buildingClasses: Set(BuildingClass.allCases),
            displayName: "Island Depot", flavorText: "Capacity for the island's largest landmark shipments.",
            weight: 10, support: 16, production: [:],
            storageCapacityBonus: [.food: 600, .goods: 600, .data: 600, .energy: 600],
            heatOutput: 0, coolingCapacity: 0, connectionRequirements: [.core],
            workersRequired: [.builder: 1, .engineer: 1], buildTimeSeconds: 35,
            placementCost: [.coins: 1000, .goods: 100], unlockLevel: 8
        )
    ]

}
