import SpriteKit

enum SurfaceKey: Hashable {
    case window(CGWindowID)
    case dock
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

    var width: CGFloat { CGFloat(heights.count) * SnowPile.columnWidth }
    var isEmpty: Bool { heights.allSatisfy { $0 < 0.2 } }

    init(key: SurfaceKey, width: CGFloat, origin: CGPoint, maxHeight: CGFloat) {
        self.key = key
        self.heights = Array(repeating: 0, count: max(1, Int(width / SnowPile.columnWidth)))
        self.origin = origin
        self.maxHeight = maxHeight
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
            m.position = CGPoint(x: (CGFloat(k) + 0.5) * step, y: -1.5)
        }
        dirty = true
    }

    /// The tallest the snow may be at a column. It thins out toward the rounded window corners.
    func cap(_ i: Int) -> CGFloat {
        let edge = CGFloat(min(i, heights.count - 1 - i)) * SnowPile.columnWidth
        let t = min(1, max(0, edge / 16))
        return maxHeight * (t * t * (3 - 2 * t))
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
                heights[j] += min(room, amount * w)
                added = true
            }
        }
        if added { dirty = true }
        return added
    }

    /// Gives every column a thin, slightly uneven dusting (used when Nook starts).
    func dust(_ amount: CGFloat) {
        for i in heights.indices {
            let wobble = 0.75 + 0.5 * CGFloat(sin(Double(i) * 0.37) * 0.5 + 0.5)
            heights[i] = min(cap(i), amount * wobble)
        }
        dirty = true
    }

    /// Lets the snow settle so it doesn't form spikes.
    func relax() {
        guard heights.count > 2 else { return }
        let limit: CGFloat = 0.9
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
                m.size = CGSize(width: SnowPile.moundWidth, height: h + 2.5)
            }
        }
    }
}
