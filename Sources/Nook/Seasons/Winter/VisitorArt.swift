import AppKit
import SpriteKit

/// Hand-drawn (in code) frames for the little winter visitors. Every frame is drawn once
/// and shared, so a walking reindeer costs about as much as one snowflake.
enum VisitorArt {
    /// How much bigger than their drawing the visitors appear on screen.
    static let displayScale: CGFloat = 1.4


    // MARK: - Drawing helpers

    private static func texture(_ w: CGFloat, _ h: CGFloat, _ draw: (CGContext) -> Void) -> SKTexture {
        let s: CGFloat = 3   // extra detail so they stay sharp when shown larger
        let ctx = CGContext(data: nil, width: Int(w * s), height: Int(h * s), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: s, y: s)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        draw(ctx)
        let t = SKTexture(cgImage: ctx.makeImage()!)
        t.filteringMode = .linear
        return t
    }

    private static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    private static func ellipse(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ color: CGColor, rotate: CGFloat = 0) {
        ctx.saveGState()
        ctx.translateBy(x: c.x, y: c.y)
        ctx.rotate(by: rotate)
        ctx.setFillColor(color)
        ctx.fillEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    private static func line(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, _ width: CGFloat, _ color: CGColor) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.move(to: a); ctx.addLine(to: b)
        ctx.strokePath()
    }

    private static func point(_ from: CGPoint, length: CGFloat, angle: CGFloat) -> CGPoint {
        // angle 0 = straight down, positive = forward (to the right)
        CGPoint(x: from.x + sin(angle) * length, y: from.y - cos(angle) * length)
    }

    // MARK: - Reindeer (faces right; 66 × 68, feet at y ≈ 2)

    static let reindeerSize = CGSize(width: 76, height: 68)

