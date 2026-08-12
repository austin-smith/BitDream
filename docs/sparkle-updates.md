# Sparkle Update Configuration

## Required Variables
- `SPARKLE_APPCAST_URL`: Sparkle feed URL.
- `SPARKLE_PUBLIC_KEY`: Sparkle public key.

## Build Contract
- `INFOPLIST_KEY_SUFeedURL[sdk=macosx*]` resolves from `$(SPARKLE_APPCAST_URL)`.
- `INFOPLIST_KEY_SUPublicEDKey[sdk=macosx*]` resolves from `$(SPARKLE_PUBLIC_KEY)`.

## Validation
- Local and pull request builds use the tracked `__UNSET__` defaults when no local override file is present.
- `Config/BuildSettings.local.xcconfig` can provide values when testing Sparkle locally.
- The release workflow validates `SPARKLE_APPCAST_URL` format and verifies embedded app `SUFeedURL` and `SUPublicEDKey` match expected values.

## Release Workflow Contract
- GitHub repository variables: `SPARKLE_APPCAST_URL`, `SPARKLE_PUBLIC_KEY`.
- Workflow injects Sparkle settings into:
  - app archive build (`xcodebuild archive`)
  - appcast generation/download steps
- Workflow verifies embedded app values match `SPARKLE_APPCAST_URL` and `SPARKLE_PUBLIC_KEY`.
