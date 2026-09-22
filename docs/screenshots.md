# Screenshot capture

Capture the library, torrent details, files, and peers in light and dark
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

The eight PNGs go under `.build/screenshots/<timestamp>/`, alongside capture
metadata and test results. Files are named `<screen>-<appearance>.png`, such as
`library-light.png`. Use `--output /path/to/new-directory` to choose a different
directory; it must not already exist.

Captures use English, US formatting, UTC, and Large text size:

- **iOS:** portrait orientation and a 9:41 status bar, cleared afterward.
- **macOS:** a centered window with 1200 × 900 points of content and a 220-point
  sidebar. The display must fit the full window, including its title bar.

Keep the OS, device, display scale, and wallpaper consistent when comparing images.

## Capture settings

Automated captures use Demo Server and fresh capture preferences.

For manual capture, add `BITDREAM_SCREENSHOT=1` under **Edit Scheme → Run →
Arguments → Environment Variables** in **BitDreamDemo**. Remove it afterward.

| Variable | Values | Default |
| --- | --- | --- |
| `BITDREAM_SCREENSHOT_APPEARANCE` | `light`, `dark` | `light` |
| `BITDREAM_SCREENSHOT_COMPACT` | `1` for the macOS table | expanded |

Manual capture uses fixed appearance, layout, text size, and time, with separate
preferences and automatic retries disabled. Set language, time zone, status bar,
and window position yourself; the script handles those for automated captures.

## Add captures

Extend `BitDreamScreenshotTests/ScreenshotTests.swift` using normal controls and
stable accessibility identifiers. Wait for the required content, attach a
screenshot, and update the script's expected filenames. Inspect the exported
PNGs for framing and appearance.
