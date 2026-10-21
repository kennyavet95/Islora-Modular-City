import SwiftUI

struct ProfileView: View {
    let session: GameSession

    var body: some View {
        ZStack {
            BlockoraSheetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Profile")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)

                    BlockoraPanel {
                        ProgressionHUDView(level: session.world.player.level, experience: session.world.player.experience)
                    }

                    section("Production per Minute") {
                        let rates = session.buildingReports.values.reduce(into: ResourceBag()) { total, report in
                            total.add(report.production.netPerHour)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ResourceType.allCases.filter { rates[$0] != nil }) { resource in
                                let rate = (rates[resource] ?? 0) / 60
                                Label("\(resource.displayName): \(rate > 0 ? "+" : "")\(String(format: "%.1f", rate))/min", systemImage: resource.symbolName)
                                    .foregroundStyle(rate < 0 ? BlockoraPalette.craneOrange : .white)
                            }
                            if rates.isEmpty { Text("Build a Field to begin your first harvest.").foregroundStyle(.white) }
                        }
                        .font(.subheadline.weight(.bold))
                    }

                    section("Island Achievements") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("City orders completed: \(session.world.completedCityOrders ?? 0)")
                            Text("Journey goals: \(session.world.claimedCityGoalIDs?.count ?? 0) / \(CityGoal.journey.count)")
                            ForEach(CityGoal.journey.filter { (session.world.claimedCityGoalIDs ?? []).contains($0.id) }) { goal in
                                Label(goal.title, systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(BlockoraPalette.coinGold)
                            }
                        }
                        .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    }

                    section("Next Unlocks") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(ModuleCatalog.all.filter { $0.unlockLevel > session.world.player.level }
                                .sorted { $0.unlockLevel < $1.unlockLevel }) { module in
                                Text("Level \(module.unlockLevel) · \(module.displayName)")
                                    .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            }
                            if session.world.player.level >= 8 {
                                Text("All modules unlocked. Master synergies and complete the Skybridge.")
                                    .foregroundStyle(.white)
                            }
                        }
                    }

                    section("Workforce") {
                        VStack(spacing: 10) {
                    ForEach(session.world.workers) { worker in
                        HStack {
                            Image(systemName: worker.type.symbolName)
                                .foregroundStyle(BlockoraPalette.coinGold)
                                .frame(width: 24)
                            Text(worker.name).font(.subheadline.weight(.bold))
                            Spacer()
                            Text(worker.isAvailable ? "Idle" : "Working")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(worker.isAvailable ? .white.opacity(0.7) : BlockoraPalette.safe)
                        }
                        .foregroundStyle(.white)
                    }
                        }
                }

                    section("Resources") {
                        VStack(spacing: 10) {
                    ForEach(ResourceType.allCases) { resource in
                        HStack {
                            Image(systemName: resource.symbolName)
                                .foregroundStyle(resource == .coins ? BlockoraPalette.coinGold : .white)
                                .frame(width: 24)
                            Text(resource.displayName).font(.subheadline.weight(.bold))
                            Spacer()
                            Text("\(Int(session.world.player.resources[resource] ?? 0))")
                                .font(.caption.weight(.heavy))
                        }
                        .foregroundStyle(.white)
                    }
                        }
                    }
                }
                .padding(22)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.black)).foregroundStyle(BlockoraPalette.coinGold)
            BlockoraPanel(padding: 14) { content() }
        }
    }
}
