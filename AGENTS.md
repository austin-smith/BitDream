# BitDream Agent Guide

This file defines project constraints for coding agents working in this repository.

## Platform + Framework Contract (Non-Negotiable)

- This app is SwiftUI-first and should remain SwiftUI-only for UI work.
- Do not add `UIKit` or `AppKit` UI implementations.
- Do not add bridge wrappers like `UIViewRepresentable` or `NSViewRepresentable` unless a maintainer explicitly asks.
- Supported platforms are:
  - iOS 26+
  - macOS 26+
- Do not add compatibility paths for older OS versions.
- Do not introduce `if #available(...)` checks for pre-26 OS support unless explicitly requested.

## File/Platform Boundaries

Keep platform distinctions clear and intentional:

- `BitDream/Views/macOS/` is for macOS-specific UI and behavior.
- `BitDream/Views/iOS/` is for iOS-specific UI and behavior.
- `BitDream/Views/Shared/` is for cross-platform SwiftUI views and reusable components.

When adding new code:

- Prefer shared implementations first.
- Use platform-specific files only when behavior or UX truly differs.
- Use `#if os(iOS)` / `#if os(macOS)` only where necessary and keep conditionals narrow.

## Code Expectations

- Prefer modern Swift and SwiftUI APIs.
- Keep state flow explicit and minimal.
- Preserve responsiveness, accessibility, and smooth animations.
- Avoid speculative abstractions that make the code harder to read.

## What Agents Should Avoid

- No UIKit/AppKit UI fallbacks.
- No legacy or pre-26 compatibility hacks.
- No broad platform conditionals when file-level separation is clearer.

When in doubt, choose the simplest modern SwiftUI-first solution and preserve the macOS/iOS/shared split.

## Building

From repo root (`/Users/austinsmith/Developer/Repos/BitDream`), build with:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project BitDream.xcodeproj \
  -scheme BitDream \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  build
```

For iOS build (compile check without signing):

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project BitDream.xcodeproj \
  -scheme BitDream \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Linting

From repo root (`/Users/austinsmith/Developer/Repos/BitDream`), run:

```bash
swiftlint lint --quiet
```
