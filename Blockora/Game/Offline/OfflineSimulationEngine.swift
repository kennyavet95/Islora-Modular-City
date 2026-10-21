import Foundation

struct OfflineSimulationResult {
    var elapsedSeconds: TimeInterval
    var wasCapped: Bool
    /// Final amount minus starting amount, per resource — what the "While You
    /// Were Away" summary shows (§35).
    var resourceDeltas: ResourceBag
    var updatedResources: ResourceBag
}

/// Bounded one-minute steps share the live recipe rules, stop at storage caps,
/// and split at event boundaries so expired boosts do not last all night.
enum OfflineSimulationEngine {
    static let maxOfflineDuration: TimeInterval = 8 * 3600

    static func simulate(
        resources: ResourceBag,
        storageCapacity: ResourceBag,
        buildings: [BuildingInstance],
        playerLevel: Int,
        elapsedSince lastSync: Date,
        now: Date,
        districts: [District] = [],
        plots: [Plot] = [],
        events: [WorldEvent] = []
    ) -> OfflineSimulationResult {
        let rawElapsed = max(0, now.timeIntervalSince(lastSync))
        let elapsed = min(rawElapsed, maxOfflineDuration)
        let orderedBuildings = buildings.sorted { $0.id.uuidString < $1.id.uuidString }
        let reports = orderedBuildings.map { building in
            (StructuralEngine.evaluate(modules: building.modules),
             SynergyEngine.evaluate(modules: building.modules, playerLevel: playerLevel))
        }
        var finalResources = resources
        var simulated: TimeInterval = 0
        let start = now.addingTimeInterval(-elapsed)
        while simulated < elapsed {
            let date = start.addingTimeInterval(simulated)
            let boundary = events.flatMap { [$0.startDate, $0.endDate] }
                .filter { $0 > date }.min()?.timeIntervalSince(date) ?? 60
            let step = min(60, elapsed - simulated, boundary)
            for (index, building) in orderedBuildings.enumerated() {
                let districtModifiers = plots.first(where: { $0.id == building.plotID })
                    .flatMap { plot in districts.first(where: { $0.id == plot.districtID }) }?.productionModifiers ?? [:]
                let production = ProductionEngine.evaluate(
                    building: building, structural: reports[index].0, synergy: reports[index].1,
                    districtModifiers: districtModifiers,
                    eventModifiers: WorldEventEngine.combinedModifiers(events, at: date),
                    availableResources: finalResources, intervalSeconds: step
                )
                for (resource, rate) in production.netPerHour {
                    var amount = max(0, finalResources[resource, default: 0] + rate * step / 3600)
                    if let cap = storageCapacity[resource] { amount = min(amount, cap) }
                    finalResources[resource] = amount
                }
            }
            simulated += step
        }

        var deltas: ResourceBag = [:]
        for resource in ResourceType.allCases {
            let delta = finalResources[resource, default: 0] - resources[resource, default: 0]
            if delta != 0 { deltas[resource] = delta }
        }

        return OfflineSimulationResult(
            elapsedSeconds: elapsed,
            wasCapped: rawElapsed > maxOfflineDuration,
            resourceDeltas: deltas,
            updatedResources: finalResources
        )
    }

}
