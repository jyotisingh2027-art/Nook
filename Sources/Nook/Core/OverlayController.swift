import AppKit
import SpriteKit

/// Owns one overlay per screen, feeds them window positions, and decides when to run or rest.
final class OverlayController: WindowTrackerObserver {
    private struct Overlay {
        let screen: NSScreen
        let window: OverlayWindow
        let view: SKView
        let scene: SeasonScene
    }

    private let season: Season
    private let tracker = WindowTracker()
    private var overlays: [Overlay] = []
    private var retired: [Overlay] = []        // kept alive briefly so SpriteKit can wind down safely
    private var screenSignature: [CGRect] = []

    private var screensAsleep = false
    private var sessionActive = true
    private var coveredScreens = Set<Int>()   // screens with a full-screen-sized window in front
    private var rebuildPending = false
    private var dockRect: CGRect?
    private var dockRefreshCounter = 0
    private var mouseMonitors: [Any] = []

    private enum Hover { case none, decoration, gift }
    private var hover = Hover.none

    // Catch the Gift
    private var giftTimer: Timer?
    private var nextGiftAt: CFTimeInterval = 0

    init(season: Season) {
        self.season = season
        tracker.observer = self
    }

    func start() {
        buildOverlays()
        observe()
        applySettings()
        watchMouse()
    }

    func brushAllSnowOff() {
        overlays.forEach { $0.scene.brushAllSnowOff() }
    }

    // MARK: - Overlays

    private func currentSignature() -> [CGRect] {
        NSScreen.screens.map { $0.frame }
    }