    /// Leg angles: front-near, front-far, back-near, back-far.
    private static func reindeer(legs: [CGFloat], headDown: Bool = false, tilt: CGFloat = 0, small: Bool = false) -> SKTexture {
        texture(reindeerSize.width, reindeerSize.height) { ctx in
            let fur = rgb(small ? 0xa06a45 : 0x8b5a3a)
            let furDark = rgb(small ? 0x7e5132 : 0x6b4329)
            let cream = rgb(0xead7bd)
            let hoof = rgb(0x3a2a22)
            let antler = rgb(0xd9c39a)

            ctx.translateBy(x: 5, y: 0)   // centre the body in the wider frame
            ctx.translateBy(x: 32, y: 26)
            ctx.rotate(by: tilt)
            ctx.translateBy(x: -32, y: -26)

            let frontHip = CGPoint(x: 41, y: 24), backHip = CGPoint(x: 21, y: 25)
            let legLen: CGFloat = 21

            func drawLeg(_ hip: CGPoint, _ a: CGFloat, _ color: CGColor) {
                let knee = point(hip, length: legLen * 0.5, angle: a)
                let foot = point(knee, length: legLen * 0.5, angle: a * 0.45)
                line(ctx, hip, knee, 4.2, color)
                line(ctx, knee, foot, 3.4, color)
                ellipse(ctx, CGPoint(x: foot.x + 0.6, y: foot.y + 0.6), 4.4, 2.8, hoof)
            }

            // Far legs sit behind the body.
            drawLeg(CGPoint(x: frontHip.x - 2, y: frontHip.y), legs[1], furDark)
            drawLeg(CGPoint(x: backHip.x + 2, y: backHip.y), legs[3], furDark)

            // Tail and body.
            ellipse(ctx, CGPoint(x: 12.5, y: 31), 6, 5, cream, rotate: 0.5)
            ellipse(ctx, CGPoint(x: 31, y: 29), 34, 17, fur)
            ellipse(ctx, CGPoint(x: 32, y: 24.5), 24, 7, cream)
            // A few winter spots on the young one.
            if small {
                for (x, y) in [(24.0, 33.0), (30.0, 35.0), (36.0, 32.5), (27.0, 30.5)] {
                    ellipse(ctx, CGPoint(x: x, y: y), 2.4, 2, rgb(0xf3e6d2, 0.9))
                }
            }

            // Near legs in front.
            drawLeg(frontHip, legs[0], fur)
            drawLeg(backHip, legs[2], fur)

            // Neck and head.
            let neckBase = CGPoint(x: 43, y: 32)
            let head = headDown ? CGPoint(x: 55, y: 15) : CGPoint(x: 52, y: 46)
            line(ctx, neckBase, head, 9, fur)
            let headTilt: CGFloat = headDown ? -1.05 : 0
            ctx.saveGState()
            ctx.translateBy(x: head.x, y: head.y)
            ctx.rotate(by: headTilt)
            // Antlers.
            if !small {
                ctx.setStrokeColor(antler)
                ctx.setLineWidth(2.1)
                for (dx, lean) in [(-2.5, -0.45), (0.5, -0.15)] as [(CGFloat, CGFloat)] {
                    let base = CGPoint(x: dx, y: 3.5)
                    let tip = CGPoint(x: base.x + sin(lean) * 16 - 4, y: base.y + cos(lean) * 16)
                    ctx.move(to: base)
                    ctx.addQuadCurve(to: tip, control: CGPoint(x: base.x - 7, y: base.y + 8))
                    let t1 = CGPoint(x: base.x - 3.5, y: base.y + 6.5)
                    ctx.move(to: t1); ctx.addLine(to: CGPoint(x: t1.x + 3.5, y: t1.y + 4.5))
                    let t2 = CGPoint(x: base.x - 5, y: base.y + 11)
                    ctx.move(to: t2); ctx.addLine(to: CGPoint(x: t2.x + 3.5, y: t2.y + 4))
                    ctx.move(to: t2); ctx.addLine(to: CGPoint(x: t2.x - 4.5, y: t2.y + 2.5))
                    ctx.strokePath()
                }
            } else {
                ellipse(ctx, CGPoint(x: -1, y: 5), 2.4, 4, antler)
            }
            // Ear, head, snout, nose, eye.
            ellipse(ctx, CGPoint(x: -5, y: 3), 7, 3.6, furDark, rotate: 0.5)
            ellipse(ctx, CGPoint(x: 0, y: 0), 13, 10.5, fur)
            ellipse(ctx, CGPoint(x: 6.5, y: -2), 9, 7, cream)
            ellipse(ctx, CGPoint(x: 10.3, y: -1.4), 3.6, 3.2, rgb(0x2b1d17))
            ellipse(ctx, CGPoint(x: 1.5, y: 2.2), 2.3, 2.6, rgb(0x1b1210))
            ellipse(ctx, CGPoint(x: 1.9, y: 2.9), 0.8, 0.8, rgb(0xffffff))
            ctx.restoreGState()
        }
    }

    struct ReindeerFrames {
        let walk: [SKTexture]
        let run: [SKTexture]
        let graze: SKTexture
        let stand: SKTexture
    }

    private static func reindeerFrames(small: Bool) -> ReindeerFrames {
        let walk = (0..<4).map { k -> SKTexture in
            let p = CGFloat(k) * .pi / 2
            let a: CGFloat = 0.38
            return reindeer(legs: [a * sin(p), a * sin(p + .pi), a * sin(p + .pi), a * sin(p)], small: small)
        }
        let run = [
            reindeer(legs: [0.85, 0.65, -0.85, -0.65], tilt: 0.06, small: small),   // stretched out
            reindeer(legs: [0.3, 0.15, -0.2, -0.05], small: small),
            reindeer(legs: [-0.45, -0.3, 0.6, 0.45], tilt: -0.05, small: small),    // gathered
        ]
        return ReindeerFrames(walk: walk, run: run,
                              graze: reindeer(legs: [0.1, -0.05, -0.05, 0.1], headDown: true, small: small),
                              stand: reindeer(legs: [0.05, -0.05, -0.05, 0.05], small: small))
    }

    static let reindeerAdult = reindeerFrames(small: false)
    static let reindeerYoung = reindeerFrames(small: true)

    // MARK: - Bunny (faces right; 30 × 28)

    static let bunnySize = CGSize(width: 30, height: 28)
    /// Drawn a touch bigger than the art so the bunny reads well on screen.
    static let bunnyDisplaySize = CGSize(width: 36, height: 33.6)

