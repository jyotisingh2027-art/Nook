import AppKit

/// Holds every decoration, saves them to this Mac, and answers "is there a decoration under the mouse?".
final class DecorationStore: ObservableObject {
    static let shared = DecorationStore()
    static let didChange = Notification.Name("NookDecorationsDidChange")

    @Published private(set) var items: [PlacedDecoration] = []   // back-to-front
    @Published var selectedID: UUID? { didSet { if oldValue != selectedID { notify() } } }
    @Published private(set) var unlocked: Set<String> = []
    @Published var isHidden: Bool = UserDefaults.standard.bool(forKey: "decorationsHidden") {
        didSet { UserDefaults.standard.set(isHidden, forKey: "decorationsHidden"); notify() }
    }

    private var saveWork: DispatchWorkItem?
    /// Turned off only by the developer preview so it never touches your saved decorations.
    static var persistenceEnabled = true

    private var fileURL: URL { WallpaperLibrary.supportFolder.appendingPathComponent("decorations.json") }

    private init() {
        unlocked = Set(UserDefaults.standard.stringArray(forKey: "unlockedDecorations") ?? [])
        load()
    }

    var selected: PlacedDecoration? { items.first { $0.id == selectedID } }

    func isUnlocked(_ kind: DecorationKind) -> Bool { !kind.lockedByDefault || unlocked.contains(kind.rawValue) }

    /// Used by Catch the Gift to reveal a new extra.
    func unlock(_ kind: DecorationKind) {
        unlocked.insert(kind.rawValue)
        UserDefaults.standard.set(Array(unlocked), forKey: "unlockedDecorations")
        notify()
    }

    // MARK: - Editing

    /// Puts a decoration that was designed in the panel onto the desktop.
    @discardableResult
    func place(_ draft: PlacedDecoration) -> PlacedDecoration {
        var d = add(draft.kind, select: false)
        d.options = draft.options
        d.sag = draft.sag
        update(d)
        selectedID = d.id
        return d
    }

    @discardableResult
    func add(_ kind: DecorationKind, select: Bool = true) -> PlacedDecoration {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let offset = Double((items.count % 6) - 3) * 70
        var d = PlacedDecoration(kind: kind, x: vf.midX + offset, y: vf.minY + 12)
        if kind == .lights {
            d.x = vf.midX - 220 + offset; d.y = vf.maxY - 140
            d.x2 = vf.midX + 220 + offset; d.y2 = vf.maxY - 140
        } else if kind == .wreath || kind == .bells || kind == .star || kind == .ornament || kind == .mistletoe {
            d.y = vf.midY + 120   // things you'd hang up start higher
        }
        items.append(d)
        if select { selectedID = d.id }
        changed()
        return d
    }

    func update(_ d: PlacedDecoration, save: Bool = true) {
        guard let i = items.firstIndex(where: { $0.id == d.id }) else { return }
        items[i] = d
        if save { changed() } else { notify() }
    }

    func setOption(_ key: String, _ value: String, for id: UUID) {
        guard var d = items.first(where: { $0.id == id }) else { return }
        d.options[key] = value
        update(d)
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        changed()
    }

    func removeAll() {
        items.removeAll()
        selectedID = nil
        changed()
    }

    func duplicate(_ id: UUID) {
        guard var d = items.first(where: { $0.id == id }) else { return }
        d.id = UUID()
        d.x += 40; d.x2 += 40
        d.seed = UInt64.random(in: 1...UInt64.max)
        items.append(d)
        selectedID = d.id
        changed()
    }

    func bringToFront(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }), i != items.count - 1 else { return }
        let d = items.remove(at: i)
        items.append(d)
        notify()
    }

    // MARK: - Hit testing (global coordinates)

    enum Part { case body, end1, end2 }

    func hitTest(_ p: CGPoint) -> (id: UUID, part: Part)? {
        guard !isHidden else { return nil }
        for d in items.reversed() {
            if d.kind == .lights {
                if hypot(p.x - d.x, p.y - d.y) < 16 { return (d.id, .end1) }
                if hypot(p.x - d.x2, p.y - d.y2) < 16 { return (d.id, .end2) }
                if StringLightsGeometry.distance(from: p, to: d) < 9 { return (d.id, .body) }
                continue
            }
            let r = DecorationRenderer.shared.render(d)
            let frame = CGRect(x: d.x - r.size.width / 2, y: d.y, width: r.size.width, height: r.size.height)
            guard frame.contains(p) else { continue }
            if r.isSolid(at: CGPoint(x: p.x - frame.minX, y: p.y - frame.minY)) { return (d.id, .body) }
        }
        return nil
    }

    // MARK: - Saving

    private func notify() {
        NotificationCenter.default.post(name: DecorationStore.didChange, object: self)
    }

    private func changed() {
        notify()
        guard DecorationStore.persistenceEnabled else { return }
        saveWork?.cancel()
        let items = self.items
        let url = fileURL
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(items) { try? data.write(to: url, options: .atomic) }
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() { changed() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              var list = try? JSONDecoder().decode([PlacedDecoration].self, from: data) else { return }
        // Bring back anything left on a screen that's no longer connected.
        let screens = NSScreen.screens.map { $0.frame }
        if let main = NSScreen.screens.first?.visibleFrame {
            for i in list.indices where !screens.contains(where: { $0.insetBy(dx: -20, dy: -20).contains(list[i].point) }) {
                let dx = main.midX - list[i].x, dy = main.minY + 12 - list[i].y
                list[i].x += dx; list[i].y += dy; list[i].x2 += dx; list[i].y2 += dy
            }
        }
        items = list
    }
}

enum StringLightsGeometry {
    /// Points along the hanging wire, in the same coordinates as the decoration's ends.
    static func points(_ d: PlacedDecoration, count: Int = 40) -> [CGPoint] {
        let a = d.point, b = d.point2
        let len = hypot(b.x - a.x, b.y - a.y)
        let dip = len * CGFloat(d.sag) * 0.5
        return (0...count).map { i in
            let t = CGFloat(i) / CGFloat(count)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t - dip * 4 * t * (1 - t))
        }
    }

    static func distance(from p: CGPoint, to d: PlacedDecoration) -> CGFloat {
        let pts = points(d)
        var best = CGFloat.greatestFiniteMagnitude
        for (a, b) in zip(pts, pts.dropFirst()) {
            let ab = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let l2 = max(ab.x * ab.x + ab.y * ab.y, 0.001)
            let t = max(0, min(1, ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / l2))
            best = min(best, hypot(p.x - (a.x + ab.x * t), p.y - (a.y + ab.y * t)))
        }
        return best
    }
}
