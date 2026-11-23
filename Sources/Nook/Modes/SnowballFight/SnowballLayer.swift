import AppKit
import SpriteKit

/// Snowball Fight on one screen. Snowmen pop up on top of windows, the Dock or the bottom of
/// the screen and lob snowballs at you; they grow as they fly closer and splat on the glass.
/// Click a snowman to throw back, hold Option and click to throw anywhere, or click an incoming
/// snowball to swat it away. Coordinates are local to the screen.
final class SnowballLayer: SKNode {

    private final class Snowman {
        let node: SKSpriteNode
        let perch: CGRect          // the ledge it stands on (zero height)
        let onDrift: Bool          // popped out of its own little snowdrift, so no ledge to lose
        init(node: SKSpriteNode, perch: CGRect, onDrift: Bool = false) {
            self.node = node; self.perch = perch; self.onDrift = onDrift
        }
    }

    /// A snowball in flight. Incoming ones grow as they come at you; yours shrink as they fly off.
    private struct Ball {
        let node: SKSpriteNode
        let from: CGPoint
        let to: CGPoint
        let startSize: CGFloat
        let endSize: CGFloat
        let duration: CGFloat
        let arc: CGFloat
        let incoming: Bool
        var t: CGFloat
        var pos: CGPoint
        var size: CGFloat
    }

    private var snowmen: [Snowman] = []
    private var balls: [Ball] = []
    private var lastTime: CFTimeInterval = 0

    /// Only plays while Snowball Fight is the chosen mode and the snow isn't paused.
    var isActive = false {
        didSet {
            guard oldValue != isActive else { return }
            lastTime = 0
            if !isActive { clear() }
        }
    }

    /// Bottom-left of this screen in global coordinates, to find the mouse pointer.
    var screenOrigin = CGPoint.zero

    /// Ledges a snowman can stand on, in local coordinates (each rect has zero height).
    /// A snowman whose ledge disappears (its window moved or closed) tumbles off.
    var perches: [CGRect] = [] { didSet { checkPerches() } }

    var hasTargets: Bool { !snowmen.isEmpty || balls.contains { $0.incoming } }