    private static func bunny(_ pose: Int) -> SKTexture {
        texture(bunnySize.width, bunnySize.height) { ctx in
            let fur = rgb(0xf1ece6), shade = rgb(0xd8d0c8), pink = rgb(0xf4a9b8)
            switch pose {
            case 1:   // mid-hop, stretched out
                ellipse(ctx, CGPoint(x: 7, y: 8), 9, 4, shade, rotate: -0.5)          // back leg kicked out
                ellipse(ctx, CGPoint(x: 14, y: 11), 18, 10, fur, rotate: 0.25)
                ellipse(ctx, CGPoint(x: 5.5, y: 11), 5.5, 5.5, rgb(0xffffff))
                ellipse(ctx, CGPoint(x: 22, y: 9), 5, 3, shade, rotate: -0.6)        // front paws
                ellipse(ctx, CGPoint(x: 22, y: 16), 10, 9, fur)
                ellipse(ctx, CGPoint(x: 18.2, y: 20.2), 11, 3.8, fur, rotate: 0.3)
                ellipse(ctx, CGPoint(x: 18.2, y: 20.2), 8, 1.6, pink, rotate: 0.3)
                ellipse(ctx, CGPoint(x: 24, y: 17), 1.8, 2, rgb(0x2a1f1f))
                ellipse(ctx, CGPoint(x: 26.6, y: 15.2), 1.6, 1.2, pink)
            case 2:   // sitting up, ears tall
                ellipse(ctx, CGPoint(x: 13, y: 8), 14, 14, fur)
                ellipse(ctx, CGPoint(x: 6.5, y: 6), 5.5, 5.5, rgb(0xffffff))
                ellipse(ctx, CGPoint(x: 17, y: 3), 7, 3.4, shade)
                ellipse(ctx, CGPoint(x: 17, y: 16), 10, 9, fur)
                ellipse(ctx, CGPoint(x: 14.5, y: 24), 3.8, 10, fur, rotate: 0.12)
                ellipse(ctx, CGPoint(x: 14.5, y: 24), 1.6, 7, pink, rotate: 0.12)
                ellipse(ctx, CGPoint(x: 18, y: 24), 3.8, 10, shade, rotate: -0.1)
                ellipse(ctx, CGPoint(x: 19.5, y: 17), 1.8, 2, rgb(0x2a1f1f))
                ellipse(ctx, CGPoint(x: 22, y: 15), 1.6, 1.2, pink)
            default:  // crouched
                ellipse(ctx, CGPoint(x: 12, y: 7.5), 17, 12, fur)
                ellipse(ctx, CGPoint(x: 4.5, y: 9), 5.5, 5.5, rgb(0xffffff))
                ellipse(ctx, CGPoint(x: 14, y: 2.5), 8, 3.4, shade)
                ellipse(ctx, CGPoint(x: 20.5, y: 11.5), 10, 9, fur)
                ellipse(ctx, CGPoint(x: 16.6, y: 15.4), 11, 3.8, fur, rotate: 0.4)
                ellipse(ctx, CGPoint(x: 16.6, y: 15.4), 8, 1.6, pink, rotate: 0.4)
                ellipse(ctx, CGPoint(x: 23, y: 12.5), 1.8, 2, rgb(0x2a1f1f))
                ellipse(ctx, CGPoint(x: 25.4, y: 10.6), 1.6, 1.2, pink)
            }
        }
    }

    static let bunnyCrouch = bunny(0)
    static let bunnyHop = bunny(1)
    static let bunnySitUp = bunny(2)

    // MARK: - Snow shoveller (faces right; 44 × 50)

    static let shovellerSize = CGSize(width: 44, height: 52)

    enum ShovelPose { case walkA, walkB, scoop, toss }

    struct Outfit: Hashable {
        let coat: UInt32
        let hat: UInt32
        let scarf: UInt32
        let skin: UInt32
    }

