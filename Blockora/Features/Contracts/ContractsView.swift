import SwiftUI

/// City Contracts (§22) — demand fulfilment, not trading (§21). Every action
/// here calls straight into GameSession/EconomyEngine; nothing on this screen
/// is a static mockup.
struct ContractsView: View {
    let session: GameSession
    @State private var celebrationID = UUID()
    @State private var celebrationTitle: String?

    var body: some View {
        ZStack {
            BlockoraSheetBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Contracts")
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)
                        .shadow(color: .blue.opacity(0.8), radius: 2, x: 0, y: 2)

                    section("Island Journey") {
                        if let goal = CityGoal.current(in: session.world) {
                            let progress = goal.progress(in: session.world)
                            VStack(alignment: .leading, spacing: 10) {
                                Text(goal.title).font(.headline.weight(.black)).foregroundStyle(.white)
                                Text(goal.detail).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                                ProgressView(value: Double(progress), total: Double(goal.target))
                                    .tint(BlockoraPalette.safe)
                                Text("\(progress) / \(goal.target) • +\(Int(goal.coins)) coins • +\(Int(goal.experience)) XP")
                                    .font(.caption.weight(.bold)).foregroundStyle(BlockoraPalette.coinGold)
                                Button(progress >= goal.target ? "Claim Journey Reward" : "Goal in progress") {
                                    session.claimCityGoal()
                                }
                                .buttonStyle(BlockoraGameButtonStyle())
                                .disabled(progress < goal.target)
                            }
                        } else {
                            Text("Island Journey complete! Keep fulfilling city orders and growing your island.")
                                .foregroundStyle(.white)
                        }
                    }

                    let activeEvents = WorldEventEngine.activeEvents(session.world.worldEvents, at: Date())
                    if !activeEvents.isEmpty {
                        section("Active Events") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(activeEvents) { event in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.title)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.white)
                                        Text(event.flavorText)
                                            .font(.caption)
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                }
                            }
                        }
                    }

                    section("Market Demand") {
                        VStack(spacing: 10) {
                            ForEach(MarketDemand.current(events: session.world.worldEvents, at: Date()), id: \.resource) { level in
                                HStack {
                                    ResourceIcon(resource: level.resource)
                                    Text(level.resource.displayName)
                                        .font(.subheadline.weight(.bold))
                                    Spacer()
                                    Text(level.label)
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(level.multiplier > 1 ? BlockoraPalette.safe : .white.opacity(0.75))
                                }
                                .foregroundStyle(.white)
                            }
                        }
                    }

                    section("City Contracts") {
                        VStack(spacing: 12) {
                            ForEach(session.world.contracts) { contract in
                                ContractRow(session: session, contract: contract)
                            }
                        }
                    }
                }
                .padding(22)
            }
        }
        .interactiveDismissDisabled()
        .onAppear { session.refreshContracts() }
        .overlay(alignment: .top) {
            if let celebrationTitle {
                RewardCelebrationView(title: celebrationTitle)
                    .id(celebrationID)
                    .padding(.top, 40)
            }
        }
        .onChange(of: session.world.completedCityOrders) { showCelebration("Order delivered!") }
        .onChange(of: session.world.claimedCityGoalIDs) { showCelebration("Journey reward earned!") }

    }

    private func showCelebration(_ title: String) {
        celebrationTitle = title
        celebrationID = UUID()
        let currentID = celebrationID
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if celebrationID == currentID { celebrationTitle = nil }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.black))
                .foregroundStyle(BlockoraPalette.coinGold)
            BlockoraPanel(padding: 14) { content() }
        }
    }
}

private struct ContractRow: View {
    let session: GameSession
    let contract: Contract

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(contract.title)
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
            Text(contract.flavorText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))

            HStack(spacing: 12) {
                ForEach(contract.requiredResources.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { resource in
                    resourceAmount(resource, contract.requiredResources[resource] ?? 0)
                }
                Image(systemName: "arrow.right")
                    .foregroundStyle(.white.opacity(0.65))
                ForEach(contract.rewardResources.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { resource in
                    resourceAmount(resource, contract.rewardResources[resource] ?? 0, prefix: "+")
                }
            }

            if contract.status == .accepted {
                ForEach(contract.requiredResources.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { resource in
                    let needed = contract.requiredResources[resource] ?? 0
                    let held = min(needed, session.world.player.resources[resource] ?? 0)
                    Text("\(resource.displayName): \(Int(held)) / \(Int(needed))")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                }
            }
            Text("+\(Int(contract.rewardExperience)) XP")
                .font(.caption.weight(.bold)).foregroundStyle(BlockoraPalette.coinGold)
            actionButton
        }
        .padding(12)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func resourceAmount(_ resource: ResourceType, _ amount: Double, prefix: String = "") -> some View {
        HStack(spacing: 4) {
            ResourceIcon(resource: resource, size: 18)
            Text("\(prefix)\(Int(amount))")
                .font(.caption.weight(.heavy))
                .foregroundStyle(prefix.isEmpty ? .white : BlockoraPalette.safe)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch contract.status {
        case .available:
            Button("Accept") { session.acceptContract(contract.id) }
                .buttonStyle(BlockoraGameButtonStyle())
                .accessibilityIdentifier("contract-action-\(contract.lane ?? 0)")
            Button("Find another order") { session.skipContract(contract.id) }
                .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.8))
        case .accepted:
            let canComplete = EconomyEngine.canComplete(contract, playerResources: session.world.player.resources)
            Button(canComplete ? "Deliver" : "Need more resources") { session.completeContract(contract.id) }
                .buttonStyle(BlockoraGameButtonStyle())
                .disabled(!canComplete)
                .accessibilityIdentifier("contract-action-\(contract.lane ?? 0)")
            if contract.isExpired(now: Date()) {
                Button("Replace expired order") { session.refreshContracts() }
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
            }
        case .completed:
            Text("Completed").font(.caption.weight(.heavy)).foregroundStyle(BlockoraPalette.safe)
        case .expired:
            Text("Expired").font(.caption.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct ResourceIcon: View {
    let resource: ResourceType
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: resource.symbolName)
            .font(.system(size: size * 0.58, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(iconColor, in: RoundedRectangle(cornerRadius: size * 0.22))
    }

    private var iconColor: Color {
        switch resource {
        case .coins: return BlockoraPalette.coinGold
        case .food: return BlockoraPalette.safe
        case .energy: return Color(red: 0.10, green: 0.55, blue: 1)
        case .goods: return BlockoraPalette.craneOrange
        case .data: return Color(red: 0.18, green: 0.72, blue: 1)
        case .blocks: return Color(red: 0.50, green: 0.62, blue: 1)
        }
    }
}
