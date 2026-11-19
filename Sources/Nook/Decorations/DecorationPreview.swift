import AppKit
import SwiftUI

/// Developer helper: draws every decoration (and some option combinations) into one image,
/// so the artwork can be reviewed without placing things on the desktop.
enum DecorationPreview {
    static func renderSheet(to path: String) {
        var items: [PlacedDecoration] = []
        func make(_ k: DecorationKind, _ o: [String: String] = [:]) {
            var d = PlacedDecoration(kind: k, x: 0, y: 0)
            d.options = o
            d.seed = 42
            items.append(d)
        }
        make(.tree)
        make(.tree, ["topper": "snowflake", "baubles": "frost", "lights": "multi", "garland": "silver", "candyCanes": "on", "gingerbread": "on"])
        make(.tree, ["topper": "bow", "baubles": "red", "lights": "none", "garland": "none", "size": "small"])
        make(.snowman)
        make(.snowman, ["hat": "beanie", "face": "cheeky", "scarf": "stripes", "outfit": "mittens"])
        make(.snowman, ["hat": "santa", "face": "surprised", "scarf": "green", "outfit": "bowtie"])
        for k in DecorationKind.allCases where k.group != .builders { make(k) }

        let cell = CGSize(width: 300, height: 380)
        let cols = 6
        let rows = (items.count + cols - 1) / cols
        let W = Int(cell.width) * cols, H = Int(cell.height) * rows
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(rgb(0x2a3566)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (i, d) in items.enumerated() {
            let r = DecorationRenderer.shared.render(d)
            let c = i % cols, row = i / cols
            let ox = CGFloat(c) * cell.width + (cell.width - r.size.width) / 2
            let oy = CGFloat(H) - CGFloat(row + 1) * cell.height + 20
            for l in r.lights {
                ctx.setFillColor(l.color.copy(alpha: 0.35)!)
                ctx.fillEllipse(in: CGRect(x: ox + l.p.x - l.radius / 2, y: oy + l.p.y - l.radius / 2, width: l.radius, height: l.radius))
            }
            ctx.draw(r.image, in: CGRect(x: ox, y: oy, width: r.size.width, height: r.size.height))
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    }

    /// Draws the Decorations panel into an image (developer check; nothing is saved).
    static func renderPanel(to path: String, page: String) {
        _ = NSApplication.shared
        DecorationStore.persistenceEnabled = false
        let store = DecorationStore.shared
        store.selectedID = nil
        let view: DecorationEditorView
        switch page {
        case "base": view = DecorationEditorView(previewPage: .pickBase(.tree))
        case "decorate":
            var d = PlacedDecoration(kind: .tree, x: 0, y: 0)
            d.options = ["treeColor": "white", "topper": "star", "topperColor": "pink", "baubles": "pink", "lights": "warm", "garland": "silver"]
            view = DecorationEditorView(previewPage: .customize, previewDraft: d)
        case "snowman":
            var d = PlacedDecoration(kind: .snowman, x: 0, y: 0)
            d.options = ["body": "chubby", "snow": "white", "hat": "beanie", "hatColor": "pink", "scarf": "pink"]
            view = DecorationEditorView(previewPage: .customize, previewDraft: d)
        case "size":
            var d = PlacedDecoration(kind: .tree, x: 0, y: 0)
            d.options = ["topper": "star", "baubles": "red", "lights": "warm"]
            store.place(d)
            view = DecorationEditorView(previewPage: .customize, previewStep: .size)
        default: view = DecorationEditorView(previewPage: .home)
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 380, height: 1250)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("Wrote \(path)")
    }
}
