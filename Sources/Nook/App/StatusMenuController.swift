import AppKit

/// The snowflake icon in the menu bar and its menu.
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let overlay: OverlayController
    private let menu = NSMenu()

    init(overlay: OverlayController) {
        self.overlay = overlay
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        NotificationCenter.default.addObserver(forName: Settings.didChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateIcon()
        }
    }

    private func updateIcon() {
        let paused = Settings.shared.isPaused
        // The two eyes from the Nook logo; they close while Nook is paused.
        statusItem.button?.image = Self.logoEyes(closed: paused)
        statusItem.button?.appearsDisabled = paused
    }

    /// The two "OO" eyeballs from the Nook logo. When paused, the eyes are closed.
    static func logoEyes(closed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 31, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            for cx in [8.0, 23.0] as [CGFloat] {
                let cy: CGFloat = 9
                if closed {
                    // A sleepy closed eye: a soft downward curve.
                    let lid = NSBezierPath()
                    lid.move(to: NSPoint(x: cx - 6, y: cy + 1))
                    lid.curve(to: NSPoint(x: cx + 6, y: cy + 1),
                              controlPoint1: NSPoint(x: cx - 3, y: cy - 4.5), controlPoint2: NSPoint(x: cx + 3, y: cy - 4.5))
                    lid.lineWidth = 2.4
                    lid.lineCapStyle = .round
                    lid.stroke()
                    continue
                }
                // The "O": a thick ring, heavier at the bottom-left, like the logo.
                let ring = NSBezierPath(ovalIn: NSRect(x: cx - 7.3, y: cy - 7, width: 14.6, height: 14))
                ring.append(NSBezierPath(ovalIn: NSRect(x: cx - 3.9, y: cy - 3.6, width: 9, height: 9)))
                ring.windingRule = .evenOdd
                ring.fill()
                // The little shine in the upper right.
                NSBezierPath(ovalIn: NSRect(x: cx + 1.9, y: cy + 1.9, width: 3.6, height: 3.6)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Nook"
        return image
    }

    // Rebuild the menu each time it opens so check marks are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = Settings.shared

        let header = NSMenuItem(title: settings.mode == .cozy ? "Nook · Winter" : "Nook · Winter · \(settings.mode.title)",
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Mode
        let modeItem = NSMenuItem(title: "Mode", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in AppMode.allCases {
            let title = mode.isAvailable ? mode.title : "\(mode.title) (coming soon)"
            let item = NSMenuItem(title: title, action: mode.isAvailable ? #selector(pickMode(_:)) : nil, keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = settings.mode == mode ? .on : .off
            item.isEnabled = mode.isAvailable
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        // Catch the Gift score
        if settings.mode == .catchGift {
            let stats = GiftStats.shared
            var lines = ["Gifts caught: \(stats.caught)   ·   Best streak: \(stats.bestStreak)"]
            if let left = stats.catchesToNextUnlock {
                lines.append(left == 1 ? "Next surprise: 1 more catch" : "Next surprise: \(left) more catches")
            } else {
                lines.append("Every surprise unlocked!")
            }
            if settings.isPaused { lines.append("Resume the snow to keep playing") }
            addInfo(lines, to: menu)
        }

        // Snowball Fight score and controls
        if settings.mode == .snowballFight {
            let stats = SnowballStats.shared
            var lines = [
                "Snowmen bonked: \(stats.bonked)   ·   Blocked: \(stats.blocked)   ·   Splats taken: \(stats.splatted)",
                "Click a snowman to throw. Hold ⌥ Option and click to throw anywhere.",
                "Click an incoming snowball to swat it away."
            ]
            if settings.isPaused { lines.append("Resume the snow to keep playing") }
            addInfo(lines, to: menu)
        }

        // Wallpaper
        let wallItem = NSMenuItem(title: "Wallpaper", action: nil, keyEquivalent: "")
        let wallMenu = NSMenu()
        let choose = NSMenuItem(title: "Choose Wallpaper…", action: #selector(chooseWallpaper), keyEquivalent: "")
        choose.target = self
        wallMenu.addItem(choose)
        let own = NSMenuItem(title: "Use My Own Photo or Video…", action: #selector(addOwnWallpaper), keyEquivalent: "")
        own.target = self
        wallMenu.addItem(own)
        wallMenu.addItem(.separator())
        let restore = NSMenuItem(title: "Restore My Original Wallpaper", action: #selector(restoreWallpaper), keyEquivalent: "")
        restore.target = self
        restore.isEnabled = WallpaperManager.shared.currentID != nil
        wallMenu.addItem(restore)
        wallItem.submenu = wallMenu
        menu.addItem(wallItem)

        // Decorations
        let decoItem = NSMenuItem(title: "Decorations", action: nil, keyEquivalent: "")
        let decoMenu = NSMenu()
        let openPanel = NSMenuItem(title: "Open Decorations Panel…", action: #selector(openDecorations), keyEquivalent: "")
        openPanel.target = self
        decoMenu.addItem(openPanel)
        decoMenu.addItem(.separator())
        let store = DecorationStore.shared
        for kind in DecorationKind.allCases where kind.group == .builders {
            decoMenu.addItem(addItem(kind))
        }
        let moreItem = NSMenuItem(title: "Add Decoration", action: nil, keyEquivalent: "")
        let moreMenu = NSMenu()
        for kind in DecorationKind.allCases where kind.group != .builders {
            let item = addItem(kind)
            if !store.isUnlocked(kind) {
                item.title = "\(kind.title) (locked)"
                item.action = nil
                item.isEnabled = false
            }
            moreMenu.addItem(item)
        }
        moreItem.submenu = moreMenu
        decoMenu.addItem(moreItem)
        decoMenu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Decorations", action: #selector(toggleDecorations), keyEquivalent: "")
        hide.target = self
        hide.state = store.isHidden ? .on : .off
        decoMenu.addItem(hide)
        let removeAll = NSMenuItem(title: "Remove All Decorations…", action: #selector(removeAllDecorations), keyEquivalent: "")
        removeAll.target = self
        removeAll.isEnabled = !store.items.isEmpty
        decoMenu.addItem(removeAll)
        decoItem.submenu = decoMenu
        menu.addItem(decoItem)

        // Snow amount
        let amountItem = NSMenuItem(title: "Snow Amount", action: nil, keyEquivalent: "")
        let amountMenu = NSMenu()
        for amount in SnowAmount.allCases {
            let item = NSMenuItem(title: amount.title, action: #selector(pickAmount(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = amount.rawValue
            item.state = settings.snowAmount == amount ? .on : .off
            amountMenu.addItem(item)
        }
        amountItem.submenu = amountMenu
        menu.addItem(amountItem)

        let clear = NSMenuItem(title: "Brush Snow Off Windows", action: #selector(clearSnow), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !settings.isPaused
        menu.addItem(clear)

        let visitors = NSMenuItem(title: "Winter Visitors (reindeer, bunnies, snow shoveller)", action: #selector(toggleVisitors), keyEquivalent: "")
        visitors.target = self
        visitors.state = settings.visitorsOn ? .on : .off
        menu.addItem(visitors)

        menu.addItem(.separator())

        let pause = NSMenuItem(title: settings.isPaused ? "Resume Snow" : "Pause Snow", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Nook", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    /// Grey, non-clickable lines that show a mode's score and controls.
    private func addInfo(_ lines: [String], to menu: NSMenu) {
        for line in lines {
            let info = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            info.isEnabled = false
            info.indentationLevel = 1
            menu.addItem(info)
        }
    }

    @objc private func pickMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = AppMode(rawValue: raw) else { return }
        Settings.shared.mode = mode
    }

    @objc private func pickAmount(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let amount = SnowAmount(rawValue: raw) else { return }
        Settings.shared.snowAmount = amount
    }

    private func addItem(_ kind: DecorationKind) -> NSMenuItem {
        let item = NSMenuItem(title: "Add \(kind.title)", action: #selector(addDecoration(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = kind.rawValue
        item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func openDecorations() { DecorationEditorController.shared.show() }

    @objc private func addDecoration(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let kind = DecorationKind(rawValue: raw) else { return }
        DecorationStore.shared.add(kind)
        DecorationEditorController.shared.show()
    }

    @objc private func toggleDecorations() { DecorationStore.shared.isHidden.toggle() }

    @objc private func removeAllDecorations() {
        let alert = NSAlert()
        alert.messageText = "Remove every decoration?"
        alert.informativeText = "This takes all \(DecorationStore.shared.items.count) decorations off your desktop. It can't be undone."
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { DecorationStore.shared.removeAll() }
    }

    @objc private func chooseWallpaper() { WallpaperPickerController.shared.show() }

    @objc private func addOwnWallpaper() { WallpaperPickerController.shared.showAndAddOwn() }

    @objc private func restoreWallpaper() { WallpaperManager.shared.restoreOriginal() }

    @objc private func clearSnow() { overlay.brushAllSnowOff() }
    @objc private func toggleVisitors() { Settings.shared.visitorsOn.toggle() }

    @objc private func togglePause() { Settings.shared.isPaused.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }
}
