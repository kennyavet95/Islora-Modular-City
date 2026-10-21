import XCTest
@testable import Blockora

final class ProgressionLoopTests: XCTestCase {
    func testCameraFitsEveryBuildingCornerBetweenHUDAndTools() {
        XCTAssertGreaterThanOrEqual(CityScene.plotSpacing, 6 * ModuleNode.cellSize)
        for screen in [CGSize(width: 440, height: 956), CGSize(width: 1032, height: 1376)] {
            let viewport = CGRect(x: 12, y: 180, width: screen.width - 24, height: screen.height - 620)
            for row in 0...5 {
                let content = BuildingNode.constructionRect(topRow: row).offsetBy(dx: 864, dy: -95)
                let fit = CityScene.fittedCamera(content: content, viewport: viewport, viewSize: screen)
                for x in [content.minX, content.maxX] {
                    for y in [content.minY, content.maxY] {
                        let point = CGPoint(x: screen.width / 2 + (x - fit.position.x) / fit.scale,
                                            y: screen.height / 2 - (y - fit.position.y) / fit.scale)
                        XCTAssertTrue(viewport.contains(point), "\(screen) row \(row): \(point)")
                    }
                }
            }
        }
    }

    @MainActor
    func testResetUsesTheSessionsStoreAndClearsTransientState() async {
        let store = SaveGameStore(fileName: "islora-reset-\(UUID()).json")
        var world = GameWorld.newGame()
        world.player.level = 8
        world.completedCityOrders = 40
        store.save(world)
        let session = GameSession(service: LocalEconomyService(store: store))
        await session.loadGame()
        session.pendingModuleRemovalPosition = GridPosition(x: 0, y: 0)
        await session.resetGame()
        XCTAssertEqual(session.world.player.level, 1)
        XCTAssertNil(session.world.completedCityOrders)
        XCTAssertNil(session.pendingModuleRemovalPosition)
        XCTAssertEqual(store.load()?.player.level, 1)
        store.deleteSave()
    }

