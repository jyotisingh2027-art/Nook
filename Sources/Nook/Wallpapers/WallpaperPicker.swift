import AppKit
import SwiftUI
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// The "Choose Wallpaper" window.
final class WallpaperPickerController {
    static let shared = WallpaperPickerController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: WallpaperPickerView())
            let w = NSWindow(contentViewController: host)
            w.title = "Nook Wallpapers"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 820, height: 560))
            w.minSize = NSSize(width: 560, height: 400)
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static let didAddWallpaper = Notification.Name("NookDidAddWallpaper")

    func close() { window?.orderOut(nil) }

    /// Applies a wallpaper and closes the window.
    func apply(_ w: Wallpaper) {
        WallpaperManager.shared.apply(w)
        close()
    }

    /// Opens the picker and lets the user choose a photo or video from their Mac.
    /// It's added to "Mine" and selected, ready to apply.
    func showAndAddOwn() {
        show()
        DispatchQueue.main.async { WallpaperPickerController.addOwn() }
    }

    /// Lets the user pick a photo or video from their Mac and selects it in the picker.
    static func addOwn() {
        let panel = NSOpenPanel()
        panel.title = "Choose a photo or video for your wallpaper"
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let w = WallpaperLibrary.shared.addCustom(from: url) else { return }
        NotificationCenter.default.post(name: didAddWallpaper, object: w.id)
    }
}

/// Loads small preview images off the main thread and caches them.
final class ThumbnailCache: ObservableObject {
    static let shared = ThumbnailCache()
    @Published private(set) var images: [String: NSImage] = [:]
    private var loading = Set<String>()

    func image(for w: Wallpaper) -> NSImage? {
        if let img = images[w.id] { return img }
        guard !loading.contains(w.id) else { return nil }
        loading.insert(w.id)
        DispatchQueue.global(qos: .userInitiated).async {
            let cg = ThumbnailCache.makeThumbnail(w)
            DispatchQueue.main.async {
                if let cg { self.images[w.id] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
            }
        }
        return nil
    }

    private static func makeThumbnail(_ w: Wallpaper) -> CGImage? {
        if w.kind == .video {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: w.url))
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 520, height: 520)
            return try? gen.copyCGImage(at: CMTime(seconds: 0.5, preferredTimescale: 600), actualTime: nil)
        }
        guard let src = CGImageSourceCreateWithURL(w.url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: 520,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

struct WallpaperPickerView: View {
    private static let recentTab = "Recent"
    private static let allTab = "All"

    @ObservedObject private var thumbs = ThumbnailCache.shared
    @State private var category = WallpaperPickerView.allTab
    @State private var currentID = WallpaperManager.shared.currentID
    @State private var selectedID = WallpaperManager.shared.currentID
    @State private var recentIDs = WallpaperManager.shared.recentIDs
    @State private var library = WallpaperLibrary.shared.all
    @State private var categories = WallpaperLibrary.shared.categories

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]

    private var shown: [Wallpaper] {
        switch category {
        case Self.allTab: return library
        case Self.recentTab: return recentIDs.compactMap { id in library.first { $0.id == id } }
        default: return library.filter { $0.category == category }
        }
    }

    private var selected: Wallpaper? { selectedID.flatMap { id in library.first { $0.id == id } } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $category) {
                    Text(Self.recentTab).tag(Self.recentTab)
                    Text(Self.allTab).tag(Self.allTab)
                    ForEach(categories, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 600)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 36)
            .padding(.bottom, 12)

            if shown.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: category == Self.recentTab ? "clock.arrow.circlepath" : "photo.on.rectangle.angled")
                        .font(.system(size: 40)).foregroundStyle(.secondary)
                    Text(category == Self.recentTab ? "No recent wallpapers yet" : "No wallpapers here yet").font(.headline)
                    Text(category == Self.recentTab
                         ? "Every wallpaper you apply will appear here, so you can find it again quickly."
                         : "You can add your own photo or video below.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(shown) { w in tile(w) }
                    }
                    .padding(20)
                }
            }

            Divider()
            HStack(spacing: 12) {
                Button("Add My Own Photo or Video…") { WallpaperPickerController.addOwn() }
                Button("Restore My Original Wallpaper") { WallpaperManager.shared.restoreOriginal() }
                    .disabled(currentID == nil)
                Spacer()
                if let s = selected {
                    Text(s.title).foregroundStyle(.secondary).lineLimit(1)
                }
                Button(selectedID != nil && selectedID == currentID ? "Applied" : "Apply") {
                    if let s = selected { WallpaperPickerController.shared.apply(s) }
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(selected == nil || selectedID == currentID)
            }
            .padding(16)
        }
        .onReceive(NotificationCenter.default.publisher(for: WallpaperManager.didChange)) { _ in
            currentID = WallpaperManager.shared.currentID
            recentIDs = WallpaperManager.shared.recentIDs
        }
        .onReceive(NotificationCenter.default.publisher(for: WallpaperLibrary.didChange)) { _ in
            library = WallpaperLibrary.shared.all
            categories = WallpaperLibrary.shared.categories
            recentIDs = WallpaperManager.shared.recentIDs
            if let id = selectedID, !library.contains(where: { $0.id == id }) { selectedID = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: WallpaperPickerController.didAddWallpaper)) { note in
            category = WallpaperLibrary.mineCategory
            selectedID = note.object as? String
        }
    }

    @ViewBuilder private func tile(_ w: Wallpaper) -> some View {
        let isSelected = w.id == selectedID
        let isApplied = w.id == currentID
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let img = thumbs.image(for: w) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(Color.secondary.opacity(0.15))
                    }
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isSelected ? 3 : 1))

                HStack(spacing: 4) {
                    if w.kind == .video { badge("play.fill") }
                    if isApplied { badge("checkmark") }
                }
                .padding(8)
            }
            HStack {
                Text(w.title).font(.callout.weight(.medium)).lineLimit(1)
                Spacer()
                if w.isCustom {
                    Button {
                        if isApplied { WallpaperManager.shared.restoreOriginal() }
                        WallpaperLibrary.shared.removeCustom(w)
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Remove from Nook")
                }
            }
        }
        .contentShape(Rectangle())
        // Click to select; double-click applies straight away.
        .onTapGesture(count: 2) { selectedID = w.id; WallpaperPickerController.shared.apply(w) }
        .onTapGesture { selectedID = w.id }
    }

    private func badge(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(6)
            .background(Circle().fill(Color.black.opacity(0.55)))
    }
}
