import AppKit
import SwiftUI

/// The floating "Decorations" panel.
final class DecorationEditorController: NSObject, NSWindowDelegate {
    static let shared = DecorationEditorController()
    static let visibilityChanged = Notification.Name("NookDecorationEditorVisibility")
    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil {
            let host = NSHostingController(rootView: DecorationEditorView())
            let p = NSPanel(contentViewController: host)
            p.title = "Decorations"
            p.styleMask = [.titled, .closable, .utilityWindow, .resizable]
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.level = .floating
            p.setContentSize(NSSize(width: 380, height: 660))
            p.minSize = NSSize(width: 340, height: 420)
            p.isReleasedWhenClosed = false
            p.delegate = self
            if let screen = NSScreen.main {
                p.setFrameTopLeftPoint(NSPoint(x: screen.visibleFrame.maxX - 400, y: screen.visibleFrame.maxY - 20))
            }
            panel = p
        }
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: DecorationEditorController.visibilityChanged, object: nil)
    }

    func close() { panel?.close() }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: DecorationEditorController.visibilityChanged, object: nil)
        }
    }
}

struct DecorationEditorView: View {
    enum Page: Equatable { case home, pickBase(DecorationKind), customize }
    enum Step: String, CaseIterable { case base = "Base", decorate = "Decorate", size = "Size" }

    @ObservedObject private var store = DecorationStore.shared
    @State private var page: Page
    @State private var step: Step = .decorate
    /// A decoration being designed in the panel; it goes on the desktop at the Size step.
    @State private var draft: PlacedDecoration?
    @State private var confirmRemoveAll = false

    init(previewPage: Page? = nil, previewDraft: PlacedDecoration? = nil, previewStep: Step = .decorate) {
        _page = State(initialValue: previewPage ?? (DecorationStore.shared.selectedID == nil ? .home : .customize))
        _draft = State(initialValue: previewDraft)
        _step = State(initialValue: previewStep)
    }

