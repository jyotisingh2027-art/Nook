import AppKit
import SpriteKit

/// Nook's own snowflake art, drawn in code so it's crisp at any size.
final class SnowTextures {
    static let shared = SnowTextures()

    let dot: SKTexture
    let crystals: [SKTexture]
    let clump: SKTexture
    let mound: SKTexture

    private init() {
        dot = SnowTextures.make(size: 32) { ctx, s in
            let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.85), CGColor(gray: 1, alpha: 0)] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 0.45, 1])!
            let c = CGPoint(x: s / 2, y: s / 2)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
        }
        crystals = [0.32, 0.5].map { branch in
            SnowTextures.make(size: 64) { ctx, s in
                let c = CGPoint(x: s / 2, y: s / 2)
                let r = s * 0.42
                ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
                ctx.setLineWidth(s * 0.05)
                ctx.setLineCap(.round)
                ctx.setShadow(offset: .zero, blur: s * 0.06, color: CGColor(red: 0.8, green: 0.9, blue: 1, alpha: 0.9))
                for i in 0..<6 {
                    let a = CGFloat(i) * .pi / 3
                    let tip = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                    ctx.move(to: c); ctx.addLine(to: tip)
                    let mid = CGPoint(x: c.x + cos(a) * r * 0.55, y: c.y + sin(a) * r * 0.55)
                    for side in [-1.0, 1.0] {
                        let b = a + CGFloat(side) * .pi / 4
                        ctx.move(to: mid)
                        ctx.addLine(to: CGPoint(x: mid.x + cos(b) * r * branch, y: mid.y + sin(b) * r * branch))
                    }
                }
                ctx.strokePath()
            }
        }
        clump = SnowTextures.make(size: 48) { ctx, s in
            let blobs: [(CGFloat, CGFloat, CGFloat)] = [(0.5, 0.45, 0.30), (0.33, 0.52, 0.2), (0.66, 0.55, 0.21), (0.48, 0.66, 0.18), (0.42, 0.36, 0.17)]
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            for (x, y, r) in blobs {
                ctx.fillEllipse(in: CGRect(x: (x - r) * s, y: (y - r) * s, width: r * 2 * s, height: r * 2 * s))
            }
            // A soft blue shadow on the underside.
            ctx.setBlendMode(.sourceAtop)
            let colors = [CGColor(red: 0.7, green: 0.8, blue: 0.95, alpha: 0.55), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: s * 0.18), end: CGPoint(x: 0, y: s * 0.55), options: [])
        }
        mound = SnowTextures.makeMound()
    }

    private static func makeMound() -> SKTexture {
        // A soft-topped column of snow, white with a faint blue base. Many of these side by side
        // (overlapping) make a smooth, slightly lumpy snow line.
        SnowTextures.make(size: 32) { ctx, s in
            let path = CGMutablePath()
            let r = s * 0.5
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: s - r))
            path.addArc(center: CGPoint(x: r, y: s - r), radius: r * 0.98, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: s, y: 0))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.clip()
            let colors = [CGColor(red: 0.80, green: 0.87, blue: 0.97, alpha: 1),
                          CGColor(red: 0.97, green: 0.985, blue: 1, alpha: 1),
                          CGColor(red: 1, green: 1, blue: 1, alpha: 1)] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.35, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: s), options: [])
        }
    }

    private static func make(size: Int, draw: (CGContext, CGFloat) -> Void) -> SKTexture {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        draw(ctx, CGFloat(size))
        let texture = SKTexture(cgImage: ctx.makeImage()!)
        texture.filteringMode = .linear
        return texture
    }
}
