import AppKit
import AVFoundation

/// Plays a muted, looping video behind the desktop icons on every screen.
/// It pauses itself whenever it can't be seen (covered by windows, screen asleep, Low Power Mode).
final class VideoWallpaper {
    private final class DesktopVideoWindow: NSWindow {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private var windows: [NSWindow] = []
    private var players: [AVQueuePlayer] = []
    private var loopers: [AVPlayerLooper] = []
    private var observers: [NSObjectProtocol] = []
    private var screensAsleep = false
    private let url: URL

    init(url: URL) {
        self.url = url
        build()
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true; self?.updatePlayback()
        })
        observers.append(ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false; self?.updatePlayback()
        })
        observers.append(NotificationCenter.default.addObserver(forName: PowerMonitor.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.updatePlayback()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.rebuild()
        })
    }

    deinit { stop() }

    func stop() {
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        tearDown()
    }

    private func tearDown() {
        players.forEach { $0.pause() }
        windows.forEach { $0.orderOut(nil) }
        windows.forEach { NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: $0) }
        windows.removeAll(); players.removeAll(); loopers.removeAll()
    }

    private func rebuild() {
        tearDown()
        build()
    }

    private func build() {
        for screen in NSScreen.screens {
            let window = DesktopVideoWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false

            let player = AVQueuePlayer()
            player.isMuted = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))

            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(layer)
            window.contentView = view
            window.orderBack(nil)

            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
            windows.append(window); players.append(player); loopers.append(looper)
        }
        updatePlayback()
    }

    @objc private func occlusionChanged() { updatePlayback() }

    private func updatePlayback() {
        for (window, player) in zip(windows, players) {
            let visible = window.occlusionState.contains(.visible)
            let play = visible && !screensAsleep && !PowerMonitor.shared.isLowPowerMode
            if play { player.play() } else { player.pause() }
        }
    }
}
