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
    }
}
