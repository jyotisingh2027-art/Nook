import AppKit
import CoreGraphics

/// A normal app window on screen. `frame` is in AppKit global coordinates (origin bottom-left).
struct TrackedWindow {
    let id: CGWindowID
    let pid: pid_t
    let frame: CGRect
}

enum WindowEvent {
    /// The window moved; velocity is in points per second (AppKit coordinates, +y is up).
    case moved(id: CGWindowID, velocity: CGVector)
    case resized(id: CGWindowID)
    /// The window no longer exists (closed, or its app quit).
    case closed(id: CGWindowID)
    /// The window still exists but isn't visible (minimized, hidden, other Space).
    case hidden(id: CGWindowID)
}

protocol WindowTrackerObserver: AnyObject {
    func windowTracker(_ tracker: WindowTracker, didUpdate windows: [TrackedWindow], events: [WindowEvent])
}

/// Watches where app windows are, using only window positions and sizes.
/// This needs no permission: it never looks at window contents or titles.
final class WindowTracker {
    private(set) var windows: [TrackedWindow] = []   // front-to-back
    weak var observer: WindowTrackerObserver?

    /// When nothing is visible (e.g. a full-screen app), poll slowly.
    var idle = false

    private var last: [CGWindowID: (frame: CGRect, time: CFTimeInterval)] = [:]
    private var timer: Timer?
    private var currentInterval: TimeInterval = 0
    private let myPid = getpid()

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        schedule(interval: 1.0 / 4.0)
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentInterval = 0
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        currentInterval = interval
    }

    private func tick() {
        // Poll quickly only while a mouse button is held (someone may be dragging a window).
        let desired: TimeInterval
        if idle { desired = 1.0 }
        else if NSEvent.pressedMouseButtons != 0 { desired = 1.0 / 30.0 }
        else { desired = 1.0 / 4.0 }
        if abs(desired - currentInterval) > 0.001 { schedule(interval: desired) }
        poll()
    }

    func poll() {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        var result: [TrackedWindow] = []
        for w in info {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let number = w[kCGWindowNumber as String] as? Int,
                  let pid = w[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != myPid,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            let alpha = w[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.1 || b.width < 80 || b.height < 40 { continue }
            // Convert from top-left origin to AppKit's bottom-left origin.
            let frame = CGRect(x: b.minX, y: primaryHeight - b.maxY, width: b.width, height: b.height)
            result.append(TrackedWindow(id: CGWindowID(number), pid: pid_t(pid), frame: frame))
        }

        let now = CACurrentMediaTime()
        var events: [WindowEvent] = []
        var seen = Set<CGWindowID>()
        for w in result {
            seen.insert(w.id)
            if let prev = last[w.id] {
                let f = w.frame, p = prev.frame
                let sizeChanged = abs(f.width - p.width) > 1 || abs(f.height - p.height) > 1
                let dx = f.minX - p.minX, dy = f.minY - p.minY
                if sizeChanged {
                    events.append(.resized(id: w.id))
                } else if abs(dx) > 2 || abs(dy) > 2 {
                    let dt = max(now - prev.time, 1.0 / 60.0)
                    events.append(.moved(id: w.id, velocity: CGVector(dx: dx / dt, dy: dy / dt)))
                }
            }
            last[w.id] = (w.frame, now)
        }

        let gone = last.keys.filter { !seen.contains($0) }
        if !gone.isEmpty {
            // Distinguish "closed" from "minimized / hidden / on another Space".
            var existing = Set<CGWindowID>()
            if let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] {
                for w in all {
                    if let n = w[kCGWindowNumber as String] as? Int { existing.insert(CGWindowID(n)) }
                }
            }
            for id in gone {
                events.append(existing.contains(id) ? .hidden(id: id) : .closed(id: id))
                last[id] = nil
            }
        }

        windows = result
        observer?.windowTracker(self, didUpdate: result, events: events)
    }
}
