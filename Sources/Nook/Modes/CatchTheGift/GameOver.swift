import AppKit
import SwiftUI

/// The card that appears when Catch the Gift runs out of lives.
final class GameOverController: NSObject, NSWindowDelegate {
    static let shared = GameOverController()
    private var panel: NSPanel?

    func show(_ result: GiftStats.GameResult) {
        panel?.close()
        let host = NSHostingController(rootView: GameOverView(result: result,
            onPlayAgain: { [weak self] in
                self?.panel?.close()
                if Settings.shared.isPaused { Settings.shared.isPaused = false }
                Settings.shared.mode = .catchGift
            },
            onDone: { [weak self] in self?.panel?.close() }))
        let p = NSPanel(contentViewController: host)
        p.title = "Game Over"
        p.styleMask = [.titled, .closable, .fullSizeContentView]
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.delegate = self
        p.setContentSize(NSSize(width: 400, height: 600))
        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    /// Developer preview of the card (`Nook --render-gameover out.png`).
    static func renderPreview(to path: String) {
        MainActor.assumeIsolated { renderPreviewOnMain(to: path) }
    }

    @MainActor private static func renderPreviewOnMain(to path: String) {
        let r = GiftStats.GameResult(score: 17, bestGame: 17, isNewBest: true, bestStreak: 9, missed: 2,
                                     stolen: 1, impsChased: 4, seconds: 154, allTimeCaught: 63)
        let view = GameOverView(result: r, onPlayAgain: {}, onDone: {}).frame(width: 400, height: 600)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

struct GameOverView: View {
    let result: GiftStats.GameResult
    let onPlayAgain: () -> Void
    let onDone: () -> Void

    private let plum = Color(red: 0.17, green: 0.08, blue: 0.16)
    private let plumLight = Color(red: 0.27, green: 0.14, blue: 0.26)
    private let cream = Color(red: 0.98, green: 0.93, blue: 0.85)
    private let lilac = Color(red: 0.78, green: 0.67, blue: 0.85)

    var body: some View {
        VStack(spacing: 16) {
            // The Nook eyes, looking a bit sad.
            HStack(spacing: 10) { eye; eye }
                .padding(.top, 26)

            Text("Game Over")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(cream)

            VStack(spacing: 2) {
                Text("\(result.score)")
                    .font(.system(size: 64, weight: .black, design: .rounded))
                    .foregroundColor(cream)
                Text(result.score == 1 ? "gift caught" : "gifts caught")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(lilac)
            }

            if result.isNewBest {
                Label("New best game!", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(plum)
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Capsule().fill(Color(red: 1, green: 0.83, blue: 0.4)))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tile("trophy.fill", "\(result.bestGame)", "Best game")
                tile("flame.fill", "\(result.bestStreak)", "Longest streak")
                tile("clock.fill", time, "Time played")
                tile("hand.raised.fill", "\(result.impsChased)", "Imps chased off")
                tile("gift.fill", "\(result.stolen)", "Gifts stolen")
                tile("arrow.down.to.line", "\(result.missed)", "Gifts missed")
            }
            .padding(.horizontal, 22)

            Text("All-time gifts caught: \(result.allTimeCaught)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(lilac)

            HStack(spacing: 12) {
                Button(action: onDone) {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundColor(cream)
                        .background(RoundedRectangle(cornerRadius: 12).stroke(lilac.opacity(0.6), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                Button(action: onPlayAgain) {
                    Text("Play Again")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .foregroundColor(plum)
                        .background(RoundedRectangle(cornerRadius: 12).fill(cream))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(plum)
    }

    private var eye: some View {
        ZStack {
            Circle().stroke(cream, lineWidth: 7).frame(width: 34, height: 34)
            Circle().fill(cream).frame(width: 9, height: 9).offset(x: -6, y: 8)   // looking down
        }
    }

    private var time: String {
        let m = result.seconds / 60, s = result.seconds % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private func tile(_ symbol: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundColor(lilac)
            Text(value).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(cream)
            Text(label).font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundColor(lilac)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(plumLight))
    }
}
