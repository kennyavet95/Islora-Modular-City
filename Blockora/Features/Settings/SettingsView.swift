import SwiftUI

struct SettingsView: View {
    let session: GameSession
    @State private var isMuted = AudioManager.shared.isMuted
    @State private var showResetConfirmation = false
    @State private var showWebsite = false

    var body: some View {
        ZStack {
            BlockoraSheetBackground()
            ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings")
                    .font(.largeTitle.weight(.black))
                    .foregroundStyle(.white)

                section("Audio") {
                    Toggle("Mute Sound", isOn: $isMuted)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .tint(BlockoraPalette.craneOrange)
                        .onChange(of: isMuted) { _, newValue in AudioManager.shared.isMuted = newValue }
                }

                section("How to Play") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Build foundations, then connect production modules. Workers finish each module automatically.")
                        Text("Fields grow Food. Add a Core and Processing Unit for Goods. Solar Panels power greenhouses and servers.")
                        Text("Complete Journey goals and City Orders to earn coins and XP. New buildings and modules unlock through Level 8.")
                        Text("Reinforce stressed structures, cool your servers, and save your best layouts as Blueprints.")
                    }
                    .font(.caption).foregroundStyle(.white.opacity(0.85))
                }

                section("About") {
                    Button("Visit Website") { showWebsite = true }
                        .buttonStyle(BlockoraGameButtonStyle())
                }

                section("Data") {
                    Button("Reset Game", role: .destructive) { showResetConfirmation = true }
                        .buttonStyle(BlockoraGameButtonStyle())
                }

                Spacer()
            }
            .padding(22)
            }

            if showResetConfirmation {
                Color.black.opacity(0.35).ignoresSafeArea()
                BlockoraPanel {
                    VStack(spacing: 14) {
                        Text("Reset Game?")
                            .font(.title2.weight(.black))
                            .foregroundStyle(.white)
                        Text("This deletes your city and starts over.")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("Cancel") { showResetConfirmation = false }
                                .buttonStyle(BlockoraGameButtonStyle())
                                .opacity(0.72)
                            Button("Reset") {
                                showResetConfirmation = false
                                Task { await session.resetGame() }
                            }
                            .buttonStyle(BlockoraGameButtonStyle())
                        }
                    }
                }
                .padding(.horizontal, 28)
            }
        }
        .sheet(isPresented: $showWebsite) {
            NavigationStack {
                WebView(url: URL(string: "https://isloramodularcity.online")!)
                    .navigationTitle("Islora")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showWebsite = false }
                        }
                    }
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
