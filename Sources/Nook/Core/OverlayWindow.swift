import AppKit

/// A transparent, borderless window covering one screen. It sits just above the Dock
/// so snow can settle on it, and lets every click pass straight through.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        // A non-activating panel: grabbing a decoration never steals focus from the app you're using.
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true   // clicks go through to your apps
        acceptsMouseMovedEvents = true
        isFloatingPanel = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
