import AppKit

struct DecoLight {
    let p: CGPoint      // points from the decoration's bottom-left
    let color: CGColor
    let radius: CGFloat
}

/// A decoration drawn into an image, plus where its twinkling lights and flames are.
struct RenderedDecoration {
    let image: CGImage
    let size: CGSize          // in screen points
    let lights: [DecoLight]
    let flames: [CGPoint]
    fileprivate let alpha: [UInt8]
    fileprivate let pxW: Int
    fileprivate let pxH: Int
    fileprivate let pxPerPt: CGFloat

    /// True if the point (from the bottom-left, in points) is on a painted part, so clicks on
    /// transparent gaps still go through to your apps.
    func isSolid(at p: CGPoint) -> Bool {
        let x = Int(p.x * pxPerPt), y = Int(p.y * pxPerPt)
        guard x >= 0, y >= 0, x < pxW, y < pxH else { return false }
        // Check a small neighbourhood so thin parts are still easy to grab.
        for dy in stride(from: -6, through: 6, by: 3) {
            for dx in stride(from: -6, through: 6, by: 3) {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < pxW, yy < pxH else { continue }
                if alpha[(pxH - 1 - yy) * pxW + xx] > 30 { return true }
            }
        }
        return false
    }
}

final class DecorationRenderer {
    static let shared = DecorationRenderer()
    private var cache: [String: RenderedDecoration] = [:]

    private func key(_ d: PlacedDecoration) -> String {
        let opts = d.options.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return "\(d.kind.rawValue)|\(Int(d.scale * 100))|\(opts)|\(d.seed)"
    }

    func render(_ d: PlacedDecoration) -> RenderedDecoration {
        let k = key(d)
        if let r = cache[k] { return r }
        if cache.count > 150 { cache.removeAll() }
        let r = draw(d)
        cache[k] = r
        return r
    }

    private func baseSize(_ d: PlacedDecoration) -> CGSize {
        switch d.kind {
        case .tree: return CGSize(width: 200, height: 275)
        case .snowman: return CGSize(width: 140, height: 200)
        case .lights: return CGSize(width: 10, height: 10)
        case .wreath: return CGSize(width: 120, height: 120)
        case .bells: return CGSize(width: 100, height: 100)
        case .candle: return CGSize(width: 56, height: 116)
        case .star: return CGSize(width: 90, height: 90)
        case .giftBox: return CGSize(width: 96, height: 96)
        case .snowGlobe: return CGSize(width: 104, height: 120)
        case .ornament: return CGSize(width: 76, height: 104)
        case .lantern: return CGSize(width: 64, height: 116)
        case .cocoaMug: return CGSize(width: 92, height: 92)
        case .gingerbreadHouse: return CGSize(width: 150, height: 140)
        case .mistletoe: return CGSize(width: 96, height: 110)
        case .penguin: return CGSize(width: 86, height: 116)
        case .candyCane: return CGSize(width: 60, height: 140)
        }
    }

    private func draw(_ d: PlacedDecoration) -> RenderedDecoration {
        let base = baseSize(d)
        let scale = CGFloat(d.scale)
        let pxPerPt = 2 * scale
        let pxW = max(1, Int(ceil(base.width * pxPerPt))), pxH = max(1, Int(ceil(base.height * pxPerPt)))
        let ctx = CGContext(data: nil, width: pxW, height: pxH, bitsPerComponent: 8, bytesPerRow: pxW * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: pxPerPt, y: pxPerPt)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        var rng = SeededRandom(seed: d.seed)
        var out = Art(ctx: ctx, W: base.width, H: base.height)

        switch d.kind {
        case .tree: out.tree(d, &rng)
        case .snowman: out.snowman(d)
        case .lights: break
        case .wreath: out.wreath(d, &rng)
        case .bells: out.bells(d)
        case .candle: out.candle(d)
        case .star: out.star(d)
        case .giftBox: out.giftBox(d)
        case .snowGlobe: out.snowGlobe(&rng)
        case .ornament: out.ornament(d)
        case .lantern: out.lantern()
        case .cocoaMug: out.cocoaMug()
        case .gingerbreadHouse: out.gingerbreadHouse()
        case .mistletoe: out.mistletoe()
        case .penguin: out.penguin()
        case .candyCane: out.candyCane()
        }

        let image = ctx.makeImage()!
        var alpha = [UInt8](repeating: 0, count: pxW * pxH)
        if let data = ctx.data {
            let bytes = data.bindMemory(to: UInt8.self, capacity: pxW * pxH * 4)
            for i in 0..<(pxW * pxH) { alpha[i] = bytes[i * 4 + 3] }
        }
        return RenderedDecoration(
            image: image,
            size: CGSize(width: base.width * scale, height: base.height * scale),
            lights: out.lights.map { DecoLight(p: CGPoint(x: $0.p.x * scale, y: $0.p.y * scale), color: $0.color, radius: $0.radius * scale) },
            flames: out.flames.map { CGPoint(x: $0.x * scale, y: $0.y * scale) },
            alpha: alpha, pxW: pxW, pxH: pxH, pxPerPt: pxPerPt)
    }
}

// MARK: - Drawing helpers

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> CGFloat { CGFloat(next() >> 11) / CGFloat(1 << 53) }
    mutating func range(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * unit() }
}

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

private struct Art {
    let ctx: CGContext
    let W: CGFloat
    let H: CGFloat
    var lights: [DecoLight] = []
    var flames: [CGPoint] = []

    init(ctx: CGContext, W: CGFloat, H: CGFloat) { self.ctx = ctx; self.W = W; self.H = H }

    // Basic shapes

    func fill(_ path: CGPath, _ c: CGColor) {
        ctx.addPath(path); ctx.setFillColor(c); ctx.fillPath()
    }

    func fill(_ path: CGPath, gradient: [CGColor], from: CGPoint, to: CGPoint) {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: gradient as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    /// A shaded ball, lit from the upper left.
    func ball(_ c: CGPoint, _ r: CGFloat, light: CGColor, dark: CGColor) {
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [light, dark] as CFArray, locations: [0, 1])!
        let hl = CGPoint(x: c.x - r * 0.35, y: c.y + r * 0.4)
        ctx.drawRadialGradient(g, startCenter: hl, startRadius: 0, endCenter: c, endRadius: r * 1.15, options: [.drawsAfterEndLocation])
        ctx.restoreGState()
    }

