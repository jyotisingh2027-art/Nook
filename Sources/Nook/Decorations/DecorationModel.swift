import Foundation
import CoreGraphics

/// A choice the user can change on a decoration (e.g. a tree's topper).
struct DecorationOption {
    let key: String
    let title: String
    let choices: [(value: String, label: String)]
    /// Base options shape the plain object (e.g. the tree's colour); the rest are add-on decorations.
    var isBase = false
    var defaultValue: String { choices[0].value }

    init(key: String, title: String, choices: [(value: String, label: String)], isBase: Bool = false) {
        self.key = key; self.title = title; self.choices = choices; self.isBase = isBase
    }
}

enum DecorationKind: String, CaseIterable, Codable {
    // Builders
    case tree, snowman, lights
    // Single items
    case wreath, bells, candle, star, giftBox, snowGlobe, ornament
    // Extras unlocked by Catch the Gift
    case lantern, cocoaMug, gingerbreadHouse, mistletoe, penguin, candyCane

    var title: String {
        switch self {
        case .tree: return "Christmas Tree"
        case .snowman: return "Snowman"
        case .lights: return "String Lights"
        case .wreath: return "Wreath"
        case .bells: return "Bells"
        case .candle: return "Candle"
        case .star: return "Star"
        case .giftBox: return "Gift Box"
        case .snowGlobe: return "Snow Globe"
        case .ornament: return "Ornament"
        case .lantern: return "Lantern"
        case .cocoaMug: return "Cocoa Mug"
        case .gingerbreadHouse: return "Gingerbread House"
        case .mistletoe: return "Mistletoe"
        case .penguin: return "Penguin"
        case .candyCane: return "Giant Candy Cane"
        }
    }

    var symbol: String {
        switch self {
        case .tree: return "tree.fill"
        case .snowman: return "figure.stand"
        case .lights: return "lightbulb.fill"
        case .wreath: return "circle.circle"
        case .bells: return "bell.fill"
        case .candle: return "flame.fill"
        case .star: return "star.fill"
        case .giftBox: return "gift.fill"
        case .snowGlobe: return "globe"
        case .ornament: return "circle.fill"
        case .lantern: return "lamp.desk.fill"
        case .cocoaMug: return "mug.fill"
        case .gingerbreadHouse: return "house.fill"
        case .mistletoe: return "leaf.fill"
        case .penguin: return "bird.fill"
        case .candyCane: return "staroflife.fill"
        }
    }

    enum Group: String, CaseIterable { case builders = "Build Your Own", singles = "Decorations", extras = "Surprise Extras" }

    var group: Group {
        switch self {
        case .tree, .snowman, .lights: return .builders
        case .wreath, .bells, .candle, .star, .giftBox, .snowGlobe, .ornament: return .singles
        default: return .extras
        }
    }

    var lockedByDefault: Bool { group == .extras }

