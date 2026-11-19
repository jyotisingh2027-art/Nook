import AppKit

/// Estimates where the Dock is. macOS doesn't report the Dock's exact width without an
/// Accessibility permission, so we estimate it from the Dock's own settings instead.
enum DockInfo {
    /// The Dock's shelf in AppKit global coordinates, or nil if hidden / not at the bottom.
    static func dockRect() -> CGRect? {
        let prefs = UserDefaults(suiteName: "com.apple.dock")
        if prefs?.bool(forKey: "autohide") == true { return nil }
        let orientation = prefs?.string(forKey: "orientation") ?? "bottom"
        guard orientation == "bottom" else { return nil }

        // The screen that has space reserved at the bottom is the one showing the Dock.
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.minY - $0.frame.minY > 8 }) else { return nil }
        let inset = screen.visibleFrame.minY - screen.frame.minY

        let tile = CGFloat(prefs?.double(forKey: "tilesize") ?? 0).nonZero ?? 48
        let pinned = prefs?.array(forKey: "persistent-apps") as? [[String: Any]] ?? []
        let others = prefs?.array(forKey: "persistent-others")?.count ?? 0
        let showRecents = prefs?.object(forKey: "show-recents") as? Bool ?? true
        let recents = showRecents ? min(prefs?.array(forKey: "recent-apps")?.count ?? 0, 3) : 0

        let pinnedIDs = Set(pinned.compactMap { item -> String? in
            (item["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
        })
        let runningUnpinned = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular
                && $0.bundleIdentifier != "com.apple.finder"
                && !pinnedIDs.contains($0.bundleIdentifier ?? "")
        }.count
        let extraApps = showRecents ? max(runningUnpinned, 0) : runningUnpinned
        let items = 1 + pinned.count + max(extraApps, recents) + others + 1   // Finder ... Trash
        let separators: CGFloat = (recents > 0 || runningUnpinned > 0) ? 2 : 1

        let slot = tile * 1.08
        var width = CGFloat(items) * slot + separators * tile * 0.45 + tile * 0.55
        width = min(width, screen.frame.width - 8)

        let top = screen.frame.minY + inset - 2
        let height = max(inset - 6, tile)
        return CGRect(x: screen.frame.midX - width / 2, y: top - height, width: width, height: height)
    }
}

private extension CGFloat {
    var nonZero: CGFloat? { self > 0 ? self : nil }
}
