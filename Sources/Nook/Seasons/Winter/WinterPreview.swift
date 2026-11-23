import AppKit
import SpriteKit

/// Developer preview: runs a winter scene off screen with a pretend window and Dock,
/// and saves snapshots over time (`Nook --render-winter out.png`). Set NOOK_VISITOR_DEMO=1
/// to have visitors arrive quickly.
enum WinterPreview {
    static func render(to path: String) {
        let size = CGSize(width: 1000, height: 260)
        let scene = WinterScene(screenFrame: CGRect(origin: .zero, size: size), visibleTop: size.height)
        scene.backgroundColor = NSColor(red: 0.16, green: 0.17, blue: 0.3, alpha: 1)
        scene.snowDensity = 2
        scene.snowSpeed = 1.6
        scene.snowBuildUp = 5
        let view = SKView(frame: CGRect(origin: .zero, size: size))
        view.presentScene(scene)

        let window = TrackedWindow(id: 1, pid: 1, frame: CGRect(x: 520, y: 40, width: 420, height: 120))
        let dock = CGRect(x: 120, y: 0, width: 360, height: 46)
        let shots: Set<Int> = [600, 900, 1100, 1300, 1500, 1700, 1900, 2100]
        var images: [CGImage] = []
        for step in 0...2100 {
            if step % 8 == 0 { scene.windowsDidUpdate([window], events: [], dockRect: dock) }
            scene.update(Double(step) / 30)
            if shots.contains(step), let tex = view.texture(from: scene) {
                images.append(tex.cgImage())
            }
        }
        let scale = CGFloat(images.first?.width ?? 1000) / size.width
        let W = size.width * scale, H = size.height * scale * CGFloat(images.count)
        let ctx = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for (i, img) in images.enumerated() {
            let y = H - size.height * scale * CGFloat(i + 1)
            // The pretend window and Dock, so the snow has something to sit on.
            ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
            ctx.fill(window.frame.applying(CGAffineTransform(scaleX: scale, y: scale)).offsetBy(dx: 0, dy: y))
            ctx.setFillColor(CGColor(gray: 0.45, alpha: 1))
            ctx.fill(dock.applying(CGAffineTransform(scaleX: scale, y: scale)).offsetBy(dx: 0, dy: y))
            ctx.draw(img, in: CGRect(x: 0, y: y, width: W, height: size.height * scale))
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.3))
            ctx.fill(CGRect(x: 0, y: y, width: W, height: 2))
        }
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
