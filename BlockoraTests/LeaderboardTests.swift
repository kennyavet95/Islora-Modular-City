import Foundation
import Testing
@testable import Blockora

@MainActor
struct LeaderboardTests {
    private func freshDefaults() -> UserDefaults {
        let name = "LeaderboardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func stats(totalXP: Int) -> PlayerStats {
        PlayerStats(level: 2, totalExperience: totalXP, buildings: 1, modules: 3, productionPerMinute: 10,
                    synergies: 1, tallestBuilding: 2, skybridgeContribution: 0, cityOrdersCompleted: 0)
    }

    @Test func builderNameHasFourDigitNumber() {
        for _ in 0..<50 {
            let name = PlayerIdentity.makeBuilderName()
            #expect(name.hasPrefix("Builder "))
            let number = Int(name.dropFirst("Builder ".count))
            #expect(number.map { (1000...9999).contains($0) } == true)
        }
    }

    @Test func identityIsStableOncePersisted() {
        let store = PlayerIdentityStore(defaults: freshDefaults())
        let first = store.identity
        #expect(store.identity == first)
        #expect(!first.isRegistered)
    }

    @Test func seasonIdMatchesSQLFormat() throws {
        // 2026-11-23 is a Monday in ISO week 48.
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-25T12:00:00Z"))
        let season = SeasonInfo.current(now: date)
        #expect(season.id == "2026-W48")
        #expect(season.endsAt == ISO8601DateFormatter().date(from: "2026-11-30T00:00:00Z"))
    }

    @Test func leagueHasFullGroupAndCountsWeeklyXPOnly() async throws {
        let service = MockLeaderboardService(defaults: freshDefaults())
        let identity = PlayerIdentity.generate()
        try await service.submit(stats(totalXP: 1_000), city: CitySnapshot(buildings: []), identity: identity)
        try await service.submit(stats(totalXP: 1_250), city: CitySnapshot(buildings: []), identity: identity)

        let league = try await service.league(identity: identity)
        #expect(league.entries.count == LeagueRules.groupSize)
        #expect(league.entries.map(\.rank) == Array(1...LeagueRules.groupSize))
        #expect(league.entries.first(where: \.isMe)?.score == 250)
    }

    @Test func giftIsLimitedToOncePerDayAndReturnsThanks() async throws {
        let service = MockLeaderboardService(defaults: freshDefaults())
        let identity = PlayerIdentity.generate()
        let target = try #require(try await service.leaderboard(.level, identity: identity).entries.first)

        let afterSend = try await service.sendGift(to: target.playerId, identity: identity)
        #expect(!afterSend.canSendToday)
        #expect(afterSend.sentTodayTo == target.playerId)
        #expect(afterSend.inbox.contains { $0.kind == .thanks })

        await #expect(throws: LeaderboardError.self) {
            _ = try await service.sendGift(to: target.playerId, identity: identity)
        }

        let claim = try await service.claimGifts(identity: identity)
        #expect(claim.blocks == GiftRules.giftBlocks + GiftRules.thanksBlocks)
        #expect(try await service.giftStatus(identity: identity).inbox.isEmpty)
    }

    @Test func factionCanBePickedOncePerSeason() async throws {
        let service = MockLeaderboardService(defaults: freshDefaults())
        let identity = PlayerIdentity.generate()
        let war = try await service.joinFaction(.delta, identity: identity)
        #expect(war.myFaction == .delta)
        #expect(!war.canSwitch)
        await #expect(throws: LeaderboardError.self) {
            _ = try await service.joinFaction(.coast, identity: identity)
        }
    }

    @Test func fakeCitiesAreInspirable() async throws {
        let service = MockLeaderboardService(defaults: freshDefaults())
        let identity = PlayerIdentity.generate()
        let top = try #require(try await service.leaderboard(.tallest, identity: identity).entries.first)
        let card = try await service.player(top.playerId, identity: identity)
        let building = try #require(card.city.buildings.first)

        let session = GameSession(service: LocalEconomyService(store: SaveGameStore(fileName: "islora-inspire-\(UUID()).json")))
        let before = session.world.blueprints.count
        let blueprint = session.importInspiredBlueprint(building, author: card.builderName)
        #expect(blueprint != nil)
        #expect(session.world.blueprints.count == before + 1)
        #expect(blueprint?.moduleDefinitionIDs.count == building.modules.count)
    }

    @Test func supabaseErrorCodesMapToFriendlyErrors() {
        let data = Data(#"{"code":"P0001","message":"gift_already_sent"}"#.utf8)
        let error = SupabaseLeaderboardService.mapError(data: data, status: 400)
        #expect((error as? LeaderboardError)?.errorDescription == LeaderboardError.giftAlreadySentToday.errorDescription)
    }

    @Test func snapshotDecodesFromSupabaseSnakeCase() throws {
        let json = #"""
        {"player_id":"a","builder_name":"Builder 1234","faction":"coast","tier":null,
         "stats":{"level":3,"total_experience":500,"buildings":1,"modules":4,"production_per_minute":12,
                  "synergies":2,"tallest_building":3,"skybridge_contribution":0,"city_orders_completed":1},
         "city":{"buildings":[{"id":"b","name":"Farm","building_class":"farm",
                 "modules":[{"definition_id":"foundation_basic","family":"foundation","x":0,"y":0}]}]},
         "is_me":false}
        """#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let card = try decoder.decode(PlayerCard.self, from: Data(json.utf8))
        #expect(card.faction == .coast)
        #expect(card.stats.tallestBuilding == 3)
        #expect(card.city.buildings.first?.modules.first?.definitionId == "foundation_basic")
    }
}
