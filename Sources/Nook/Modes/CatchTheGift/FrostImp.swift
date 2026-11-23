import AppKit
import SpriteKit

/// Nook's villain: a big white yeti, built like a gorilla, carried on a swirling gust of snow.
/// In Catch the Gift it swoops in from the side to snatch a falling gift before you catch it.
/// Click it to chase it off. (The code still calls it the "imp".)
enum FrostImpArt {
    static let size = CGSize(width: 64, height: 77)

    enum Pose { case flyA, flyB, grab, shooed }

    private static var cache: [Pose: SKTexture] = [:]

    static func texture(_ pose: Pose) -> SKTexture {
        if let t = cache[pose] { return t }
        let s: CGFloat = 3
        let ctx = CGContext(data: nil, width: Int(size.width * s), height: Int(size.height * s), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: s, y: s)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        draw(ctx, pose)
        let t = SKTexture(cgImage: ctx.makeImage()!)
        cache[pose] = t
        return t
    }

    private static func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    private static func oval(_ ctx: CGContext, _ c: CGPoint, _ w: CGFloat, _ h: CGFloat, _ col: CGColor) {
        ctx.setFillColor(col)
        ctx.fillEllipse(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
    }

    private static func poly(_ ctx: CGContext, _ pts: [CGPoint], _ col: CGColor) {
        ctx.setFillColor(col)
        ctx.addLines(between: pts)
        ctx.closePath()
        ctx.fillPath()
    }

    private static func draw(_ ctx: CGContext, _ pose: Pose) {
        let fur = rgb(0xf5f7fc), furShade = rgb(0xd3dbea), furLine = rgb(0xaab7cf)
        let skin = rgb(0x8a9fc2), skinLight = rgb(0xaebfdc), ink = rgb(0x1b2033)
        let cx: CGFloat = 32

        // The swirling gust of snow that carries it.
        let swirl: CGFloat = pose == .flyB ? 2 : 0
        oval(ctx, CGPoint(x: cx, y: 5), 50, 9, rgb(0xdbe9fb, 0.55))
        oval(ctx, CGPoint(x: cx - 14 + swirl, y: 7), 18, 9, rgb(0xffffff, 0.8))
        oval(ctx, CGPoint(x: cx + 2 - swirl, y: 8.5), 22, 10, rgb(0xffffff, 0.85))
        oval(ctx, CGPoint(x: cx + 16 + swirl, y: 6.5), 16, 8, rgb(0xffffff, 0.75))
        ctx.setStrokeColor(rgb(0xcfe2fa, 0.9)); ctx.setLineWidth(1.2)
        ctx.addArc(center: CGPoint(x: cx - 6 + swirl, y: 9), radius: 6, startAngle: .pi * 0.1, endAngle: .pi * 0.9, clockwise: false)
        ctx.strokePath()

        // Short stocky legs with grey feet.
        for side in [-1.0, 1.0] as [CGFloat] {
            oval(ctx, CGPoint(x: cx + side * 8.5, y: 13), 14, 13, furShade)
            oval(ctx, CGPoint(x: cx + side * 9.5, y: 9), 11, 5, skin)
        }

        // Arms: long and heavy like a gorilla's. They hang low while it swoops,
        // and go up over its head to grab a gift (or flail when it's chased off).
        let raised = pose == .grab || pose == .shooed
        let swing: CGFloat = pose == .flyA ? 0 : 2.5
        let shoulders = [CGPoint(x: cx - 16, y: 38), CGPoint(x: cx + 16, y: 38)]
        let fists: [CGPoint] = raised
            ? (pose == .shooed ? [CGPoint(x: cx - 27, y: 60), CGPoint(x: cx + 25, y: 63)]
                               : [CGPoint(x: cx - 20, y: 64), CGPoint(x: cx + 20, y: 64)])
            : [CGPoint(x: cx - 25, y: 12 + swing), CGPoint(x: cx + 25, y: 14.5 - swing)]
        for (sh, fist) in zip(shoulders, fists) {
            ctx.setStrokeColor(furLine); ctx.setLineWidth(13.5)
            ctx.move(to: sh); ctx.addLine(to: fist); ctx.strokePath()
            ctx.setStrokeColor(fur); ctx.setLineWidth(12)
            ctx.move(to: sh); ctx.addLine(to: fist); ctx.strokePath()
        }

        // Big barrel body and hulking shoulders, with shaggy tufts.
        oval(ctx, CGPoint(x: cx, y: 29), 41, 36, furLine)
        oval(ctx, CGPoint(x: cx, y: 29), 39, 34, fur)
        for side in [-1.0, 1.0] as [CGFloat] {
            oval(ctx, CGPoint(x: cx + side * 15, y: 39), 20, 17, fur)
        }
        for (x, y) in [(cx - 19, 22.0), (cx + 19, 22.0), (cx - 14, 15.0), (cx + 14, 15.0), (cx - 21, 31.0), (cx + 21, 31.0)] as [(CGFloat, CGFloat)] {
            poly(ctx, [CGPoint(x: x - 2.5, y: y + 2), CGPoint(x: x + 2.5, y: y + 2), CGPoint(x: x + (x < cx ? -2.5 : 2.5), y: y - 3)], fur)
        }
        // Bare chest, the way a gorilla's is.
        oval(ctx, CGPoint(x: cx, y: 27), 17, 14, skinLight)
        ctx.setStrokeColor(skin); ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: cx, y: 32)); ctx.addLine(to: CGPoint(x: cx, y: 24)); ctx.strokePath()

