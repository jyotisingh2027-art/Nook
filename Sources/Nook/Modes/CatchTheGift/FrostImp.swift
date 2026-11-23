import AppKit
import SpriteKit

/// Nook's villain: a cheeky little frost imp riding a puff of cloud. In Catch the Gift it
/// sneaks in from the side and tries to snatch a falling gift before you catch it.
/// Click it to chase it off.
enum FrostImpArt {
    static let size = CGSize(width: 54, height: 60)

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
        let skin = rgb(0x7d97c2), skinDark = rgb(0x5c739e), belly = rgb(0xb8cbe8)
        let ice = rgb(0xdff6ff), cloud = rgb(0xf4f9ff), cloudShade = rgb(0xc9dcf2)
        let ink = rgb(0x1d2238)
        let cx: CGFloat = 27

        // Its little cloud. The puffs shift between frames so it looks like it's drifting.
        let puff: CGFloat = pose == .flyB ? 1.5 : 0
        oval(ctx, CGPoint(x: cx, y: 8), 40, 10, cloudShade)
        oval(ctx, CGPoint(x: cx - 12 + puff, y: 11), 16, 12, cloud)
        oval(ctx, CGPoint(x: cx + 1 - puff, y: 13), 20, 14, cloud)
        oval(ctx, CGPoint(x: cx + 13 + puff, y: 10.5), 14, 11, cloud)

