import SpriteKit

/// Winter on one screen: falling snow, snow settling on windows and the Dock,
/// and clumps flying off when windows move, resize or close.
final class WinterScene: SeasonScene {

    // MARK: - Types

    private struct Flake {
        let node: SKSpriteNode
        var pos: CGPoint
        var fallSpeed: CGFloat
        var depth: CGFloat        // 0 = far away, 1 = close
        var phase: CGFloat
        var swayAmount: CGFloat
        var swaySpeed: CGFloat
        var spin: CGFloat
        var size: CGFloat
        var canLand: Bool         // far-away flakes drift past; close ones settle
    }

    private struct Chunk {
        let node: SKSpriteNode
        var pos: CGPoint
        var vel: CGVector
        let size: CGFloat
        let ignore: SurfaceKey?
        var ignoreTime: CGFloat
        let spin: CGFloat
    }

    private struct Surface {
        let key: SurfaceKey
        let minX: CGFloat
        let maxX: CGFloat
        let y: CGFloat
        let blocked: [ClosedRange<CGFloat>]   // parts covered by a window in front
    }

    private enum ShedStyle {
        case thrown(CGVector)
        case crumble
        case tumble
    }

    // MARK: - Tuning

    private let windowSnowMax: CGFloat = 20
    private let dockSnowMax: CGFloat = 22
    private let groundSnowMax: CGFloat = 20
    private let gravity: CGFloat = 650
    private let maxChunks = 450

    // MARK: - State

    private var flakes: [Flake] = []
    private var chunks: [Chunk] = []
    private var piles: [SurfaceKey: SnowPile] = [:]
    private var stashed: [CGWindowID: SnowPile] = [:]   // snow on minimized/hidden windows
    private var surfaces: [Surface] = []
    /// Open windows on this screen. Snow is hidden inside them, so it only falls on the desktop.
    private var windowRects: [CGRect] = []

    private func insideWindow(_ p: CGPoint) -> Bool {
        for r in windowRects where r.contains(p) { return true }
        return false
    }

    private var lastTime: TimeInterval = 0
    private var clock: Double = 0
    private var settleTimer: Double = 0
    private var hasDusted = false

    private let textures = SnowTextures.shared
    private let flakeLayer = SKNode()
    private let pileLayer = SKNode()
    private let chunkLayer = SKNode()
    private let visitors = WinterVisitors()

