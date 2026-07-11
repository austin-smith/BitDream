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

## Branches, Commits, and Pull Requests

- Use plain lowercase kebab-case for branch names. Keep names descriptive and do not include issue numbers, prefixes, or namespaces such as `feature/`, `fix/`, usernames, or agent names.
- Write commit messages entirely lowercase. Use the imperative mood for the subject, keep each commit focused on one logical change, do not use type or scope prefixes, and do not end the subject with a period. Add a body when the reason or important tradeoffs are not clear from the subject.
- Keep each pull request focused on one coherent change.
- Write concise, specific, imperative pull request titles in sentence case. Do not use prefixes or trailing periods, and make the title understandable without the branch name.
- Pull request descriptions must include `What Changed`, `Why`, and `Validation`. Include `UI Changes` only when the pull request changes the UI. Keep descriptions concise, self-contained, complete, and accurate to the final diff.
- Link any related issues in the pull request description; do not include issue numbers in branch names.
- Review the complete diff before opening a pull request. Update the title and description whenever the scope changes, and remove unrelated changes.

## Issues

- Search open and closed issues before creating a new issue.
- Keep each issue focused on one problem or change.
- Use a concise, specific, sentence-case title without type prefixes.
- Give enough context to understand the issue without first inspecting the code.
- For bugs, describe the current and expected behavior. Include reproduction steps, environment details, and supporting evidence when available.
- For enhancements, explain the problem or goal, the desired outcome, and clear acceptance criteria.
- For UI issues, include screenshots. Include a short video when motion or interaction is relevant.
- Link any related issues and pull requests.
- Apply the appropriate existing labels when creating an issue: `bug` for bugs, `enhancement` for feature requests, and any applicable platform labels (`macOS`, `iOS`, `iPadOS`).

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

## Testing

From repo root (`/Users/austinsmith/Developer/Repos/BitDream`), run macOS tests with:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project BitDream.xcodeproj \
  -scheme BitDream \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
```

Testing guidance:

- Add tests when they protect meaningful user-visible behavior, cross-file integration, bug regressions, or non-trivial logic that is easy to break.
- Do not add dedicated tests for every small helper extraction, straightforward computed property, or internal refactor unless the change introduces real behavioral risk.
- Prefer a small number of high-signal tests over many narrow tests that only restate the implementation.

## Linting

From repo root (`/Users/austinsmith/Developer/Repos/BitDream`), run:

```bash
swiftlint lint --quiet
```