    override init() {
        super.init()
        zPosition = 50
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    private var screenSize: CGSize { scene?.size ?? CGSize(width: 1440, height: 900) }

    // MARK: - Snowmen

    func spawnSnowman() {
        guard isActive, snowmen.count < 4 else { return }
        let options = [
            "body": ["classic", "chubby"].randomElement()!,
            "hat": ["topHat", "beanie", "santa"].randomElement()!,
            "hatColor": ["red", "blue", "green", "pink", "gold"].randomElement()!,
            "face": ["happy", "cheeky", "surprised"].randomElement()!,
            "scarf": ["red", "green", "blue", "pink", "stripes"].randomElement()!,
            "outfit": ["buttons", "mittens", "bowtie"].randomElement()!
        ]
        let art = DecorationRenderer.shared.render(
            PlacedDecoration(kind: .snowman, x: 0, y: 0, scale: 0.56, options: options, seed: 1))
        let w = art.size.width

        // Usually they pop out of a snowdrift anywhere on screen; sometimes they stand on a window or the Dock.
        let ledges = perches.filter { $0.width > w + 30 }
        var perch = CGRect.zero
        var spot: CGFloat?
        var onDrift = false
        if ledges.isEmpty || Double.random(in: 0...1) < 0.65 {
            let size = screenSize
            let top = (scene as? SeasonScene)?.visibleTop ?? size.height - 30
            let maxY = top - art.size.height - 50
            guard maxY > 100, size.width > w + 100 else { return }
            for _ in 0..<10 {
                let p = CGPoint(x: CGFloat.random(in: (w / 2 + 40)...(size.width - w / 2 - 40)), y: CGFloat.random(in: 90...maxY))
                let clear = snowmen.allSatisfy { hypot($0.node.position.x - p.x, $0.node.position.y - p.y) > w * 1.8 }
                if clear { spot = p.x; perch = CGRect(x: p.x - w, y: p.y, width: w * 2, height: 0); onDrift = true; break }
            }
        } else if let ledge = ledges.randomElement() {
            perch = ledge
            for _ in 0..<6 {
                let x = CGFloat.random(in: (perch.minX + w / 2 + 10)...(perch.maxX - w / 2 - 10))
                let clear = snowmen.allSatisfy { abs($0.node.position.x - x) > w * 1.3 || abs($0.perch.minY - perch.minY) > 5 }
                if clear { spot = x; break }
            }
        }
        guard let x = spot else { return }

        let node = SKSpriteNode(texture: SKTexture(cgImage: art.image))
        node.size = art.size
        node.anchorPoint = CGPoint(x: 0.5, y: 0)
        node.position = CGPoint(x: x, y: perch.minY - 2)
        node.yScale = 0.01
        addChild(node)
        if onDrift {
            // A little mound of snow for it to burst out of.
            let drift = SKSpriteNode(texture: SnowTextures.shared.mound)
            drift.anchorPoint = CGPoint(x: 0.5, y: 0)
            drift.size = CGSize(width: w * 1.6, height: 22)
            drift.position = CGPoint(x: x, y: perch.minY - 6)
            drift.zPosition = 0.5
            drift.alpha = 0
            addChild(drift)
            drift.run(.sequence([.fadeIn(withDuration: 0.15), .wait(forDuration: 4.6),
                                 .fadeOut(withDuration: 0.6), .removeFromParent()]))
            ModeEffects.burst(in: self, at: CGPoint(x: x, y: perch.minY + 8), count: 12, colours: ModeEffects.snowColours,
                              sizes: 3...7, distance: 15...45)
        }
        let snowman = Snowman(node: node, perch: perch, onDrift: onDrift)
        snowmen.append(snowman)

        let rise = SKAction.scaleY(to: 1, duration: 0.3)
        rise.timingMode = .easeOut
        let throwOne = SKAction.run { [weak self, weak snowman] in
            if let snowman { self?.snowmanThrows(snowman) }
        }
        var steps: [SKAction] = [rise, .wait(forDuration: TimeInterval.random(in: 0.6...1.3)), throwOne, .wait(forDuration: TimeInterval.random(in: 1.6...2.4))]
        if Bool.random() { steps += [throwOne, .wait(forDuration: 1.5)] }
        steps += [
            .scaleY(to: 0.01, duration: 0.25),
            .run { [weak self, weak snowman] in self?.snowmen.removeAll { $0 === snowman } },
            .removeFromParent()
        ]
        node.run(.sequence(steps))
    }

    private func snowmanThrows(_ s: Snowman) {
        guard isActive, snowmen.contains(where: { $0 === s }) else { return }
        s.node.run(.sequence([.moveBy(x: 0, y: 8, duration: 0.08), .moveBy(x: 0, y: -8, duration: 0.1)]))
        let hand = CGPoint(x: s.node.position.x + s.node.size.width * 0.3,
                           y: s.node.position.y + s.node.size.height * 0.55)
        addBall(from: hand, to: aimPoint(), startSize: 12, endSize: 110, duration: 0.95, arc: 70, incoming: true)
    }

    /// Snowmen aim roughly at your pointer (not too precisely), or somewhere central.
    private func aimPoint() -> CGPoint {
        let size = screenSize
        let m = NSEvent.mouseLocation
        let local = CGPoint(x: m.x - screenOrigin.x, y: m.y - screenOrigin.y)
        var p: CGPoint
        if CGRect(origin: .zero, size: size).contains(local) {
            p = CGPoint(x: local.x + CGFloat.random(in: -140...140), y: local.y + CGFloat.random(in: -140...140))
        } else {
            p = CGPoint(x: CGFloat.random(in: (size.width * 0.25)...(size.width * 0.75)),
                        y: CGFloat.random(in: (size.height * 0.3)...(size.height * 0.7)))
        }
        p.x = min(max(p.x, 80), size.width - 80)
        p.y = min(max(p.y, 80), size.height - 80)
        return p
    }

    private func snowman(at p: CGPoint) -> Snowman? {
        snowmen.first { $0.node.frame.insetBy(dx: -8, dy: -8).contains(p) }
    }

    private func checkPerches() {
        for s in snowmen where !s.onDrift {
            let x = s.node.position.x
            let still = perches.contains { abs($0.minY - s.perch.minY) < 3 && $0.minX <= x && $0.maxX >= x }
            if !still { tumble(s) }
        }
    }

    /// The ledge went away, so the snowman falls off the bottom of the screen.
    private func tumble(_ s: Snowman) {
        snowmen.removeAll { $0 === s }
        s.node.removeAllActions()
        let fall = SKAction.moveBy(x: CGFloat.random(in: -40...40), y: -(s.node.position.y + 150), duration: 0.9)
        fall.timingMode = .easeIn
        s.node.run(.sequence([
            .group([fall, .rotate(byAngle: CGFloat.random(in: -2...2), duration: 0.9), .fadeOut(withDuration: 0.9)]),
            .removeFromParent()
        ]))
    }

    /// Knocked over by your snowball.
    private func bonk(_ s: Snowman, at hit: CGPoint) {
        snowmen.removeAll { $0 === s }
        s.node.removeAllActions()
        // Hit on the left side, it falls to the right, and the other way round.
        let angle: CGFloat = hit.x < s.node.position.x ? -1.4 : 1.4
        s.node.run(.sequence([
            .group([.rotate(byAngle: angle, duration: 0.35), .moveBy(x: angle < 0 ? 24 : -24, y: 0, duration: 0.35)]),
            .wait(forDuration: 0.5), .fadeOut(withDuration: 0.4), .removeFromParent()
        ]))
        ModeEffects.burst(in: self, at: hit, count: 22, colours: ModeEffects.snowColours, sizes: 4...10, distance: 25...80)

        SnowballStats.shared.recordBonk()
        let streak = SnowballStats.shared.streak
        let top = CGPoint(x: s.node.position.x, y: s.node.position.y + s.node.size.height + 20)
        ModeEffects.floatText(in: self, streak >= 2 ? "Bonk!  ·  \(streak) in a row" : "Bonk!",
                              at: top, size: 22, screenWidth: screenSize.width)
    }

    // MARK: - Throwing and clicking

    /// Your throw: it starts low near the bottom of the screen, as if from your hand.
    func throwAt(_ target: CGPoint) {
        let w = screenSize.width
        let from = CGPoint(x: w / 2 + (target.x - w / 2) * 0.35, y: -40)
        let dist = hypot(target.x - from.x, target.y - from.y)
        addBall(from: from, to: target, startSize: 64, endSize: 22,
                duration: 0.3 + dist / 3200, arc: min(140, dist * 0.18), incoming: false)
    }

    /// True if the pointer is over a snowman or an incoming snowball, so Nook should take the click.
    func hitTest(_ p: CGPoint) -> Bool {
        !isFrozen && (incomingBall(at: p) != nil || snowman(at: p) != nil)
    }

    /// While the game is paused, snowmen and snowballs hold still and can't be clicked.
    var isFrozen = false {
        didSet {
            guard oldValue != isFrozen else { return }
            isPaused = isFrozen
            lastTime = 0
        }
    }

    /// Handles a click. `anywhere` is true when Option is held, which throws even at empty space.
    func handleClick(at p: CGPoint, anywhere: Bool) -> Bool {
        guard isActive, !isFrozen else { return false }
        if let i = incomingBall(at: p) {
            let b = balls.remove(at: i)
            b.node.removeFromParent()
            ModeEffects.burst(in: self, at: b.pos, count: 16, colours: ModeEffects.snowColours, sizes: 4...9, distance: 30...90)
            SnowballStats.shared.recordBlock()
            ModeEffects.floatText(in: self, "Blocked!", at: CGPoint(x: b.pos.x, y: b.pos.y + 40), size: 22,
                                  screenWidth: screenSize.width)
            return true
        }
        if anywhere || snowman(at: p) != nil {
            throwAt(p)
            return true
        }
        return false
    }

    private func incomingBall(at p: CGPoint) -> Int? {
        balls.firstIndex { $0.incoming && hypot(p.x - $0.pos.x, p.y - $0.pos.y) < $0.size / 2 + 14 }
    }

    private func addBall(from: CGPoint, to: CGPoint, startSize: CGFloat, endSize: CGFloat,
                         duration: CGFloat, arc: CGFloat, incoming: Bool) {
        let node = SKSpriteNode(texture: SnowballLayer.ballTexture)
        node.size = CGSize(width: startSize, height: startSize)
        node.position = from
        node.zPosition = incoming ? 4 : 1
        addChild(node)
        balls.append(Ball(node: node, from: from, to: to, startSize: startSize, endSize: endSize,
                          duration: duration, arc: arc, incoming: incoming, t: 0, pos: from, size: startSize))
    }

    // MARK: - Every frame

    func step(_ now: CFTimeInterval) {
        guard isActive, !isFrozen, !balls.isEmpty else { lastTime = 0; return }
        let dt = CGFloat(lastTime == 0 ? 1.0 / 30.0 : min(0.1, max(0.001, now - lastTime)))
        lastTime = now

        var i = 0
        while i < balls.count {
            var b = balls[i]
            b.t = min(1, b.t + dt / b.duration)
            let t = b.t
            b.pos = CGPoint(x: b.from.x + (b.to.x - b.from.x) * t,
                            y: b.from.y + (b.to.y - b.from.y) * t + sin(.pi * t) * b.arc)
            // Incoming snowballs swell faster at the end, like they're about to hit your face.
            let grow = b.incoming ? t * t : t.squareRoot()
            b.size = b.startSize + (b.endSize - b.startSize) * grow
            b.node.position = b.pos
            b.node.size = CGSize(width: b.size, height: b.size)
            b.node.zRotation += dt * 3

            if t >= 1 {
                balls.remove(at: i)
                impact(b)
                continue
            }
            balls[i] = b
            i += 1
        }
    }

    private func impact(_ b: Ball) {
        b.node.removeFromParent()
        if b.incoming {
            splat(at: b.to, size: CGFloat.random(in: 170...230), onGlass: true)
            SnowballStats.shared.recordSplat()
        } else if let s = snowmen.first(where: { $0.node.frame.insetBy(dx: -12, dy: -12).contains(b.to) }) {
            bonk(s, at: b.to)
        } else {
            splat(at: b.to, size: 38, onGlass: false)
        }
    }

    /// A splat right on your screen slides down a little and melts away. A miss far off is just a puff.
    private func splat(at p: CGPoint, size: CGFloat, onGlass: Bool) {
        let node = SKSpriteNode(texture: SnowballLayer.splatTextures.randomElement()!)
        node.size = CGSize(width: size, height: size)
        node.position = p
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))
        node.zPosition = onGlass ? 5 : 0.5
        addChild(node)
        if onGlass {
            node.alpha = 0
            node.setScale(0.6)
            let slide = SKAction.moveBy(x: 0, y: -60, duration: 3)
            slide.timingMode = .easeIn
            node.run(.sequence([
                .group([.scale(to: 1, duration: 0.08), .fadeAlpha(to: 0.95, duration: 0.08)]),
                .wait(forDuration: 1.4),
                .group([slide, .fadeOut(withDuration: 3)]),
                .removeFromParent()
            ]))
            ModeEffects.burst(in: self, at: p, count: 14, colours: ModeEffects.snowColours, sizes: 6...14, distance: 60...140)
        } else {
            node.alpha = 0.9
            node.run(.sequence([.wait(forDuration: 0.5), .fadeOut(withDuration: 1), .removeFromParent()]))
            ModeEffects.burst(in: self, at: p, count: 8, colours: ModeEffects.snowColours, sizes: 3...6, distance: 15...40)
        }
    }

    // MARK: - Hint and clearing up

    /// A one-time reminder of the controls when the mode starts.
    func showHint() {
        let size = screenSize
        ModeEffects.floatText(in: self, "Click a snowman to throw  ·  Hold ⌥ Option and click to throw anywhere",
                              at: CGPoint(x: size.width / 2, y: size.height * 0.55), size: 22, hold: 3,
                              screenWidth: size.width)
    }

    private func clear() {
        snowmen.removeAll()
        balls.removeAll()
        for child in children {
            child.removeAllActions()
            child.run(.sequence([.fadeOut(withDuration: 0.3), .removeFromParent()]))
        }
    }

    // MARK: - Art

    private static let ballTexture: SKTexture = SnowballLayer.makeTexture(size: 64) { ctx, s in
        ctx.addEllipse(in: CGRect(x: 1, y: 1, width: s - 2, height: s - 2))
        ctx.clip()
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                      CGColor(red: 0.93, green: 0.96, blue: 1, alpha: 1),
                      CGColor(red: 0.72, green: 0.8, blue: 0.93, alpha: 1)] as CFArray
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: s * 0.38, y: s * 0.64), startRadius: 0,
                               endCenter: CGPoint(x: s / 2, y: s / 2), endRadius: s / 2,
                               options: [.drawsAfterEndLocation])
    }

    /// A few different splat shapes: a round middle, lumpy edges, flecks and a couple of drips.
    private static let splatTextures: [SKTexture] = (0..<3).map { _ in
        SnowballLayer.makeTexture(size: 256) { ctx, s in
            let c = CGPoint(x: s / 2, y: s / 2)
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            func blob(_ p: CGPoint, _ r: CGFloat) {
                ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            blob(c, s * 0.26)
            let lumps = Int.random(in: 10...14)
            for i in 0..<lumps {
                let a = CGFloat(i) / CGFloat(lumps) * 2 * .pi + CGFloat.random(in: -0.3...0.3)
                let d = s * CGFloat.random(in: 0.2...0.36)
                blob(CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d), s * CGFloat.random(in: 0.05...0.11))
            }
            for _ in 0..<Int.random(in: 6...10) {
                let a = CGFloat.random(in: 0...(2 * .pi))
                let d = s * CGFloat.random(in: 0.38...0.47)
                blob(CGPoint(x: c.x + cos(a) * d, y: c.y + sin(a) * d), s * CGFloat.random(in: 0.012...0.03))
            }
            for _ in 0..<Int.random(in: 2...3) {
                let x = c.x + s * CGFloat.random(in: -0.18...0.18)
                let len = s * CGFloat.random(in: 0.18...0.32)
                let w = s * CGFloat.random(in: 0.035...0.06)
                ctx.fill(CGRect(x: x - w / 2, y: c.y - len, width: w, height: len))
                blob(CGPoint(x: x, y: c.y - len), w * 0.75)
            }
            // Soft blue shading toward the bottom so it reads as snow on any background.
            ctx.setBlendMode(.sourceAtop)
            let colors = [CGColor(red: 0.7, green: 0.8, blue: 0.95, alpha: 0.5), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: s * 0.05), end: CGPoint(x: 0, y: s * 0.6), options: [])
        }
    }

    private static func makeTexture(size: Int, draw: (CGContext, CGFloat) -> Void) -> SKTexture {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, CGFloat(size))
        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }
}
