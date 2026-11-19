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
    }

    func weatherVisibilityChanged() {}

    // MARK: - Mouse (only reaches Nook while the pointer is over a decoration)

    private func globalPoint(_ e: NSEvent) -> CGPoint {
        let p = e.location(in: self)
        return CGPoint(x: p.x + screenFrame.minX, y: p.y + screenFrame.minY)
    }

    override func mouseDown(with event: NSEvent) { DecorationInteraction.shared.mouseDown(at: globalPoint(event), event: event) }
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