    func shine(_ c: CGPoint, _ r: CGFloat) {
        ctx.setFillColor(rgb(0xffffff, 0.75))
        ctx.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y + r * 0.2, width: r * 0.42, height: r * 0.28))
    }

    func glow(_ p: CGPoint, _ r: CGFloat, _ c: CGColor) {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [c, c.copy(alpha: c.alpha * 0.3)!, c.copy(alpha: 0)!] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: r, options: [])
    }

    func stroke(_ path: CGPath, _ c: CGColor, _ w: CGFloat) {
        ctx.addPath(path); ctx.setStrokeColor(c); ctx.setLineWidth(w); ctx.strokePath()
    }

    func line(_ a: CGPoint, _ b: CGPoint, _ c: CGColor, _ w: CGFloat) {
        let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); stroke(p, c, w)
    }

    func starPath(_ c: CGPoint, _ r: CGFloat, inner: CGFloat = 0.45) -> CGPath {
        let p = CGMutablePath()
        for i in 0..<10 {
            let a = CGFloat(i) * .pi / 5 + .pi / 2
            let rr = i % 2 == 0 ? r : r * inner
            let q = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }

    func goldStar(_ c: CGPoint, _ r: CGFloat) {
        fill(starPath(c, r), gradient: [rgb(0xfff2b0), rgb(0xf5b52e), rgb(0xc77d12)], from: CGPoint(x: c.x - r, y: c.y + r), to: CGPoint(x: c.x + r, y: c.y - r))
        stroke(starPath(c, r), rgb(0xa86410, 0.6), max(0.8, r * 0.05))
    }

    func bow(_ c: CGPoint, _ s: CGFloat, _ color: CGColor, _ dark: CGColor) {
        for side in [-1.0, 1.0] as [CGFloat] {
            let loop = CGMutablePath()
            loop.move(to: c)
            loop.addCurve(to: c, control1: CGPoint(x: c.x + side * s * 1.4, y: c.y + s * 0.9), control2: CGPoint(x: c.x + side * s * 1.4, y: c.y - s * 0.7))
            fill(loop, gradient: [color, dark], from: CGPoint(x: c.x, y: c.y + s), to: CGPoint(x: c.x, y: c.y - s))
            let tail = CGMutablePath()
            tail.move(to: CGPoint(x: c.x - side * s * 0.1, y: c.y))
            tail.addLine(to: CGPoint(x: c.x + side * s * 0.7, y: c.y - s * 1.3))
            tail.addLine(to: CGPoint(x: c.x + side * s * 0.35, y: c.y - s * 1.2))
            tail.closeSubpath()
            fill(tail, dark)
        }
        ctx.setFillColor(dark)
        ctx.fillEllipse(in: CGRect(x: c.x - s * 0.28, y: c.y - s * 0.28, width: s * 0.56, height: s * 0.56))
    }

    func holly(_ c: CGPoint, _ s: CGFloat) {
        for a in [-0.5, 0.5, 2.6] as [CGFloat] {
            let leaf = CGMutablePath()
            let tip = CGPoint(x: c.x + cos(a) * s * 1.6, y: c.y + sin(a) * s * 0.9)
            leaf.move(to: c)
            leaf.addQuadCurve(to: tip, control: CGPoint(x: (c.x + tip.x) / 2, y: (c.y + tip.y) / 2 + s * 0.6))
            leaf.addQuadCurve(to: c, control: CGPoint(x: (c.x + tip.x) / 2, y: (c.y + tip.y) / 2 - s * 0.6))
            fill(leaf, gradient: [rgb(0x3f9a4c), rgb(0x1e5a2a)], from: c, to: tip)
        }
        for (dx, dy) in [(-0.25, 0.15), (0.25, 0.2), (0, -0.2)] as [(CGFloat, CGFloat)] {
            ball(CGPoint(x: c.x + dx * s, y: c.y + dy * s), s * 0.32, light: rgb(0xff6b6b), dark: rgb(0xa8121c))
        }
    }

    func flame(_ p: CGPoint, _ s: CGFloat) {
        let f = CGMutablePath()
        f.move(to: CGPoint(x: p.x, y: p.y + s * 1.6))
        f.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s * 0.2), control: CGPoint(x: p.x + s * 1.1, y: p.y + s * 0.2))
        f.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s * 1.6), control: CGPoint(x: p.x - s * 1.1, y: p.y + s * 0.2))
        fill(f, gradient: [rgb(0xfff6c8), rgb(0xffc23d), rgb(0xff7a1f)], from: CGPoint(x: p.x, y: p.y), to: CGPoint(x: p.x, y: p.y + s * 1.6))
    }

    /// Light, mid and dark shades for coloured metal/fabric parts.
    static let shades: [String: [UInt32]] = [
        "gold": [0xfff2b0, 0xf5b52e, 0xc77d12], "white": [0xffffff, 0xe8edf6, 0xb8c2d6], "pink": [0xffd6e6, 0xff7fb0, 0xc94680],
        "red": [0xff8a8f, 0xe63946, 0x9e1422], "silver": [0xf6f8fb, 0xc3c9d6, 0x868fa3], "blue": [0xd2e6ff, 0x5b8def, 0x2b56c4],
        "green": [0xa8e6b8, 0x3fae6a, 0x1f7a44], "black": [0x4a4d5a, 0x24262e, 0x101116]
    ]

    static func shade(_ name: String) -> [CGColor] { (shades[name] ?? shades["gold"]!).map { rgb($0) } }

    func heartPath(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addCurve(to: CGPoint(x: c.x, y: c.y + r * 0.55), control1: CGPoint(x: c.x - r * 1.6, y: c.y - r * 0.1), control2: CGPoint(x: c.x - r * 0.7, y: c.y + r * 1.25))
        p.addCurve(to: CGPoint(x: c.x, y: c.y - r), control1: CGPoint(x: c.x + r * 0.7, y: c.y + r * 1.25), control2: CGPoint(x: c.x + r * 1.6, y: c.y - r * 0.1))
        p.closeSubpath()
        return p
    }

    func coloredStar(_ c: CGPoint, _ r: CGFloat, _ colour: String) {
        let sh = Art.shade(colour)
        fill(starPath(c, r), gradient: sh, from: CGPoint(x: c.x - r, y: c.y + r), to: CGPoint(x: c.x + r, y: c.y - r))
        stroke(starPath(c, r), sh[2].copy(alpha: 0.6)!, max(0.8, r * 0.05))
    }

    static let palette: [String: [UInt32]] = [
        "red": [0xe63946, 0xb5172a], "gold": [0xf7c548, 0xd89a1e], "frost": [0x9fd3ff, 0xe8f3ff, 0xbfc9d9],
        "mixed": [0xe63946, 0xf7c548, 0x4f86f7, 0xd9dde8, 0x3fae6a], "green": [0x3fae6a, 0x1f7a44], "blue": [0x4f86f7, 0x2b56c4],
        "pink": [0xff7fb0, 0xffb3d1, 0xd94c8a]
    ]

    static func lightColors(_ name: String) -> [UInt32] {
        switch name {
        case "multi": return [0xff5a5a, 0xffd34f, 0x5ad1ff, 0x7dff8a, 0xff8ad8]
        case "icy": return [0xbfe8ff, 0x8fd0ff, 0xffffff]
        case "candy": return [0xff4d5e, 0xffffff]
        case "pink": return [0xff8ad8, 0xffc2e6, 0xff5fa8]
        default: return [0xffd88a, 0xffe7b0, 0xffc66b]
        }
    }

    // MARK: Tree

    mutating func tree(_ d: PlacedDecoration, _ rng: inout SeededRandom) {
        let cx = W / 2
        // Snow mound and trunk
        ctx.setFillColor(rgb(0xc9d6f2)); ctx.fillEllipse(in: CGRect(x: cx - W * 0.36, y: 0, width: W * 0.72, height: H * 0.07))
        ctx.setFillColor(rgb(0xf4f7ff)); ctx.fillEllipse(in: CGRect(x: cx - W * 0.33, y: H * 0.012, width: W * 0.66, height: H * 0.06))
        fill(CGPath(rect: CGRect(x: cx - W * 0.055, y: H * 0.03, width: W * 0.11, height: H * 0.12), transform: nil),
             gradient: [rgb(0x7a4a2a), rgb(0x4a2a16)], from: CGPoint(x: cx - W * 0.05, y: 0), to: CGPoint(x: cx + W * 0.05, y: 0))

        let treeShades: [String: [UInt32]] = [
            "green": [0x4c9a5a, 0x2b6b3c, 0x174a28], "white": [0xf7f9fd, 0xdbe3f0, 0xa9b6cc], "blue": [0x6fa7b5, 0x3e7486, 0x1f4a5a],
            "silver": [0xe3e7ee, 0xaeb6c6, 0x7a8398], "pink": [0xffc2d8, 0xf08bb0, 0xbf557f], "dark": [0x2f5a3c, 0x1a3d27, 0x0d2618]
        ]
        let tc = treeShades[d.option("treeColor")] ?? treeShades["green"]!
        let body = tc.map { rgb($0) }
        let needleLight = rgb(tc[0], 0.5).copy(alpha: 0.5)!
        let needleDark = rgb(tc[2], 0.5)
        struct Tier { let bottom: CGFloat; let top: CGFloat; let half: CGFloat }
        var tiers: [Tier] = []
        let n = 4
        for i in 0..<n {
            let f = CGFloat(i)
            let bottom = H * 0.1 + f * H * 0.165
            tiers.append(Tier(bottom: bottom, top: bottom + H * 0.3, half: W * 0.47 * (1 - f * 0.2)))
        }

        for t in tiers {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx, y: t.top))
            path.addQuadCurve(to: CGPoint(x: cx - t.half, y: t.bottom), control: CGPoint(x: cx - t.half * 0.35, y: t.bottom + (t.top - t.bottom) * 0.35))
            let zig = 8
            var tips: [CGPoint] = []
            for z in 1...zig {
                let x = cx - t.half + 2 * t.half * CGFloat(z) / CGFloat(zig)
                let mid = cx - t.half + 2 * t.half * (CGFloat(z) - 0.5) / CGFloat(zig)
                path.addLine(to: CGPoint(x: mid, y: t.bottom + H * 0.028))
                path.addLine(to: CGPoint(x: x, y: t.bottom))
                tips.append(CGPoint(x: x, y: t.bottom))
            }
            path.addQuadCurve(to: CGPoint(x: cx, y: t.top), control: CGPoint(x: cx + t.half * 0.35, y: t.bottom + (t.top - t.bottom) * 0.35))
            path.closeSubpath()
            fill(path, gradient: body, from: CGPoint(x: cx - t.half, y: t.top), to: CGPoint(x: cx + t.half, y: t.bottom))
            // Needle texture
            ctx.saveGState(); ctx.addPath(path); ctx.clip()
            for _ in 0..<Int(t.half * 1.2) {
                let y = rng.range(t.bottom, t.top)
                let span = t.half * (1 - (y - t.bottom) / (t.top - t.bottom))
                let x = cx + rng.range(-span, span)
                line(CGPoint(x: x, y: y), CGPoint(x: x + rng.range(-5, 5), y: y - rng.range(3, 7)), rng.unit() < 0.5 ? needleLight : needleDark, 1)
            }
            ctx.restoreGState()
            // Snow on the branch tips
            for tip in [CGPoint(x: cx - t.half, y: t.bottom)] + tips.dropLast() {
                let inward: CGFloat = tip.x < cx ? 1 : -1
                let r = CGRect(x: tip.x + inward * W * 0.012 - W * 0.022, y: tip.y + H * 0.008, width: W * 0.044, height: H * 0.016)
                ctx.setFillColor(rgb(0xb9c7e8, 0.9)); ctx.fillEllipse(in: r.offsetBy(dx: 0, dy: -0.8))
                ctx.setFillColor(rgb(0xf6f8ff)); ctx.fillEllipse(in: r)
            }
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: cx, y: t.top))
            cap.addQuadCurve(to: CGPoint(x: cx - t.half * 0.28, y: t.top - (t.top - t.bottom) * 0.28), control: CGPoint(x: cx - t.half * 0.1, y: t.top - (t.top - t.bottom) * 0.1))
            cap.addQuadCurve(to: CGPoint(x: cx + t.half * 0.18, y: t.top - (t.top - t.bottom) * 0.22), control: CGPoint(x: cx, y: t.top - (t.top - t.bottom) * 0.4))
            cap.closeSubpath()
            fill(cap, rgb(0xf4f7ff, 0.9))
        }

        func inside(_ t: Tier, _ fy: CGFloat, _ fx: CGFloat) -> CGPoint {
            let y = t.bottom + (t.top - t.bottom) * fy
            let span = t.half * (1 - fy) * 0.82
            return CGPoint(x: cx + span * fx, y: y)
        }

        // Garland
        let garland = d.option("garland")
        if garland != "none" {
            let c1 = garland == "gold" ? rgb(0xf7c548) : garland == "red" ? rgb(0xd62f3d) : rgb(0xe3e7f0)
            let c2 = garland == "gold" ? rgb(0xfff0b3) : garland == "red" ? rgb(0xff9aa0) : rgb(0xffffff)
            for t in tiers.dropLast() {
                let a = inside(t, 0.32, -1), b = inside(t, 0.5, 1)
                let p = CGMutablePath(); p.move(to: a)
                p.addQuadCurve(to: b, control: CGPoint(x: cx, y: (a.y + b.y) / 2 - H * 0.06))
                stroke(p, c1, W * 0.018)
                ctx.saveGState(); ctx.setLineDash(phase: 0, lengths: [2, 4]); stroke(p, c2, W * 0.012); ctx.restoreGState()
            }
        }

        // Candy canes and gingerbread
        if d.option("candyCanes") == "on" {
            for (i, t) in tiers.dropLast().enumerated() {
                let p = inside(t, 0.2, i % 2 == 0 ? 0.55 : -0.5)
                let hook = CGMutablePath()
                hook.move(to: CGPoint(x: p.x, y: p.y - H * 0.035))
                hook.addLine(to: CGPoint(x: p.x, y: p.y + H * 0.02))
                hook.addQuadCurve(to: CGPoint(x: p.x + W * 0.035, y: p.y + H * 0.015), control: CGPoint(x: p.x + W * 0.018, y: p.y + H * 0.05))
                stroke(hook, rgb(0xffffff), W * 0.016)
                ctx.saveGState(); ctx.setLineDash(phase: 0, lengths: [2.5, 2.5]); stroke(hook, rgb(0xe63946), W * 0.016); ctx.restoreGState()
            }
        }
        if d.option("gingerbread") == "on" {
            for (i, t) in tiers.dropLast().enumerated() {
                let p = inside(t, 0.45, i % 2 == 0 ? -0.45 : 0.45)
                gingerbreadMan(p, H * 0.035)
            }
        }

        // Baubles
        let bauble = d.option("baubles")
        if bauble != "none", let colors = Art.palette[bauble] {
            for t in tiers {
                for _ in 0..<3 {
                    let p = inside(t, rng.range(0.08, 0.5), rng.range(-1, 1))
                    let r = W * rng.range(0.03, 0.042)
                    let c = colors[Int(rng.next() % UInt64(colors.count))]
                    ctx.setFillColor(rgb(0xb8b8b8)); ctx.fill(CGRect(x: p.x - r * 0.3, y: p.y + r * 0.85, width: r * 0.6, height: r * 0.4))
                    ball(p, r, light: rgb(c), dark: darken(rgb(c)))
                    shine(p, r)
                }
            }
        }

        // Lights
        let lightSet = d.option("lights")
        if lightSet != "none" {
            let colors = Art.lightColors(lightSet == "multi" ? "multi" : "warm")
            var k = 0
            for t in tiers {
                for j in 0..<6 {
                    let fx = -0.95 + 1.9 * CGFloat(j) / 5
                    let fy = 0.22 + 0.12 * (1 - fx * fx)
                    let p = inside(t, fy, fx)
                    let c = rgb(colors[k % colors.count])
                    ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
                    lights.append(DecoLight(p: p, color: c, radius: W * 0.06))
                    k += 1
                }
            }
        }

        // Topper
        let apex = CGPoint(x: cx, y: tiers.last!.top)
        let tcol = d.option("topperColor")
        let glowColour = Art.shade(tcol)[1]
        switch d.option("topper") {
        case "star":
            let c = CGPoint(x: cx, y: apex.y + H * 0.03)
            coloredStar(c, W * 0.085, tcol)
            lights.append(DecoLight(p: c, color: glowColour, radius: W * 0.2))
        case "heart":
            let c = CGPoint(x: cx, y: apex.y + H * 0.03)
            let sh = Art.shade(tcol)
            fill(heartPath(c, W * 0.065), gradient: sh, from: CGPoint(x: c.x - W * 0.07, y: c.y + W * 0.07), to: CGPoint(x: c.x + W * 0.07, y: c.y - W * 0.07))
            shine(CGPoint(x: c.x - W * 0.02, y: c.y), W * 0.04)
            lights.append(DecoLight(p: c, color: glowColour, radius: W * 0.18))
        case "snowflake":
            let c = CGPoint(x: cx, y: apex.y + H * 0.035)
            let col = Art.shade(tcol)[tcol == "white" || tcol == "silver" ? 0 : 1]
            for i in 0..<6 {
                let a = CGFloat(i) * .pi / 3 + .pi / 2
                let tip = CGPoint(x: c.x + cos(a) * W * 0.075, y: c.y + sin(a) * W * 0.075)
                line(c, tip, col, W * 0.015)
                let m = CGPoint(x: c.x + cos(a) * W * 0.045, y: c.y + sin(a) * W * 0.045)
                for s in [-0.6, 0.6] as [CGFloat] {
                    line(m, CGPoint(x: m.x + cos(a + s) * W * 0.025, y: m.y + sin(a + s) * W * 0.025), col, W * 0.011)
                }
            }
            lights.append(DecoLight(p: c, color: glowColour, radius: W * 0.16))
        case "bow":
            let sh = Art.shade(tcol == "gold" ? "red" : tcol)
            bow(CGPoint(x: cx, y: apex.y + H * 0.005), W * 0.07, sh[1], sh[2])
        default: break
        }
    }

    func darken(_ c: CGColor) -> CGColor {
        let comps = c.components ?? [0, 0, 0, 1]
        return CGColor(red: comps[0] * 0.55, green: comps[1] * 0.55, blue: comps[2] * 0.55, alpha: 1)
    }

    func gingerbreadMan(_ c: CGPoint, _ s: CGFloat) {
        let body = rgb(0xb5733c)
        ctx.setFillColor(body)
        ctx.fillEllipse(in: CGRect(x: c.x - s * 0.5, y: c.y + s * 0.5, width: s, height: s))            // head
        ctx.fill(CGRect(x: c.x - s * 0.4, y: c.y - s * 0.6, width: s * 0.8, height: s * 1.2))          // body
        line(CGPoint(x: c.x - s * 0.3, y: c.y + s * 0.3), CGPoint(x: c.x - s, y: c.y), body, s * 0.38) // arms
        line(CGPoint(x: c.x + s * 0.3, y: c.y + s * 0.3), CGPoint(x: c.x + s, y: c.y), body, s * 0.38)
        line(CGPoint(x: c.x - s * 0.2, y: c.y - s * 0.5), CGPoint(x: c.x - s * 0.55, y: c.y - s * 1.2), body, s * 0.4)
        line(CGPoint(x: c.x + s * 0.2, y: c.y - s * 0.5), CGPoint(x: c.x + s * 0.55, y: c.y - s * 1.2), body, s * 0.4)
        ctx.setFillColor(rgb(0xffffff))
        for y in [0.1, -0.25] as [CGFloat] { ctx.fillEllipse(in: CGRect(x: c.x - s * 0.08, y: c.y + y * s, width: s * 0.16, height: s * 0.16)) }
        ctx.setFillColor(rgb(0x3a1d0c))
        ctx.fillEllipse(in: CGRect(x: c.x - s * 0.25, y: c.y + s * 1.0, width: s * 0.12, height: s * 0.12))
        ctx.fillEllipse(in: CGRect(x: c.x + s * 0.13, y: c.y + s * 1.0, width: s * 0.12, height: s * 0.12))
    }

    // MARK: Snowman

    mutating func snowman(_ d: PlacedDecoration) {
        let cx = W / 2
        let snowShades: [String: [UInt32]] = ["white": [0xffffff, 0xb9c7e8], "icy": [0xf0f8ff, 0x93bde8], "cream": [0xfffaf0, 0xd9cbb3]]
        let sc = snowShades[d.option("snow")] ?? snowShades["white"]!
        let snowLight = rgb(sc[0]), snowDark = rgb(sc[1])

        // Body shape: ball centres and sizes.
        var balls: [(CGPoint, CGFloat)]
        switch d.option("body") {
        case "chubby": balls = [(CGPoint(x: cx, y: 54), 52), (CGPoint(x: cx, y: 134), 32)]
        case "tall": balls = [(CGPoint(x: cx, y: 38), 34), (CGPoint(x: cx, y: 96), 27), (CGPoint(x: cx, y: 142), 21)]
        default: balls = [(CGPoint(x: cx, y: 46), 44), (CGPoint(x: cx, y: 108), 32), (CGPoint(x: cx, y: 152), 24)]
        }
        let (head, hr) = balls.last!
        let torso = balls.count == 3 ? balls[1] : balls[0]
        let k = hr / 24   // face and hat scale with the head

        ctx.setFillColor(rgb(0x8796c4, 0.35)); ctx.fillEllipse(in: CGRect(x: cx - balls[0].1 * 1.2, y: 0, width: balls[0].1 * 2.4, height: 14))
        // Stick arms (behind the body)
        let wood = rgb(0x6b4226)
        let armY = torso.0.y + torso.1 * 0.15, armX = torso.1 * 0.7
        let lHand = CGPoint(x: cx - armX - 40, y: armY + 26), rHand = CGPoint(x: cx + armX + 40, y: armY + 28)
        line(CGPoint(x: cx - armX, y: armY), lHand, wood, 3.2)
        line(CGPoint(x: lHand.x + 12, y: lHand.y - 7), CGPoint(x: lHand.x + 6, y: lHand.y + 8), wood, 2.4)
        line(CGPoint(x: cx + armX, y: armY), rHand, wood, 3.2)
        line(CGPoint(x: rHand.x - 12, y: rHand.y - 8), CGPoint(x: rHand.x - 2, y: rHand.y - 16), wood, 2.4)
        for (c, r) in balls { ball(c, r, light: snowLight, dark: snowDark) }

        // Outfit
        let coal = rgb(0x22252e)
        let buttonYs: [CGFloat] = balls.count == 3
            ? [torso.0.y + torso.1 * 0.25, torso.0.y - torso.1 * 0.25, balls[0].0.y + balls[0].1 * 0.35, balls[0].0.y]
            : [torso.0.y + torso.1 * 0.45, torso.0.y + torso.1 * 0.1, torso.0.y - torso.1 * 0.25]
        switch d.option("outfit") {
        case "buttons", "mittens":
            for y in buttonYs { ball(CGPoint(x: cx, y: y), 3.4, light: rgb(0x555a66), dark: coal) }
            if d.option("outfit") == "mittens" {
                for h in [lHand, rHand] {
                    ball(h, 7, light: rgb(0xff6b6b), dark: rgb(0xa8121c))
                    ctx.setFillColor(rgb(0xffffff)); ctx.fill(CGRect(x: h.x - 6, y: h.y - 9, width: 12, height: 4))
                }
            }
        case "bowtie":
            bow(CGPoint(x: cx, y: head.y - hr - 2), 8 * k, rgb(0xe63946), rgb(0x9e1422))
            for y in buttonYs.dropFirst() { ball(CGPoint(x: cx, y: y), 3.4, light: rgb(0x555a66), dark: coal) }
        default: break
        }

        // Face
        let eyeY = head.y + 6 * k, ex = 8 * k
        switch d.option("face") {
        case "sleepy":
            for x in [cx - ex, cx + ex] {
                let p = CGMutablePath(); p.move(to: CGPoint(x: x - 4 * k, y: eyeY)); p.addQuadCurve(to: CGPoint(x: x + 4 * k, y: eyeY), control: CGPoint(x: x, y: eyeY - 4 * k))
                stroke(p, coal, 1.8)
            }
            ctx.setFillColor(coal); ctx.fillEllipse(in: CGRect(x: cx - 2.5 * k, y: head.y - 14 * k, width: 5 * k, height: 5 * k))
        case "surprised":
            for x in [cx - ex, cx + ex] { ball(CGPoint(x: x, y: eyeY), 3.6 * k, light: rgb(0x555a66), dark: coal) }
            ctx.setStrokeColor(coal); ctx.setLineWidth(2); ctx.strokeEllipse(in: CGRect(x: cx - 4 * k, y: head.y - 18 * k, width: 8 * k, height: 9 * k))
        case "cheeky":
            ball(CGPoint(x: cx - ex, y: eyeY), 3 * k, light: rgb(0x555a66), dark: coal)
            let wink = CGMutablePath(); wink.move(to: CGPoint(x: cx + ex - 4 * k, y: eyeY)); wink.addQuadCurve(to: CGPoint(x: cx + ex + 4 * k, y: eyeY), control: CGPoint(x: cx + ex, y: eyeY + 4 * k))
            stroke(wink, coal, 1.8)
            glow(CGPoint(x: cx - 15 * k, y: head.y - 6 * k), 8 * k, rgb(0xff8fa3, 0.6)); glow(CGPoint(x: cx + 15 * k, y: head.y - 6 * k), 8 * k, rgb(0xff8fa3, 0.6))
            smile(cx, head.y, k, coal)
        default:
            for x in [cx - ex, cx + ex] { ball(CGPoint(x: x, y: eyeY), 3 * k, light: rgb(0x555a66), dark: coal) }
            smile(cx, head.y, k, coal)
        }
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: cx - 1, y: head.y + 1 * k)); nose.addLine(to: CGPoint(x: cx + 20 * k, y: head.y - 4 * k)); nose.addLine(to: CGPoint(x: cx - 1, y: head.y - 5 * k)); nose.closeSubpath()
        fill(nose, gradient: [rgb(0xffa040), rgb(0xe0621c)], from: CGPoint(x: cx, y: head.y + 1), to: CGPoint(x: cx, y: head.y - 6))

        // Scarf
        let scarf = d.option("scarf")
        if scarf != "none" {
            let main: CGColor = scarf == "stripes" ? rgb(0x2f6fd6) : Art.shade(scarf)[1]
            let dark = darken(main)
            let ny = head.y - hr - 4
            let band = CGPath(roundedRect: CGRect(x: cx - hr * 1.12, y: ny, width: hr * 2.24, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)
            let tail = CGPath(roundedRect: CGRect(x: cx + hr * 0.3, y: ny - 28, width: 13, height: 34), cornerWidth: 4, cornerHeight: 4, transform: nil)
            for p in [tail, band] {
                fill(p, gradient: [main, dark], from: CGPoint(x: cx, y: ny + 12), to: CGPoint(x: cx, y: ny - 28))
                if scarf == "stripes" {
                    ctx.saveGState(); ctx.addPath(p); ctx.clip()
                    ctx.setFillColor(rgb(0xffffff, 0.9))
                    var x = cx - 40
                    while x < cx + 40 { ctx.fill(CGRect(x: x, y: ny - 40, width: 4, height: 60)); x += 9 }
                    ctx.restoreGState()
                }
            }
            for x in stride(from: cx + hr * 0.3 + 1, through: cx + hr * 0.3 + 12, by: 3) { line(CGPoint(x: x, y: ny - 28), CGPoint(x: x, y: ny - 33), dark, 1.4) }
        }

        // Hat
        let hc = Art.shade(d.option("hatColor"))
        let top = head.y + hr - 8 * k
        switch d.option("hat") {
        case "topHat":
            fill(CGPath(ellipseIn: CGRect(x: cx - 26 * k, y: top, width: 52 * k, height: 9 * k), transform: nil), rgb(0x1d1f27))
            fill(CGPath(rect: CGRect(x: cx - 16 * k, y: top + 4 * k, width: 32 * k, height: 26 * k), transform: nil), gradient: [rgb(0x3a3d4a), rgb(0x15161c)], from: CGPoint(x: cx - 16, y: 0), to: CGPoint(x: cx + 16, y: 0))
            fill(CGPath(rect: CGRect(x: cx - 16 * k, y: top + 7 * k, width: 32 * k, height: 5 * k), transform: nil), hc[1])
            holly(CGPoint(x: cx + 10 * k, y: top + 11 * k), 4 * k)
        case "beanie":
            let dome = CGMutablePath()
            dome.addArc(center: CGPoint(x: cx, y: top + 4 * k), radius: 23 * k, startAngle: 0, endAngle: .pi, clockwise: false)
            dome.closeSubpath()
            fill(dome, gradient: [hc[1], hc[2]], from: CGPoint(x: cx, y: top + 27 * k), to: CGPoint(x: cx, y: top + 4 * k))
            fill(CGPath(roundedRect: CGRect(x: cx - 25 * k, y: top, width: 50 * k, height: 9 * k), cornerWidth: 4, cornerHeight: 4, transform: nil), rgb(0xf4f7ff))
            ball(CGPoint(x: cx, y: top + 30 * k), 7 * k, light: rgb(0xffffff), dark: rgb(0xc9d3ee))
        case "santa":
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: cx - 23 * k, y: top + 6 * k))
            cone.addQuadCurve(to: CGPoint(x: cx + 30 * k, y: top + 18 * k), control: CGPoint(x: cx - 2 * k, y: top + 45 * k))
            cone.addLine(to: CGPoint(x: cx + 22 * k, y: top + 6 * k))
            cone.closeSubpath()
            fill(cone, gradient: [hc[1], hc[2]], from: CGPoint(x: cx, y: top + 40 * k), to: CGPoint(x: cx, y: top + 6 * k))
            fill(CGPath(roundedRect: CGRect(x: cx - 26 * k, y: top, width: 52 * k, height: 10 * k), cornerWidth: 5, cornerHeight: 5, transform: nil), rgb(0xf8faff))
            ball(CGPoint(x: cx + 30 * k, y: top + 16 * k), 6 * k, light: rgb(0xffffff), dark: rgb(0xc9d3ee))
        default: break
        }
    }

    func smile(_ cx: CGFloat, _ headY: CGFloat, _ k: CGFloat, _ coal: CGColor) {
        for i in 0..<5 {
            let t = CGFloat(i) / 4
            let x = cx - 9 * k + 18 * k * t, y = headY - 11 * k - 4 * k * sin(.pi * t)
            ctx.setFillColor(coal); ctx.fillEllipse(in: CGRect(x: x - 1.6 * k, y: y - 1.6 * k, width: 3.2 * k, height: 3.2 * k))
        }
    }

    // MARK: Single items

    mutating func wreath(_ d: PlacedDecoration, _ rng: inout SeededRandom) {
        let c = CGPoint(x: W / 2, y: H * 0.55), r = W * 0.33
        let greenery = d.option("greenery")
        let greens: [UInt32] = greenery == "frosted" ? [0x9fc7b0, 0xd8eee2, 0x6fa58a, 0xf2fbf6]
            : greenery == "gold" ? [0xd9a63a, 0xf5d27a, 0xa8781e, 0xffe6a0] : [0x2f7a40, 0x3c9a52, 0x1f5a2e, 0x4aa95e]
        for i in 0..<110 {
            let a = CGFloat(i) / 110 * 2 * .pi + rng.range(-0.05, 0.05)
            let rr = r + rng.range(-W * 0.07, W * 0.07)
            let p = CGPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: a + .pi / 2 + rng.range(-0.6, 0.6))
            ctx.setFillColor(rgb(greens[i % greens.count]))
            ctx.fillEllipse(in: CGRect(x: -W * 0.07, y: -W * 0.025, width: W * 0.14, height: W * 0.05))
            ctx.restoreGState()
        }
        for i in 0..<9 {
            let a = CGFloat(i) / 9 * 2 * .pi + 0.3
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            for k in 0..<3 {
                ball(CGPoint(x: p.x + CGFloat(k - 1) * 4, y: p.y + CGFloat(k % 2) * 4), 3.2, light: rgb(0xff6b6b), dark: rgb(0xa8121c))
            }
        }
        // Light dusting of snow on top
        for i in 0..<14 {
            let a = .pi * 0.25 + CGFloat(i) / 14 * .pi * 0.5
            let p = CGPoint(x: c.x + cos(a) * (r + W * 0.04), y: c.y + sin(a) * (r + W * 0.04))
            ctx.setFillColor(rgb(0xf4f7ff, 0.9)); ctx.fillEllipse(in: CGRect(x: p.x - 6, y: p.y - 2, width: 12, height: 5))
        }
        if d.option("bow") != "none" {
            let sh = Art.shade(d.option("bow"))
            bow(CGPoint(x: c.x, y: c.y - r - W * 0.02), W * 0.11, sh[1], sh[2])
        }
        if d.option("lights") == "on" {
            let colors = Art.lightColors("warm")
            for i in 0..<12 {
                let a = CGFloat(i) / 12 * 2 * .pi
                let p = CGPoint(x: c.x + cos(a) * (r - W * 0.02), y: c.y + sin(a) * (r - W * 0.02))
                lights.append(DecoLight(p: p, color: rgb(colors[i % colors.count]), radius: W * 0.07))
            }
        }
    }

    func bells(_ d: PlacedDecoration) {
        let bellShade = Art.shade(d.option("color"))
        func bell(_ c: CGPoint, _ angle: CGFloat) {
            ctx.saveGState()
            ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: angle)
            let s = W * 0.2
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -s * 0.3, y: s * 1.1))
            p.addQuadCurve(to: CGPoint(x: -s * 0.7, y: -s * 0.2), control: CGPoint(x: -s * 0.75, y: s * 0.7))
            p.addQuadCurve(to: CGPoint(x: -s * 1.05, y: -s * 0.75), control: CGPoint(x: -s * 0.75, y: -s * 0.6))
            p.addLine(to: CGPoint(x: s * 1.05, y: -s * 0.75))
            p.addQuadCurve(to: CGPoint(x: s * 0.7, y: -s * 0.2), control: CGPoint(x: s * 0.75, y: -s * 0.6))
            p.addQuadCurve(to: CGPoint(x: s * 0.3, y: s * 1.1), control: CGPoint(x: s * 0.75, y: s * 0.7))
            p.closeSubpath()
            fill(p, gradient: bellShade, from: CGPoint(x: -s, y: s), to: CGPoint(x: s, y: -s))
            ctx.setFillColor(darken(bellShade[2])); ctx.fillEllipse(in: CGRect(x: -s * 0.25, y: -s * 1.05, width: s * 0.5, height: s * 0.45))
            ctx.setFillColor(rgb(0xffffff, 0.6)); ctx.fillEllipse(in: CGRect(x: -s * 0.55, y: s * 0.1, width: s * 0.18, height: s * 0.6))
            ctx.restoreGState()
        }
        bell(CGPoint(x: W * 0.36, y: H * 0.36), 0.3)
        bell(CGPoint(x: W * 0.64, y: H * 0.36), -0.3)
        line(CGPoint(x: W * 0.4, y: H * 0.55), CGPoint(x: W * 0.5, y: H * 0.76), rgb(0xc8202f), 3)
        line(CGPoint(x: W * 0.6, y: H * 0.55), CGPoint(x: W * 0.5, y: H * 0.76), rgb(0xc8202f), 3)
        holly(CGPoint(x: W * 0.5, y: H * 0.74), W * 0.09)
        bow(CGPoint(x: W * 0.5, y: H * 0.8), W * 0.1, rgb(0xe63946), rgb(0x9e1422))
    }

    mutating func candle(_ d: PlacedDecoration) {
        let body = CGPath(roundedRect: CGRect(x: W * 0.24, y: H * 0.06, width: W * 0.52, height: H * 0.58), cornerWidth: 3, cornerHeight: 3, transform: nil)
        let candleShades: [String: [UInt32]] = ["red": [0xff5c63, 0xd1222f, 0x8f0f1a], "white": [0xffffff, 0xece6da, 0xc4bba8],
                                                "gold": [0xffe9a0, 0xe8b440, 0xa87a1a], "green": [0x7fd99a, 0x2f9e5a, 0x1a5e34]]
        fill(body, gradient: (candleShades[d.option("color")] ?? candleShades["red"]!).map { rgb($0) }, from: CGPoint(x: W * 0.24, y: 0), to: CGPoint(x: W * 0.76, y: 0))
        let drip = CGMutablePath()
        drip.move(to: CGPoint(x: W * 0.24, y: H * 0.64))
        drip.addLine(to: CGPoint(x: W * 0.24, y: H * 0.55))
        drip.addQuadCurve(to: CGPoint(x: W * 0.38, y: H * 0.56), control: CGPoint(x: W * 0.31, y: H * 0.5))
        drip.addLine(to: CGPoint(x: W * 0.42, y: H * 0.44))
        drip.addQuadCurve(to: CGPoint(x: W * 0.5, y: H * 0.45), control: CGPoint(x: W * 0.46, y: H * 0.39))
        drip.addLine(to: CGPoint(x: W * 0.55, y: H * 0.57))
        drip.addQuadCurve(to: CGPoint(x: W * 0.76, y: H * 0.55), control: CGPoint(x: W * 0.68, y: H * 0.5))
        drip.addLine(to: CGPoint(x: W * 0.76, y: H * 0.64))
        drip.closeSubpath()
        fill(drip, rgb(0xff8a8f, 0.75))
        line(CGPoint(x: W * 0.5, y: H * 0.64), CGPoint(x: W * 0.5, y: H * 0.69), rgb(0x2a2a2a), 1.5)
        let f = CGPoint(x: W * 0.5, y: H * 0.69)
        flame(f, W * 0.08)
        flames.append(CGPoint(x: f.x, y: f.y + W * 0.08))
        fill(CGPath(ellipseIn: CGRect(x: W * 0.06, y: 0, width: W * 0.88, height: H * 0.09), transform: nil), gradient: [rgb(0xf2d27a), rgb(0xb3842a)], from: CGPoint(x: 0, y: H * 0.09), to: .zero)
        holly(CGPoint(x: W * 0.24, y: H * 0.08), W * 0.12)
    }

    mutating func star(_ d: PlacedDecoration) {
        let c = CGPoint(x: W / 2, y: H / 2)
        coloredStar(c, W * 0.4, d.option("color"))
        lights.append(DecoLight(p: c, color: Art.shade(d.option("color"))[1], radius: W * 0.55))
    }

    func giftBox(_ d: PlacedDecoration) {
        let boxShade = Art.shades[d.option("color")] ?? Art.shades["red"]!
        let main: [UInt32] = [boxShade[1], boxShade[2]]
        let rs = Art.shades[d.option("ribbon")] ?? Art.shades["gold"]!
        let ribbon: [UInt32] = [rs[0], rs[1]]
        let box = CGPath(rect: CGRect(x: W * 0.1, y: 0, width: W * 0.8, height: H * 0.6), transform: nil)
        fill(box, gradient: [rgb(main[0]), rgb(main[1])], from: CGPoint(x: W * 0.1, y: H * 0.6), to: CGPoint(x: W * 0.9, y: 0))
        let lid = CGPath(roundedRect: CGRect(x: W * 0.05, y: H * 0.58, width: W * 0.9, height: H * 0.15), cornerWidth: 3, cornerHeight: 3, transform: nil)
        fill(lid, gradient: [rgb(main[0]), rgb(main[1])], from: CGPoint(x: 0, y: H * 0.73), to: CGPoint(x: 0, y: H * 0.58))
        fill(CGPath(rect: CGRect(x: W * 0.43, y: 0, width: W * 0.14, height: H * 0.73), transform: nil), gradient: [rgb(ribbon[0]), rgb(ribbon[1])], from: CGPoint(x: W * 0.43, y: 0), to: CGPoint(x: W * 0.57, y: 0))
        fill(CGPath(rect: CGRect(x: W * 0.1, y: H * 0.27, width: W * 0.8, height: H * 0.1), transform: nil), rgb(ribbon[1], 0.9))
        ctx.setFillColor(rgb(0xf4f7ff, 0.95)); ctx.fillEllipse(in: CGRect(x: W * 0.06, y: H * 0.69, width: W * 0.4, height: H * 0.07))
        bow(CGPoint(x: W * 0.5, y: H * 0.8), W * 0.2, rgb(ribbon[0]), rgb(ribbon[1]))
    }

    func snowGlobe(_ rng: inout SeededRandom) {
        let c = CGPoint(x: W / 2, y: H * 0.56), r = W * 0.4
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
        ctx.setFillColor(rgb(0x8fb4ff, 0.28)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        glow(CGPoint(x: c.x, y: c.y - r * 0.2), r * 1.2, rgb(0xffe6b0, 0.35))
        fill(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 1.15, width: 2 * r, height: r * 0.8), transform: nil), rgb(0xf4f7ff))
        // A tiny tree inside
        for i in 0..<3 {
            let f = CGFloat(i)
            let p = CGMutablePath()
            let b = c.y - r * 0.5 + f * r * 0.28, half = r * (0.42 - f * 0.11)
            p.move(to: CGPoint(x: c.x - half, y: b)); p.addLine(to: CGPoint(x: c.x, y: b + r * 0.42)); p.addLine(to: CGPoint(x: c.x + half, y: b)); p.closeSubpath()
            fill(p, gradient: [rgb(0x3c9a52), rgb(0x1f5a2e)], from: CGPoint(x: c.x - half, y: b), to: CGPoint(x: c.x + half, y: b))
        }
        goldStar(CGPoint(x: c.x, y: c.y + r * 0.36), r * 0.1)
        for _ in 0..<30 {
            let p = CGPoint(x: c.x + rng.range(-r, r), y: c.y + rng.range(-r * 0.4, r))
            ctx.setFillColor(rgb(0xffffff, rng.range(0.6, 1)))
            let s = rng.range(1, 2.6)
            ctx.fillEllipse(in: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s))
        }
        ctx.restoreGState()
        ctx.setStrokeColor(rgb(0xffffff, 0.55)); ctx.setLineWidth(1.5)
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        let hl = CGMutablePath()
        hl.addArc(center: c, radius: r * 0.82, startAngle: .pi * 0.6, endAngle: .pi * 0.95, clockwise: false)
        stroke(hl, rgb(0xffffff, 0.7), 3)
        let base = CGMutablePath()
        base.move(to: CGPoint(x: W * 0.16, y: 0)); base.addLine(to: CGPoint(x: W * 0.84, y: 0))
        base.addLine(to: CGPoint(x: W * 0.74, y: H * 0.22)); base.addLine(to: CGPoint(x: W * 0.26, y: H * 0.22)); base.closeSubpath()
        fill(base, gradient: [rgb(0x9a5a32), rgb(0x5a2f16)], from: CGPoint(x: W * 0.2, y: H * 0.22), to: CGPoint(x: W * 0.8, y: 0))
        fill(CGPath(rect: CGRect(x: W * 0.22, y: H * 0.15, width: W * 0.56, height: H * 0.04), transform: nil), rgb(0xf2c75a))
    }

    func ornament(_ d: PlacedDecoration) {
        let color = d.option("color")
        let os = Art.shades[color] ?? Art.shades["red"]!
        let cs: [UInt32] = [os[0], os[2]]
        line(CGPoint(x: W / 2, y: H), CGPoint(x: W / 2, y: H * 0.8), rgb(0xc8202f), 1.6)
        fill(CGPath(roundedRect: CGRect(x: W * 0.4, y: H * 0.74, width: W * 0.2, height: H * 0.08), cornerWidth: 2, cornerHeight: 2, transform: nil),
             gradient: [rgb(0xfff0a8), rgb(0xb3842a)], from: CGPoint(x: W * 0.4, y: 0), to: CGPoint(x: W * 0.6, y: 0))
        let c = CGPoint(x: W / 2, y: H * 0.4), r = W * 0.44
        ball(c, r, light: rgb(cs[0]), dark: rgb(cs[1]))
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); ctx.clip()
        let trim = rgb(color == "gold" ? 0xffffff : 0xf7d56b, 0.9)
        switch d.option("pattern") {
        case "stripes":
            for dy in [-r * 0.45, 0, r * 0.45] { ctx.setFillColor(trim); ctx.fill(CGRect(x: c.x - r, y: c.y + dy - 2.5, width: 2 * r, height: 5)) }
        case "dots":
            for (dx, dy) in [(-0.5, 0.3), (0.1, 0.5), (0.5, 0.1), (-0.2, -0.2), (0.35, -0.5), (-0.6, -0.4)] as [(CGFloat, CGFloat)] {
                ctx.setFillColor(trim); ctx.fillEllipse(in: CGRect(x: c.x + dx * r - 3.5, y: c.y + dy * r - 3.5, width: 7, height: 7))
            }
        case "plain": break
        default:
            let band = CGMutablePath()
            band.move(to: CGPoint(x: c.x - r, y: c.y))
            for i in 0...8 { band.addLine(to: CGPoint(x: c.x - r + CGFloat(i) * r / 4, y: c.y + (i % 2 == 0 ? -5 : 5))) }
            stroke(band, trim, 3)
        }
        ctx.restoreGState()
        shine(c, r)
    }

    // MARK: Extras

    mutating func lantern() {
        let frame = rgb(0x24242c)
        let glass = CGRect(x: W * 0.2, y: H * 0.14, width: W * 0.6, height: H * 0.52)
        fill(CGPath(rect: glass, transform: nil), gradient: [rgb(0xfff2c4), rgb(0xffb04a)], from: CGPoint(x: glass.midX, y: glass.maxY), to: CGPoint(x: glass.midX, y: glass.minY))
        fill(CGPath(rect: CGRect(x: glass.midX - W * 0.07, y: glass.minY, width: W * 0.14, height: glass.height * 0.4), transform: nil), rgb(0xfff8e8))
        flame(CGPoint(x: glass.midX, y: glass.minY + glass.height * 0.42), W * 0.06)
        flames.append(CGPoint(x: glass.midX, y: glass.minY + glass.height * 0.5))
        lights.append(DecoLight(p: CGPoint(x: glass.midX, y: glass.midY), color: rgb(0xffb347), radius: W * 0.9))
        for x in [glass.minX, glass.midX, glass.maxX] { line(CGPoint(x: x, y: glass.minY), CGPoint(x: x, y: glass.maxY), frame, 2.4) }
        fill(CGPath(rect: CGRect(x: W * 0.12, y: 0, width: W * 0.76, height: H * 0.14), transform: nil), frame)
        let cap = CGMutablePath()
        cap.move(to: CGPoint(x: W * 0.08, y: glass.maxY)); cap.addLine(to: CGPoint(x: W * 0.5, y: H * 0.84)); cap.addLine(to: CGPoint(x: W * 0.92, y: glass.maxY)); cap.closeSubpath()
        fill(cap, frame)
        ctx.setStrokeColor(frame); ctx.setLineWidth(2.4)
        ctx.strokeEllipse(in: CGRect(x: W * 0.38, y: H * 0.84, width: W * 0.24, height: H * 0.13))
        ctx.setFillColor(rgb(0xf4f7ff)); ctx.fillEllipse(in: CGRect(x: W * 0.12, y: glass.maxY + 2, width: W * 0.76, height: H * 0.07))
    }

    mutating func cocoaMug() {
        let body = CGPath(roundedRect: CGRect(x: W * 0.12, y: 0, width: W * 0.62, height: H * 0.55), cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.setStrokeColor(rgb(0xb5172a)); ctx.setLineWidth(W * 0.07)
        ctx.strokeEllipse(in: CGRect(x: W * 0.62, y: H * 0.14, width: W * 0.26, height: H * 0.26))
        fill(body, gradient: [rgb(0xff5c63), rgb(0xb5172a)], from: CGPoint(x: W * 0.12, y: H * 0.5), to: CGPoint(x: W * 0.74, y: 0))
        // White snowflake on the mug
        let c = CGPoint(x: W * 0.43, y: H * 0.26)
        for i in 0..<6 {
            let a = CGFloat(i) * .pi / 3
            line(c, CGPoint(x: c.x + cos(a) * W * 0.1, y: c.y + sin(a) * W * 0.1), rgb(0xffffff), 2)
        }
        // Cream and marshmallows
        for (x, y, r) in [(0.22, 0.58, 0.11), (0.36, 0.62, 0.13), (0.52, 0.6, 0.12), (0.64, 0.57, 0.09), (0.44, 0.7, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
            ball(CGPoint(x: W * x, y: H * y), W * r, light: rgb(0xffffff), dark: rgb(0xe6dccd))
        }
        for (x, y, col) in [(0.3, 0.72, 0xffc2d6), (0.58, 0.7, 0xffffff)] as [(CGFloat, CGFloat, UInt32)] {
            fill(CGPath(roundedRect: CGRect(x: W * x, y: H * y, width: W * 0.1, height: W * 0.08), cornerWidth: 3, cornerHeight: 3, transform: nil), rgb(col))
        }
        for x in [0.34, 0.5] as [CGFloat] {
            let s = CGMutablePath()
            s.move(to: CGPoint(x: W * x, y: H * 0.8))
            s.addCurve(to: CGPoint(x: W * x, y: H * 0.98), control1: CGPoint(x: W * (x + 0.08), y: H * 0.86), control2: CGPoint(x: W * (x - 0.08), y: H * 0.92))
            stroke(s, rgb(0xffffff, 0.55), 2.5)
        }
    }

    mutating func gingerbreadHouse() {
        let wall = CGRect(x: W * 0.14, y: 0, width: W * 0.72, height: H * 0.5)
        fill(CGPath(rect: wall, transform: nil), gradient: [rgb(0xc9844a), rgb(0x8f5226)], from: CGPoint(x: wall.minX, y: wall.maxY), to: CGPoint(x: wall.maxX, y: 0))
        let roof = CGMutablePath()
        roof.move(to: CGPoint(x: W * 0.04, y: H * 0.46)); roof.addLine(to: CGPoint(x: W * 0.5, y: H * 0.92)); roof.addLine(to: CGPoint(x: W * 0.96, y: H * 0.46)); roof.closeSubpath()
        fill(roof, gradient: [rgb(0xa8642f), rgb(0x6e3a18)], from: CGPoint(x: 0, y: H * 0.9), to: CGPoint(x: 0, y: H * 0.46))
        // Snowy icing on the roof edges
        let icing = CGMutablePath()
        icing.move(to: CGPoint(x: W * 0.04, y: H * 0.46)); icing.addLine(to: CGPoint(x: W * 0.5, y: H * 0.92)); icing.addLine(to: CGPoint(x: W * 0.96, y: H * 0.46))
        stroke(icing, rgb(0xffffff), W * 0.05)
        for i in 0..<10 {
            let t = CGFloat(i) / 9
            let x = W * 0.06 + t * W * 0.88
            ctx.setFillColor(rgb(0xffffff)); ctx.fillEllipse(in: CGRect(x: x - 5, y: H * 0.42, width: 10, height: 9))
        }
        for (x, col) in [(0.3, 0xe63946), (0.5, 0x3fae6a), (0.7, 0xf7c548)] as [(CGFloat, UInt32)] {
            ball(CGPoint(x: W * x, y: H * 0.66), W * 0.035, light: rgb(col), dark: darken(rgb(col)))
        }
        let door = CGPath(roundedRect: CGRect(x: W * 0.42, y: 0, width: W * 0.16, height: H * 0.28), cornerWidth: 8, cornerHeight: 8, transform: nil)
        fill(door, rgb(0x5a2f16))
        for x in [0.2, 0.66] as [CGFloat] {
            let win = CGRect(x: W * x, y: H * 0.2, width: W * 0.14, height: H * 0.14)
            glow(CGPoint(x: win.midX, y: win.midY), W * 0.16, rgb(0xffb347, 0.5))
            fill(CGPath(rect: win, transform: nil), gradient: [rgb(0xfff0b8), rgb(0xffa040)], from: CGPoint(x: 0, y: win.maxY), to: CGPoint(x: 0, y: win.minY))
            ctx.setStrokeColor(rgb(0xffffff)); ctx.setLineWidth(2); ctx.stroke(win)
            line(CGPoint(x: win.midX, y: win.minY), CGPoint(x: win.midX, y: win.maxY), rgb(0xffffff), 1.5)
        }
        for i in 0..<6 {
            let x = W * 0.16 + CGFloat(i) * W * 0.13
            ball(CGPoint(x: x, y: H * 0.03), W * 0.03, light: rgb(i % 2 == 0 ? 0xff6b8a : 0x7dd3a0), dark: rgb(i % 2 == 0 ? 0xc22a4a : 0x2f8a55))
        }
    }

    func mistletoe() {
        line(CGPoint(x: W / 2, y: H), CGPoint(x: W / 2, y: H * 0.66), rgb(0xc8202f), 2.4)
        let c = CGPoint(x: W / 2, y: H * 0.52)
        for (i, a) in stride(from: -2.6, through: -0.5, by: 0.35).enumerated() {
            let tip = CGPoint(x: c.x + cos(CGFloat(a)) * W * 0.48, y: c.y + sin(CGFloat(a)) * W * 0.42)
            let leaf = CGMutablePath()
            let nx = -(tip.y - c.y) * 0.28, ny = (tip.x - c.x) * 0.28
            leaf.move(to: c)
            leaf.addQuadCurve(to: tip, control: CGPoint(x: (c.x + tip.x) / 2 + nx, y: (c.y + tip.y) / 2 + ny))
            leaf.addQuadCurve(to: c, control: CGPoint(x: (c.x + tip.x) / 2 - nx, y: (c.y + tip.y) / 2 - ny))
            fill(leaf, gradient: [rgb(i % 2 == 0 ? 0x7fbf5a : 0x5a9a3c), rgb(0x2f5a1f)], from: c, to: tip)
        }
        for (dx, dy) in [(-6, 4), (5, 6), (0, -2), (-2, 10), (8, -1)] as [(CGFloat, CGFloat)] {
            ball(CGPoint(x: c.x + dx, y: c.y + dy), 5, light: rgb(0xffffff), dark: rgb(0xd8e0c8))
        }
        bow(CGPoint(x: W / 2, y: H * 0.66), W * 0.13, rgb(0xe63946), rgb(0x9e1422))
    }

    func penguin() {
        let cx = W / 2
        fill(CGPath(ellipseIn: CGRect(x: cx - W * 0.4, y: H * 0.04, width: W * 0.8, height: H * 0.78), transform: nil),
             gradient: [rgb(0x3a3f52), rgb(0x161820)], from: CGPoint(x: cx - W * 0.4, y: H * 0.8), to: CGPoint(x: cx + W * 0.4, y: 0))
        fill(CGPath(ellipseIn: CGRect(x: cx - W * 0.27, y: H * 0.07, width: W * 0.54, height: H * 0.56), transform: nil),
             gradient: [rgb(0xffffff), rgb(0xd5dcef)], from: CGPoint(x: cx, y: H * 0.6), to: CGPoint(x: cx, y: H * 0.07))
        for x in [cx - W * 0.13, cx + W * 0.13] {
            ctx.setFillColor(rgb(0xffffff)); ctx.fillEllipse(in: CGRect(x: x - 6, y: H * 0.64, width: 12, height: 12))
            ctx.setFillColor(rgb(0x111111)); ctx.fillEllipse(in: CGRect(x: x - 3, y: H * 0.655, width: 6, height: 7))
        }
        let beak = CGMutablePath()
        beak.move(to: CGPoint(x: cx - 7, y: H * 0.6)); beak.addLine(to: CGPoint(x: cx + 7, y: H * 0.6)); beak.addLine(to: CGPoint(x: cx, y: H * 0.53)); beak.closeSubpath()
        fill(beak, rgb(0xff9a2e))
        for x in [cx - W * 0.17, cx + W * 0.17] {
            ctx.setFillColor(rgb(0xff9a2e)); ctx.fillEllipse(in: CGRect(x: x - 10, y: 0, width: 20, height: 9))
        }
        fill(CGPath(roundedRect: CGRect(x: cx - W * 0.33, y: H * 0.47, width: W * 0.66, height: H * 0.08), cornerWidth: 4, cornerHeight: 4, transform: nil), rgb(0xd62f3d))
        fill(CGPath(roundedRect: CGRect(x: cx + W * 0.1, y: H * 0.27, width: W * 0.13, height: H * 0.22), cornerWidth: 3, cornerHeight: 3, transform: nil), rgb(0xb5172a))
        let dome = CGMutablePath()
        dome.addArc(center: CGPoint(x: cx, y: H * 0.78), radius: W * 0.28, startAngle: 0, endAngle: .pi, clockwise: false)
        dome.closeSubpath()
        fill(dome, gradient: [rgb(0x5b8def), rgb(0x2b56c4)], from: CGPoint(x: cx, y: H), to: CGPoint(x: cx, y: H * 0.78))
        ball(CGPoint(x: cx, y: H * 0.95), W * 0.07, light: rgb(0xffffff), dark: rgb(0xc9d3ee))
    }

    func candyCane() {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: W * 0.62, y: H * 0.1))
        p.addLine(to: CGPoint(x: W * 0.62, y: H * 0.7))
        p.addQuadCurve(to: CGPoint(x: W * 0.2, y: H * 0.7), control: CGPoint(x: W * 0.42, y: H * 0.95))
        stroke(p, rgb(0xd8dbe6), W * 0.27)
        stroke(p, rgb(0xffffff), W * 0.23)
        ctx.saveGState(); ctx.setLineDash(phase: 0, lengths: [W * 0.12, W * 0.12])
        stroke(p, rgb(0xe63946), W * 0.23)
        ctx.restoreGState()
        bow(CGPoint(x: W * 0.62, y: H * 0.56), W * 0.2, rgb(0x3fae6a), rgb(0x1f7a44))
    }
}
