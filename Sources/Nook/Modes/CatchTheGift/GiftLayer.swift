import AppKit
import SpriteKit

/// Catch the Gift on one screen: gift boxes drift down with the snow and you click them
/// before they land. Coordinates are local to the screen, like the rest of the scene.
final class GiftLayer: SKNode {

    private struct Gift {
        let node: SKNode
        let box: SKSpriteNode
        var pos: CGPoint
        let fallSpeed: CGFloat
        var phase: CGFloat
        let sway: CGFloat
        let halfHeight: CGFloat
        let radius: CGFloat      // generous, so gifts are easy to click
    }

    private static let boxColours = ["red", "green", "blue", "gold", "pink", "silver"]
    private static let ribbonColours = ["gold", "red", "silver", "white"]
    private static let sparkleColours: [NSColor] = [
        NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1),
        .white,
        NSColor(red: 1, green: 0.6, blue: 0.75, alpha: 1),
        NSColor(red: 0.7, green: 0.85, blue: 1, alpha: 1)
    ]

    private var gifts: [Gift] = []
    private var lastTime: CFTimeInterval = 0

    /// Gifts only fall while Catch the Gift is the chosen mode and the snow isn't paused.
    var isActive = false {
        didSet {
            guard oldValue != isActive else { return }
            lastTime = 0
            if !isActive { clear() }
        }
    }

    /// The Dock on this screen (local coordinates), so missed gifts land on top of it.
    var dockRect: CGRect?

    /// Fewer frames on battery means gifts can fall a little slower too.
    var energySaving = false

    var hasGifts: Bool { !gifts.isEmpty }

    override init() {
        super.init()
        zPosition = 50
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    // MARK: - Dropping

    /// Drops one new gift from above the top of a screen of the given size.
    func drop(in size: CGSize) {
        guard isActive, size.width > 200 else { return }

        let colour = Self.boxColours.randomElement()!
        let ribbon = Self.ribbonColours.filter { $0 != colour }.randomElement()!
        let art = DecorationRenderer.shared.render(
            PlacedDecoration(kind: .giftBox, x: 0, y: 0, scale: 0.6,
                             options: ["color": colour, "ribbon": ribbon], seed: 1))

        let node = SKNode()
        let glow = SKSpriteNode(texture: SnowTextures.shared.dot)
        glow.size = CGSize(width: art.size.width * 2.1, height: art.size.width * 2.1)
        glow.color = NSColor(red: 1, green: 0.86, blue: 0.5, alpha: 1)
        glow.colorBlendFactor = 1
        glow.alpha = 0.35
        glow.run(.repeatForever(.sequence([.fadeAlpha(to: 0.6, duration: 0.7), .fadeAlpha(to: 0.3, duration: 0.7)])))
        node.addChild(glow)

        let box = SKSpriteNode(texture: SKTexture(cgImage: art.image))
        box.size = art.size
        node.addChild(box)

        // Speeds up a little while you keep a streak going, so it stays interesting.
        let streakBoost = CGFloat(min(GiftStats.shared.streak, 15)) * 4
        let margin = art.size.width
        let start = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)),
                            y: size.height + art.size.height)
        node.position = start
        addChild(node)

        gifts.append(Gift(node: node, box: box, pos: start,
                          fallSpeed: (CGFloat.random(in: 55...75) + streakBoost) * (energySaving ? 0.9 : 1),
                          phase: CGFloat.random(in: 0...(2 * .pi)),
                          sway: CGFloat.random(in: 18...40),
                          halfHeight: art.size.height / 2,
                          radius: max(art.size.width, art.size.height) * 0.6 + 8))
    }

    // MARK: - Every frame

    func step(_ now: CFTimeInterval) {
        guard isActive, !gifts.isEmpty else { lastTime = 0; return }
        let dt = CGFloat(lastTime == 0 ? 1.0 / 30.0 : min(0.1, max(0.001, now - lastTime)))
        lastTime = now

        var i = 0
        while i < gifts.count {
            var g = gifts[i]
            g.phase += dt * 1.6
            g.pos.y -= g.fallSpeed * dt
            g.pos.x += cos(g.phase) * g.sway * dt
            g.node.position = g.pos
            g.box.zRotation = sin(g.phase) * 0.16

            if g.pos.y - g.halfHeight <= floorY(at: g.pos.x) {
                land(g)
                gifts.remove(at: i)
                continue
            }
            gifts[i] = g
            i += 1
        }
    }

    private func floorY(at x: CGFloat) -> CGFloat {
        if let d = dockRect, x >= d.minX, x <= d.maxX { return d.maxY }
        return 2
    }

    /// A missed gift settles where it fell, then fades away. The streak starts over.
    private func land(_ g: Gift) {
        g.box.run(.rotate(toAngle: 0, duration: 0.2))
        g.node.run(.sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 0.8), .removeFromParent()]))
        GiftStats.shared.recordMiss()
    }

    // MARK: - Catching

    func hitTest(_ p: CGPoint) -> Bool {
        gifts.contains { hypot(p.x - $0.pos.x, p.y - $0.pos.y) < $0.radius }
    }

    /// Catches the gift under the point, if there is one.
    func catchGift(at p: CGPoint) -> Bool {
        guard isActive, let i = gifts.firstIndex(where: { hypot(p.x - $0.pos.x, p.y - $0.pos.y) < $0.radius }) else {
            return false
        }
        let g = gifts.remove(at: i)
        g.node.removeAllActions()
        g.node.run(.sequence([.group([.scale(to: 1.5, duration: 0.22), .fadeOut(withDuration: 0.22)]), .removeFromParent()]))

        let revealed = GiftStats.shared.recordCatch()
        let streak = GiftStats.shared.streak
        burst(at: g.pos, big: revealed != nil)
        floatText(streak >= 2 ? "+1  ·  \(streak) in a row" : "+1", at: CGPoint(x: g.pos.x, y: g.pos.y + 34), size: 20)
        if let kind = revealed {
            floatText("Surprise unlocked: \(kind.title)!", at: CGPoint(x: g.pos.x, y: g.pos.y + 66), size: 24, hold: 2.2)
        }
        return true
    }

    // MARK: - Effects

    private func burst(at p: CGPoint, big: Bool) {
        let count = big ? 40 : 18
        for i in 0..<count {
            let s = SKSpriteNode(texture: SnowTextures.shared.dot)
            let d = CGFloat.random(in: 5...(big ? 13 : 10))
            s.size = CGSize(width: d, height: d)
            s.color = Self.sparkleColours.randomElement()!
            s.colorBlendFactor = 1
            s.position = p
            s.zPosition = 2
            addChild(s)
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + CGFloat.random(in: -0.2...0.2)
            let dist = CGFloat.random(in: 40...(big ? 170 : 100))
            let move = SKAction.moveBy(x: cos(angle) * dist, y: sin(angle) * dist, duration: 0.7)
            move.timingMode = .easeOut
            s.run(.sequence([.group([move, .fadeOut(withDuration: 0.7), .scale(to: 0.3, duration: 0.7)]), .removeFromParent()]))
        }
    }

    /// Text that floats up from a catch and fades out. A soft shadow keeps it readable on any wallpaper.
    private func floatText(_ text: String, at p: CGPoint, size: CGFloat, hold: TimeInterval = 0.5) {
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
        // Keep the text on screen even when the gift was caught near an edge.
        let width = scene?.size.width ?? 2000
        let half = CGFloat(text.count) * size * 0.3
        node.position = CGPoint(x: min(max(p.x, half + 10), max(half + 10, width - half - 10)), y: p.y)
        node.zPosition = 3
        node.setScale(0.6)
        addChild(node)
        let rise = SKAction.moveBy(x: 0, y: 46, duration: 0.9 + hold)
        rise.timingMode = .easeOut
        node.run(.sequence([
            .group([.scale(to: 1, duration: 0.18), rise,
                    .sequence([.wait(forDuration: 0.5 + hold), .fadeOut(withDuration: 0.4)])]),
            .removeFromParent()
        ]))
    }

    private func clear() {
        for g in gifts {
            g.node.removeAllActions()
            g.node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
        gifts.removeAll()
    }
}