    static let outfits: [Outfit] = [
        Outfit(coat: 0xc8423b, hat: 0x2f6e4f, scarf: 0xf2d16b, skin: 0xf3cfa8),
        Outfit(coat: 0x2f6aa8, hat: 0xd94a4a, scarf: 0xffffff, skin: 0xc68c5e),
        Outfit(coat: 0xe0a43a, hat: 0x6b4ca0, scarf: 0x5ab0d8, skin: 0x8d5a3b),
        Outfit(coat: 0x3d8a5a, hat: 0xf0f0f0, scarf: 0xd94a4a, skin: 0xe8b98f),
    ]

    private static var shovelCache: [String: SKTexture] = [:]

    static func shoveller(_ pose: ShovelPose, outfit: Outfit) -> SKTexture {
        let key = "\(pose)|\(outfit.coat)|\(outfit.skin)"
        if let t = shovelCache[key] { return t }
        let t = texture(shovellerSize.width, shovellerSize.height) { ctx in
            let pants = rgb(0x34405a), boot = rgb(0x3b2b24)
            let coat = rgb(outfit.coat), hat = rgb(outfit.hat), scarf = rgb(outfit.scarf), skin = rgb(outfit.skin)
            let wood = rgb(0xa8774a), metal = rgb(0xb9c3cc)

            let hip = CGPoint(x: 20, y: 17)
            let shoulder = CGPoint(x: 21, y: 31)

            // Legs.
            let stride: (CGFloat, CGFloat)
            switch pose {
            case .walkA: stride = (0.42, -0.36)
            case .walkB: stride = (-0.3, 0.38)
            case .scoop: stride = (0.5, -0.3)
            case .toss: stride = (0.15, -0.35)
            }
            for (i, a) in [stride.1, stride.0].enumerated() {
                let foot = point(CGPoint(x: hip.x + (i == 0 ? -1.5 : 1.5), y: hip.y), length: 14, angle: a)
                line(ctx, CGPoint(x: hip.x + (i == 0 ? -1.5 : 1.5), y: hip.y), foot, 5, pants)
                ellipse(ctx, CGPoint(x: foot.x + 1.6, y: foot.y + 0.4), 7, 4, boot)
            }

            // Shovel position: where the hands hold it and where the blade ends up.
            let top: CGPoint, blade: CGPoint
            switch pose {
            case .walkA, .walkB: top = CGPoint(x: 25, y: 27); blade = CGPoint(x: 38, y: 6)
            case .scoop: top = CGPoint(x: 27, y: 21); blade = CGPoint(x: 41, y: 2.5)
            case .toss: top = CGPoint(x: 22, y: 31); blade = CGPoint(x: 9, y: 39)
            }

            func drawShovel() {
                line(ctx, top, blade, 2, wood)
                let dx = blade.x - top.x, dy = blade.y - top.y
                let len = max(0.001, hypot(dx, dy))
                let ux = dx / len, uy = dy / len          // along the handle
                let px = -uy, py = ux                     // across
                let w: CGFloat = 4.5, l: CGFloat = 8
                ctx.setFillColor(metal)
                ctx.move(to: CGPoint(x: blade.x + px * w, y: blade.y + py * w))
                ctx.addLine(to: CGPoint(x: blade.x + px * w + ux * l, y: blade.y + py * w + uy * l))
                ctx.addLine(to: CGPoint(x: blade.x - px * w + ux * l, y: blade.y - py * w + uy * l))
                ctx.addLine(to: CGPoint(x: blade.x - px * w, y: blade.y - py * w))
                ctx.closePath(); ctx.fillPath()
                if pose == .toss || pose == .scoop {   // a lump of snow on the blade
                    let c = CGPoint(x: blade.x + ux * l * 0.6 + px * 1.5, y: blade.y + uy * l * 0.6 + py * 1.5 + (pose == .toss ? 2.5 : 1.5))
                    ellipse(ctx, c, 9, 6, rgb(0xffffff))
                }
            }

            if pose == .toss { drawShovel() }   // raised behind, so it sits behind the body

            // Coat.
            let body = CGPath(roundedRect: CGRect(x: 13.5, y: 15, width: 14, height: 19), cornerWidth: 5, cornerHeight: 5, transform: nil)
            ctx.addPath(body); ctx.setFillColor(coat); ctx.fillPath()
            line(ctx, CGPoint(x: 20.5, y: 17), CGPoint(x: 20.5, y: 31), 0.8, rgb(0x000000, 0.18))

            // Arms reach to the handle.
            let hand1 = CGPoint(x: top.x + (blade.x - top.x) * 0.05, y: top.y + (blade.y - top.y) * 0.05)
            let hand2 = CGPoint(x: top.x + (blade.x - top.x) * 0.38, y: top.y + (blade.y - top.y) * 0.38)
            line(ctx, shoulder, hand1, 4.2, coat)
            if pose != .toss { drawShovel() }
            line(ctx, CGPoint(x: shoulder.x + 1, y: shoulder.y - 1), hand2, 4.2, coat)
            ellipse(ctx, hand1, 3.6, 3.6, rgb(0x5b3b2b))
            ellipse(ctx, hand2, 3.6, 3.6, rgb(0x5b3b2b))

            // Scarf with a tail flapping behind.
            let neck = CGPath(roundedRect: CGRect(x: 14.5, y: 31.5, width: 12.5, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil)
            ctx.addPath(neck); ctx.setFillColor(scarf); ctx.fillPath()
            line(ctx, CGPoint(x: 15.5, y: 33), CGPoint(x: 10, y: 29.5 + (pose == .walkB ? 1.5 : 0)), 3, scarf)

            // Head, cheek, eye, nose.
            ellipse(ctx, CGPoint(x: 21.5, y: 40), 12, 11.5, skin)
            ellipse(ctx, CGPoint(x: 25, y: 38), 3.2, 2.2, rgb(0xf08a8a, 0.55))
            ellipse(ctx, CGPoint(x: 24.6, y: 41), 1.5, 1.8, rgb(0x2a1f1f))
            ellipse(ctx, CGPoint(x: 27.4, y: 39.6), 2, 1.8, rgb(0xe9a98a))

            // Woolly hat with a folded brim and a pompom.
            ctx.setFillColor(hat)
            ctx.addArc(center: CGPoint(x: 21, y: 42.5), radius: 6.6, startAngle: 0, endAngle: .pi, clockwise: false)
            ctx.fillPath()
            let brim = CGPath(roundedRect: CGRect(x: 14, y: 41.2, width: 14, height: 3), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(brim); ctx.setFillColor(rgb(0xffffff, 0.85)); ctx.fillPath()
            ellipse(ctx, CGPoint(x: 20, y: 49.2), 4.2, 4.2, rgb(0xffffff))
        }
        shovelCache[key] = t
        return t
    }
}

extension VisitorArt {
    /// Developer preview: every visitor frame on one sheet (`Nook --render-visitors out.png`).
    static func renderSheet(to path: String) {
        let a = reindeerAdult, y = reindeerYoung
        let o = outfits
        let rows: [[SKTexture]] = [
            a.walk + [a.graze, a.stand],
            a.run + [y.walk[0], y.run[0], y.graze],
            [bunnyCrouch, bunnyHop, bunnySitUp],
            [shoveller(.walkA, outfit: o[0]), shoveller(.walkB, outfit: o[0]), shoveller(.scoop, outfit: o[1]),
             shoveller(.toss, outfit: o[2]), shoveller(.walkA, outfit: o[3])],
            [FrostImpArt.texture(.flyA), FrostImpArt.texture(.flyB), FrostImpArt.texture(.grab), FrostImpArt.texture(.shooed)],
        ]
        let cell: CGFloat = 80, scale: CGFloat = 3
        let W = cell * 6, H = cell * CGFloat(rows.count)
        let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.3, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (r, row) in rows.enumerated() {
            let baseY = H - cell * CGFloat(r + 1) + 8
            ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
            ctx.fill(CGRect(x: 0, y: baseY - 8, width: W, height: 10))
            for (c, t) in row.enumerated() {
                let img = t.cgImage()
                let w = CGFloat(img.width) / 3, h = CGFloat(img.height) / 3
                ctx.draw(img, in: CGRect(x: CGFloat(c) * cell + (cell - w) / 2, y: baseY - 3, width: w, height: h))
            }
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
