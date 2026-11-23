import AppKit
import SpriteKit

/// Little effects shared by the playful modes: sparkle bursts and floating text.
enum ModeEffects {
    static let sparkleColours: [NSColor] = [
        NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1),
        .white,
        NSColor(red: 1, green: 0.6, blue: 0.75, alpha: 1),
        NSColor(red: 0.7, green: 0.85, blue: 1, alpha: 1)
    ]

    static let snowColours: [NSColor] = [
        .white,
        NSColor(red: 0.88, green: 0.94, blue: 1, alpha: 1),
        NSColor(red: 0.8, green: 0.88, blue: 0.98, alpha: 1)
    ]

    /// Dots flying outward from a point, then fading.
    static func burst(in parent: SKNode, at p: CGPoint, count: Int, colours: [NSColor] = sparkleColours,
                      sizes: ClosedRange<CGFloat> = 5...10, distance: ClosedRange<CGFloat> = 40...100) {
        for i in 0..<count {
            let s = SKSpriteNode(texture: SnowTextures.shared.dot)
            let d = CGFloat.random(in: sizes)
            s.size = CGSize(width: d, height: d)
            s.color = colours.randomElement()!
            s.colorBlendFactor = 1
            s.position = p
            s.zPosition = 2
            parent.addChild(s)
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.2...0.2)
            let dist = CGFloat.random(in: distance)
            let move = SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: 0.7)
            move.timingMode = .easeOut
            s.run(.sequence([.group([move, .fadeOut(withDuration: 0.7), .scale(to: 0.3, duration: 0.7)]), .removeFromParent()]))
        }
    }

    /// Text that floats up and fades out. A soft shadow keeps it readable on any wallpaper.
    static func floatText(in parent: SKNode, _ text: String, at p: CGPoint, size: CGFloat,
                          hold: TimeInterval = 0.5, screenWidth: CGFloat) {
        let node = SKNode()
        let layers: [(CGPoint, NSColor, CGFloat)] = [(CGPoint(x: 1.5, y: -1.5), .black, 0.45), (CGPoint.zero, .white, 1)]
        for (offset, colour, alpha) in layers {
            let label = SKLabelNode(text: text)
            label.fontName = "AvenirNext-Bold"
            label.fontSize = size
            label.fontColor = colour
            label.alpha = alpha
            label.position = offset
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            node.addChild(label)
        }
        // Keep the text on screen even near an edge.
        let half = CGFloat(text.count) * size * 0.3
        node.position = CGPoint(x: min(max(p.x, half + 10), max(half + 10, screenWidth - half - 10)), y: p.y)
        node.zPosition = 3
        node.setScale(0.6)
        parent.addChild(node)
        let rise = SKAction.moveBy(x: 0, y: 46, duration: 0.9 + hold)
        rise.timingMode = .easeOut
        node.run(.sequence([
            .group([.scale(to: 1, duration: 0.18), rise,
                    .sequence([.wait(forDuration: 0.5 + hold), .fadeOut(withDuration: 0.4)])]),
            .removeFromParent()
        ]))
    }
}
