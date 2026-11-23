import AppKit
import SpriteKit

/// Everything that falls in Catch the Gift. Gifts are the important ones: let one land (or get
/// stolen) and you lose a life. The treats are bonus points, and the golden star is rare and worth a lot.
enum CatchItemKind: CaseIterable {
    case gift, cookie, candyCane, ornament, stocking, goldenStar

    var points: Int {
        switch self {
        case .stocking: return 2
        case .goldenStar: return 5
        default: return 1
        }
    }

    /// Only gifts cost a life when missed.
    var costsLife: Bool { self == .gift }

    /// Size on screen.
    var size: CGSize {
        switch self {
        case .gift: return CGSize(width: 56, height: 58)
        case .cookie: return CGSize(width: 50, height: 56)
        case .candyCane: return CGSize(width: 38, height: 60)
        case .ornament: return CGSize(width: 46, height: 54)
        case .stocking: return CGSize(width: 46, height: 58)
        case .goldenStar: return CGSize(width: 58, height: 56)
        }
    }

    /// The colour of its glow.
    var glow: NSColor {
        switch self {
        case .goldenStar: return NSColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)
        case .cookie: return NSColor(red: 1, green: 0.75, blue: 0.45, alpha: 1)
        case .candyCane, .stocking: return NSColor(red: 1, green: 0.55, blue: 0.6, alpha: 1)
        default: return NSColor(red: 1, green: 0.9, blue: 0.6, alpha: 1)
        }
    }

    /// Picks what falls next: mostly gifts, plenty of treats, the odd golden star.
    static func random() -> CatchItemKind {
        let r = Double.random(in: 0...1)
        switch r {
        case ..<0.42: return .gift
        case ..<0.60: return .cookie
        case ..<0.75: return .candyCane
        case ..<0.88: return .ornament
        case ..<0.96: return .stocking
        default: return .goldenStar
        }
    }
}

enum CatchItemArt {
    private static var cache: [String: SKTexture] = [:]

    static let giftColours: [(UInt32, UInt32)] = [   // box, ribbon
        (0xff2d55, 0xffd84d), (0x1fc95a, 0xffe46b), (0x2f80ff, 0xffffff), (0xa855f7, 0xffd84d),
        (0xffb81a, 0xff2d55), (0xff4fa3, 0xffffff), (0x10c7c0, 0xff4f6d)
    ]
    static let ornamentColours: [UInt32] = [0xff2d55, 0x2f80ff, 0xa855f7, 0x1fc95a, 0xffb81a]

    static func texture(_ kind: CatchItemKind, variant: Int) -> SKTexture {
        let key = "\(kind)|\(variant)"
        if let t = cache[key] { return t }
        let size = kind.size
        let s: CGFloat = 3
        let ctx = CGContext(data: nil, width: Int(size.width * s), height: Int(size.height * s), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: s, y: s)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch kind {
        case .gift: drawGift(ctx, size, giftColours[variant % giftColours.count])
        case .cookie: drawCookie(ctx, size)
        case .candyCane: drawCandyCane(ctx, size)
        case .ornament: drawOrnament(ctx, size, ornamentColours[variant % ornamentColours.count])
        case .stocking: drawStocking(ctx, size)
        case .goldenStar: drawStar(ctx, size)
        }
        let t = SKTexture(cgImage: ctx.makeImage()!)
        cache[key] = t
        return t
    }

