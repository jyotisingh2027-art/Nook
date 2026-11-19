import AppKit
import UniformTypeIdentifiers

struct Wallpaper: Identifiable, Hashable {
    enum Kind: String { case image, video }

    let id: String
    let title: String
    let category: String
    let url: URL
    let kind: Kind
    let isCustom: Bool
}

/// Knows which wallpapers exist: the ones that ship with Nook, plus the user's own photos/videos.
final class WallpaperLibrary {
    static let shared = WallpaperLibrary()
    static let didChange = Notification.Name("NookWallpaperLibraryDidChange")

    static let mineCategory = "Mine"

    private(set) var builtIn: [Wallpaper] = []
    private(set) var custom: [Wallpaper] = []

    var all: [Wallpaper] { builtIn + custom }
    var categories: [String] {
        var seen: [String] = []
        for w in builtIn where !seen.contains(w.category) { seen.append(w.category) }
        if !custom.isEmpty { seen.append(WallpaperLibrary.mineCategory) }
        return seen
    }

    /// ~/Library/Application Support/Nook
    static var supportFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Nook", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var customFolder: URL {
        let url = WallpaperLibrary.supportFolder.appendingPathComponent("My Wallpapers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() { reload() }

    func wallpaper(id: String) -> Wallpaper? { all.first { $0.id == id } }

    func reload() {
        builtIn = loadBuiltIn()
        custom = loadCustom()
        NotificationCenter.default.post(name: WallpaperLibrary.didChange, object: self)
    }

    /// Built-in wallpapers live in the app under Resources/Wallpapers, described by catalog.json.
    private func loadBuiltIn() -> [Wallpaper] {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("Wallpapers"),
              let data = try? Data(contentsOf: folder.appendingPathComponent("catalog.json")),
              let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return [] }
        return entries.compactMap { e in
            guard let id = e["id"], let file = e["file"] else { return nil }
            let url = folder.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return Wallpaper(id: id, title: e["title"] ?? id, category: e["category"] ?? "Winter", url: url,
                             kind: Wallpaper.Kind(rawValue: e["kind"] ?? "") ?? .image, isCustom: false)
        }
    }

    private func loadCustom() -> [Wallpaper] {
        let files = (try? FileManager.default.contentsOfDirectory(at: customFolder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
            let kind: Wallpaper.Kind
            if type.conforms(to: .movie) { kind = .video } else if type.conforms(to: .image) { kind = .image } else { return nil }
            let title = url.deletingPathExtension().lastPathComponent
            return Wallpaper(id: "mine." + url.lastPathComponent, title: title, category: WallpaperLibrary.mineCategory,
                             url: url, kind: kind, isCustom: true)
        }
    }

    /// Copies a photo or video into Nook's own folder so it keeps working even if the original moves.
    func addCustom(from source: URL) -> Wallpaper? {
        var dest = customFolder.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = customFolder.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent) \(n).\(source.pathExtension)")
            n += 1
        }
        do { try FileManager.default.copyItem(at: source, to: dest) } catch { return nil }
        reload()
        return custom.first { $0.url.standardizedFileURL == dest.standardizedFileURL }
    }

    func removeCustom(_ w: Wallpaper) {
        guard w.isCustom else { return }
        try? FileManager.default.removeItem(at: w.url)
        reload()
    }
}
