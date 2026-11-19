import AppKit
import AVFoundation

/// Applies wallpapers to every screen, remembers the user's original wallpaper so it can be
/// restored, and keeps Nook's wallpaper in place when you switch Spaces.
/// Setting the desktop picture needs no permission.
final class WallpaperManager {
    static let shared = WallpaperManager()
    static let didChange = Notification.Name("NookWallpaperDidChange")

    private let defaults = UserDefaults.standard
    private var video: VideoWallpaper?

    /// The wallpaper Nook is currently showing, if any.
    var currentID: String? {
        get { defaults.string(forKey: "wallpaperID") }
        set { defaults.set(newValue, forKey: "wallpaperID") }
    }

    private var originals: [String: String] {
        get { defaults.dictionary(forKey: "originalWallpapers") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "originalWallpapers") }
    }

    var hasOriginalSaved: Bool { !originals.isEmpty }

    /// Wallpapers that have been applied at least once, most recent first.
    var recentIDs: [String] {
        get { (defaults.stringArray(forKey: "recentWallpapers") ?? []).filter { WallpaperLibrary.shared.wallpaper(id: $0) != nil } }
        set { defaults.set(Array(newValue.prefix(30)), forKey: "recentWallpapers") }
    }

    func start() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reapplyIfNeeded()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.reapplyIfNeeded() }
        }
        // Restore the moving wallpaper after a restart.
        if let id = currentID, let w = WallpaperLibrary.shared.wallpaper(id: id) {
            if w.kind == .video { startVideo(w) }
            reapplyIfNeeded()
        }
    }

    func apply(_ w: Wallpaper) {
        saveOriginalsIfNeeded()
        video?.stop()
        video = nil
        currentID = w.id
        recentIDs = [w.id] + recentIDs.filter { $0 != w.id }
        if w.kind == .video { startVideo(w) }
        reapplyIfNeeded(force: true)
        NotificationCenter.default.post(name: WallpaperManager.didChange, object: self)
    }

    func restoreOriginal() {
        video?.stop()
        video = nil
        let saved = originals
        for screen in NSScreen.screens {
            if let path = saved[key(for: screen)] ?? saved.values.first {
                try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
            }
        }
        originals = [:]
        currentID = nil
        NotificationCenter.default.post(name: WallpaperManager.didChange, object: self)
    }

    // MARK: - Internals

    private func key(for screen: NSScreen) -> String {
        let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return n.map { "\($0)" } ?? screen.localizedName
    }

    private func saveOriginalsIfNeeded() {
        guard originals.isEmpty else { return }
        var saved: [String: String] = [:]
        for screen in NSScreen.screens {
            if let url = NSWorkspace.shared.desktopImageURL(for: screen) { saved[key(for: screen)] = url.path }
        }
        originals = saved
    }

    /// The still image to use as the desktop picture (for videos, a frame from the video).
    private func stillImageURL(for w: Wallpaper) -> URL? {
        if w.kind == .image { return appliedCopy(of: w) }
        let folder = WallpaperLibrary.supportFolder.appendingPathComponent("Video Stills", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let still = folder.appendingPathComponent(w.id.replacingOccurrences(of: "/", with: "_") + ".jpg")
        if FileManager.default.fileExists(atPath: still.path) { return still }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: w.url))
        gen.appliesPreferredTrackTransform = true
        guard let cg = try? gen.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil),
              let data = NSBitmapImageRep(cgImage: cg).representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { return nil }
        try? data.write(to: still)
        return still
    }

    /// macOS remembers desktop pictures by file location, so an updated image at the same place can
    /// keep showing the old version. Nook applies a copy whose name changes whenever the image changes.
    private func appliedCopy(of w: Wallpaper) -> URL {
        let folder = WallpaperLibrary.supportFolder.appendingPathComponent("Applied", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let attrs = try? FileManager.default.attributesOfItem(atPath: w.url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        let stamp = Int((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        let safeID = w.id.replacingOccurrences(of: "/", with: "_")
        let dest = folder.appendingPathComponent("\(safeID)-\(size)-\(stamp).\(w.url.pathExtension)")
        if !FileManager.default.fileExists(atPath: dest.path) {
            // Remove older copies of anything except the new one.
            for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: old)
            }
            guard (try? FileManager.default.copyItem(at: w.url, to: dest)) != nil else { return w.url }
        }
        return dest
    }

    private func reapplyIfNeeded(force: Bool = false) {
        guard let id = currentID, let w = WallpaperLibrary.shared.wallpaper(id: id), let url = stillImageURL(for: w) else { return }
        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true
        ]
        for screen in NSScreen.screens {
            if !force, NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL == url.standardizedFileURL { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }

    private func startVideo(_ w: Wallpaper) {
        video?.stop()
        video = VideoWallpaper(url: w.url)
    }
}
