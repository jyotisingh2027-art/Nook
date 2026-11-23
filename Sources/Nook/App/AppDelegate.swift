import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayController!
    private var statusMenu: StatusMenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        PowerMonitor.shared.start()
        WallpaperManager.shared.start()
        overlay = OverlayController(season: WinterSeason())
        overlay.start()
        statusMenu = StatusMenuController(overlay: overlay)
        watchDeleteKey()
    }

    /// Pressing Delete (or Fn-Delete) removes the selected decoration, unless you're typing in a field.
    private func watchDeleteKey() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let deleteKeys: Set<UInt16> = [51, 117]
            guard deleteKeys.contains(event.keyCode),
                  let id = DecorationStore.shared.selectedID,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return event }
            DecorationStore.shared.remove(id)
            return nil
        }
    }
}
