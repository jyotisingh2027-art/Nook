# Nook

A cozy desktop overlay for macOS. Seasonal weather and little toys live on top of your real desktop. Version 1 is winter.

- Gentle snowfall that settles on the tops of your windows and the Dock
- Fling or resize a window and its snow flies off. Close one and its snow tumbles down
- Snow stays out of your open windows, and clicks always go through to your apps
- Wallpapers you can pick from, plus your own photos or videos
- Desktop decorations you design yourself: Christmas trees, snowmen, string lights, wreaths and more
- **Catch the Gift** mode: every so often a glowing gift drifts down with the snow. Click it before it lands to catch it. Keep a streak going and gifts fall a little faster; catches unlock the six Surprise Extras decorations (1, 3, 6, 10, 15 and 21 gifts). Your score and best streak show in the menu
- **Snowball Fight** mode: cheeky snowmen pop up on top of your windows, the Dock or the bottom of the screen and lob snowballs at you. Incoming snowballs swell as they get closer and splat on your screen, then slide down and melt. Click a snowman to throw one back (bonk!), hold ⌥ Option and click to throw anywhere, or click an incoming snowball to swat it away. If you move or close the window a snowman is standing on, it tumbles off. Note: while you hold Option in this mode, clicks go to Nook instead of your apps
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
- `Sources/Nook/Modes`: playful modes (`CatchTheGift/`, `SnowballFight/`, and shared effects in `ModeEffects.swift`)
- `Sources/Nook/Wallpapers`: the wallpaper library, picker and video wallpapers
- `Resources/Wallpapers`: the wallpaper images that come with Nook