    private func teardown(_ o: Overlay) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: o.window)
        o.view.isPaused = true
        o.window.orderOut(nil)
        o.view.presentScene(nil)
    }

    private func buildOverlays() {
        overlays.forEach(teardown)
        retired.append(contentsOf: overlays)
        overlays.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.retired.removeAll()
        }
        screenSignature = currentSignature()
        dockRect = DockInfo.dockRect()

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = OverlaySKView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.allowsTransparency = true
            view.ignoresSiblingOrder = true
            view.shouldCullNonVisibleNodes = true
            window.contentView = view

            let visibleTop = screen.visibleFrame.maxY - screen.frame.minY
            let scene = season.makeScene(screenFrame: screen.frame, visibleTop: visibleTop)
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            view.presentScene(scene)
            scene.decorationLayer.sync()
            scene.giftLayer.isActive = giftsOn

            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
            overlays.append(Overlay(screen: screen, window: window, view: view, scene: scene))
        }
        applyEnergySettings()
        updateRunState()
    }

    private func scheduleRebuild() {
        guard !rebuildPending else { return }
        rebuildPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.rebuildPending = false
            self.dockRect = DockInfo.dockRect()
            if self.currentSignature() != self.screenSignature {
                self.buildOverlays()
            } else {
                // Same screens; just refresh the menu bar / Dock area.
                for o in self.overlays { o.scene.visibleTop = o.screen.visibleFrame.maxY - o.screen.frame.minY }
            }
        }
    }

    // MARK: - Observing the system

    private func observe() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRebuild()
        }
        nc.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in self?.applySettings() }
        nc.addObserver(forName: PowerMonitor.didChange, object: nil, queue: .main) { [weak self] _ in self?.applyEnergySettings() }
        for name in [DecorationStore.didChange, DecorationEditorController.visibilityChanged] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.decorationsChanged() }
        }
        DecorationInteraction.shared.onDragEnded = { [weak self] in self?.updateMouseCapture() }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true; self?.updateRunState()
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false; self?.updateRunState()
        }
        ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = false; self?.updateRunState()
        }
        ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = true; self?.updateRunState()
        }
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.tracker.poll() }
        }
        // The Dock grows/shrinks as apps launch and quit.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self?.dockRect = DockInfo.dockRect() }
            }
        }
    }

    @objc private func occlusionChanged(_ note: Notification) {
        updateRunState()
    }

    // MARK: - Run state

    private func applySettings() {
        let amount = Settings.shared.snowAmount
        for o in overlays {
            o.scene.snowDensity = amount.density
            o.scene.snowSpeed = amount.speed
            o.scene.snowBuildUp = amount.buildUp
            o.scene.giftLayer.isActive = giftsOn
        }
        updateGiftTimer()
        updateRunState()
    }

    // MARK: - Catch the Gift

    /// Gifts fall only in Catch the Gift mode, and never while the snow is paused.
    private var giftsOn: Bool { Settings.shared.mode == .catchGift && !Settings.shared.isPaused }

    private func updateGiftTimer() {
        if giftsOn {
            guard giftTimer == nil else { return }
            nextGiftAt = CACurrentMediaTime() + 2.5   // the first gift comes quickly
            let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.giftTick() }
            RunLoop.main.add(t, forMode: .common)
            giftTimer = t
        } else {
            giftTimer?.invalidate()
            giftTimer = nil
            updateMouseCapture()
        }
    }

    private func giftTick() {
        let now = CACurrentMediaTime()
        if now >= nextGiftAt {
            // Drop on one screen that's awake and showing, chosen at random.
            let ready = overlays.filter { !$0.view.isPaused && $0.window.isVisible }
            ready.randomElement()?.scene.dropGift()
            let wait = Double.random(in: 6...14) * (PowerMonitor.shared.shouldSaveEnergy ? 1.5 : 1)
            nextGiftAt = now + wait
        }
        // Gifts move under a still pointer, so keep checking whether one is there to click.
        if hover == .gift || overlays.contains(where: { $0.scene.giftLayer.hasGifts }) {
            updateMouseCapture()
        }
    }

    private func applyEnergySettings() {
        let save = PowerMonitor.shared.shouldSaveEnergy
        let snowOff = Settings.shared.isPaused
        for o in overlays {
            o.view.preferredFramesPerSecond = snowOff ? 15 : (save ? 20 : 30)
            o.scene.energySaving = save
            o.scene.giftLayer.energySaving = save
        }
    }

    // MARK: - Decorations

    private var hasVisibleDecorations: Bool {
        let store = DecorationStore.shared
        return !store.isHidden && !store.items.isEmpty
    }

    private func decorationsChanged() {
        overlays.forEach { $0.scene.decorationLayer.sync() }
        updateRunState()
        updateMouseCapture()
    }

    /// Clicks normally pass straight through Nook. Only while the pointer is over a decoration
    /// or a falling gift does that screen's layer catch the mouse, so you can grab or catch it.
    private func watchMouse() {
        let types: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseUp, .scrollWheel]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: types, handler: { [weak self] _ in self?.updateMouseCapture() }) {
            mouseMonitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseUp], handler: { [weak self] e in
            self?.updateMouseCapture(); return e
        }) {
            mouseMonitors.append(l)
        }
    }

    private func updateMouseCapture() {
        guard !DecorationInteraction.shared.isDragging else { return }
        let p = NSEvent.mouseLocation
        let overGift = giftsOn && overlays.contains {
            $0.screen.frame.contains(p) && $0.window.isVisible && $0.scene.giftHit(atGlobal: p)
        }
        let overDecoration = !overGift && hasVisibleDecorations && DecorationStore.shared.hitTest(p) != nil
        let over = overGift || overDecoration
        for o in overlays {
            let capture = over && o.screen.frame.contains(p) && o.window.isVisible
            if o.window.ignoresMouseEvents == capture { o.window.ignoresMouseEvents = !capture }
        }
        let now: Hover = overGift ? .gift : (overDecoration ? .decoration : .none)
        if now != hover {
            hover = now
            switch now {
            case .gift: NSCursor.pointingHand.set()
            case .decoration: NSCursor.openHand.set()
            case .none: NSCursor.arrow.set()
            }
        }
    }

    private func updateRunState() {
        let snowOff = Settings.shared.isPaused
        let awake = !screensAsleep && sessionActive
        let active = !snowOff && awake
        // With snow paused, Nook stays on screen only to show your decorations.
        let showWindows = !snowOff || hasVisibleDecorations
        var anyRunning = false

        for (i, o) in overlays.enumerated() {
            if !showWindows {
                o.window.orderOut(nil)
            } else if !o.window.isVisible {
                o.window.orderFrontRegardless()
            }
            o.scene.weatherVisible = !snowOff
            let visible = o.window.occlusionState.contains(.visible)
            let run = showWindows && awake && visible && !coveredScreens.contains(i)
            if o.view.isPaused == run { o.view.isPaused = !run }
            anyRunning = anyRunning || (run && !snowOff)
        }
        applyEnergySettings()

        if active {
            tracker.idle = !anyRunning
            tracker.start()
        } else {
            tracker.stop()
        }
    }

    // MARK: - WindowTrackerObserver

    func windowTracker(_ tracker: WindowTracker, didUpdate windows: [TrackedWindow], events: [WindowEvent]) {
        // Pause screens where a window fills the whole screen (games, borderless full-screen video).
        var covered = Set<Int>()
        for (i, o) in overlays.enumerated() {
            let sf = o.screen.frame
            if let front = windows.first(where: { sf.intersects($0.frame) }),
               abs(front.frame.minX - sf.minX) < 2, abs(front.frame.minY - sf.minY) < 2,
               abs(front.frame.width - sf.width) < 2, abs(front.frame.height - sf.height) < 2 {
                covered.insert(i)
            }
        }
        if covered != coveredScreens {
            coveredScreens = covered
            updateRunState()
        }

        dockRefreshCounter += 1
        if dockRefreshCounter % 40 == 0 { dockRect = DockInfo.dockRect() }

        let own = NSApp.windows.filter { $0.isVisible && !($0 is OverlayWindow) && $0.level.rawValue > Int(CGWindowLevelForKey(.desktopWindow)) }.map { $0.frame }
        for o in overlays {
            o.scene.ownWindowFrames = own
            o.scene.giftLayer.dockRect = dockRect.map { o.scene.toLocal($0) }
            o.scene.windowsDidUpdate(windows, events: events, dockRect: dockRect)
        }
    }
}

/// Lets the first click on a decoration work even though Nook isn't the active app.
final class OverlaySKView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
