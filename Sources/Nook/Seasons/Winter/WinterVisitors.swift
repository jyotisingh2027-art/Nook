import SpriteKit

/// Little winter visitors that wander along the snowy tops of windows and the Dock:
/// reindeer (walking, running, or stopping to graze), hopping bunnies, and a person
/// with a shovel who turns up to clear snow once it has piled up deep.
final class WinterVisitors {
    let layer = SKNode()

    /// Hooks into the winter scene.
    var piles: () -> [SurfaceKey: SnowPile] = { [:] }
    var throwSnow: (_ at: CGPoint, _ velocity: CGVector, _ size: CGFloat, _ passThrough: SurfaceKey?) -> Void = { _, _, _, _ in }
    var isCovered: (CGPoint) -> Bool = { _ in false }

    private var visitors: [Visitor] = []
    private var clock: Double = 0
    private var nextAnimalAt = Double.random(in: 10...20)    // the first visitor comes fairly soon
    private var nextShovelCheckAt = 6.0
    private var shovellerRestUntil = 0.0
    private var checkSettingAt = 0.0
    private var enabled = Settings.shared.visitorsOn

    private let gravity: CGFloat = 650
    /// For testing: `NOOK_VISITOR_DEMO=1` makes visitors turn up every few seconds.
    private let demo = ProcessInfo.processInfo.environment["NOOK_VISITOR_DEMO"] != nil

    // MARK: - Per frame

    func step(dt: CGFloat, visibleTop: CGFloat) {
        clock += Double(dt)
        if clock >= checkSettingAt {
            checkSettingAt = clock + 1
            enabled = Settings.shared.visitorsOn
        }
        let piles = self.piles()

        if enabled {
            if clock >= nextAnimalAt {
                nextAnimalAt = clock + (demo ? 8 : Double.random(in: 28...75))
                if !visitors.contains(where: { $0.isAnimal }) { spawnAnimal(piles, visibleTop: visibleTop) }
            }
            if clock >= nextShovelCheckAt {
                nextShovelCheckAt = clock + 2
                if clock >= shovellerRestUntil, !visitors.contains(where: { $0.isShoveller }) {
                    spawnShovellerIfNeeded(piles, visibleTop: visibleTop)
                }
            }
        }

        var i = 0
        while i < visitors.count {
            let v = visitors[i]
            if !enabled { v.leaving = true }
            if update(v, dt: dt, piles: piles) {
                i += 1
            } else {
                if v.isShoveller { shovellerRestUntil = clock + (demo ? 3 : Double.random(in: 6...15)) }
                v.node.removeFromParent()
                visitors.remove(at: i)
            }
        }
    }

    /// A window was dragged: anyone on it hangs on for slow moves but gets flung off fast ones.
    func surfaceShaken(_ key: SurfaceKey, velocity: CGVector) {
        guard hypot(velocity.dx, velocity.dy) > 500 else { return }
        for v in visitors where v.key == key && v.falling == nil {
            v.falling = CGVector(dx: max(-500, min(500, velocity.dx * 0.4)), dy: 120 + max(0, min(300, velocity.dy * 0.3)))
        }
    }

    // MARK: - Choosing where they go

    private func usablePiles(_ piles: [SurfaceKey: SnowPile], minWidth: CGFloat, headroom: CGFloat, visibleTop: CGFloat) -> [SnowPile] {
        piles.values.filter { p in
            // The ground may pass behind windows (visitors just walk behind them too).
            if p.key == .ground { return p.width >= minWidth }
            guard p.width >= minWidth, p.hiddenColumns.isEmpty,
                  p.origin.y > -4, p.origin.y + headroom < visibleTop else { return false }
            // Skip tops that another window (or one of Nook's panels) sits over.
            for f in [0.15, 0.5, 0.85] as [CGFloat] {
                if isCovered(CGPoint(x: p.origin.x + p.width * f, y: p.origin.y + headroom * 0.5)) { return false }
            }
            return true
        }
    }

    private func pick(_ list: [SnowPile]) -> SnowPile? {
        // The Dock is a favourite spot when it's free.
        if let dock = list.first(where: { $0.key == .dock }), Bool.random() { return dock }
        return list.randomElement()
    }

