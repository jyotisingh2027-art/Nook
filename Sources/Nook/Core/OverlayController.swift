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

    private enum Hover { case none, decoration, gift, snowball, aiming }
    private var hover = Hover.none

    // Playful modes (Catch the Gift, Snowball Fight)
    private var modeTimer: Timer?
    private var timerMode: AppMode?
    private var nextSpawnAt: CFTimeInterval = 0
    private var wasAiming = false

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
            scene.snowballLayer.isActive = snowballsOn

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
        nc.addObserver(forName: GiftStats.gameOver, object: nil, queue: .main) { note in
            // Out of lives: stop the game and show the scores.
            Settings.shared.mode = .cozy
            if let result = note.object as? GiftStats.GameResult { GameOverController.shared.show(result) }
        }
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
            o.scene.snowballLayer.isActive = snowballsOn
            o.scene.giftLayer.isFrozen = Settings.shared.gamePaused
            o.scene.snowballLayer.isFrozen = Settings.shared.gamePaused
        }
        updateModeTimer()
        updateRunState()
    }

    // MARK: - Playful modes

    /// The playful modes run only while chosen, and never while the snow is paused.
    private var giftsOn: Bool { Settings.shared.mode == .catchGift && !Settings.shared.isPaused }
    private var snowballsOn: Bool { Settings.shared.mode == .snowballFight && !Settings.shared.isPaused }

    private func updateModeTimer() {
        let mode: AppMode? = giftsOn ? .catchGift : (snowballsOn ? .snowballFight : nil)
        guard mode != timerMode else { return }
        timerMode = mode
        // A new game of Catch the Gift starts with 3 lives. Pausing and resuming keeps the game going;
        // switching to another mode ends it.
        if Settings.shared.mode != .catchGift { GiftStats.shared.abandonGame() }
        let main = overlays.first { $0.screen == NSScreen.screens.first } ?? overlays.first
        for o in overlays { o.scene.giftLayer.hudVisible = o.scene === main?.scene }
        if mode == .catchGift && !GiftStats.shared.inGame {
            GiftStats.shared.startGame()
            main?.scene.giftLayer.announceStart()
        }
        modeTimer?.invalidate()
        modeTimer = nil
        guard let mode else { updateMouseCapture(); return }

        nextSpawnAt = CACurrentMediaTime() + (mode == .catchGift ? 2.5 : 3.5)   // the first one comes quickly
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.modeTick() }
        RunLoop.main.add(t, forMode: .common)
        modeTimer = t

        if mode == .snowballFight {
            // Remind people how to throw, on the screen with the menu bar.
            let main = overlays.first { $0.screen == NSScreen.screens.first } ?? overlays.first
            main?.scene.snowballLayer.showHint()
        }
    }

    private func modeTick() {
        let now = CACurrentMediaTime()
        if Settings.shared.gamePaused {
            // Nothing new appears while paused; push the next arrival back so it doesn't come instantly.
            nextSpawnAt = max(nextSpawnAt, now + 1.5)
            return
        }
        if now >= nextSpawnAt {
            // Something new appears on one screen that's awake and showing, chosen at random.
            let ready = overlays.filter { !$0.view.isPaused && $0.window.isVisible }
            let wait: Double
            if timerMode == .snowballFight {
                ready.randomElement()?.scene.snowballLayer.spawnSnowman()
                wait = Double.random(in: 4...9)
            } else {
                ready.randomElement()?.scene.dropGift()
                // Gifts come more often as your score climbs.
                wait = Double.random(in: 4.5...8) * max(0.28, pow(0.94, Double(GiftStats.shared.score)))
            }
            nextSpawnAt = now + wait * (PowerMonitor.shared.shouldSaveEnergy ? 1.5 : 1)
        }
        // Targets move under a still pointer, and Option can be pressed without moving the mouse,
        // so keep checking whether Nook should take the next click.
        let aiming = isAiming
        let busy = overlays.contains { $0.scene.giftLayer.hasGifts || $0.scene.snowballLayer.hasTargets }
        if busy || aiming != wasAiming || hover == .gift || hover == .snowball {
            updateMouseCapture()
        }
    }

    /// Holding Option in Snowball Fight turns the pointer into a crosshair that throws anywhere.
    private var isAiming: Bool { snowballsOn && NSEvent.modifierFlags.contains(.option) }

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
        let aiming = isAiming
        wasAiming = aiming
        let pointerScene = overlays.first { $0.screen.frame.contains(p) && $0.window.isVisible }?.scene
        let overGift = giftsOn && pointerScene?.giftHit(atGlobal: p) == true
        let overSnowball = snowballsOn && pointerScene?.snowballTargetHit(atGlobal: p) == true
        let overDecoration = !overGift && !overSnowball && !aiming
            && hasVisibleDecorations && DecorationStore.shared.hitTest(p) != nil
        let over = overGift || overSnowball || aiming || overDecoration
        for o in overlays {
            let capture = over && o.screen.frame.contains(p) && o.window.isVisible
            if o.window.ignoresMouseEvents == capture { o.window.ignoresMouseEvents = !capture }
        }
        let now: Hover = overGift ? .gift : overSnowball ? .snowball : aiming ? .aiming : overDecoration ? .decoration : .none
        if now != hover {
            hover = now
            switch now {
            case .gift: NSCursor.pointingHand.set()
            case .snowball, .aiming: NSCursor.crosshair.set()
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
            if snowballsOn { o.scene.snowballLayer.perches = perches(for: o, windows: windows) }
            o.scene.windowsDidUpdate(windows, events: events, dockRect: dockRect)
        }
    }

    // MARK: - Snowball Fight ledges

    /// Ledges on one screen where a snowman can stand: the tops of the front few windows,
    /// the Dock, and the bottom of the screen when the Dock isn't there.
    private func perches(for o: Overlay, windows: [TrackedWindow]) -> [CGRect] {
        let scene = o.scene
        let bounds = CGRect(origin: .zero, size: scene.size)
        var result: [CGRect] = []
        var dockAtBottom = false
        if let d = dockRect.map({ scene.toLocal($0) }), d.intersects(bounds) {
            result.append(CGRect(x: max(0, d.minX), y: d.maxY, width: min(bounds.maxX, d.maxX) - max(0, d.minX), height: 0))
            dockAtBottom = d.minY < 5 && d.width > d.height
        }
        if !dockAtBottom { result.append(CGRect(x: 0, y: 0, width: bounds.width, height: 0)) }

        var inFront: [CGRect] = []
        for w in windows.prefix(6) {
            let r = scene.toLocal(w.frame)
            defer { inFront.append(r) }
            // Skip windows tucked under the menu bar, too low to stand on, or mostly off screen.
            guard r.maxY > 60, r.maxY < scene.visibleTop - 120, r.width > 160 else { continue }
            let minX = max(0, r.minX), maxX = min(bounds.maxX, r.maxX)
            guard maxX - minX > 160 else { continue }
            // Skip a ledge whose middle is hidden behind a window in front of it.
            let mid = CGPoint(x: (minX + maxX) / 2, y: r.maxY + 4)
            if inFront.contains(where: { $0.contains(mid) }) { continue }
            result.append(CGRect(x: minX, y: r.maxY, width: maxX - minX, height: 0))
        }
        return result
    }
}

/// Lets the first click on a decoration work even though Nook isn't the active app.
final class OverlaySKView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
