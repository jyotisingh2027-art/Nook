import Foundation

/// Running totals for Snowball Fight, saved on this Mac only.
final class SnowballStats {
    static let shared = SnowballStats()

    private let defaults = UserDefaults.standard

    /// Snowmen you knocked over.
    private(set) var bonked: Int {
        get { defaults.integer(forKey: "snowmenBonked") }
        set { defaults.set(newValue, forKey: "snowmenBonked") }
    }

    /// Incoming snowballs you clicked away before they hit.
    private(set) var blocked: Int {
        get { defaults.integer(forKey: "snowballsBlocked") }
        set { defaults.set(newValue, forKey: "snowballsBlocked") }
    }

    /// Snowballs that splatted on your screen.
    private(set) var splatted: Int {
        get { defaults.integer(forKey: "snowballsTaken") }
        set { defaults.set(newValue, forKey: "snowballsTaken") }
    }

    /// Snowmen bonked in a row without taking a splat.
    private(set) var streak = 0

    func recordBonk() { bonked += 1; streak += 1 }
    func recordBlock() { blocked += 1 }
    func recordSplat() { splatted += 1; streak = 0 }
}