    private func spawnAnimal(_ piles: [SurfaceKey: SnowPile], visibleTop: CGFloat) {
        if Double.random(in: 0...1) < 0.6 {
            guard let pile = pick(usablePiles(piles, minWidth: 300, headroom: 100, visibleTop: visibleTop)) else { return }
            let dir: CGFloat = Bool.random() ? 1 : -1
            let roll = Double.random(in: 0...1)
            let gait: Visitor.Gait = roll < 0.35 ? .walk : (roll < 0.65 ? .run : .wander)
            let stopFraction = CGFloat.random(in: 0.35...0.65)
            let pause = CGFloat.random(in: 2.5...4.5)
            let adult = Visitor(kind: .reindeer(young: false), key: pile.key, pile: pile, dir: dir, gait: gait)
            adult.stopAt = adult.distance(at: stopFraction, of: pile)
            adult.pauseLength = pause
            add(adult, size: VisitorArt.reindeerSize)
            // Sometimes a youngster tags along behind.
            if Double.random(in: 0...1) < 0.3 {
                let young = Visitor(kind: .reindeer(young: true), key: pile.key, pile: pile, dir: dir, gait: gait)
                young.startDelay = 58 * VisitorArt.displayScale / young.speed
                young.stopAt = adult.stopAt
                young.pauseLength = pause
                add(young, size: CGSize(width: VisitorArt.reindeerSize.width * 0.72, height: VisitorArt.reindeerSize.height * 0.72))
            }
        } else {
            guard let pile = pick(usablePiles(piles, minWidth: 160, headroom: 50, visibleTop: visibleTop)) else { return }
            let v = Visitor(kind: .bunny, key: pile.key, pile: pile, dir: Bool.random() ? 1 : -1, gait: .walk)
            add(v, size: VisitorArt.bunnyDisplaySize)
        }
    }

    private func spawnShovellerIfNeeded(_ piles: [SurfaceKey: SnowPile], visibleTop: CGFloat) {
        let deep = usablePiles(piles, minWidth: 170, headroom: 80, visibleTop: visibleTop)
            .filter { $0.fullness > (demo ? 0.15 : 0.35) }
            .max { $0.fullness < $1.fullness }
        guard let pile = deep else { return }
        let outfit = VisitorArt.outfits.randomElement()!
        let v = Visitor(kind: .shoveller(outfit), key: pile.key, pile: pile, dir: Bool.random() ? 1 : -1, gait: .walk)
        add(v, size: VisitorArt.shovellerSize)
    }

    private func add(_ v: Visitor, size: CGSize) {
        v.node.size = CGSize(width: size.width * VisitorArt.displayScale, height: size.height * VisitorArt.displayScale)
        v.node.anchorPoint = CGPoint(x: 0.5, y: 0)
        v.node.zPosition = 18          // behind the snow surface, so feet sink in a little
        v.node.alpha = 0
        v.node.xScale = v.dir
        v.node.isHidden = true
        layer.addChild(v.node)
        visitors.append(v)
    }

    // MARK: - Moving them

    /// Returns false once the visitor has gone.
    private func update(_ v: Visitor, dt: CGFloat, piles: [SurfaceKey: SnowPile]) -> Bool {
        let pile = piles[v.key]
        if pile == nil && v.falling == nil {
            // The window closed or vanished under them: down they go.
            v.falling = CGVector(dx: v.dir * 40, dy: 90)
        }

        if var f = v.falling {
            f.dy -= gravity * dt
            v.pos.x += f.dx * dt
            v.pos.y += f.dy * dt
            v.falling = f
            v.node.zRotation += -v.dir * 3 * dt
            v.node.alpha = max(0, v.node.alpha - dt * 0.7)
            v.node.position = v.pos
            return v.pos.y > -90 && v.node.alpha > 0.02
        }
        guard let pile else { return false }

        if v.startDelay > 0 {
            v.startDelay -= dt
            return true
        }

        v.anim += dt
        var bounce: CGFloat = 0

        switch v.kind {
        case .reindeer(let young):
            bounce = stepReindeer(v, dt: dt, pile: pile, young: young)
        case .bunny:
            bounce = stepBunny(v, dt: dt)
        case .shoveller(let outfit):
            stepShoveller(v, dt: dt, pile: pile, outfit: outfit)
        }

        // Fade in at the start, out near the far end (or when asked to leave).
        let onGround = v.key == .ground
        let remaining = (v.dir > 0 ? pile.width - v.u : v.u) + (onGround ? 45 : 0)
        var target: CGFloat = onGround ? 1 : min(1, v.anim / 0.6)
        if !onGround { target = min(target, max(0, (remaining - 4) / 26)) }
        if v.leaving { target = 0 }
        let a = v.leaving ? max(0, v.node.alpha - dt * 1.5) : target
        v.node.alpha = a
        if remaining <= 4 || (v.leaving && a <= 0.01) { return false }

        let x = pile.origin.x + v.u
        let ground = pile.origin.y + feetHeight(pile, x: x) - 2.5
        v.pos = CGPoint(x: x, y: ground + bounce)
        v.node.position = v.pos
        let covered = isCovered(CGPoint(x: x, y: ground + v.node.size.height * 0.5))
        if v.node.isHidden != covered { v.node.isHidden = covered }
        return true
    }

