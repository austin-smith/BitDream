# Screenshot capture

Capture the library, torrent details, and files in light and dark
appearances using the sample data from [demo mode](demo-mode.md).

## Capture PNGs

For macOS, run from the repository root:

```sh
python3 scripts/capture-screenshots.py
```

For a **booted** iOS simulator, pass its ID (listed by `xcrun simctl list devices`):

```sh
python3 scripts/capture-screenshots.py \
  --destination 'platform=iOS Simulator,id=YOUR-SIMULATOR-UDID'
```

The six PNGs go under `.build/screenshots/<timestamp>-macos/` or
`.build/screenshots/<timestamp>-ios/`, alongside capture metadata and test results.
Files are named `<screen>-<appearance>.png`, such as
`library-light.png`. Use `--output /path/to/new-directory` to choose a different
directory; it must not already exist.

Captures use English, US formatting, UTC, and Large text size:

- **iOS:** portrait orientation and a 9:41 status bar, cleared afterward.
- **macOS:** a window with 1200 × 900 points of content and a 220-point
  sidebar. The display must fit the full window, including its title bar.

Keep the OS, device, display scale, and wallpaper consistent when comparing images.

## Device frames

Install ImageMagick 7 (`brew install imagemagick`) and download the matching PNG
and Photoshop bezel from [Apple Design Resources](https://developer.apple.com/design/resources/#product-bezels).
Keep downloaded artwork in `.build/screenshot-frames/`; it is not committed.
Use matching PNG and PSD files for the selected device:

| Device argument | Apple artwork |
| --- | --- |
| `iphone-18-pro` | iPhone 18 Pro, portrait, same color for both files |
| `macbook-pro-14-silver` | MacBook Pro M5 14-inch Silver |
| `studio-display` | Studio Display 2026 On Light Background |
| `imac-pink` | iMac M4 24-inch Pink |

For iPhone:

```sh
python3 scripts/frame-screenshots.py .build/screenshots/<timestamp>-ios \
  --device iphone-18-pro --frame /path/to/frame.png --template /path/to/template.psd
```

For Mac, provide light and dark wallpapers:

```sh
python3 scripts/frame-screenshots.py .build/screenshots/<timestamp>-macos \
  --device macbook-pro-14-silver \
  --frame /path/to/frame.png --template /path/to/template.psd \
  --wallpaper-light /path/to/TahoeLight.heic --wallpaper-dark /path/to/TahoeDark.heic
```

Apple's Tahoe images are bundled in
`/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources/`.
Mac compositions use the wallpaper, rounded window edges, and a shadow, with no
menu bar or Dock. The app image scales proportionally to fit; iPhone images stay
at native resolution. Neither command controls the desktop or changes originals.

Each command creates six transparent PNGs directly in the capture's `framed/`
folder, named `<screen>-<appearance>-<device>.png`, plus `<device>.json` with
source hashes, output hashes, and rendering settings. Run it for each desired
device. Use `--screen detail` for just the two detail previews, or `--replace`
to regenerate matching exports. Failed renders leave existing exports intact.

## Capture settings

Automated captures use Demo Server and fresh capture preferences.

For manual capture, add `BITDREAM_SCREENSHOT=1` under **Edit Scheme → Run →
Arguments → Environment Variables** in **BitDreamDemo**. Remove it afterward.

| Variable | Values | Default |
| --- | --- | --- |
| `BITDREAM_SCREENSHOT_APPEARANCE` | `light`, `dark` | `light` |
| `BITDREAM_SCREENSHOT_COMPACT` | `1` for the macOS table | expanded |

Manual capture uses fixed appearance, layout, text size, and time, with separate
preferences and automatic retries disabled. Set language, time zone, and status
bar yourself; the script handles those for automated captures.

## Add captures

Extend `BitDreamScreenshotTests/ScreenshotTests.swift` using normal controls and
stable accessibility identifiers. Wait for the required content, attach a
screenshot, and update the script's expected filenames. Inspect the exported
PNGs for framing and appearance.