        // Big fists (drawn after the body so the hanging ones show in front).
        for fist in fists {
            oval(ctx, fist, 12.5, 11, furShade)
            oval(ctx, CGPoint(x: fist.x, y: fist.y - (raised ? -1.5 : 1.5)), 9, 5.5, skin)
        }

        // Head: sits low between the shoulders, with a tall crest.
        let hy: CGFloat = 48
        oval(ctx, CGPoint(x: cx, y: hy + 7), 15, 11, fur)            // crest
        oval(ctx, CGPoint(x: cx, y: hy), 24, 21, fur)
        // Face.
        oval(ctx, CGPoint(x: cx, y: hy - 1.5), 16.5, 14, skin)
        oval(ctx, CGPoint(x: cx, y: hy - 5), 13, 7.5, skinLight)        // muzzle
        // Heavy brow.
        ctx.setFillColor(rgb(0x6d82a8))
        ctx.addPath(CGPath(roundedRect: CGRect(x: cx - 8.5, y: hy + 1.8, width: 17, height: 3.4), cornerWidth: 1.7, cornerHeight: 1.7, transform: nil))
        ctx.fillPath()

        if pose == .shooed {
            // Dizzy swirls and an "oof" mouth.
            ctx.setStrokeColor(ink); ctx.setLineWidth(1.2)
            for ex in [cx - 4, cx + 4] {
                ctx.addArc(center: CGPoint(x: ex, y: hy - 0.5), radius: 2.4, startAngle: 0, endAngle: .pi * 1.6, clockwise: false)
                ctx.strokePath()
            }
            oval(ctx, CGPoint(x: cx, y: hy - 7), 4.5, 4.5, ink)
        } else {
            // Icy glowing eyes under an angry frown.
            ctx.setShadow(offset: .zero, blur: 3, color: rgb(0x7ff0ff))
            for ex in [cx - 4, cx + 4] {
                oval(ctx, CGPoint(x: ex, y: hy - 0.3), 3.6, 2.8, rgb(0xa8f6ff))
            }
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            for ex in [cx - 4, cx + 4] { oval(ctx, CGPoint(x: ex, y: hy - 0.3), 1.3, 1.6, ink) }
            ctx.setStrokeColor(ink); ctx.setLineWidth(1.6)
            ctx.move(to: CGPoint(x: cx - 7.5, y: hy + 3)); ctx.addLine(to: CGPoint(x: cx - 1.2, y: hy + 1.2))
            ctx.move(to: CGPoint(x: cx + 7.5, y: hy + 3)); ctx.addLine(to: CGPoint(x: cx + 1.2, y: hy + 1.2))
            ctx.strokePath()
            // A snarl with fangs.
            ctx.setFillColor(ink)
            ctx.addPath(CGPath(roundedRect: CGRect(x: cx - 5, y: hy - 9, width: 10, height: 3.6), cornerWidth: 1.8, cornerHeight: 1.8, transform: nil))
            ctx.fillPath()
            for fx in [cx - 3.4, cx + 1.8] {
                poly(ctx, [CGPoint(x: fx, y: hy - 5.4), CGPoint(x: fx + 1.6, y: hy - 5.4), CGPoint(x: fx + 0.8, y: hy - 8)], rgb(0xffffff))
            }
        }
        // Wide flat nose.
        oval(ctx, CGPoint(x: cx, y: hy - 3.6), 6.5, 2.8, rgb(0x5d7098))
        oval(ctx, CGPoint(x: cx - 1.6, y: hy - 3.8), 1.3, 1.1, ink)
        oval(ctx, CGPoint(x: cx + 1.6, y: hy - 3.8), 1.3, 1.1, ink)
    }
}

