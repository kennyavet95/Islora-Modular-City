import SpriteKit
import SwiftUI

/// A small, readable worker figure (§9) — not decoration: it appears while a
/// module is under construction and walks off once the job completes.
final class WorkerNode: SKNode {
    init(type: WorkerType) {
        super.init()

        let body = SKShapeNode(rectOf: CGSize(width: 14, height: 20), cornerRadius: 4)
        body.fillColor = SKColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)
        body.strokeColor = .white
        body.lineWidth = 1.5
        body.position = CGPoint(x: 0, y: 10)
        let figure = SKNode()
        addChild(figure)
        figure.addChild(body)

        let helmet = SKShapeNode(ellipseOf: CGSize(width: 16, height: 10))
        helmet.fillColor = SKColor(BlockoraPalette.craneOrange)
        helmet.strokeColor = .white
        helmet.position = CGPoint(x: 0, y: 22)
        figure.addChild(helmet)
        let tool = SKShapeNode(rectOf: CGSize(width: 4, height: 14), cornerRadius: 1)
        tool.fillColor = .lightGray
        tool.strokeColor = .white
        tool.position = CGPoint(x: 11, y: 14)
        figure.addChild(tool)
        if !UIAccessibility.isReduceMotionEnabled {
            tool.run(.repeatForever(.sequence([
                .rotate(toAngle: -0.6, duration: 0.28), .rotate(toAngle: 0.4, duration: 0.22), .wait(forDuration: 0.3)
            ])))
        }

        if !UIAccessibility.isReduceMotionEnabled {
            let dust = SKEmitterNode()
            dust.particleBirthRate = 5
            dust.particleLifetime = 0.5
            dust.particleLifetimeRange = 0.2
            dust.particleSize = CGSize(width: 3, height: 3)
            dust.particleColor = SKColor(red: 1, green: 0.85, blue: 0.5, alpha: 1)
            dust.particleAlpha = 0.6
            dust.particleAlphaSpeed = -1.2
            dust.particleSpeed = 14
            dust.particleSpeedRange = 8
            dust.emissionAngle = .pi / 2
            dust.emissionAngleRange = .pi
            dust.position = CGPoint(x: 14, y: 3)
            addChild(dust)
        }
        let bob = SKAction.repeatForever(.sequence([
            .moveBy(x: 0, y: 3, duration: 0.35), .moveBy(x: 0, y: -3, duration: 0.35),
        ]))
        if !UIAccessibility.isReduceMotionEnabled { figure.run(bob) }
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    func walk(to point: CGPoint, duration: TimeInterval, completion: (() -> Void)? = nil) {
        let move = SKAction.move(to: point, duration: duration)
        move.timingMode = .easeInEaseOut
        if let completion {
            run(.sequence([move, .run(completion)]))
        } else {
            run(move)
        }
    }
}
