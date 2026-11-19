# Nook

A cozy desktop overlay for macOS. Seasonal weather and little toys live on top of your real desktop. Version 1 is winter.

- Gentle snowfall that settles on the tops of your windows and the Dock
- Fling or resize a window and its snow flies off. Close one and its snow tumbles down
- Snow stays out of your open windows, and clicks always go through to your apps
- Wallpapers you can pick from, plus your own photos or videos
- Desktop decorations you design yourself: Christmas trees, snowmen, string lights, wreaths and more
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
- `Sources/Nook/Wallpapers`: the wallpaper library, picker and video wallpapers
- `Resources/Wallpapers`: the wallpaper images that come with Nook
