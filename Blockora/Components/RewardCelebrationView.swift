import SwiftUI

/// Short, non-blocking reward feedback. All particles disappear with the view.
struct RewardCelebrationView: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<18, id: \.self) { index in
                    let angle = Double(index) * .pi * 2 / 18
                    Image(systemName: index.isMultiple(of: 3) ? "star.fill" : "sparkle")
                        .font(.system(size: index.isMultiple(of: 3) ? 16 : 10, weight: .bold))
                        .foregroundStyle(index.isMultiple(of: 2) ? BlockoraPalette.coinGold : .white)
                        .rotationEffect(.degrees(Double(progress) * (index.isMultiple(of: 2) ? 100 : -100)))
                        .offset(x: CGFloat(cos(angle)) * 130 * progress,
                                y: CGFloat(sin(angle)) * 65 * progress + 25 * progress * progress)
                        .opacity(Double(1 - progress))
                }
            }
            Label(title, systemImage: "checkmark.seal.fill")
                .font(.headline.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(BlockoraPalette.safe.gradient, in: Capsule())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)
                .scaleEffect(reduceMotion ? 1 : 0.88 + 0.12 * min(progress * 5, 1))
                .opacity(Double(min(1, (1 - progress) * 5)))
        }
        .frame(height: 160)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8)) { progress = 1 }
        }
    }
}