    func testProcessingCannotCreateGoodsWithoutFoodOnlineOrOffline() {
        let ground = GridPosition(x: 0, y: 0)
        let core = GridPosition(x: 0, y: 1)
        let unit = GridPosition(x: 1, y: 1)
        let building = BuildingInstance(buildingClass: .farm, plotID: UUID(), displayName: "Factory", modules: [
            ground: ModuleInstance(definitionID: "foundation_basic", position: ground, constructionProgress: 1),
            core: ModuleInstance(definitionID: "structural_core", position: core, constructionProgress: 1),
            unit: ModuleInstance(definitionID: "processing_unit", position: unit, constructionProgress: 1)
        ])
        let structural = StructuralEngine.evaluate(modules: building.modules)
        let synergy = SynergyEngine.evaluate(modules: building.modules, playerLevel: 2)
        let empty = ProductionEngine.evaluate(building: building, structural: structural, synergy: synergy,
                                               availableResources: [:], intervalSeconds: 60)
        XCTAssertEqual(empty.netPerHour[.goods] ?? 0, 0)
        let now = Date()
        let offline = OfflineSimulationEngine.simulate(resources: [.food: 3], storageCapacity: [.goods: 200],
            buildings: [building], playerLevel: 2, elapsedSince: now.addingTimeInterval(-3600), now: now)
        XCTAssertEqual(offline.updatedResources[.food] ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(offline.updatedResources[.goods] ?? 0, 4.2, accuracy: 0.01)
    }

    func testOfflineHonorsDistrictAndEventEndTime() {
        let world = GameWorld.newGame()
        let plot = world.plots[0]
        let ground = GridPosition(x: 0, y: 0)
        let field = GridPosition(x: 0, y: 1)
        let building = BuildingInstance(buildingClass: .farm, plotID: plot.id, displayName: "Farm", modules: [
            ground: ModuleInstance(definitionID: "foundation_basic", position: ground, constructionProgress: 1),
            field: ModuleInstance(definitionID: "farm_field", position: field, constructionProgress: 1)
        ])
        let start = Date(timeIntervalSince1970: 1000)
        var event = WorldEventEngine.harvestFestival(starting: start)
        event.endDate = start.addingTimeInterval(30)
        let result = OfflineSimulationEngine.simulate(resources: [:], storageCapacity: [.food: 1000],
            buildings: [building], playerLevel: 1, elapsedSince: start, now: start.addingTimeInterval(60),
            districts: world.districts, plots: world.plots, events: [event])
        XCTAssertEqual(result.updatedResources[.food] ?? 0, 18 * 1.15 * 1.3, accuracy: 0.01)
    }

    func testDemandRewardsAndExpiryUseRealOrderState() {
        var order = EconomyEngine.nextContract(lane: 0, level: 1)
        let boosted = EconomyEngine.applyDemandBonus(order, events: [WorldEventEngine.harvestFestival(starting: Date())])
        XCTAssertEqual(boosted.requiredResources, order.requiredResources)
        XCTAssertGreaterThan(boosted.rewardResources[.coins] ?? 0, order.rewardResources[.coins] ?? 0)
        order.status = .accepted
        order.acceptedAt = Date(timeIntervalSince1970: 0)
        XCTAssertFalse(EconomyEngine.canComplete(order, playerResources: [.food: 1000]))
    }

    func testLaterModulesUnlockAndUseExistingSystems() throws {
        XCTAssertEqual(Set(ModuleCatalog.all.map(\.id)).count, ModuleCatalog.all.count)
        for (id, level) in [("hydroponic_greenhouse", 5), ("coastal_turbine", 6), ("research_server", 7), ("island_depot", 8)] {
            let module = try XCTUnwrap(ModuleCatalog.definition(for: id))
            XCTAssertEqual(module.unlockLevel, level)
            XCTAssertGreaterThanOrEqual(module.support, module.weight)
            let buildingClass = try XCTUnwrap(module.buildingClasses.first)
            XCTAssertFalse(ModuleCatalog.modules(for: buildingClass, unlockedUpTo: level - 1).contains { $0.id == id })
            XCTAssertTrue(ModuleCatalog.modules(for: buildingClass, unlockedUpTo: level).contains { $0.id == id })
        }
    }

    @MainActor
    func testNormalTimeFirstSessionProducesFoodWithinFiveMinutes() async {
        let store = SaveGameStore(fileName: "islora-pacing-\(UUID()).json")
        var world = GameWorld.newGame()
        let ground = GridPosition(x: 0, y: 0)
        let field = GridPosition(x: 0, y: 1)
        let building = BuildingInstance(buildingClass: .farm, plotID: world.plots[0].id, displayName: "Farm", modules: [
            ground: ModuleInstance(definitionID: "foundation_basic", position: ground, constructionProgress: 1),
            field: ModuleInstance(definitionID: "farm_field", position: field, constructionProgress: 1)
        ])
        world.buildings[building.id] = building
        world.plots[0].buildingID = building.id
        store.save(world)
        let session = GameSession(service: LocalEconomyService(store: store))
        await session.loadGame()
        for _ in 0..<300 { session.tick(deltaSeconds: 1) }
        XCTAssertGreaterThanOrEqual(session.world.player.resources[.food] ?? 0, 100)
        XCTAssertLessThanOrEqual(session.world.player.resources[.food] ?? 0, 300)
        await Task.yield()
        store.deleteSave()
    }

    func testOrderVarietyStaysAffordableAndUnlocksIndustries() {
        for level in 1...7 {
            for lane in 0..<3 {
                var previous = ""
                for _ in 0..<100 {
                    let order = EconomyEngine.nextContract(lane: lane, level: level, excluding: previous)
                    XCTAssertNotEqual(order.title, previous)
                    XCTAssertEqual(order.lane, lane)
                    for (resource, amount) in order.requiredResources {
                        XCTAssertLessThanOrEqual(amount, PlayerProfile.baseStorageCapacity[resource] ?? 0)
                        if level == 1 { XCTAssertEqual(resource, .food) }
                        if level < 4 { XCTAssertNotEqual(resource, .data) }
                    }
                    previous = order.title
                }
            }
        }
    }

    func testLegacySaveAndExpiredBoardMigration() throws {
        var world = GameWorld.newGame()
        world.contracts = [world.contracts[0]]
        world.contracts[0].status = .accepted
        world.contracts[0].acceptedAt = Date(timeIntervalSince1970: 0)
        EconomyEngine.refreshBoard(&world)
        XCTAssertEqual(world.contracts.count, 3)
        XCTAssertTrue(world.contracts.allSatisfy { $0.status == .available })
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(world)) as? [String: Any])
        json.removeValue(forKey: "claimedCityGoalIDs")
        let decoded = try JSONDecoder().decode(GameWorld.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.claimedCityGoalIDs)
        XCTAssertEqual(CityGoal.current(in: decoded)?.id, "harvest")
    }

    @MainActor
    func testJourneyRequiresFinishedBuildingAndCannotClaimTwice() async {
        let store = SaveGameStore(fileName: "islora-goals-\(UUID()).json")
        var world = GameWorld.newGame()
        let position = GridPosition(x: 0, y: 1)
        let ground = GridPosition(x: 0, y: 0)
        var building = BuildingInstance(buildingClass: .farm, plotID: world.plots[0].id, displayName: "Farm",
                                        modules: [ground: ModuleInstance(definitionID: "foundation_basic", position: ground, constructionProgress: 1),
                                                  position: ModuleInstance(definitionID: "farm_field", position: position)])
        world.buildings[building.id] = building
        XCTAssertEqual(CityGoal.current(in: world)?.progress(in: world), 0)
        building.modules[position]?.constructionProgress = 1
        world.buildings[building.id] = building
        store.save(world)
        let session = GameSession(service: LocalEconomyService(store: store))
        await session.loadGame()
        let coins = session.world.player.resources[.coins, default: 0]
        session.claimCityGoal()
        XCTAssertEqual(session.world.player.resources[.coins], coins + 150)
        XCTAssertEqual(CityGoal.current(in: session.world)?.id, "solar")
        session.claimCityGoal()
        XCTAssertEqual(session.world.player.resources[.coins], coins + 150)
        let restored = try? JSONDecoder().decode(GameWorld.self, from: JSONEncoder().encode(session.world))
        XCTAssertTrue(restored?.claimedCityGoalIDs?.contains("harvest") == true)
        await Task.yield()
        store.deleteSave()
    }

    @MainActor
    func testStorageCapacityTracksBuiltModulesAndRemoval() async {
        let store = SaveGameStore(fileName: "islora-storage-test-\(UUID()).json")
        var world = GameWorld.newGame()
        let plotID = world.plots[0].id
        let foundation = GridPosition(x: 0, y: 0)
        let storage = GridPosition(x: 0, y: 1)
        let building = BuildingInstance(buildingClass: .farm, plotID: plotID, displayName: "Farm", modules: [
            foundation: ModuleInstance(definitionID: "foundation_basic", position: foundation, constructionProgress: 1),
            storage: ModuleInstance(definitionID: "storage_crate", position: storage, constructionProgress: 1)
        ])
        world.buildings[building.id] = building
        world.plots[0].buildingID = building.id
        store.save(world)
        let session = GameSession(service: LocalEconomyService(store: store))
        await session.loadGame()
        XCTAssertEqual(session.world.player.storageCapacity[.food], 450)
        XCTAssertEqual(session.world.player.storageCapacity[.energy], 400)
        session.removeModule(buildingID: building.id, at: storage)
        XCTAssertEqual(session.world.player.storageCapacity[.food], 300)
        XCTAssertEqual(session.world.player.storageCapacity[.energy], 300)
        await Task.yield()
        store.deleteSave()
    }

    @MainActor
    func testRepeatedDeliveriesReachDataCentersWithEnoughTechnicians() async {
        let store = SaveGameStore(fileName: "islora-progression-test-\(UUID()).json")
        var world = GameWorld.newGame()
        world.player.resources[.food] = 10_000
        world.contracts[0].status = .completed
        world.workers.removeAll { $0.name == "Nia" }
        store.save(world)
        let session = GameSession(service: LocalEconomyService(store: store))
        await session.loadGame()
        XCTAssertEqual(session.world.contracts[0].status, .available)
        XCTAssertEqual(session.world.workers.filter { $0.type == .technician }.count, 2)
        for _ in 0..<30 {
            let contractID = session.world.contracts[0].id
            session.acceptContract(contractID)
            session.completeContract(contractID)
            XCTAssertNotEqual(session.world.contracts[0].id, contractID)
            XCTAssertEqual(session.world.contracts[0].status, .available)
        }
        XCTAssertGreaterThanOrEqual(session.world.player.level, 4)
        XCTAssertEqual(session.world.contracts.count, 3)
        XCTAssertEqual(session.world.completedCityOrders, 30)
        await Task.yield()
        store.deleteSave()
    }
}