    var options: [DecorationOption] {
        typealias O = DecorationOption
        let colours: [(value: String, label: String)] = [("red", "Red"), ("green", "Green"), ("blue", "Blue"), ("gold", "Gold"), ("pink", "Pink"), ("silver", "Silver")]
        switch self {
        case .tree:
            return [
                O(key: "treeColor", title: "Tree", choices: [("green", "Green"), ("white", "Snowy White"), ("blue", "Blue Spruce"), ("silver", "Silver"), ("pink", "Pink"), ("dark", "Forest")], isBase: true),
                O(key: "topper", title: "Topper Shape", choices: [("star", "Star"), ("snowflake", "Snowflake"), ("bow", "Bow"), ("heart", "Heart"), ("none", "None")]),
                O(key: "topperColor", title: "Topper Colour", choices: [("gold", "Gold"), ("white", "White"), ("pink", "Pink"), ("red", "Red"), ("silver", "Silver"), ("blue", "Blue")]),
                O(key: "baubles", title: "Baubles", choices: [("mixed", "Mixed"), ("red", "Red"), ("gold", "Gold"), ("frost", "Frost"), ("pink", "Pink"), ("none", "None")]),
                O(key: "lights", title: "Lights", choices: [("warm", "Warm"), ("multi", "Colourful"), ("none", "None")]),
                O(key: "garland", title: "Garland", choices: [("gold", "Gold"), ("silver", "Silver"), ("red", "Red"), ("none", "None")]),
                O(key: "candyCanes", title: "Candy Canes", choices: [("off", "Off"), ("on", "On")]),
                O(key: "gingerbread", title: "Gingerbread", choices: [("off", "Off"), ("on", "On")])
            ]
        case .snowman:
            return [
                O(key: "body", title: "Shape", choices: [("classic", "Classic"), ("chubby", "Chubby"), ("tall", "Tall")], isBase: true),
                O(key: "snow", title: "Snow", choices: [("white", "White"), ("icy", "Icy Blue"), ("cream", "Cream")], isBase: true),
                O(key: "hat", title: "Hat", choices: [("topHat", "Top Hat"), ("beanie", "Beanie"), ("santa", "Santa Hat"), ("none", "None")]),
                O(key: "hatColor", title: "Hat Colour", choices: [("red", "Red"), ("blue", "Blue"), ("green", "Green"), ("pink", "Pink"), ("gold", "Gold")]),
                O(key: "face", title: "Face", choices: [("happy", "Happy"), ("cheeky", "Cheeky"), ("sleepy", "Sleepy"), ("surprised", "Surprised")]),
                O(key: "scarf", title: "Scarf", choices: [("red", "Red"), ("green", "Green"), ("blue", "Blue"), ("pink", "Pink"), ("stripes", "Stripes"), ("none", "None")]),
                O(key: "outfit", title: "Outfit", choices: [("buttons", "Buttons"), ("bowtie", "Bow Tie"), ("mittens", "Mittens"), ("none", "None")])
            ]
        case .lights:
            return [
                O(key: "wire", title: "Wire", choices: [("green", "Green"), ("white", "White"), ("brown", "Brown")], isBase: true),
                O(key: "colors", title: "Bulb Colours", choices: [("warm", "Warm"), ("multi", "Colourful"), ("icy", "Icy Blue"), ("candy", "Candy"), ("pink", "Pink")]),
                O(key: "bulb", title: "Bulb Shape", choices: [("round", "Round"), ("classic", "Classic"), ("star", "Star")])
            ]
        case .wreath:
            return [
                O(key: "greenery", title: "Wreath", choices: [("green", "Evergreen"), ("frosted", "Frosted"), ("gold", "Golden")], isBase: true),
                O(key: "bow", title: "Bow", choices: [("red", "Red"), ("gold", "Gold"), ("blue", "Blue"), ("none", "None")]),
                O(key: "lights", title: "Lights", choices: [("off", "Off"), ("on", "On")])
            ]
        case .giftBox:
            return [
                O(key: "color", title: "Box", choices: colours, isBase: true),
                O(key: "ribbon", title: "Ribbon", choices: [("gold", "Gold"), ("red", "Red"), ("silver", "Silver"), ("white", "White")])
            ]
        case .ornament:
            return [
                O(key: "color", title: "Ornament", choices: colours, isBase: true),
                O(key: "pattern", title: "Pattern", choices: [("zigzag", "Zigzag"), ("stripes", "Stripes"), ("dots", "Dots"), ("plain", "Plain")])
            ]
        case .star:
            return [O(key: "color", title: "Star", choices: [("gold", "Gold"), ("white", "White"), ("pink", "Pink"), ("silver", "Silver"), ("blue", "Blue")], isBase: true)]
        case .candle:
            return [O(key: "color", title: "Candle", choices: [("red", "Red"), ("white", "White"), ("gold", "Gold"), ("green", "Green")], isBase: true)]
        case .bells:
            return [O(key: "color", title: "Bells", choices: [("gold", "Gold"), ("silver", "Silver")], isBase: true)]
        default:
            return []
        }
    }

    var baseOptions: [DecorationOption] { options.filter { $0.isBase } }
    var addOnOptions: [DecorationOption] { options.filter { !$0.isBase } }

    /// Every plain starting point for this decoration (all combinations of its base options).
    var baseVariants: [[String: String]] {
        var result: [[String: String]] = [[:]]
        for opt in baseOptions {
            result = result.flatMap { partial in opt.choices.map { c in partial.merging([opt.key: c.value]) { $1 } } }
        }
        return result
    }

    func variantName(_ options: [String: String]) -> String {
        let names = baseOptions.compactMap { opt in opt.choices.first { $0.value == options[opt.key] }?.label }
        return names.isEmpty ? title : names.joined(separator: " · ")
    }
}

/// One decoration placed on the desktop. Positions are in global screen points (bottom-left origin);
/// (x, y) is the bottom-centre of the item. String lights use (x, y) and (x2, y2) as their two ends.
struct PlacedDecoration: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: DecorationKind
    var x: Double
    var y: Double
    var scale: Double = 1
    var options: [String: String] = [:]
    var x2: Double = 0
    var y2: Double = 0
    var sag: Double = 0.35
    var seed: UInt64 = UInt64.random(in: 1...UInt64.max)

    func option(_ key: String) -> String {
        if let v = options[key] { return v }
        return kind.options.first { $0.key == key }?.defaultValue ?? ""
    }

    func optionLegacy(_ key: String) -> String {
        options[key] ?? kind.options.first { $0.key == key }?.defaultValue ?? ""
    }

    var point: CGPoint { CGPoint(x: x, y: y) }
    var point2: CGPoint { CGPoint(x: x2, y: y2) }
}
