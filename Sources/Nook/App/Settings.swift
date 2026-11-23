import Foundation

enum SnowAmount: String, CaseIterable {
    case light, medium, heavy

    var title: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .heavy: return "Heavy"
        }
    }

    /// Multiplier applied to the base number of flakes.
    var density: Double {
        switch self {
        case .light: return 1.0
        case .medium: return 2.0
        case .heavy: return 3.0
        }
    }

    /// Multiplier applied to how fast flakes fall.
    var speed: Double {
        switch self {
        case .light: return 1.3
        case .medium: return 1.4
        case .heavy: return 2.0
        }
    }

    /// How quickly snow piles up on windows (1 = the pace you approved).
    var buildUp: Double {
        switch self {
        case .light: return 0.8
        case .medium: return 1.0
        case .heavy: return 1.4
        }
    }
}

/// Only one mode runs at a time.
enum AppMode: String, CaseIterable {
    case cozy, catchGift, snowballFight, focus

    var title: String {
        switch self {
        case .cozy: return "Cozy"
        case .catchGift: return "Catch the Gift"
        case .snowballFight: return "Snowball Fight"
        case .focus: return "Focus"
        }
    }

    /// Modes become available as they are built.
    var isAvailable: Bool { self != .focus }
}

/// User preferences, stored locally on this Mac only.
final class Settings {
    static let shared = Settings()
    static let didChange = Notification.Name("NookSettingsDidChange")

    private let defaults = UserDefaults.standard

    var snowAmount: SnowAmount {
        get { SnowAmount(rawValue: defaults.string(forKey: "snowAmount") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "snowAmount"); changed() }
    }

    var mode: AppMode {
        get { AppMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .cozy }
        set { defaults.set(newValue.rawValue, forKey: "mode"); changed() }
    }

    var isPaused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused"); changed() }
    }

    private func changed() {
        NotificationCenter.default.post(name: Settings.didChange, object: self)
    }
}
