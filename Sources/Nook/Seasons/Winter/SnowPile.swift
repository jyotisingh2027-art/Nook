import SpriteKit

enum SurfaceKey: Hashable {
    case window(CGWindowID)
    case dock
    case ground   // the bottom edge of the screen
}

/// A strip of settled snow along the top edge of a window or the Dock.
/// Snow is stored as a row of column heights so it can build up unevenly and be shed in pieces.
final class SnowPile {
    static let columnWidth: CGFloat = 3

    let key: SurfaceKey
    private(set) var heights: [CGFloat]
    /// Local scene position of the pile's left end and the surface line.
    var origin: CGPoint {
        didSet { node.position = origin }
    }
    /// Each mound sprite covers this many columns, and is a little wider so neighbours blend.
    private static let columnsPerMound = 3
    private static let moundWidth: CGFloat = 15
    var maxHeight: CGFloat
    /// Real snow drifts: each pile has its own pattern of humps and dips, so some
    /// spots pile up high while others stay low.
    private let driftPhases: (CGFloat, CGFloat, CGFloat, CGFloat)
    private(set) var hiddenColumns = IndexSet()   // covered by a window in front
    private(set) var dirty = true

    func setHiddenColumns(_ set: IndexSet) {
        guard set != hiddenColumns else { return }
        hiddenColumns = set
        dirty = true
    }

    /// The pile is a row of soft snow mounds that grow and shrink. All mounds share one
    /// texture, so the graphics chip draws a whole pile in a single cheap step.
    let node = SKNode()
    private var mounds: [SKSpriteNode] = []
    private var moundWidths: [Int: CGFloat] = [:]

    /// A repeatable 0…1 number for mound `k`.
    private static func hash(_ k: Int, _ seed: CGFloat) -> CGFloat {
        let v = sin(CGFloat(k) * 12.9898 + seed * 78.233) * 43758.5453
        return v - floor(v)
    }

    var width: CGFloat { CGFloat(heights.count) * SnowPile.columnWidth }
    var isEmpty: Bool { heights.allSatisfy { $0 < 0.2 } }

    init(key: SurfaceKey, width: CGFloat, origin: CGPoint, maxHeight: CGFloat) {
        self.key = key
        self.heights = Array(repeating: 0, count: max(1, Int(width / SnowPile.columnWidth)))
        self.origin = origin
        self.maxHeight = maxHeight
        self.driftPhases = (CGFloat.random(in: 0...(2 * .pi)), CGFloat.random(in: 0...(2 * .pi)),
                            CGFloat.random(in: 0...(2 * .pi)), CGFloat.random(in: 0.8...1.25))
        node.position = origin
        node.zPosition = 10
        rebuildMounds()
    }

    /// Changes the width, keeping the existing snow centred.
    func setWidth(_ width: CGFloat) {
        let count = max(1, Int(width / SnowPile.columnWidth))
        guard count != heights.count else { return }
        var new = Array(repeating: CGFloat(0), count: count)
        let shift = (count - heights.count) / 2
        for (i, h) in heights.enumerated() {
            let j = i + shift
            if j >= 0 && j < count { new[j] = h }
        }
        heights = new
        dirty = true
        rebuildMounds()
    }

    private func rebuildMounds() {
        let needed = (heights.count + SnowPile.columnsPerMound - 1) / SnowPile.columnsPerMound
        while mounds.count > needed { mounds.removeLast().removeFromParent() }
        while mounds.count < needed {
            let m = SKSpriteNode(texture: SnowTextures.shared.mound)
            m.anchorPoint = CGPoint(x: 0.5, y: 0)
            m.zPosition = 10
            m.isHidden = true
            node.addChild(m)
            mounds.append(m)
        }
        let step = CGFloat(SnowPile.columnsPerMound) * SnowPile.columnWidth
        for (k, m) in mounds.enumerated() {
            // Each mound gets its own width and a small nudge, so the edge looks like real
            // lumpy snow instead of a neat row of scallops.
            let r1 = SnowPile.hash(k, driftPhases.0), r2 = SnowPile.hash(k, driftPhases.1)
            moundWidths[k] = SnowPile.moundWidth * (0.85 + r1 * 1.1)
            m.position = CGPoint(x: (CGFloat(k) + 0.5) * step + (r2 - 0.5) * 4, y: -1.5)
        }
        dirty = true
    }

