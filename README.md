# Nook

A cozy desktop overlay for macOS. Seasonal weather and little toys live on top of your real desktop. Version 1 is winter.

- Gentle snowfall that settles on the tops of your windows and the Dock
- Fling or resize a window and its snow flies off. Close one and its snow tumbles down
- Snow stays out of your open windows, and clicks always go through to your apps
- Wallpapers you can pick from, plus your own photos or videos
- Desktop decorations you design yourself: Christmas trees, snowmen, string lights, wreaths and more
- **Catch the Gift** mode: every so often a glowing gift drifts down with the snow. Click it before it lands to catch it. Keep a streak going and gifts fall a little faster; catches unlock the six Surprise Extras decorations (1, 3, 6, 10, 15 and 21 gifts). Your score and best streak show in the menu
- Light on battery: it pauses for full-screen apps and when the screen sleeps, and shows fewer flakes on battery

Free, with no accounts and no tracking. Everything stays on your Mac.

## Build it yourself

You need macOS 13 or later and Apple's Command Line Tools (`xcode-select --install`). Xcode is not needed.

```bash
./scripts/run.sh
```

This builds `build/Nook.app` and opens it. Nook lives in the menu bar (the eye icon).

## Project layout

- `Sources/Nook/Core`: the see-through overlay, window tracking, Dock and power detection
- `Sources/Nook/Seasons`: season scenes (`Winter/` today; new seasons plug in through the `Season` protocol)
- `Sources/Nook/Decorations`: decoration art, the editor panel, dragging and saving
- `Sources/Nook/Modes`: playful modes (`CatchTheGift/` today: falling gifts, score and unlocks)
- `Sources/Nook/Wallpapers`: the wallpaper library, picker and video wallpapers
- `Resources/Wallpapers`: the wallpaper images that come with Nook
