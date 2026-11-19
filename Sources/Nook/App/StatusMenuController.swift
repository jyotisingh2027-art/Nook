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
        // A single eye; it gets a line through it while the snow is paused.
        let name = paused ? "eye.slash" : "eye"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Nook")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.appearsDisabled = paused
    }

    // Rebuild the menu each time it opens so check marks are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = Settings.shared

        let header = NSMenuItem(title: "Nook · Winter", action: nil, keyEquivalent: "")
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

        menu.addItem(.separator())

        let pause = NSMenuItem(title: settings.isPaused ? "Resume Snow" : "Pause Snow", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Nook", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
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

    @objc private func togglePause() { Settings.shared.isPaused.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }
}
