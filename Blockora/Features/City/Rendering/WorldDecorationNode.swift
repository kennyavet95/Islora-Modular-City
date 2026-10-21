import SpriteKit
import SwiftUI
import UIKit

/// Animated ambient art behind the interactive SpriteKit world (§16/§36).
final class WorldDecorationNode: SKNode {
    init(sceneSize: CGSize) {
        super.init()

        let background = SKSpriteNode(imageNamed: "BlockoraWorldBackground")
        background.zPosition = -100
        let verticalOffset = sceneSize.height * 0.15
        background.position = CGPoint(x: 0, y: verticalOffset)
        // Shifting the image up to better frame the skyline moves its bottom
        // edge up by the same amount, so plain cover-scaling against
        // `sceneSize` left a gap at the bottom of the screen (the scene's
        // flat background color showing through). Covering
        // `sceneSize.height + 2 * verticalOffset` instead keeps the shifted
        // image's edges outside the viewport on both sides regardless of size.
        let neededHeight = sceneSize.height + 2 * verticalOffset
        let scale = max(sceneSize.width / background.size.width, neededHeight / background.size.height)
        background.size = CGSize(width: background.size.width * scale, height: background.size.height * scale)
        addChild(background)
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        // Small, slow water glints preserve the painted backdrop's composition.
        for index in 0..<14 {
            let sparkle = SKShapeNode(rectOf: CGSize(width: 10, height: 1.5), cornerRadius: 0.75)
            sparkle.fillColor = .white
            sparkle.strokeColor = .clear
            sparkle.position = CGPoint(x: (CGFloat((index * 73) % 100) / 100 - 0.5) * sceneSize.width,
                                       y: -sceneSize.height * (0.26 + CGFloat(index % 5) * 0.035))
            sparkle.zPosition = -90
            sparkle.alpha = 0
            addChild(sparkle)
            sparkle.run(.repeatForever(.sequence([
                .wait(forDuration: Double(index % 7) * 0.45),
                .group([.fadeAlpha(to: 0.45, duration: 1.2), .scaleX(to: 1.5, duration: 1.2)]),
                .group([.fadeOut(withDuration: 1.2), .scaleX(to: 0.7, duration: 1.2)]),
                .wait(forDuration: 2)
            ])))
        }
        for index in 0..<3 {
            let bird = SKShapeNode()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -8, y: 0))
            path.addQuadCurve(to: .zero, control: CGPoint(x: -4, y: 4))
            path.addQuadCurve(to: CGPoint(x: 8, y: 0), control: CGPoint(x: 4, y: 4))
            bird.path = path
            bird.strokeColor = .white.withAlphaComponent(0.8)
            bird.lineWidth = 1.5
            bird.zPosition = -90
            bird.position = CGPoint(x: -sceneSize.width * 0.6, y: sceneSize.height * (0.28 + CGFloat(index) * 0.04))
            addChild(bird)
            bird.run(.repeatForever(.sequence([
                .wait(forDuration: Double(index) * 6),
                .moveBy(x: sceneSize.width * 1.2, y: 12, duration: 25),
                .moveBy(x: -sceneSize.width * 1.2, y: -12, duration: 0)
            ])))
            bird.run(.repeatForever(.sequence([.scaleY(to: 0.35, duration: 0.55), .scaleY(to: 1, duration: 0.55)])))
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }
}