    override init(screenFrame: CGRect, visibleTop: CGFloat) {
        super.init(screenFrame: screenFrame, visibleTop: visibleTop)
        addChild(pileLayer)
        addChild(visitors.layer)
        addChild(chunkLayer)
        addChild(flakeLayer)

        visitors.piles = { [unowned self] in self.piles }
        visitors.isCovered = { [unowned self] p in self.insideWindow(p) }
        visitors.throwSnow = { [unowned self] p, v, size, passThrough in
            self.spawnChunk(at: p, velocity: v, size: size, ignore: passThrough, ignoreTime: passThrough == nil ? 0 : 2.5)
        }
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    // MARK: - Flakes

    private var targetFlakeCount: Int {
        let area = size.width * size.height / 1_000_000
        var n = Double(area) * 120 * snowDensity
        if energySaving { n *= 0.5 }
        return max(15, min(800, Int(n)))
    }

    private func makeFlake(anywhere: Bool) -> Flake {
        let depth = CGFloat.random(in: 0.25...1)
        let crystal = depth > 0.5 && Double.random(in: 0...1) < 0.14
        let size: CGFloat = crystal
            ? CGFloat.random(in: 11...17) * (0.75 + 0.25 * depth)
            : (2.6 + depth * 5.4) * CGFloat.random(in: 0.8...1.2)
        let node = SKSpriteNode(texture: crystal ? textures.crystals.randomElement()! : textures.dot)
        node.size = CGSize(width: size, height: size)
        node.alpha = 0.35 + depth * 0.6
        node.zPosition = depth > 0.6 ? 20 : 5
        flakeLayer.addChild(node)

        var f = Flake(node: node, pos: .zero,
                      fallSpeed: (14 + depth * 36) * CGFloat.random(in: 0.85...1.15),
                      depth: depth,
                      phase: CGFloat.random(in: 0...(2 * .pi)),
                      swayAmount: CGFloat.random(in: 6...22) * depth,
                      swaySpeed: CGFloat.random(in: 0.4...1.2),
                      spin: crystal ? CGFloat.random(in: -0.6...0.6) : 0,
                      size: size,
                      canLand: depth > 0.55)
        f.pos = CGPoint(x: CGFloat.random(in: -40...(self.size.width + 40)),
                        y: anywhere ? CGFloat.random(in: 0...(self.size.height + 20))
                                    : self.size.height + CGFloat.random(in: 4...60))
        node.position = f.pos
        return f
    }

    private func respawn(_ f: inout Flake) {
        f.pos = CGPoint(x: CGFloat.random(in: -40...(size.width + 40)), y: size.height + CGFloat.random(in: 4...50))
        f.phase = CGFloat.random(in: 0...(2 * .pi))
    }

    private func adjustFlakeCount() {
        let target = targetFlakeCount
        if flakes.isEmpty {
            flakes = (0..<target).map { _ in makeFlake(anywhere: true) }
            return
        }
        if flakes.count < target {
            for _ in 0..<min(4, target - flakes.count) { flakes.append(makeFlake(anywhere: false)) }
        } else if flakes.count > target {
            for _ in 0..<min(6, flakes.count - target) { flakes.removeLast().node.removeFromParent() }
        }
    }

    // MARK: - Frame update

    override func weatherVisibilityChanged() {
        flakeLayer.isHidden = !weatherVisible
        pileLayer.isHidden = !weatherVisible
        chunkLayer.isHidden = !weatherVisible
        visitors.layer.isHidden = !weatherVisible
    }

    override func update(_ currentTime: TimeInterval) {
        guard weatherVisible else { lastTime = 0; return }
        let dt = CGFloat(lastTime == 0 ? 1.0 / 30.0 : min(0.1, max(0.001, currentTime - lastTime)))
        lastTime = currentTime
        clock += Double(dt)

        adjustFlakeCount()

        // A soft, slowly changing breeze.
        let wind = CGFloat(sin(clock * 0.05) * 10 + sin(clock * 0.17 + 1.3) * 5)
        let w = size.width
        let speed = CGFloat(snowSpeed)
        // More and faster flakes means more landings; keep the pile-up pace steady.
        let landAmount = CGFloat(0.6 * snowBuildUp / (snowDensity * snowSpeed))

        for i in flakes.indices {
            var f = flakes[i]
            let prevY = f.pos.y
            f.pos.y -= f.fallSpeed * speed * dt
            f.phase += f.swaySpeed * dt
            f.pos.x += (cos(f.phase) * f.swayAmount + wind * f.depth) * dt

            if f.canLand, let pile = landingPile(x: f.pos.x, fromY: prevY, toY: f.pos.y, ignoring: nil) {
                pile.add(atLocalX: f.pos.x, amount: f.size * landAmount)
                respawn(&f)
            } else if f.pos.y < -12 || f.pos.x < -50 || f.pos.x > w + 50 {
                respawn(&f)
            }
            f.node.position = f.pos
            let hideFlake = insideWindow(f.pos)
            if f.node.isHidden != hideFlake { f.node.isHidden = hideFlake }
            if f.spin != 0 { f.node.zRotation += f.spin * dt }
            flakes[i] = f
        }

        updateChunks(dt)
        visitors.step(dt: dt, visibleTop: visibleTop)

        settleTimer += Double(dt)
        if settleTimer > 0.1 {
            settleTimer = 0
            for pile in piles.values {
                pile.relax()
                pile.redrawIfNeeded()
            }
        }
    }

    private func landingPile(x: CGFloat, fromY y0: CGFloat, toY y1: CGFloat, ignoring: SurfaceKey?) -> SnowPile? {
        for s in surfaces {
            guard x >= s.minX, x <= s.maxX, s.key != ignoring, let pile = piles[s.key] else { continue }
            let top = s.y + pile.surfaceHeight(atLocalX: x)
            if y0 >= top - 0.5 && y1 < top {
                if s.blocked.contains(where: { $0.contains(x) }) { continue }
                return pile
            }
        }
        return nil
    }

    // MARK: - Clumps of snow in flight

    private func spawnChunk(at p: CGPoint, velocity: CGVector, size: CGFloat, ignore: SurfaceKey?, ignoreTime: CGFloat) {
        guard chunks.count < maxChunks else { return }
        let node = SKSpriteNode(texture: textures.clump)
        node.size = CGSize(width: size, height: size)
        node.position = p
        node.zPosition = 15
        node.zRotation = CGFloat.random(in: 0...(2 * .pi))
        chunkLayer.addChild(node)
        chunks.append(Chunk(node: node, pos: p, vel: velocity, size: size, ignore: ignore,
                            ignoreTime: ignoreTime, spin: CGFloat.random(in: -4...4)))
    }

    private func updateChunks(_ dt: CGFloat) {
        guard !chunks.isEmpty else { return }
        let w = size.width
        var i = 0
        while i < chunks.count {
            var c = chunks[i]
            let prevY = c.pos.y
            c.vel.dy -= gravity * dt
            c.vel.dx *= max(0, 1 - 0.5 * dt)
            c.pos.x += c.vel.dx * dt
            c.pos.y += c.vel.dy * dt
            c.ignoreTime -= dt

            var remove = false
            if c.vel.dy < 0,
               let pile = landingPile(x: c.pos.x, fromY: prevY, toY: c.pos.y, ignoring: c.ignoreTime > 0 ? c.ignore : nil) {
                pile.add(atLocalX: c.pos.x, amount: c.size * 0.45)
                remove = true
            } else if c.pos.y < -20 || c.pos.x < -60 || c.pos.x > w + 60 {
                remove = true
            }

            if remove {
                c.node.removeFromParent()
                chunks.swapAt(i, chunks.count - 1)
                chunks.removeLast()
                continue
            }
            c.node.position = c.pos
            let hideChunk = insideWindow(c.pos)
            if c.node.isHidden != hideChunk { c.node.isHidden = hideChunk }
            c.node.zRotation += c.spin * dt
            chunks[i] = c
            i += 1
        }
    }

    /// Breaks a pile into clumps that fly or fall away.
    private func shed(_ pile: SnowPile, style: ShedStyle) {
        let cw = SnowPile.columnWidth
        let group = 4
        var start = 0
        while start < pile.heights.count {
            let range = start..<min(start + group, pile.heights.count)
            let hidden = range.allSatisfy { pile.hiddenColumns.contains($0) }
            let amount = pile.take(columns: range)
            if amount > 1.5 && !hidden {
                let avg = amount / CGFloat(range.count)
                let x = pile.origin.x + (CGFloat(range.lowerBound) + CGFloat(range.count) / 2) * cw
                let p = CGPoint(x: x + CGFloat.random(in: -1...1), y: pile.origin.y + avg * 0.5)
                let size = min(9, max(2.5, sqrt(amount) * 1.4))
                var v: CGVector
                var ignoreTime: CGFloat = 0
                switch style {
                case .thrown(let wv):
                    v = CGVector(dx: wv.dx * 0.7 + CGFloat.random(in: -40...40),
                                 dy: wv.dy * 0.7 + CGFloat.random(in: 10...90))
                    let mag = hypot(v.dx, v.dy)
                    if mag > 2200 { v.dx *= 2200 / mag; v.dy *= 2200 / mag }
                    ignoreTime = 0.35
                case .crumble:
                    v = CGVector(dx: CGFloat.random(in: -25...25), dy: CGFloat.random(in: -10...40))
                case .tumble:
                    v = CGVector(dx: CGFloat.random(in: -50...50), dy: CGFloat.random(in: 20...110))
                }
                spawnChunk(at: p, velocity: v, size: size, ignore: pile.key, ignoreTime: ignoreTime)
            }
            start += group
        }
        pile.redrawIfNeeded()
    }

    override func brushAllSnowOff() {
        for pile in piles.values { shed(pile, style: .crumble) }
    }

    // MARK: - Windows

    override func windowsDidUpdate(_ windows: [TrackedWindow], events: [WindowEvent], dockRect: CGRect?) {
        for event in events {
            switch event {
            case .moved(let id, let velocity):
                if let p = piles[.window(id)] { shed(p, style: .thrown(velocity)) }
                visitors.surfaceShaken(.window(id), velocity: velocity)
            case .resized(let id):
                if let p = piles[.window(id)] { shed(p, style: .crumble) }
            case .closed(let id):
                if let p = piles.removeValue(forKey: .window(id)) {
                    shed(p, style: .tumble)
                    p.node.removeFromParent()
                }
                stashed[id] = nil
            case .hidden(let id):
                if let p = piles.removeValue(forKey: .window(id)) { stash(id, p) }
            }
        }

        var newSurfaces: [Surface] = []
        var inFront: [CGRect] = []
        var live = Set<SurfaceKey>()

        // The Dock is always in front of windows.
        if let dock = dockRect.map({ toLocal($0) }), dock.intersects(CGRect(origin: .zero, size: size)) {
            let s = Surface(key: .dock, minX: max(0, dock.minX), maxX: min(size.width, dock.maxX), y: dock.maxY, blocked: [])
            upsertPile(for: s, maxHeight: dockSnowMax)
            newSurfaces.append(s)
            inFront.append(dock)
            live.insert(.dock)
        }

        for w in windows {
            let r = toLocal(w.frame)
            defer { inFront.append(r) }
            let top = r.maxY
            // Skip windows whose top edge is off this screen (or tucked under the menu bar),
            // and windows that are mostly pushed off the side of the screen.
            guard top > 4, top <= visibleTop + 2 else { continue }
            let minX = max(0, r.minX), maxX = min(size.width, r.maxX)
            guard maxX - minX > 40, maxX - minX >= r.width * 0.35 else { continue }
            // Windows up near the menu bar get a smaller pile that fits the space above them.
            // Ones that touch it (like a maximised browser) get a thin layer resting on their top edge.
            let room = visibleTop - top
            var surfaceY = top
            var maxHeight = windowSnowMax
            if room < 14 {
                surfaceY = visibleTop - 13
                maxHeight = 7
            } else if room < windowSnowMax * 1.7 + 4 {
                maxHeight = max(5, (room - 4) / 1.7)
            }
            let blocked = inFront
                .filter { $0.minX < maxX && $0.maxX > minX && $0.minY < surfaceY + 8 && $0.maxY > surfaceY - 1 }
                .map { $0.minX...$0.maxX }
            let s = Surface(key: .window(w.id), minX: minX, maxX: maxX, y: surfaceY, blocked: blocked)
            upsertPile(for: s, maxHeight: maxHeight)
            newSurfaces.append(s)
            live.insert(s.key)
        }

        // With no Dock on this screen (hidden, or on the side), snow settles along the bottom
        // of the screen instead, and visitors can walk there. When the Dock is showing,
        // everything stays on top of it rather than down among the apps.
        if !live.contains(.dock) {
            let groundBlocked = inFront.filter { $0.minY < groundSnowMax * 1.6 && $0.maxY > 0 }.map { $0.minX...$0.maxX }
            let ground = Surface(key: .ground, minX: 0, maxX: size.width, y: 0, blocked: groundBlocked)
            upsertPile(for: ground, maxHeight: groundSnowMax)
            newSurfaces.append(ground)
            live.insert(.ground)
        }

        for (key, pile) in Array(piles) where !live.contains(key) {
            piles[key] = nil
            if case .window(let id) = key { stash(id, pile) } else { pile.node.removeFromParent() }
        }
        surfaces = newSurfaces
        let bounds = CGRect(origin: .zero, size: size)
        windowRects = (windows.map { $0.frame } + ownWindowFrames).map { toLocal($0) }.filter { $0.intersects(bounds) }

        // When Nook starts, give everything a light dusting so the effect is visible right away.
        if !hasDusted && !piles.isEmpty {
            hasDusted = true
            piles.values.forEach { $0.dust(5) }
        }
    }

    private func upsertPile(for s: Surface, maxHeight: CGFloat) {
        let origin = CGPoint(x: s.minX, y: s.y - 1)
        let width = s.maxX - s.minX
        let pile: SnowPile
        if let existing = piles[s.key] {
            pile = existing
        } else if case .window(let id) = s.key, let saved = stashed.removeValue(forKey: id) {
            pile = saved
            pileLayer.addChild(pile.node)
            piles[s.key] = pile
        } else {
            pile = SnowPile(key: s.key, width: width, origin: origin, maxHeight: maxHeight)
            pileLayer.addChild(pile.node)
            piles[s.key] = pile
        }
        pile.setWidth(width)
        if pile.origin != origin { pile.origin = origin }
        pile.maxHeight = maxHeight

        var hidden = IndexSet()
        let cw = SnowPile.columnWidth
        for b in s.blocked {
            let lo = max(0, Int(floor((b.lowerBound - s.minX) / cw)))
            let hi = min(pile.heights.count, Int(ceil((b.upperBound - s.minX) / cw)))
            if lo < hi { hidden.insert(integersIn: lo..<hi) }
        }
        pile.setHiddenColumns(hidden)
    }

    private func stash(_ id: CGWindowID, _ pile: SnowPile) {
        pile.node.removeFromParent()
        if stashed.count > 200 { stashed.removeAll() }
        stashed[id] = pile
    }
}