    private func feetHeight(_ pile: SnowPile, x: CGFloat) -> CGFloat {
        (pile.surfaceHeight(atLocalX: x - 6) + pile.surfaceHeight(atLocalX: x) * 2 + pile.surfaceHeight(atLocalX: x + 6)) / 4
    }

    private func stepReindeer(_ v: Visitor, dt: CGFloat, pile: SnowPile, young: Bool) -> CGFloat {
        let frames = young ? VisitorArt.reindeerYoung : VisitorArt.reindeerAdult

        // Stopping to graze and look around.
        if v.pauseLeft > 0 {
            v.pauseLeft -= dt
            let lookUp = Int(v.pauseLeft * 1.3) % 3 == 0
            v.setTexture(lookUp ? frames.stand : frames.graze)
            return 0
        }
        if v.gait == .wander, let stop = v.stopAt, !v.didPause,
           (v.dir > 0 && v.u >= stop) || (v.dir < 0 && v.u <= stop) {
            v.didPause = true
            v.pauseLeft = v.pauseLength
            return 0
        }

        v.u += v.dir * v.speed * dt
        if v.gait == .run {
            let cycle: CGFloat = 0.27
            let k = Int(v.anim / (cycle / 3)) % 3
            v.setTexture(frames.run[k])
            // Hooves kick up little puffs of snow.
            v.kickTimer -= dt
            if v.kickTimer <= 0 {
                v.kickTimer = 0.14
                kickSnow(v, pile: pile, strength: young ? 0.6 : 1)
            }
            return abs(sin(v.anim * .pi / cycle)) * (young ? 4 : 6)
        }
        let k = Int(v.anim / 0.17) % 4
        v.setTexture(frames.walk[k])
        return 0
    }

    private func stepBunny(_ v: Visitor, dt: CGFloat) -> CGFloat {
        let hopTime: CGFloat = 0.32
        if v.restLeft > 0 {
            v.restLeft -= dt
            v.setTexture(v.sittingUp ? VisitorArt.bunnySitUp : VisitorArt.bunnyCrouch)
            if v.restLeft <= 0 { v.hopT = 0 }
            return 0
        }
        v.hopT += dt
        v.u += v.dir * (24 / hopTime) * dt
        v.setTexture(VisitorArt.bunnyHop)
        let t = min(1, v.hopT / hopTime)
        if v.hopT >= hopTime {
            v.sittingUp = Double.random(in: 0...1) < 0.18
            v.restLeft = v.sittingUp ? CGFloat.random(in: 1.0...1.8) : CGFloat.random(in: 0.12...0.8)
        }
        return sin(t * .pi) * 9
    }

    private func stepShoveller(_ v: Visitor, dt: CGFloat, pile: SnowPile, outfit: VisitorArt.Outfit) {
        v.workT += dt
        switch v.work {
        case .walking:
            let snowAhead = snowDepth(pile, fromU: v.u + v.dir * 8, length: 24, dir: v.dir) - pile.maxHeight * 0.15
            // Stroll faster over bare patches.
            v.u += v.dir * (snowAhead > 1.4 ? 38 : 60) * dt
            v.setTexture(VisitorArt.shoveller(Int(v.workT / 0.14) % 2 == 0 ? .walkA : .walkB, outfit: outfit))
            if v.workT > 0.5 && snowAhead > 1.4 && !v.leaving {
                v.work = .scooping
                v.workT = 0
            }
        case .scooping:
            v.setTexture(VisitorArt.shoveller(.scoop, outfit: outfit))
            if v.workT > 0.26 {
                // Lift the snow in front and heave it back over the shoulder.
                let start = v.u + v.dir * 6
                let a = min(start, start + v.dir * 28), b = max(start, start + v.dir * 28)
                let lo = max(0, Int(a / SnowPile.columnWidth)), hi = min(pile.heights.count, Int(b / SnowPile.columnWidth) + 1)
                let amount = lo < hi ? pile.scoop(columns: lo..<hi, keep: pile.maxHeight * 0.15) : 0
                v.work = .tossing
                v.workT = 0
                if amount > 0.5 {
                    let n = min(4, 1 + Int(amount / 14))
                    let from = CGPoint(x: v.pos.x - v.dir * 12, y: v.pos.y + 44 * VisitorArt.displayScale)
                    for _ in 0..<n {
                        let size = min(8, max(3, sqrt(amount / CGFloat(n)) * 1.5))
                        throwSnow(CGPoint(x: from.x + CGFloat.random(in: -3...3), y: from.y),
                                  CGVector(dx: -v.dir * CGFloat.random(in: 60...150), dy: CGFloat.random(in: 70...170)),
                                  size, v.key)
                    }
                }
            }
        case .tossing:
            v.setTexture(VisitorArt.shoveller(.toss, outfit: outfit))
            if v.workT > 0.34 {
                v.work = .walking
                v.workT = 0
            }
        }
    }

