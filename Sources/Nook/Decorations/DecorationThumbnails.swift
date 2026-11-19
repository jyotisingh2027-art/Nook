import AppKit

/// Small pictures of decorations for the panel, drawn with the same art as the desktop.
enum DecorationThumbnails {
    private static var cache: [String: NSImage] = [:]

    /// The part of the picture worth zooming in on for an option (e.g. just the hat).
    static func focus(kind: DecorationKind, option: String?) -> ClosedRange<CGFloat>? {
        switch (kind, option) {
        case (.snowman, "hat"): return 0.7...1.0
        case (.snowman, "face"): return 0.62...0.88
        case (.snowman, "scarf"): return 0.4...0.76
        case (.tree, "topper"): return 0.8...1.0
        default: return nil
        }
    }

    static func image(kind: DecorationKind, options: [String: String], sag: Double = 0.35, focus: ClosedRange<CGFloat>? = nil) -> NSImage {
        let key = "\(kind.rawValue)|\(options.sorted { $0.key < $1.key })|\(sag)|\(String(describing: focus))"
        if let img = cache[key] { return img }
        if cache.count > 300 { cache.removeAll() }

        let img: NSImage
        if kind == .lights {
            img = lightsImage(colors: options["colors"] ?? "warm", wire: options["wire"] ?? "green", bulb: options["bulb"] ?? "round", sag: sag)
        } else {
            var d = PlacedDecoration(kind: kind, x: 0, y: 0)
            d.options = options
            d.seed = 7
            d.scale = 0.7
            let r = DecorationRenderer.shared.render(d)
            var cg = r.image
            if let f = focus {
                let h = CGFloat(cg.height), w = CGFloat(cg.width)
                let ch = (f.upperBound - f.lowerBound) * h
                let cw = min(w, ch * 1.25)   // crop tightly around the middle so the detail fills the tile
                let rect = CGRect(x: (w - cw) / 2, y: (1 - f.upperBound) * h, width: cw, height: ch)
                cg = cg.cropping(to: rect.integral) ?? cg
            }
            img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 1.4, height: CGFloat(cg.height) / 1.4))
        }
        cache[key] = img
        return img
    }

    private static func lightsImage(colors: String, wire: String, bulb: String, sag: Double) -> NSImage {
        let W: CGFloat = 160, H: CGFloat = 80, s: CGFloat = 2
        let ctx = CGContext(data: nil, width: Int(W * s), height: Int(H * s), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: s, y: s)
        let a = CGPoint(x: 10, y: 66), b = CGPoint(x: W - 10, y: 66)
        let dip = (b.x - a.x) * CGFloat(sag) * 0.5
        let pts = (0...40).map { i -> CGPoint in
            let t = CGFloat(i) / 40
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y - dip * 4 * t * (1 - t))
        }
        ctx.addLines(between: pts)
        ctx.setStrokeColor(BulbArt.wireColor(wire)); ctx.setLineWidth(2); ctx.strokePath()
        let hex: [UInt32]
        switch colors {
        case "multi": hex = [0xff5a5a, 0xffd34f, 0x5ad1ff, 0x7dff8a, 0xff8ad8]
        case "icy": hex = [0xbfe8ff, 0x8fd0ff, 0xffffff]
        case "candy": hex = [0xff4d5e, 0xffffff]
        case "pink": hex = [0xff8ad8, 0xffc2e6, 0xff5fa8]
        default: hex = [0xffd88a, 0xffe7b0, 0xffc66b]
        }
        for (k, i) in stride(from: 2, to: 40, by: 4).enumerated() {
            let p = CGPoint(x: pts[i].x, y: pts[i].y - 5)
            let c = rgb(hex[k % hex.count])
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c.copy(alpha: 0.7)!, c.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: 11, options: [])
            let r = bulb == "star" ? CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12) : bulb == "classic" ? CGRect(x: p.x - 4, y: p.y - 7, width: 8, height: 12) : CGRect(x: p.x - 3, y: p.y - 4, width: 6, height: 8)
            ctx.saveGState(); ctx.translateBy(x: 0, y: 0)
            ctx.addPath(BulbArt.path(bulb, in: r)); ctx.setFillColor(c); ctx.fillPath()
            ctx.restoreGState()
        }
        let cg = ctx.makeImage()!
        return NSImage(cgImage: cg, size: NSSize(width: W, height: H))
    }
}
