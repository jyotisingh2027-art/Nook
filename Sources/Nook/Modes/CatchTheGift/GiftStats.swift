import Foundation

/// Score and progress for Catch the Gift, saved on this Mac only.
final class GiftStats {
    static let shared = GiftStats()
    static let didChange = Notification.Name("NookGiftStatsDidChange")

    /// Total catches needed for each surprise extra (first, second, third…).
    static let unlockAt = [1, 3, 6, 10, 15, 21]

    private let defaults = UserDefaults.standard

    /// Every gift you've ever caught.
    private(set) var caught: Int {
        get { defaults.integer(forKey: "giftsCaught") }
        set { defaults.set(newValue, forKey: "giftsCaught") }
    }

    /// Longest run of catches without letting one land.
    private(set) var bestStreak: Int {
        get { defaults.integer(forKey: "giftBestStreak") }
        set { defaults.set(newValue, forKey: "giftBestStreak") }
    }

    /// Catches in a row right now. Resets when a gift lands.
    private(set) var streak = 0

    private var extras: [DecorationKind] { DecorationKind.allCases.filter { $0.lockedByDefault } }

    /// Records a catch. Returns the surprise decoration it unlocked, if any.
    func recordCatch() -> DecorationKind? {
        caught += 1
        streak += 1
        if streak > bestStreak { bestStreak = streak }

        var revealed: DecorationKind?
        let store = DecorationStore.shared
        let locked = extras.filter { !store.isUnlocked($0) }
        let have = extras.count - locked.count
        if have < Self.unlockAt.count, caught >= Self.unlockAt[have], let next = locked.randomElement() {
            store.unlock(next)
            revealed = next
        }
        notify()
        return revealed
    }

    /// A gift reached the ground.
    func recordMiss() {
        guard streak != 0 else { return }
        streak = 0
        notify()
    }

    /// Catches still needed for the next surprise, or nil once everything is unlocked.
    var catchesToNextUnlock: Int? {
        let store = DecorationStore.shared
        let have = extras.filter { store.isUnlocked($0) }.count
        guard have < extras.count, have < Self.unlockAt.count else { return nil }
        return max(1, Self.unlockAt[have] - caught)
    }

    private func notify() {
        NotificationCenter.default.post(name: GiftStats.didChange, object: self)
    }
}