    /// A little four-pointed twinkle for the sparkles around each item.
    static let sparkle: SKTexture = {
        let s: CGFloat = 3, w: CGFloat = 16
        let ctx = CGContext(data: nil, width: Int(w * s), height: Int(w * s), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: s, y: s)
        let c = CGPoint(x: w / 2, y: w / 2)
        ctx.setShadow(offset: .zero, blur: 2.5, color: CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 1))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.move(to: CGPoint(x: c.x, y: c.y + 7))
        ctx.addQuadCurve(to: CGPoint(x: c.x + 7, y: c.y), control: c)
        ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y - 7), control: c)
        ctx.addQuadCurve(to: CGPoint(x: c.x - 7, y: c.y), control: c)
        ctx.addQuadCurve(to: CGPoint(x: c.x, y: c.y + 7), control: c)
        ctx.fillPath()
        return SKTexture(cgImage: ctx.makeImage()!)
    }()

    // MARK: - Drawing helpers

    private static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    private static func shade(_ hex: UInt32, _ f: CGFloat) -> CGColor {
        let r = CGFloat((hex >> 16) & 0xff) / 255, g = CGFloat((hex >> 8) & 0xff) / 255, b = CGFloat(hex & 0xff) / 255
        return CGColor(red: min(1, r * f), green: min(1, g * f), blue: min(1, b * f), alpha: 1)
    }

    private static func fillGradient(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor, rect: CGRect) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
        ctx.restoreGState()
    }

    private static func oval(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) {
        ctx.setFillColor(col)
        ctx.fillEllipse(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
    }

    // MARK: - Items

    private static func drawGift(_ ctx: CGContext, _ size: CGSize, _ colours: (UInt32, UInt32)) {
        let (box, ribbon) = colours
        let body = CGRect(x: 6, y: 3, width: size.width - 12, height: size.height - 24)
        let lid = CGRect(x: 3, y: body.maxY - 3, width: size.width - 6, height: 10)
        let bodyPath = CGPath(roundedRect: body, cornerWidth: 4, cornerHeight: 4, transform: nil)
        let lidPath = CGPath(roundedRect: lid, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 2, color: rgb(0x000000, 0.35))
        fillGradient(ctx, bodyPath, top: shade(box, 1.05), bottom: shade(box, 0.78), rect: body)
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        fillGradient(ctx, lidPath, top: shade(box, 1.18), bottom: shade(box, 0.95), rect: lid)
        // Ribbon.
        ctx.setFillColor(rgb(ribbon))
        ctx.fill(CGRect(x: size.width / 2 - 4, y: body.minY, width: 8, height: lid.maxY - body.minY))
        ctx.fill(CGRect(x: body.minX, y: body.midY - 3.5, width: body.width, height: 7))
        ctx.setFillColor(rgb(0xffffff, 0.35))
        ctx.fill(CGRect(x: size.width / 2 - 4, y: body.minY, width: 2.5, height: lid.maxY - body.minY))
        // Bow.
        let knot = CGPoint(x: size.width / 2, y: lid.maxY + 2)
        for side in [-1.0, 1.0] as [CGFloat] {
            ctx.saveGState()
            ctx.translateBy(x: knot.x + side * 7, y: knot.y + 3.5)
            ctx.rotate(by: side * 0.45)
            ctx.setFillColor(rgb(ribbon))
            ctx.fillEllipse(in: CGRect(x: -7.5, y: -4.5, width: 15, height: 9))
            ctx.setFillColor(shade(ribbon, 0.75))
            ctx.fillEllipse(in: CGRect(x: -3.5, y: -2, width: 7, height: 4))
            ctx.restoreGState()
        }
        oval(ctx, knot, 7, 6.5, shade(ribbon, 0.9))
        // Shine.
        ctx.setFillColor(rgb(0xffffff, 0.45))
        ctx.fill(CGRect(x: body.minX + 3, y: body.minY + 4, width: 3, height: body.height - 8))
        oval(ctx, CGPoint(x: lid.minX + 6, y: lid.midY + 1), 5, 3, rgb(0xffffff, 0.7))
    }

    private static func drawCookie(_ ctx: CGContext, _ size: CGSize) {
        let dough = rgb(0xc9772f), edge = rgb(0x9a5622)
        let cx = size.width / 2
        let shape = CGMutablePath()
        shape.addEllipse(in: CGRect(x: cx - 10, y: 34, width: 20, height: 20))                        // head
        shape.addPath(CGPath(roundedRect: CGRect(x: cx - 10.5, y: 15, width: 21, height: 23), cornerWidth: 8, cornerHeight: 8, transform: nil))
        shape.addPath(CGPath(roundedRect: CGRect(x: 3, y: 27, width: size.width - 6, height: 10), cornerWidth: 5, cornerHeight: 5, transform: nil)) // arms
        for side in [-1.0, 1.0] as [CGFloat] {                                                          // legs
            let leg = CGPath(roundedRect: CGRect(x: -5.5, y: -14, width: 11, height: 20), cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
            var t = CGAffineTransform(translationX: cx + side * 6.5, y: 15).rotated(by: side * 0.35)
            if let p = leg.copy(using: &t) { shape.addPath(p) }
        }
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 2, color: rgb(0x000000, 0.35))
        ctx.addPath(shape); ctx.setFillColor(edge); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        var inset = CGAffineTransform(translationX: cx, y: 30).scaledBy(x: 0.93, y: 0.93).translatedBy(x: -cx, y: -30)
        if let inner = shape.copy(using: &inset) {
            fillGradient(ctx, inner, top: rgb(0xe8954a), bottom: dough, rect: CGRect(origin: .zero, size: size))
        }
        // Icing squiggles on the arms and legs.
        ctx.setStrokeColor(rgb(0xffffff)); ctx.setLineWidth(1.6)
        for x in [7.0, size.width - 7] as [CGFloat] {
            ctx.move(to: CGPoint(x: x - 1.5, y: 29)); ctx.addLine(to: CGPoint(x: x + 1.5, y: 32)); ctx.addLine(to: CGPoint(x: x - 1.5, y: 35))
        }
        for side in [-1.0, 1.0] as [CGFloat] {
            let x = cx + side * 9.5
            ctx.move(to: CGPoint(x: x - 3, y: 5)); ctx.addLine(to: CGPoint(x: x, y: 7.5)); ctx.addLine(to: CGPoint(x: x + 3, y: 5))
        }
        ctx.strokePath()
        // Face and candy buttons.
        oval(ctx, CGPoint(x: cx - 3.5, y: 46), 2.6, 2.8, rgb(0x2b1a10))
        oval(ctx, CGPoint(x: cx + 3.5, y: 46), 2.6, 2.8, rgb(0x2b1a10))
        ctx.setStrokeColor(rgb(0xffffff)); ctx.setLineWidth(1.5)
        ctx.addArc(center: CGPoint(x: cx, y: 42.5), radius: 3.6, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        ctx.strokePath()
        oval(ctx, CGPoint(x: cx - 6.5, y: 42), 3, 2, rgb(0xff8a8a, 0.8))
        oval(ctx, CGPoint(x: cx + 6.5, y: 42), 3, 2, rgb(0xff8a8a, 0.8))
        oval(ctx, CGPoint(x: cx, y: 30), 4.4, 4.4, rgb(0xff2d55))
        oval(ctx, CGPoint(x: cx, y: 22.5), 4.4, 4.4, rgb(0x1fc95a))
        oval(ctx, CGPoint(x: cx - 0.8, y: 30.8), 1.4, 1.2, rgb(0xffffff, 0.8))
        oval(ctx, CGPoint(x: cx - 0.8, y: 23.3), 1.4, 1.2, rgb(0xffffff, 0.8))
    }

    private static func drawCandyCane(_ ctx: CGContext, _ size: CGSize) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 13, y: 5))
        path.addLine(to: CGPoint(x: 13, y: 40))
        path.addArc(center: CGPoint(x: 22, y: 42), radius: 9, startAngle: .pi * 0.95, endAngle: .pi * 0.05, clockwise: true)
        path.addLine(to: CGPoint(x: 31, y: 37))
        let stroke = path.copy(strokingWithWidth: 9.5, lineCap: .round, lineJoin: .round, miterLimit: 10)
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 2, color: rgb(0x000000, 0.35))
        ctx.addPath(stroke); ctx.setFillColor(rgb(0xffffff)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.saveGState()
        ctx.addPath(stroke); ctx.clip()
        ctx.setFillColor(rgb(0xff1f45))
        var y: CGFloat = -20
        while y < size.height + 20 {
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: size.width, y: y + 14))
            ctx.addLine(to: CGPoint(x: size.width, y: y + 19)); ctx.addLine(to: CGPoint(x: 0, y: y + 5)); ctx.closePath()
            ctx.fillPath()
            y += 10
        }
        // A glossy highlight down one side.
        ctx.setStrokeColor(rgb(0xffffff, 0.55)); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: 10.8, y: 8)); ctx.addLine(to: CGPoint(x: 10.8, y: 38)); ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawOrnament(_ ctx: CGContext, _ size: CGSize, _ colour: UInt32) {
        let c = CGPoint(x: size.width / 2, y: 22)
        let r: CGFloat = 19
        // Cap and loop.
        ctx.setStrokeColor(rgb(0xd4a017)); ctx.setLineWidth(1.8)
        ctx.addArc(center: CGPoint(x: c.x, y: c.y + r + 8), radius: 3.5, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
        let cap = CGRect(x: c.x - 5.5, y: c.y + r - 2, width: 11, height: 7)
        fillGradient(ctx, CGPath(roundedRect: cap, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil),
                     top: rgb(0xffe27a), bottom: rgb(0xc8941a), rect: cap)
        // Glossy ball.
        let ball = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2), transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 2, color: rgb(0x000000, 0.35))
        ctx.addPath(ball); ctx.setFillColor(rgb(colour)); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(ball); ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [shade(colour, 1.45), rgb(colour), shade(colour, 0.6)] as CFArray, locations: [0, 0.45, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: c.x - 6, y: c.y + 7), startRadius: 0, endCenter: c, endRadius: r * 1.1, options: [.drawsAfterEndLocation])
        // A gold band with dots.
        ctx.setFillColor(rgb(0xffd84d)); ctx.fill(CGRect(x: c.x - r, y: c.y - 2.5, width: r * 2, height: 5))
        for k in stride(from: -15.0, through: 15.0, by: 6) { oval(ctx, CGPoint(x: c.x + CGFloat(k), y: c.y - 7), 2.4, 2.4, rgb(0xffffff, 0.85)) }
        ctx.restoreGState()
        oval(ctx, CGPoint(x: c.x - 7, y: c.y + 9), 7, 4.5, rgb(0xffffff, 0.75))
    }

    private static func drawStocking(_ ctx: CGContext, _ size: CGSize) {
        let sock = CGMutablePath()
        sock.move(to: CGPoint(x: 12, y: 46))
        sock.addLine(to: CGPoint(x: 12, y: 22))
        sock.addCurve(to: CGPoint(x: 6, y: 9), control1: CGPoint(x: 12, y: 16), control2: CGPoint(x: 6, y: 15))
        sock.addCurve(to: CGPoint(x: 16, y: 2), control1: CGPoint(x: 6, y: 4), control2: CGPoint(x: 11, y: 2))
        sock.addLine(to: CGPoint(x: 30, y: 4))
        sock.addCurve(to: CGPoint(x: 36, y: 14), control1: CGPoint(x: 35, y: 5), control2: CGPoint(x: 37, y: 9))
        sock.addLine(to: CGPoint(x: 34, y: 46))
        sock.closeSubpath()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 2, color: rgb(0x000000, 0.35))
        ctx.addPath(sock); ctx.setFillColor(rgb(0xe8102e)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        fillGradient(ctx, sock, top: rgb(0xff3a55), bottom: rgb(0xc90c28), rect: CGRect(origin: .zero, size: size))
        // Green toe and heel.
        ctx.saveGState(); ctx.addPath(sock); ctx.clip()
        oval(ctx, CGPoint(x: 9, y: 6), 14, 12, rgb(0x16a34a))
        oval(ctx, CGPoint(x: 35, y: 18), 10, 12, rgb(0x16a34a))
        // Little white stripes.
        ctx.setFillColor(rgb(0xffffff, 0.9))
        for y in [26.0, 34.0] as [CGFloat] { ctx.fill(CGRect(x: 8, y: y, width: 30, height: 2.5)) }
        ctx.restoreGState()
        // Fluffy white cuff and a hanging loop.
        for (k, x) in stride(from: 9.0, through: 37.0, by: 5.6).enumerated() {
            oval(ctx, CGPoint(x: CGFloat(x), y: 49 + (k % 2 == 0 ? 0.8 : -0.6)), 9, 10, rgb(0xffffff))
        }
        ctx.setStrokeColor(rgb(0x16a34a)); ctx.setLineWidth(1.8)
        ctx.addArc(center: CGPoint(x: 11, y: 55), radius: 2.6, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()
    }

    private static func drawStar(_ ctx: CGContext, _ size: CGSize) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2 - 1)
        let star = CGMutablePath()
        for i in 0..<10 {
            let r: CGFloat = i % 2 == 0 ? 26 : 11.5
            let a = CGFloat(i) * .pi / 5 + .pi / 2
            let p = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
            i == 0 ? star.move(to: p) : star.addLine(to: p)
        }
        star.closeSubpath()
        ctx.setShadow(offset: .zero, blur: 4, color: rgb(0xffd23f))
        ctx.addPath(star); ctx.setFillColor(rgb(0xffc21a)); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        fillGradient(ctx, star, top: rgb(0xfff3a0), bottom: rgb(0xf5a300), rect: CGRect(x: 0, y: c.y - 26, width: size.width, height: 52))
        ctx.addPath(star); ctx.setStrokeColor(rgb(0xd97f00)); ctx.setLineWidth(1.4); ctx.strokePath()
        oval(ctx, CGPoint(x: c.x - 5, y: c.y + 6), 6, 4, rgb(0xffffff, 0.8))
        oval(ctx, CGPoint(x: c.x - 4, y: c.y + 1), 2.6, 3, rgb(0x5a3600))
        oval(ctx, CGPoint(x: c.x + 4, y: c.y + 1), 2.6, 3, rgb(0x5a3600))
        ctx.setStrokeColor(rgb(0x5a3600)); ctx.setLineWidth(1.3)
        ctx.addArc(center: CGPoint(x: c.x, y: c.y - 2), radius: 3.4, startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: false)
        ctx.strokePath()
    }
}