/// Developer preview: a gift falls, the imp chases and steals it (`Nook --render-imp out.png`).
enum FrostImpPreview {
    static func render(to path: String) {
        UserDefaults.standard.set(max(1, UserDefaults.standard.integer(forKey: "giftsCaught")), forKey: "giftsCaught")
        let size = CGSize(width: 900, height: 500)
        let scene = SKScene(size: size)
        scene.backgroundColor = NSColor(red: 0.18, green: 0.1, blue: 0.2, alpha: 1)
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)
        let layer = GiftLayer()
        scene.addChild(layer)
        layer.isActive = true
        var images: [CGImage] = []
        var t: CFTimeInterval = 100
        var dropped = 0
        for step in 0..<330 {
            if step == 0 || (step % 60 == 0 && !layer.hasGifts && dropped < 6) { layer.drop(in: size); dropped += 1 }
            layer.step(t)
            t += 1.0 / 30
            if [40, 80, 110, 140, 170, 200].contains(step), let tex = view.texture(from: scene) { images.append(tex.cgImage()) }
        }
        let w = images[0].width, h = images[0].height
        let ctx = CGContext(data: nil, width: w * 3, height: h * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (i, img) in images.enumerated() {
            ctx.draw(img, in: CGRect(x: (i % 3) * w, y: (1 - i / 3) * h, width: w, height: h))
        }
        try? NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

/// Hearts for the lives counter.
enum HeartArt {
    static let full = make(filled: true)
    static let empty = make(filled: false)

    private static func make(filled: Bool) -> SKTexture {
        let w: CGFloat = 52, h: CGFloat = 48
        let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let path = CGMutablePath()
        path.move(to: CGPoint(x: w / 2, y: 5))
        path.addCurve(to: CGPoint(x: 4, y: 30), control1: CGPoint(x: 18, y: 15), control2: CGPoint(x: 4, y: 20))
        path.addArc(center: CGPoint(x: 15, y: 32), radius: 11.2, startAngle: .pi * 1.08, endAngle: 0.15, clockwise: true)
        path.addArc(center: CGPoint(x: 37, y: 32), radius: 11.2, startAngle: .pi - 0.15, endAngle: -0.08, clockwise: true)
        path.addCurve(to: CGPoint(x: w / 2, y: 5), control1: CGPoint(x: 48, y: 20), control2: CGPoint(x: 34, y: 15))
        path.closeSubpath()
        ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 3, color: CGColor(gray: 0, alpha: 0.45))
        ctx.addPath(path)
        if filled {
            ctx.setFillColor(CGColor(red: 1, green: 0.33, blue: 0.42, alpha: 1))
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.55))
            ctx.fillEllipse(in: CGRect(x: 10, y: 31, width: 8, height: 6))
        } else {
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
            ctx.setLineWidth(3)
            ctx.strokePath()
        }
        return SKTexture(cgImage: ctx.makeImage()!)
    }
}
