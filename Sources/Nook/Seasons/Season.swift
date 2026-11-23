import QuartzCore
import SpriteKit

/// A season (winter, autumn, spring, rain…) supplies the scene drawn on each screen.
/// Version 1 has only Winter; new seasons plug in by implementing this protocol.
protocol Season {
    var id: String { get }
    var displayName: String { get }
    func makeScene(screenFrame: CGRect, visibleTop: CGFloat) -> SeasonScene
}

/// Base class for a season's per-screen scene. Coordinates inside the scene are local
/// to the screen (0,0 = bottom-left of that screen).
class SeasonScene: SKScene {
    /// This screen's frame in global coordinates.
    let screenFrame: CGRect
    /// Height (from the bottom) below which content isn't hidden by the menu bar.
    var visibleTop: CGFloat

    /// Decorations are shared by every season, so the base scene owns them.
    let decorationLayer: DecorationLayer

    /// The playful modes live on every season's scene, so every season gets them for free.
    let giftLayer = GiftLayer()
    let snowballLayer = SnowballLayer()

    /// False when the user pauses the weather; decorations still show.
    var weatherVisible = true { didSet { if oldValue != weatherVisible { weatherVisibilityChanged() } } }

    /// Nook's own open windows (panels, wallpaper picker), which snow also stays out of.
    var ownWindowFrames: [CGRect] = []

    var snowDensity: Double = 1.0
    var snowSpeed: Double = 1.0
    var snowBuildUp: Double = 1.0
    var energySaving = false

    init(screenFrame: CGRect, visibleTop: CGFloat) {
        self.screenFrame = screenFrame
        self.visibleTop = visibleTop
        self.decorationLayer = DecorationLayer(screenOrigin: screenFrame.origin)
        super.init(size: screenFrame.size)
        addChild(decorationLayer)
        addChild(giftLayer)
        snowballLayer.screenOrigin = screenFrame.origin
        addChild(snowballLayer)
    }

    /// Runs after the season's own update each frame.
    override func didFinishUpdate() {
        let now = CACurrentMediaTime()
        giftLayer.step(now)
        snowballLayer.step(now)
    }

    // MARK: - Playful modes (global coordinates)

    private func local(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - screenFrame.minX, y: p.y - screenFrame.minY) }

    func dropGift() { giftLayer.drop(in: size) }

    func giftHit(atGlobal p: CGPoint) -> Bool { giftLayer.hitTest(local(p)) }

    /// A snowman or an incoming snowball is under the pointer.
    func snowballTargetHit(atGlobal p: CGPoint) -> Bool { snowballLayer.hitTest(local(p)) }

    func weatherVisibilityChanged() {}

    // MARK: - Mouse (only reaches Nook while the pointer is over a decoration)

    private func globalPoint(_ e: NSEvent) -> CGPoint {
        let p = e.location(in: self)
        return CGPoint(x: p.x + screenFrame.minX, y: p.y + screenFrame.minY)
    }

    override func mouseDown(with event: NSEvent) {
        let p = globalPoint(event)
        if giftLayer.catchGift(at: local(p)) { return }
        // Holding Option throws a snowball wherever you click.
        if snowballLayer.handleClick(at: local(p), anywhere: event.modifierFlags.contains(.option)) { return }
        DecorationInteraction.shared.mouseDown(at: p, event: event)
    }
    override func mouseDragged(with event: NSEvent) { DecorationInteraction.shared.mouseDragged(to: globalPoint(event)) }
    override func mouseUp(with event: NSEvent) { DecorationInteraction.shared.mouseUp() }
    override func scrollWheel(with event: NSEvent) { DecorationInteraction.shared.scroll(at: globalPoint(event), event: event) }
    override func rightMouseDown(with event: NSEvent) {
        guard let view else { return }
        DecorationInteraction.shared.rightMouseDown(at: globalPoint(event), event: event, in: view)
    }

    required init?(coder aDecoder: NSCoder) { fatalError("not used") }

    /// Called several times a second with the current windows (front-to-back) and what changed.
    func windowsDidUpdate(_ windows: [TrackedWindow], events: [WindowEvent], dockRect: CGRect?) {}

    func brushAllSnowOff() {}

    /// Converts a global rect to this scene's local coordinates.
    func toLocal(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }
}
