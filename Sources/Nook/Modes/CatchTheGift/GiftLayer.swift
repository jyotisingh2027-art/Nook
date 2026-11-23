import AppKit
import SpriteKit

/// Catch the Gift on one screen: gift boxes drift down with the snow and you click them
/// before they land. Coordinates are local to the screen, like the rest of the scene.
final class GiftLayer: SKNode {

    private struct Gift {
        let id: Int
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

    private var gifts: [Gift] = []
    private var nextGiftID = 0

    // MARK: The frost imp (the villain)

    private enum ImpState { case sneaking, escaping, leaving, shooed }

    private final class Imp {
        let node = SKSpriteNode(texture: FrostImpArt.texture(.flyA))
        var pos: CGPoint
        let targetID: Int
        let homeX: CGFloat
        var state = ImpState.sneaking
        var t: CGFloat = 0
        var vel = CGVector.zero
        var carried: Gift?
        init(pos: CGPoint, targetID: Int, homeX: CGFloat) {
            self.pos = pos; self.targetID = targetID; self.homeX = homeX
        }
        var bodyCentre: CGPoint { CGPoint(x: pos.x, y: pos.y + 4) }
    }

    private var imp: Imp?
    private var pendingImp: (giftID: Int, delay: CGFloat)?
    private static let iceColours: [NSColor] = [
        NSColor(red: 0.75, green: 0.9, blue: 1, alpha: 1), .white, NSColor(red: 0.6, green: 0.75, blue: 1, alpha: 1)
    ]
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

    var hasGifts: Bool { !gifts.isEmpty || imp != nil }

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
            PlacedDecoration(kind: .giftBox, x: 0, y: 0, scale: 0.82,
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

        // The more you've caught this game, the faster gifts fall.
        let streakBoost = CGFloat(min(GiftStats.shared.score, 40)) * 3.5
        let margin = art.size.width
        let start = CGPoint(x: CGFloat.random(in: margin...(size.width - margin)),
                            y: size.height + art.size.height)
        node.position = start
        addChild(node)

        nextGiftID += 1
        // Now and then the frost imp spots a gift and sneaks in to steal it.
        if imp == nil, pendingImp == nil, GiftStats.shared.caught >= 1, Double.random(in: 0...1) < 0.4 {
            pendingImp = (nextGiftID, CGFloat.random(in: 1.0...2.2))
        }
        gifts.append(Gift(id: nextGiftID, node: node, box: box, pos: start,
                          fallSpeed: (CGFloat.random(in: 55...75) + streakBoost) * (energySaving ? 0.9 : 1),
                          phase: CGFloat.random(in: 0...(2 * .pi)),
                          sway: CGFloat.random(in: 18...40),
                          halfHeight: art.size.height / 2,
                          radius: max(art.size.width, art.size.height) * 0.6 + 8))
    }

    // MARK: - Every frame

    /// While the game is paused everything holds still and can't be clicked.
    var isFrozen = false {
        didSet {
            guard oldValue != isFrozen else { return }
            isPaused = isFrozen       // stops the glow and other little animations too
            lastTime = 0
            if isFrozen && hudVisible && GiftStats.shared.inGame, let s = scene {
                floatText("Paused", at: CGPoint(x: s.size.width / 2, y: s.size.height * 0.6), size: 26, hold: 0.8)
            }
        }
    }

