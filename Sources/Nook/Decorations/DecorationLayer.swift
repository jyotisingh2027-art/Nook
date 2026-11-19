import SpriteKit

/// Shows every decoration on one screen. Each screen draws all decorations shifted by its own
/// position, so items (and string lights) can span screens naturally.
final class DecorationLayer: SKNode {
    private let origin: CGPoint
    private var nodes: [UUID: DecorationSprite] = [:]
    private var hasSynced = false

    /// Decorations sit in front of settled snow but behind the nearest falling flakes.
    static let baseZ: CGFloat = 12

    init(screenOrigin: CGPoint) {
        origin = screenOrigin
        super.init()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func sync() {
        let store = DecorationStore.shared
        isHidden = store.isHidden
        let showSelection = DecorationEditorController.shared.isVisible
        var seen = Set<UUID>()
        for (i, d) in store.items.enumerated() {
            seen.insert(d.id)
            let node: DecorationSprite
            if let n = nodes[d.id] { node = n } else {
                node = DecorationSprite()
                nodes[d.id] = node
                addChild(node)
                if hasSynced {   // a new decoration: a little "pop" so you can see where it landed
                    node.setScale(0.4)
                    let pop = SKAction.scale(to: 1, duration: 0.35)
                    pop.timingMode = .easeOut
                    node.run(pop)
                }
            }
            node.zPosition = DecorationLayer.baseZ + CGFloat(i) * 0.01
            node.update(d, origin: origin, selected: showSelection && store.selectedID == d.id)
        }
        hasSynced = true
        for (id, node) in nodes where !seen.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
    }
}

final class DecorationSprite: SKNode {
    private let sprite = SKSpriteNode()
    private let extras = SKNode()
    private var outline: SKShapeNode?
    private var contentKey = ""
    private var outlineKey = ""

    override init() {
        super.init()
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        addChild(sprite)
        addChild(extras)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    func update(_ d: PlacedDecoration, origin: CGPoint, selected: Bool) {
        if d.kind == .lights {
            position = .zero
            let key = "\(d.x),\(d.y),\(d.x2),\(d.y2),\(d.sag),\(d.option("colors")),\(d.option("wire")),\(d.option("bulb")),\(origin)"
            if key != contentKey {
                contentKey = key
                buildLights(d, origin: origin)
            }
            setOutline(selected, key: "L\(key)") { self.lightsOutline(d, origin: origin) }
            return
        }

        position = CGPoint(x: d.x - origin.x, y: d.y - origin.y)
        let r = DecorationRenderer.shared.render(d)
        let opts = d.options.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        let key = "\(d.kind)|\(d.scale)|\(opts)|\(d.seed)"
        if key != contentKey {
            contentKey = key
            sprite.isHidden = false
            sprite.texture = SKTexture(cgImage: r.image)
            sprite.size = r.size
            extras.removeAllChildren()
            for light in r.lights {
                let g = glowNode(color: light.color, size: light.radius * 2)
                g.position = CGPoint(x: light.p.x - r.size.width / 2, y: light.p.y)
                twinkle(g)
                extras.addChild(g)
            }
            for f in r.flames {
                let g = glowNode(color: CGColor(red: 1, green: 0.75, blue: 0.35, alpha: 1), size: 34 * CGFloat(d.scale))
                g.position = CGPoint(x: f.x - r.size.width / 2, y: f.y)
                flicker(g)
                extras.addChild(g)
            }
        }
        setOutline(selected, key: "S\(r.size)") {
            let rect = CGRect(x: -r.size.width / 2 - 6, y: -6, width: r.size.width + 12, height: r.size.height + 12)
            return SKShapeNode(rect: rect, cornerRadius: 10)
        }
    }

    // MARK: - String lights

    private func buildLights(_ d: PlacedDecoration, origin: CGPoint) {
        sprite.isHidden = true
        extras.removeAllChildren()
        let pts = StringLightsGeometry.points(d, count: 60).map { CGPoint(x: $0.x - origin.x, y: $0.y - origin.y) }
        let wire = CGMutablePath()
        wire.addLines(between: pts)
        let wireNode = SKShapeNode(path: wire)
        wireNode.strokeColor = NSColor(cgColor: BulbArt.wireColor(d.option("wire"))) ?? .darkGray
        wireNode.lineWidth = 2
        wireNode.isAntialiased = true
        extras.addChild(wireNode)

        // Bulbs every ~26 points along the wire.
        let colors = lightColors(d.option("colors"))
        var lengthSoFar: CGFloat = 0, next: CGFloat = 8, index = 0
        for (a, b) in zip(pts, pts.dropFirst()) {
            let seg = hypot(b.x - a.x, b.y - a.y)
            while next <= lengthSoFar + seg {
                let t = (next - lengthSoFar) / max(seg, 0.001)
                let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t - 4)
                let c = colors[index % colors.count]
                let shape = d.option("bulb")
                let bulb = SKSpriteNode(texture: BulbArt.texture(shape))
                bulb.size = shape == "star" ? CGSize(width: 13, height: 13) : shape == "classic" ? CGSize(width: 9, height: 14) : CGSize(width: 8, height: 10)
                bulb.color = NSColor(cgColor: c) ?? .white
                bulb.colorBlendFactor = 1
                bulb.position = p
                extras.addChild(bulb)
                let g = glowNode(color: c, size: 30)
                g.position = p
                twinkle(g)
                extras.addChild(g)
                next += 26
                index += 1
            }
            lengthSoFar += seg
        }
    }