        // Feet dangling into the cloud, and a curly tail tipped with an icicle.
        oval(ctx, CGPoint(x: cx - 5, y: 16), 6, 4, skinDark)
        oval(ctx, CGPoint(x: cx + 5, y: 16), 6, 4, skinDark)
        ctx.setStrokeColor(skinDark); ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: cx + 8, y: 20))
        ctx.addCurve(to: CGPoint(x: cx + 19, y: 26), control1: CGPoint(x: cx + 16, y: 16), control2: CGPoint(x: cx + 20, y: 20))
        ctx.strokePath()
        poly(ctx, [CGPoint(x: cx + 17, y: 25), CGPoint(x: cx + 21.5, y: 25.5), CGPoint(x: cx + 20, y: 31)], ice)

        // Body.
        oval(ctx, CGPoint(x: cx, y: 24), 20, 17, skin)
        oval(ctx, CGPoint(x: cx, y: 22.5), 12, 10, belly)

        // Arms: tucked while flying, raised when grabbing or startled.
        ctx.setStrokeColor(skin); ctx.setLineWidth(3.4)
        switch pose {
        case .flyA, .flyB:
            let wave: CGFloat = pose == .flyA ? 0 : 2
            ctx.move(to: CGPoint(x: cx - 8, y: 27)); ctx.addLine(to: CGPoint(x: cx - 14, y: 22 + wave))
            ctx.move(to: CGPoint(x: cx + 8, y: 27)); ctx.addLine(to: CGPoint(x: cx + 14, y: 22 + 2 - wave))
        case .grab, .shooed:
            ctx.move(to: CGPoint(x: cx - 8, y: 28)); ctx.addLine(to: CGPoint(x: cx - 16, y: 37))
            ctx.move(to: CGPoint(x: cx + 8, y: 28)); ctx.addLine(to: CGPoint(x: cx + 16, y: 37))
        }
        ctx.strokePath()
        // Claws.
        let hands: [CGPoint] = (pose == .grab || pose == .shooed)
            ? [CGPoint(x: cx - 16, y: 37.5), CGPoint(x: cx + 16, y: 37.5)]
            : [CGPoint(x: cx - 14.5, y: 21.5 + (pose == .flyA ? 0 : 2)), CGPoint(x: cx + 14.5, y: 23.5 - (pose == .flyA ? 0 : 2))]
        for h in hands { oval(ctx, h, 4.6, 4.6, skinDark) }

        // Big pointy ears.
        let headY: CGFloat = 39
        for side in [-1.0, 1.0] as [CGFloat] {
            poly(ctx, [CGPoint(x: cx + side * 9, y: headY + 4), CGPoint(x: cx + side * 25, y: headY + 12), CGPoint(x: cx + side * 11, y: headY - 3)], skin)
            poly(ctx, [CGPoint(x: cx + side * 11, y: headY + 2.5), CGPoint(x: cx + side * 21, y: headY + 8.5), CGPoint(x: cx + side * 12, y: headY - 1)], rgb(0xa9bde0))
        }

        // Head.
        oval(ctx, CGPoint(x: cx, y: headY), 26, 22, skin)

        // A crest of little icicles on top.
        for (dx, h) in [(-6.0, 6.0), (0.0, 9.0), (6.0, 6.0)] as [(CGFloat, CGFloat)] {
            poly(ctx, [CGPoint(x: cx + dx - 3, y: headY + 9), CGPoint(x: cx + dx + 3, y: headY + 9), CGPoint(x: cx + dx, y: headY + 9 + h)], ice)
        }

        // Eyes.
        let eyeY = headY + 1.5
        if pose == .shooed {
            // Dizzy swirls after being chased off.
            ctx.setStrokeColor(ink); ctx.setLineWidth(1.4)
            for ex in [cx - 6, cx + 6] {
                ctx.addArc(center: CGPoint(x: ex, y: eyeY), radius: 3, startAngle: 0, endAngle: .pi * 1.6, clockwise: false)
                ctx.move(to: CGPoint(x: ex + 1.2, y: eyeY))
                ctx.addArc(center: CGPoint(x: ex, y: eyeY), radius: 1.2, startAngle: 0, endAngle: .pi * 1.5, clockwise: false)
                ctx.strokePath()
            }
        } else {
            for ex in [cx - 6, cx + 6] {
                oval(ctx, CGPoint(x: ex, y: eyeY), 7.5, 6, rgb(0xffe066))
                oval(ctx, CGPoint(x: ex + 0.6, y: eyeY), 2, 5, ink)         // sly slit pupils
            }
            // Mischievous brows slanting toward the middle.
            ctx.setStrokeColor(ink); ctx.setLineWidth(1.8)
            ctx.move(to: CGPoint(x: cx - 10, y: eyeY + 5.5)); ctx.addLine(to: CGPoint(x: cx - 2.5, y: eyeY + 3.2))
            ctx.move(to: CGPoint(x: cx + 10, y: eyeY + 5.5)); ctx.addLine(to: CGPoint(x: cx + 2.5, y: eyeY + 3.2))
            ctx.strokePath()
        }

        // Mouth: a wide sly grin with two little fangs, or an "o" when startled.
        let mouthY = headY - 5.5
        if pose == .shooed {
            oval(ctx, CGPoint(x: cx, y: mouthY), 5, 5.5, ink)
        } else {
            ctx.setFillColor(ink)
            ctx.move(to: CGPoint(x: cx - 7.5, y: mouthY + 1.5))
            ctx.addQuadCurve(to: CGPoint(x: cx + 7.5, y: mouthY + 1.5), control: CGPoint(x: cx, y: mouthY - 6))
            ctx.addQuadCurve(to: CGPoint(x: cx - 7.5, y: mouthY + 1.5), control: CGPoint(x: cx, y: mouthY - 0.5))
            ctx.fillPath()
            poly(ctx, [CGPoint(x: cx - 4, y: mouthY), CGPoint(x: cx - 2, y: mouthY), CGPoint(x: cx - 3, y: mouthY - 2.6)], rgb(0xffffff))
            poly(ctx, [CGPoint(x: cx + 2, y: mouthY), CGPoint(x: cx + 4, y: mouthY), CGPoint(x: cx + 3, y: mouthY - 2.6)], rgb(0xffffff))
        }
        // Frosty cheeks.
        oval(ctx, CGPoint(x: cx - 9, y: mouthY + 1.5), 4, 2.4, rgb(0xc7a6e0, 0.7))
        oval(ctx, CGPoint(x: cx + 9, y: mouthY + 1.5), 4, 2.4, rgb(0xc7a6e0, 0.7))
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