    func step(_ now: CFTimeInterval) {
        refreshHUD()
        if isFrozen { return }
        guard isActive, !gifts.isEmpty || imp != nil else { lastTime = 0; return }
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
                if let imp, imp.targetID == g.id, imp.state == .sneaking {
                    imp.state = .leaving
                    floatText("Hmph!", at: CGPoint(x: imp.pos.x, y: imp.pos.y + 44), size: 18)
                }
                land(g)
                gifts.remove(at: i)
                continue
            }
            gifts[i] = g
            i += 1
        }
        stepImp(dt)
    }

    // MARK: - The imp

    private func stepImp(_ dt: CGFloat) {
        if var p = pendingImp {
            p.delay -= dt
            pendingImp = p
            if p.delay <= 0 {
                pendingImp = nil
                if let g = gifts.first(where: { $0.id == p.giftID }), let w = scene?.size.width {
                    // It comes in from the side nearest the gift, a little below it.
                    let fromLeft = g.pos.x < w / 2
                    let homeX: CGFloat = fromLeft ? -50 : w + 50
                    let i = Imp(pos: CGPoint(x: homeX, y: max(90, g.pos.y - 150)), targetID: g.id, homeX: homeX)
                    i.node.size = CGSize(width: FrostImpArt.size.width * 1.3, height: FrostImpArt.size.height * 1.3)
                    i.node.zPosition = 1
                    i.node.position = i.pos
                    addChild(i.node)
                    imp = i
                }
            }
        }
        guard let imp else { return }
        imp.t += dt
        let bob = sin(imp.t * 5) * 3

        switch imp.state {
        case .sneaking:
            guard let g = gifts.first(where: { $0.id == imp.targetID }) else {
                imp.state = .leaving
                return
            }
            let target = CGPoint(x: g.pos.x, y: g.pos.y - 58)
            let dx = target.x - imp.pos.x, dy = target.y - imp.pos.y
            let d = max(0.001, hypot(dx, dy))
            let speed: CGFloat = (100 + CGFloat(min(GiftStats.shared.streak, 10)) * 4) * (energySaving ? 0.9 : 1)
            imp.pos.x += dx / d * speed * dt
            imp.pos.y += dy / d * speed * dt
            imp.node.texture = FrostImpArt.texture(Int(imp.t * 6) % 2 == 0 ? .flyA : .flyB)
            imp.node.xScale = dx < 0 ? -1 : 1
            if d < 22 { steal(g, by: imp) }
        case .escaping:
            imp.pos.x += (imp.homeX < 0 ? -1 : 1) * 240 * dt
            imp.pos.y += 40 * dt
            imp.node.texture = FrostImpArt.texture(.grab)
            if var c = imp.carried {
                c.pos = CGPoint(x: imp.pos.x, y: imp.pos.y + 62 + bob)
                c.node.position = c.pos
                imp.carried = c
            }
        case .leaving:
            imp.pos.x += (imp.homeX < 0 ? -1 : 1) * 170 * dt
            imp.pos.y += 30 * dt
            imp.node.texture = FrostImpArt.texture(Int(imp.t * 6) % 2 == 0 ? .flyA : .flyB)
            imp.node.xScale = imp.homeX < 0 ? -1 : 1
        case .shooed:
            imp.vel.dy -= 120 * dt
            imp.pos.x += imp.vel.dx * dt
            imp.pos.y += imp.vel.dy * dt
            imp.node.zRotation += 7 * dt
            imp.node.alpha = max(0, imp.node.alpha - dt * 0.9)
        }
        imp.node.position = CGPoint(x: imp.pos.x, y: imp.pos.y + (imp.state == .shooed ? 0 : bob))

        let w = scene?.size.width ?? 2000
        if imp.pos.x < -80 || imp.pos.x > w + 80 || imp.node.alpha <= 0.01 {
            imp.node.removeFromParent()
            imp.carried?.node.removeFromParent()
            self.imp = nil
        }
    }

    /// The imp got there first: it grabs the gift and makes off with it.
    private func steal(_ g: Gift, by imp: Imp) {
        gifts.removeAll { $0.id == g.id }
        imp.carried = g
        imp.state = .escaping
        imp.node.xScale = imp.homeX < 0 ? -1 : 1
        GiftStats.shared.recordStolen()
        lifeLostText(at: CGPoint(x: imp.pos.x, y: imp.pos.y + 100))
        floatText("ROAR! Stolen!", at: CGPoint(x: imp.pos.x, y: imp.pos.y + 70), size: 20)
    }

    /// Clicking the imp scares it off. If it was carrying a gift, the gift drops back down.
    private func shoo(_ imp: Imp) {
        imp.state = .shooed
        imp.node.texture = FrostImpArt.texture(.shooed)
        imp.vel = CGVector(dx: (imp.homeX < 0 ? -1 : 1) * 160, dy: 230)
        ModeEffects.burst(in: self, at: imp.bodyCentre, count: 16, colours: Self.iceColours, sizes: 4...9, distance: 30...80)
        GiftStats.shared.recordImpShooed()
        if var c = imp.carried {
            imp.carried = nil
            c.pos = CGPoint(x: c.pos.x, y: c.pos.y)
            gifts.append(c)
            floatText("Shoo, yeti! Gift rescued!", at: CGPoint(x: imp.pos.x, y: imp.pos.y + 60), size: 20)
        } else {
            floatText("Shoo, yeti!", at: CGPoint(x: imp.pos.x, y: imp.pos.y + 50), size: 20)
        }
    }

    private func impHit(_ p: CGPoint) -> Imp? {
        guard let imp, imp.state != .shooed else { return nil }
        return hypot(p.x - imp.bodyCentre.x, p.y - imp.bodyCentre.y) < 50 ? imp : nil
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
        lifeLostText(at: CGPoint(x: g.pos.x, y: g.pos.y + 40))
    }

    // MARK: - Catching

    func hitTest(_ p: CGPoint) -> Bool {
        guard !isFrozen else { return false }
        return impHit(p) != nil || gifts.contains { hypot(p.x - $0.pos.x, p.y - $0.pos.y) < $0.radius }
    }

    /// Catches the gift under the point, if there is one.
    func catchGift(at p: CGPoint) -> Bool {
        guard !isFrozen else { return false }
        if isActive, let imp = impHit(p) {
            shoo(imp)
            return true
        }
        guard isActive, let i = gifts.firstIndex(where: { hypot(p.x - $0.pos.x, p.y - $0.pos.y) < $0.radius }) else {
            return false
        }
        let g = gifts.remove(at: i)
        if let imp, imp.targetID == g.id, imp.state == .sneaking {
            imp.state = .leaving
            floatText("Grr!", at: CGPoint(x: imp.pos.x, y: imp.pos.y + 44), size: 18)
        }
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

    // MARK: - Lives and score on screen

    /// Shown on one screen only (the one with the menu bar) while a game is on.
    var hudVisible = false
    private let hud = SKNode()
    private var hearts: [SKSpriteNode] = []
    private var scoreLabels: [SKLabelNode] = []
    private var shownLives = -1, shownScore = -1

    private func buildHUD() {
        guard hearts.isEmpty else { return }
        hud.zPosition = 5
        addChild(hud)
        for i in 0..<GiftStats.maxLives {
            let h = SKSpriteNode(texture: HeartArt.full)
            h.size = CGSize(width: 26, height: 24)
            h.position = CGPoint(x: CGFloat(i - 1) * 32, y: 0)
            hud.addChild(h)
            hearts.append(h)
        }
        for (offset, colour, alpha) in [(CGPoint(x: 1.2, y: -1.2), NSColor.black, 0.45), (.zero, NSColor.white, 1.0)] as [(CGPoint, NSColor, CGFloat)] {
            let l = SKLabelNode(text: "")
            l.fontName = "AvenirNext-Bold"
            l.fontSize = 17
            l.fontColor = colour
            l.alpha = alpha
            l.verticalAlignmentMode = .center
            l.position = CGPoint(x: offset.x, y: -30 + offset.y)
            hud.addChild(l)
            scoreLabels.append(l)
        }
    }

    private func refreshHUD() {
        let stats = GiftStats.shared
        let show = hudVisible && isActive && stats.inGame
        if !show {
            if !hud.isHidden { hud.isHidden = true }
            return
        }
        buildHUD()
        hud.isHidden = false
        if let s = scene as? SeasonScene {
            hud.position = CGPoint(x: s.size.width / 2, y: s.visibleTop - 34)
        }
        if stats.lives != shownLives {
            let lost = shownLives > stats.lives && shownLives >= 0
            shownLives = stats.lives
            for (i, h) in hearts.enumerated() {
                h.texture = i < stats.lives ? HeartArt.full : HeartArt.empty
            }
            if lost, stats.lives < hearts.count {
                let h = hearts[stats.lives]
                h.run(.sequence([.scale(to: 1.5, duration: 0.12), .scale(to: 1, duration: 0.25)]))
            }
        }
        if stats.score != shownScore {
            shownScore = stats.score
            scoreLabels.forEach { $0.text = "Score \(stats.score)" }
        }
    }

    private func lifeLostText(at p: CGPoint) {
        guard GiftStats.shared.inGame || GiftStats.shared.lives == 0 else { return }
        let left = GiftStats.shared.lives
        let text = left == 0 ? "No lives left!" : (left == 1 ? "−1 life  ·  last one!" : "−1 life  ·  \(left) left")
        floatText(text, at: p, size: 18, hold: 0.8)
    }

    /// A little "Ready? 3 lives. Go!" when a game starts.
    func announceStart() {
        guard let s = scene as? SeasonScene else { return }
        floatText("Catch the Gift!  3 lives.  Go!", at: CGPoint(x: s.size.width / 2, y: s.size.height * 0.6), size: 26, hold: 1.4)
    }

    // MARK: - Effects

    private func burst(at p: CGPoint, big: Bool) {
        ModeEffects.burst(in: self, at: p, count: big ? 40 : 18, sizes: 5...(big ? 13 : 10), distance: 40...(big ? 170 : 100))
    }

    private func floatText(_ text: String, at p: CGPoint, size: CGFloat, hold: TimeInterval = 0.5) {
        ModeEffects.floatText(in: self, text, at: p, size: size, hold: hold, screenWidth: scene?.size.width ?? 2000)
    }

    private func clear() {
        for g in gifts {
            g.node.removeAllActions()
            g.node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
        gifts.removeAll()
        pendingImp = nil
        if let imp {
            imp.carried?.node.removeFromParent()
            imp.node.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
            self.imp = nil
        }
    }
}
