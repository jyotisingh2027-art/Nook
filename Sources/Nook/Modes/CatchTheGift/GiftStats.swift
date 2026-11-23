import Foundation

/// Score and progress for Catch the Gift, saved on this Mac only.
final class GiftStats {
    static let shared = GiftStats()
    static let didChange = Notification.Name("NookGiftStatsDidChange")
    /// Posted (with a `GameResult` as the object) when the last life is lost.
    static let gameOver = Notification.Name("NookGiftGameOver")
    static let maxLives = 3

    /// How one game went, for the Game Over card.
    struct GameResult {
        let score: Int
        let bestGame: Int
        let isNewBest: Bool
        let bestStreak: Int
        let missed: Int
        let stolen: Int
        let impsChased: Int
        let seconds: Int
        let allTimeCaught: Int
    }

    // MARK: This game (not saved; a new game starts fresh)

    private(set) var inGame = false
    private(set) var score = 0
    private(set) var lives = GiftStats.maxLives
    private(set) var gameStreakBest = 0
    private(set) var gameMissed = 0
    private(set) var gameStolen = 0
    private(set) var gameImps = 0
    private var gameStart = Date()

    /// Most gifts caught in a single game.
    private(set) var bestGame: Int {
        get { defaults.integer(forKey: "giftBestGame") }
        set { defaults.set(newValue, forKey: "giftBestGame") }
    }

    func startGame() {
        inGame = true
        score = 0
        lives = Self.maxLives
        streak = 0
        gameStreakBest = 0
        gameMissed = 0
        gameStolen = 0
        gameImps = 0
        gameStart = Date()
        notify()
    }

    /// Leaving the game early (switching mode) ends it quietly, without a Game Over card.
    func abandonGame() {
        guard inGame else { return }
        inGame = false
        notify()
    }

    private func loseLife() {
        guard inGame else { return }
        lives = max(0, lives - 1)
        guard lives == 0 else { return }
        let result = finish()
        // Announce it after the current frame finishes, so nothing is cleared mid-update.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: GiftStats.gameOver, object: result)
        }
    }

    /// Ending the game yourself (Play Game → End Game) shows the same score card.
    func endGame() -> GameResult? {
        guard inGame else { return nil }
        let r = finish()
        notify()
        return r
    }

    private func finish() -> GameResult {
        inGame = false
        let newBest = score > bestGame
        if newBest { bestGame = score }
        return GameResult(score: score, bestGame: bestGame, isNewBest: newBest && score > 0,
                                bestStreak: gameStreakBest, missed: gameMissed, stolen: gameStolen,
                                impsChased: gameImps, seconds: Int(Date().timeIntervalSince(gameStart)),
                                allTimeCaught: caught)
    }

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

    /// Times you've chased the frost imp away, and gifts it got away with.
    private(set) var impsShooed: Int {
        get { defaults.integer(forKey: "impsShooed") }
        set { defaults.set(newValue, forKey: "impsShooed") }
    }
    private(set) var giftsStolen: Int {
        get { defaults.integer(forKey: "giftsStolen") }
        set { defaults.set(newValue, forKey: "giftsStolen") }
    }

    /// Catches in a row right now. Resets when a gift lands.
    private(set) var streak = 0

    private var extras: [DecorationKind] { DecorationKind.allCases.filter { $0.lockedByDefault } }

    /// Records a catch. Returns the surprise decoration it unlocked, if any.
    func recordCatch() -> DecorationKind? {
        caught += 1
        streak += 1
        if streak > bestStreak { bestStreak = streak }
        if inGame {
            score += 1
            gameStreakBest = max(gameStreakBest, streak)
        }

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
        streak = 0
        if inGame { gameMissed += 1 }
        loseLife()
        notify()
    }

    /// The imp made off with a gift: that ends the streak.
    func recordStolen() {
        giftsStolen += 1
        streak = 0
        if inGame { gameStolen += 1 }
        loseLife()
        notify()
    }

    func recordImpShooed() {
        impsShooed += 1
        if inGame { gameImps += 1 }
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