    /// How deep the snow likes to be at a column: about 0.3 in the dips up to 1.5 on the drifts.
    func drift(_ i: Int) -> CGFloat {
        let x = CGFloat(i) * SnowPile.columnWidth
        let (a, b, c, scale) = driftPhases
        let v = 0.85
            + 0.48 * sin(x / (30 * scale) + a)
            + 0.24 * sin(x / (11.5 * scale) + b)
            + 0.09 * sin(x / 4.6 + c)
        return min(1.7, max(0.2, v))
    }

    /// The tallest the snow may be at a column. It follows the drift pattern and thins out
    /// toward the rounded window corners.
    func cap(_ i: Int) -> CGFloat {
        let edge = CGFloat(min(i, heights.count - 1 - i)) * SnowPile.columnWidth
        let t = min(1, max(0, edge / 16))
        return maxHeight * (t * t * (3 - 2 * t)) * drift(i)
    }

    /// How full the snow is overall (0 = bare, 1 = as deep as it can get).
    var fullness: CGFloat {
        var have: CGFloat = 0, room: CGFloat = 0
        for i in heights.indices { have += heights[i]; room += cap(i) }
        return room > 0 ? have / room : 0
    }

    func column(forLocalX x: CGFloat) -> Int? {
        let i = Int((x - origin.x) / SnowPile.columnWidth)
        return (i >= 0 && i < heights.count) ? i : nil
    }

    func surfaceHeight(atLocalX x: CGFloat) -> CGFloat {
        guard let i = column(forLocalX: x) else { return 0 }
        return heights[i]
    }

    /// Adds snow at a point. Returns false if the pile is already full there.
    @discardableResult
    func add(atLocalX x: CGFloat, amount: CGFloat) -> Bool {
        guard let i = column(forLocalX: x) else { return false }
        let spread: [(Int, CGFloat)] = [(-2, 0.15), (-1, 0.6), (0, 1.0), (1, 0.6), (2, 0.15)]
        var added = false
        for (o, w) in spread {
            let j = i + o
            guard j >= 0 && j < heights.count else { continue }
            let room = cap(j) - heights[j]
            if room > 0 {
                // Snow catches more on the drifts than in the dips.
                heights[j] += min(room, amount * w * (0.45 + 0.55 * drift(j)))
                added = true
            }
        }
        if added { dirty = true }
        return added
    }

    /// Gives every column a thin, slightly uneven dusting (used when Nook starts).
    func dust(_ amount: CGFloat) {
        for i in heights.indices {
            heights[i] = min(cap(i), amount * drift(i))
        }
        dirty = true
    }

    /// Lets the snow settle so it doesn't form spikes.
    func relax() {
        guard heights.count > 2 else { return }
        let limit: CGFloat = 1.3
        for _ in 0..<2 {
            for i in 0..<(heights.count - 1) {
                let d = heights[i] - heights[i + 1]
                if abs(d) > limit {
                    let move = (abs(d) - limit) * 0.5 * (d > 0 ? 1 : -1)
                    heights[i] -= move
                    heights[i + 1] += move
                    dirty = true
                }
            }
        }
    }

    /// Removes snow from a range of columns and returns how much was removed.
    func take(columns range: Range<Int>) -> CGFloat {
        var total: CGFloat = 0
        for i in range where i >= 0 && i < heights.count {
            total += heights[i]
            heights[i] = 0
        }
        if total > 0 { dirty = true }
        return total
    }

    /// Lowers snow on a range of columns to `keep` and returns how much was removed.
    func scoop(columns range: Range<Int>, keep: CGFloat) -> CGFloat {
        var total: CGFloat = 0
        for i in range where i >= 0 && i < heights.count && heights[i] > keep {
            total += heights[i] - keep
            heights[i] = keep
        }
        if total > 0 { dirty = true }
        return total
    }

    func clear() {
        for i in heights.indices { heights[i] = 0 }
        dirty = true
    }

    /// Updates the mounds if the snow changed.
    func redrawIfNeeded() {
        guard dirty else { return }
        dirty = false
        let per = SnowPile.columnsPerMound
        var anyVisible = false
        defer { node.isHidden = !anyVisible }   // skip whole piles that are empty or covered
        for (k, m) in mounds.enumerated() {
            var h: CGFloat = 0
            var allHidden = true
            for i in (k * per)..<min((k + 1) * per, heights.count) {
                if !hiddenColumns.contains(i) { allHidden = false; h = max(h, heights[i]) }
            }
            if allHidden || h < 0.3 {
                m.isHidden = true
            } else {
                m.isHidden = false
                anyVisible = true
                m.size = CGSize(width: moundWidths[k] ?? SnowPile.moundWidth, height: h + 2.5)
            }
        }
    }
}
