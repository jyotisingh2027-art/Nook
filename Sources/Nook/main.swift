import AppKit

// Nook runs as a menu-bar-only app (no Dock icon).
if let i = CommandLine.arguments.firstIndex(of: "--render-decorations"), i + 1 < CommandLine.arguments.count {
    DecorationPreview.renderSheet(to: CommandLine.arguments[i + 1])
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-panel"), i + 2 < CommandLine.arguments.count {
    DecorationPreview.renderPanel(to: CommandLine.arguments[i + 1], page: CommandLine.arguments[i + 2])
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-visitors"), i + 1 < CommandLine.arguments.count {
    VisitorArt.renderSheet(to: CommandLine.arguments[i + 1])
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-winter"), i + 1 < CommandLine.arguments.count {
    WinterPreview.render(to: CommandLine.arguments[i + 1])
    exit(0)
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
