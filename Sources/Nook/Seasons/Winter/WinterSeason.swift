import CoreGraphics

struct WinterSeason: Season {
    let id = "winter"
    let displayName = "Winter"

    func makeScene(screenFrame: CGRect, visibleTop: CGFloat) -> SeasonScene {
        WinterScene(screenFrame: screenFrame, visibleTop: visibleTop)
    }
}