    /// What the panel is editing: the draft, or the decoration selected on the desktop.
    private var target: PlacedDecoration? { draft ?? store.selected }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Group {
                    switch page {
                    case .home: home
                    case .pickBase(let kind): pickBase(kind)
                    case .customize: customize
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .onChange(of: store.selectedID) { id in
            withAnimation(.easeInOut(duration: 0.15)) {
                if let id, draft == nil || draft?.id != id {
                    // Clicked a decoration on the desktop: edit that one.
                    draft = nil
                    page = .customize
                    if step == .size && store.selected?.kind != nil { step = .size } else { step = .decorate }
                } else if id == nil && draft == nil && page == .customize {
                    page = .home
                }
            }
        }
        .alert("Remove every decoration?", isPresented: $confirmRemoveAll) {
            Button("Remove All", role: .destructive) { store.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This takes all \(store.items.count) decorations off your desktop. It can't be undone.")
        }
    }

    // MARK: Home

    private var home: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(DecorationKind.Group.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.rawValue).font(.headline)
                    if group == .extras {
                        Text("Catch falling gifts in Catch the Gift to unlock these.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: group == .builders ? 100 : 88), spacing: 10)], spacing: 10) {
                        ForEach(DecorationKind.allCases.filter { $0.group == group }, id: \.self) { kind in
                            homeTile(kind, large: group == .builders)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func homeTile(_ kind: DecorationKind, large: Bool) -> some View {
        let unlocked = store.isUnlocked(kind)
        Button {
            guard unlocked else { return }
            start(kind)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    if unlocked {
                        picture(DecorationThumbnails.image(kind: kind, options: showcase(kind)))
                    } else {
                        Image(systemName: "gift.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.35))
                        Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                            .offset(x: 16, y: 14)
                    }
                }
                .frame(height: large ? 96 : 72)
                tileLabel(unlocked ? kind.title : "Mystery", dim: !unlocked)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(tileBackground(selected: false))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .help(unlocked ? kind.title : "Unlock by catching a gift in Catch the Gift")
    }

    /// A nicely decorated example for the home tiles.
    private func showcase(_ kind: DecorationKind) -> [String: String] {
        switch kind {
        case .tree: return ["topper": "star", "baubles": "mixed", "lights": "warm", "garland": "gold"]
        case .snowman: return ["hat": "topHat", "scarf": "red"]
        default: return [:]
        }
    }

    private func start(_ kind: DecorationKind) {
        withAnimation(.easeInOut(duration: 0.15)) {
            store.selectedID = nil
            if kind.baseVariants.count > 1 {
                page = .pickBase(kind)
            } else {
                beginDraft(kind, base: [:])
            }
        }
    }

    /// Starts designing: the plain object with no add-ons yet.
    private func beginDraft(_ kind: DecorationKind, base: [String: String]) {
        var d = PlacedDecoration(kind: kind, x: 0, y: 0)
        var options = base
        for opt in kind.addOnOptions {
            if let none = opt.choices.first(where: { $0.value == "none" || $0.value == "off" }) { options[opt.key] = none.value }
        }
        d.options = options
        if kind.addOnOptions.isEmpty {
            draft = d
            placeDraft()
        } else {
            draft = d
            step = .decorate
            page = .customize
        }
    }

    // MARK: Step 1 — plain base

    private func pickBase(_ kind: DecorationKind) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            backButton("All Decorations") { page = .home }
            stepHeader(current: .base)
            Text("Choose your \(kind.title.lowercased())").font(.title3.weight(.semibold))
            Text("Start with a plain one — you'll add the decorations next.")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                ForEach(Array(kind.baseVariants.enumerated()), id: \.offset) { _, base in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { beginDraft(kind, base: base) }
                    } label: {
                        VStack(spacing: 6) {
                            picture(DecorationThumbnails.image(kind: kind, options: plain(kind, base)))
                                .frame(height: 104)
                            tileLabel(kind.variantName(base))
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(tileBackground(selected: false))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func plain(_ kind: DecorationKind, _ base: [String: String]) -> [String: String] {
        var o = base
        for opt in kind.addOnOptions {
            if let none = opt.choices.first(where: { $0.value == "none" || $0.value == "off" }) { o[opt.key] = none.value }
        }
        return o
    }

    // MARK: Steps 2 & 3 — decorate and size

    @ViewBuilder private var customize: some View {
        if let d = target {
            VStack(alignment: .leading, spacing: 16) {
                backButton("All Decorations") { draft = nil; store.selectedID = nil; page = .home }
                stepHeader(current: step, placed: draft == nil)

                // Big live preview while designing; once placed, your desktop is the preview.
                HStack(spacing: 12) {
                    picture(DecorationThumbnails.image(kind: d.kind, options: d.options, sag: d.sag))
                        .frame(width: draft == nil ? 72 : 150, height: draft == nil ? 72 : 150)
                        .padding(8)
                        .background(tileBackground(selected: draft == nil))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.kind.title).font(.title3.weight(.semibold))
                        if draft == nil {
                            Label("Selected on your desktop", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(Color.accentColor)
                        } else {
                            Text("Preview").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                switch step {
                case .base:
                    optionRows(d, d.kind.baseOptions)
                case .decorate:
                    if d.kind.addOnOptions.isEmpty {
                        Text("This one is ready as it is.").foregroundStyle(.secondary)
                    }
                    optionRows(d, d.kind.addOnOptions)
                    if d.kind == .lights { droop(d) }
                case .size:
                    sizeStep(d)
                }

                if draft != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { placeDraft() }
                    } label: {
                        Label("Next: Put It on My Desktop", systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                } else {
                    HStack {
                        Button { store.duplicate(d.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        Spacer()
                        Button(role: .destructive) { store.remove(d.id) } label: { Label("Remove", systemImage: "trash") }
                    }
                }
            }
        } else {
            home
        }
    }

    private func placeDraft() {
        guard let d = draft else { return }
        draft = nil
        store.place(d)
        step = .size
        page = .customize
    }

    private func stepHeader(current: Step, placed: Bool = false) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(Step.allCases.enumerated()), id: \.offset) { i, s in
                let isCurrent = s == current
                let reachable = placed || s != .size
                Button {
                    guard page == .customize, reachable else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { step = s }
                } label: {
                    HStack(spacing: 5) {
                        Text("\(i + 1)")
                            .font(.caption2.weight(.bold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.25)))
                            .foregroundStyle(isCurrent ? .white : .primary)
                        Text(s.rawValue).font(.caption.weight(isCurrent ? .semibold : .regular))
                    }
                    .padding(.vertical, 4).padding(.horizontal, 8)
                    .background(Capsule().fill(isCurrent ? Color.accentColor.opacity(0.15) : Color.clear))
                }
                .buttonStyle(.plain)
                .opacity(reachable ? 1 : 0.45)
                if i < Step.allCases.count - 1 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }

    private func optionRows(_ d: PlacedDecoration, _ options: [DecorationOption]) -> some View {
        ForEach(options, id: \.key) { opt in
            VStack(alignment: .leading, spacing: 8) {
                Text(opt.title).font(.subheadline.weight(.semibold))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(opt.choices, id: \.value) { choice in choiceTile(d, opt, choice) }
                    }
                    .padding(.vertical, 3).padding(.horizontal, 2)
                }
            }
        }
    }

    private func setOption(_ key: String, _ value: String) {
        if draft != nil { draft?.options[key] = value }
        else if let id = store.selectedID { store.setOption(key, value, for: id) }
    }

    private func choiceTile(_ d: PlacedDecoration, _ opt: DecorationOption, _ choice: (value: String, label: String)) -> some View {
        let selected = d.option(opt.key) == choice.value
        var options = d.options
        options[opt.key] = choice.value
        // Colour choices make most sense shown on the part they change (e.g. the topper).
        let focusKey = opt.key == "topperColor" ? "topper" : opt.key == "hatColor" ? "hat" : opt.key
        if opt.key == "topperColor", d.option("topper") == "none" { options["topper"] = "star" }
        if opt.key == "hatColor", d.option("hat") == "none" { options["hat"] = "beanie" }
        let img = DecorationThumbnails.image(kind: d.kind, options: options, sag: d.sag,
                                             focus: DecorationThumbnails.focus(kind: d.kind, option: focusKey))
        return Button {
            setOption(opt.key, choice.value)
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    picture(img).frame(width: 64, height: 64)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 6, y: -6)
                    }
                }
                tileLabel(choice.label, small: true, bold: selected)
            }
            .padding(6)
            .frame(width: 82)
            .background(tileBackground(selected: selected))
        }
        .buttonStyle(.plain)
    }

    private func droop(_ d: PlacedDecoration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Droop").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                ForEach([("Tight", 0.08), ("Gentle", 0.3), ("Deep", 0.6)], id: \.0) { name, sag in
                    let selected = abs(d.sag - sag) < 0.12
                    Button {
                        if draft != nil { draft?.sag = sag } else if var s = store.selected { s.sag = sag; store.update(s) }
                    } label: {
                        VStack(spacing: 4) {
                            picture(DecorationThumbnails.image(kind: .lights, options: d.options, sag: sag)).frame(width: 82, height: 42)
                            tileLabel(name, small: true, bold: selected)
                        }
                        .padding(6)
                        .background(tileBackground(selected: selected))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Size (watched live on the desktop)

    private static let sizes: [(name: String, scale: Double)] = [("Small", 0.6), ("Medium", 0.9), ("Large", 1.25), ("Extra Large", 1.7)]

    private func sizeStep(_ d: PlacedDecoration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if d.kind == .lights {
                Text("Your lights are on your desktop.").font(.subheadline.weight(.semibold))
                Text("Drag either end of the lights to stretch them anywhere — along a window, the Dock or across screens.")
                    .font(.callout).foregroundStyle(.secondary)
                droop(d)
            } else {
                Text("Look at your desktop and pick the size that fits.").font(.subheadline.weight(.semibold))
                Text("Your \(d.kind.title.lowercased()) grows and shrinks right there as you choose. You can also drag it wherever you like.")
                    .font(.callout).foregroundStyle(.secondary)
                let current = Self.sizes.min { abs($0.scale - d.scale) < abs($1.scale - d.scale) }?.name
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Self.sizes, id: \.name) { size in
                        let selected = current == size.name && abs(d.scale - size.scale) < 0.08
                        Button {
                            if var s = store.selected { s.scale = size.scale; store.update(s) }
                        } label: {
                            VStack(spacing: 4) {
                                picture(DecorationThumbnails.image(kind: d.kind, options: d.options, sag: d.sag))
                                    .frame(width: 26 + 26 * size.scale, height: 26 + 26 * size.scale)
                                    .frame(height: 74, alignment: .bottom)
                                tileLabel(size.name, small: true, bold: selected)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity)
                            .background(tileBackground(selected: selected))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Button { nudge(1 / 1.1) } label: { Image(systemName: "minus") }
                    Text("\(Int((d.scale * 100).rounded()))%").monospacedDigit().frame(minWidth: 48)
                    Button { nudge(1.1) } label: { Image(systemName: "plus") }
                    Spacer()
                    Text("Fine-tune").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func nudge(_ f: Double) {
        guard var s = store.selected else { return }
        s.scale = min(2.5, max(0.4, s.scale * f))
        store.update(s)
    }

    // MARK: Pieces

    private var footer: some View {
        HStack {
            Toggle(isOn: Binding(get: { !store.isHidden }, set: { store.isHidden = !$0 })) {
                Text("Show on desktop")
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Spacer()
            Button("Remove All…") { confirmRemoveAll = true }
                .disabled(store.items.isEmpty)
            Button("Done") {
                draft = nil
                store.selectedID = nil
                page = .home
                DecorationEditorController.shared.close()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private func backButton(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { action() }
        } label: {
            Label(title, systemImage: "chevron.left").font(.callout)
        }
        .buttonStyle(.borderless)
    }

    private func tileLabel(_ text: String, small: Bool = false, bold: Bool = false, dim: Bool = false) -> some View {
        Text(text)
            .font(small ? .caption2.weight(bold ? .semibold : .regular) : .caption.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(.white.opacity(dim ? 0.5 : 0.92))
    }

    private func picture(_ img: NSImage) -> some View {
        Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
    }

    private func tileBackground(selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.38), Color(red: 0.1, green: 0.13, blue: 0.27)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(selected ? Color.accentColor : Color.white.opacity(0.08), lineWidth: selected ? 3 : 1))
    }
}
