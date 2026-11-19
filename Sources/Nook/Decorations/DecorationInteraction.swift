import AppKit

/// Handles clicking, dragging, scrolling and right-clicking on decorations.
final class DecorationInteraction {
    static let shared = DecorationInteraction()

    private(set) var isDragging = false
    private var dragPart: DecorationStore.Part = .body
    private var dragStart = CGPoint.zero
    private var original: PlacedDecoration?
    private var moved = false
    private var menuActions: [ClosureTarget] = []

    var onDragEnded: (() -> Void)?

    private var store: DecorationStore { .shared }

    func mouseDown(at p: CGPoint, event: NSEvent) {
        guard let hit = store.hitTest(p) else { return }
        store.selectedID = hit.id
        store.bringToFront(hit.id)
        moved = false
        original = store.items.first { $0.id == hit.id }
        dragPart = hit.part
        dragStart = p
        isDragging = true
        NSCursor.closedHand.set()
    }

    func mouseDragged(to p: CGPoint) {
        guard isDragging, var d = original else { return }
        if hypot(p.x - dragStart.x, p.y - dragStart.y) > 3 { moved = true }
        let dx = Double(p.x - dragStart.x), dy = Double(p.y - dragStart.y)
        switch dragPart {
        case .body:
            d.x += dx; d.y += dy; d.x2 += dx; d.y2 += dy
        case .end1:
            d.x += dx; d.y += dy
        case .end2:
            d.x2 += dx; d.y2 += dy
        }
        store.update(d, save: false)
    }

    func mouseUp() {
        guard isDragging else { return }
        isDragging = false
        original = nil
        store.saveNow()
        NSCursor.openHand.set()
        if !moved { DecorationEditorController.shared.show() }
        onDragEnded?()
    }

    func scroll(at p: CGPoint, event: NSEvent) {
        guard let hit = store.hitTest(p), var d = store.items.first(where: { $0.id == hit.id }) else { return }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.004 : event.scrollingDeltaY * 0.04
        if d.kind == .lights {
            d.sag = min(1, max(0, d.sag - Double(delta)))
        } else {
            d.scale = min(2.5, max(0.4, d.scale * (1 + Double(delta))))
        }
        store.update(d)
    }

    func rightMouseDown(at p: CGPoint, event: NSEvent, in view: NSView) {
        guard let hit = store.hitTest(p) else { return }
        let id = hit.id
        store.selectedID = id
        let menu = NSMenu()
        menuActions = []
        func add(_ title: String, _ action: @escaping () -> Void) {
            let target = ClosureTarget(action)
            menuActions.append(target)
            let item = NSMenuItem(title: title, action: #selector(ClosureTarget.run), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        add("Edit…") { DecorationEditorController.shared.show() }
        let isLights = store.items.first { $0.id == id }?.kind == .lights
        if !isLights {
            add("Make Bigger") { self.resize(id, by: 1.15) }
            add("Make Smaller") { self.resize(id, by: 1 / 1.15) }
        }
        add("Duplicate") { self.store.duplicate(id) }
        menu.addItem(.separator())
        add("Remove") { self.store.remove(id) }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private func resize(_ id: UUID, by f: Double) {
        guard var d = store.items.first(where: { $0.id == id }) else { return }
        d.scale = min(2.5, max(0.4, d.scale * f))
        store.update(d)
    }
}

/// Lets a menu item run a closure.
final class ClosureTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}