    private func snowDepth(_ pile: SnowPile, fromU u: CGFloat, length: CGFloat, dir: CGFloat) -> CGFloat {
        let a = min(u, u + dir * length), b = max(u, u + dir * length)
        let lo = max(0, Int(a / SnowPile.columnWidth)), hi = min(pile.heights.count, Int(b / SnowPile.columnWidth) + 1)
        guard lo < hi else { return 0 }
        return pile.heights[lo..<hi].max() ?? 0
    }

    private func kickSnow(_ v: Visitor, pile: SnowPile, strength: CGFloat) {
        let i = Int((v.u - v.dir * 14 * VisitorArt.displayScale) / SnowPile.columnWidth)
        guard i >= 1, i < pile.heights.count - 1, pile.heights[i] > 2 else { return }
        let taken = pile.scoop(columns: (i - 1)..<(i + 2), keep: pile.heights[i] - 1.2 * strength)
        guard taken > 0.3 else { return }
        throwSnow(CGPoint(x: v.pos.x - v.dir * 14, y: v.pos.y + 4),
                  CGVector(dx: -v.dir * CGFloat.random(in: 40...110), dy: CGFloat.random(in: 60...130)),
                  CGFloat.random(in: 2.5...4), nil)
    }
}

// MARK: - One visitor

private final class Visitor {
    enum Kind {
        case reindeer(young: Bool)
        case bunny
        case shoveller(VisitorArt.Outfit)
    }
    enum Gait { case walk, run, wander }
    enum Work { case walking, scooping, tossing }

    let kind: Kind
    let key: SurfaceKey
    let dir: CGFloat
    let gait: Gait
    let node = SKSpriteNode()

    /// Distance from the pile's left end, so they ride along when a window moves slowly.
    var u: CGFloat
    var pos: CGPoint = .zero
    var anim: CGFloat = 0
    var startDelay: CGFloat = 0
    var leaving = false
    var falling: CGVector?

    // Reindeer
    var stopAt: CGFloat?
    var pauseLength: CGFloat = 3
    var pauseLeft: CGFloat = 0
    var didPause = false
    var kickTimer: CGFloat = 0

    // Bunny
    var hopT: CGFloat = 0
    var restLeft: CGFloat = 0.4
    var sittingUp = false

    // Shoveller
    var work: Work = .walking
    var workT: CGFloat = 0

    private var currentTexture: SKTexture?

    var isAnimal: Bool { if case .shoveller = kind { return false } else { return true } }
    var isShoveller: Bool { !isAnimal }

    var speed: CGFloat {
        switch kind {
        case .reindeer(let young): return gait == .run ? 150 : (young ? 34 : 34)
        case .bunny: return 40
        case .shoveller: return 40
        }
    }

    init(kind: Kind, key: SurfaceKey, pile: SnowPile, dir: CGFloat, gait: Gait) {
        self.kind = kind
        self.key = key
        self.dir = dir
        self.gait = gait
        // On the ground they walk in from beyond the screen edge; elsewhere they start at an end.
        let margin: CGFloat = key == .ground ? -45 : 6
        self.u = dir > 0 ? margin : pile.width - margin
    }

    func distance(at fraction: CGFloat, of pile: SnowPile) -> CGFloat {
        dir > 0 ? pile.width * fraction : pile.width * (1 - fraction)
    }

    func setTexture(_ t: SKTexture) {
        guard t !== currentTexture else { return }
        currentTexture = t
        node.texture = t
    }
}
