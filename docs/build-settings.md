# Build Settings Reference

## Files
- `Config/BuildSettings.xcconfig` (tracked): shared defaults and variable declarations.
- `Config/BuildSettings.example.local.xcconfig` (tracked): template for local setup.
- `Config/BuildSettings.local.xcconfig` (ignored): required local/CI overrides.

These files configure the direct-download `BitDream` target. The
`BitDreamAppStore` target neither reads Sparkle settings nor requires a local
override file.

## Local Setup
1. Copy `Config/BuildSettings.example.local.xcconfig` to `Config/BuildSettings.local.xcconfig`.
2. Set local values (currently `SPARKLE_APPCAST_URL` and `SPARKLE_PUBLIC_KEY`).

## CI / Release
- CI writes `Config/BuildSettings.local.xcconfig` before archive builds.
- For Sparkle, release workflow uses repo variables `SPARKLE_APPCAST_URL` and `SPARKLE_PUBLIC_KEY`.
- The Mac App Store build uses its dedicated Sparkle-free target and scheme.