    private func lightsOutline(_ d: PlacedDecoration, origin: CGPoint) -> SKShapeNode {
        let path = CGMutablePath()
        for p in [d.point, d.point2] {
            path.addEllipse(in: CGRect(x: p.x - origin.x - 9, y: p.y - origin.y - 9, width: 18, height: 18))
        }
        return SKShapeNode(path: path)
    }

    private func lightColors(_ name: String) -> [CGColor] {
        let hex: [UInt32]
        switch name {
        case "multi": hex = [0xff5a5a, 0xffd34f, 0x5ad1ff, 0x7dff8a, 0xff8ad8]
        case "icy": hex = [0xbfe8ff, 0x8fd0ff, 0xffffff]
        case "candy": hex = [0xff4d5e, 0xffffff]
        case "pink": hex = [0xff8ad8, 0xffc2e6, 0xff5fa8]
        default: hex = [0xffd88a, 0xffe7b0, 0xffc66b]
        }
        return hex.map { rgb($0) }
    }

    // MARK: - Helpers

    private func setOutline(_ show: Bool, key: String, make: () -> SKShapeNode) {
        if !show {
            outline?.removeFromParent(); outline = nil; outlineKey = ""
            return
        }
        guard key != outlineKey || outline == nil else { return }
        outline?.removeFromParent()
        let o = make()
        o.strokeColor = NSColor.controlAccentColor
        o.lineWidth = 2.5
        o.glowWidth = 3
        o.fillColor = .clear
        o.zPosition = 0.5
        addChild(o)
        outline = o
        outlineKey = key
    }

    private func glowNode(color: CGColor, size: CGFloat) -> SKSpriteNode {
        let g = SKSpriteNode(texture: SnowTextures.shared.dot)
        g.size = CGSize(width: size, height: size)
        g.color = NSColor(cgColor: color) ?? .white
        g.colorBlendFactor = 1
        g.blendMode = .add
        g.alpha = 0.8
        g.zPosition = 0.2
        return g
    }

    private func twinkle(_ n: SKNode) {
        let down = SKAction.fadeAlpha(to: CGFloat.random(in: 0.25...0.5), duration: Double.random(in: 0.5...1.4))
        let up = SKAction.fadeAlpha(to: CGFloat.random(in: 0.8...1), duration: Double.random(in: 0.5...1.4))
        down.timingMode = .easeInEaseOut; up.timingMode = .easeInEaseOut
        n.run(.sequence([.wait(forDuration: Double.random(in: 0...1.5)), .repeatForever(.sequence([down, up]))]))
    }

    private func flicker(_ n: SKNode) {
        var steps: [SKAction] = []
        for _ in 0..<6 {
            steps.append(.group([.scale(to: CGFloat.random(in: 0.8...1.15), duration: Double.random(in: 0.08...0.2)),
                                 .fadeAlpha(to: CGFloat.random(in: 0.6...0.95), duration: Double.random(in: 0.08...0.2))]))
        }
        n.run(.repeatForever(.sequence(steps)))
    }
}

/// Shapes for string-light bulbs (drawn white, then tinted).
enum BulbArt {
    private static var cache: [String: SKTexture] = [:]

    static func wireColor(_ name: String) -> CGColor {
        switch name {
        case "white": return rgb(0xe8ecf2)
        case "brown": return rgb(0x5a3a24)
        default: return rgb(0x1f3a26)
        }
    }

    static func path(_ shape: String, in r: CGRect) -> CGPath {
        switch shape {
        case "classic":   // a little cone-shaped bulb
            let p = CGMutablePath()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.15, y: r.minY + r.height * 0.75), control: CGPoint(x: r.minX - r.width * 0.1, y: r.minY + r.height * 0.3))
            p.addLine(to: CGPoint(x: r.maxX - r.width * 0.15, y: r.minY + r.height * 0.75))
            p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.maxX + r.width * 0.1, y: r.minY + r.height * 0.3))
            p.closeSubpath()
            p.addRect(CGRect(x: r.midX - r.width * 0.22, y: r.minY + r.height * 0.75, width: r.width * 0.44, height: r.height * 0.25))
            return p
        case "star":
            let p = CGMutablePath()
            let c = CGPoint(x: r.midX, y: r.midY), R = min(r.width, r.height) / 2
            for i in 0..<10 {
                let a = CGFloat(i) * .pi / 5 + .pi / 2
                let rr = i % 2 == 0 ? R : R * 0.45
                let q = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
            }
            p.closeSubpath()
            return p
        default:
            return CGPath(ellipseIn: r, transform: nil)
        }
    }

    static func texture(_ shape: String) -> SKTexture {
        if let t = cache[shape] { return t }
        let size = 48
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.addPath(path(shape, in: CGRect(x: 4, y: 4, width: size - 8, height: size - 8)))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillPath()
        let t = SKTexture(cgImage: ctx.makeImage()!)
        cache[shape] = t
        return t
    }
}
