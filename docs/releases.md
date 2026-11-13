# Creating a Release

## Version and Build Numbers

Every BitDream build carries two numbers:

- **Version** (`CFBundleShortVersionString`): the user-facing `major.minor.patch` version, set by `MARKETING_VERSION` in the project.
- **Build number** (`CFBundleVersion`): for shipping builds, the number of commits reachable from the archived commit (`git rev-list --count HEAD`). It is never edited by hand.

Sparkle and App Store Connect both require build numbers to increase, and the commit count increases with every commit merged into `main`. Shipping builds receive it as `CURRENT_PROJECT_VERSION` on the `xcodebuild` command line, so the app and its widget get the same value from the same build setting:

- The release workflow archives the direct-download build.
- `scripts/archive-app-store.sh` archives the Mac App Store and iOS builds. See `docs/mac-app-store.md`.

A direct-download, Mac App Store, and iOS build of the same commit therefore share one build number. The About screen shows it after the version, as `Version 2.1.2 (560)`.

Local builds keep the project's placeholder build number of `1`. Archiving requires the commit count: the `Verify Build Number` phase fails any archive whose build number differs from it, including an archive made with **Product > Archive** in Xcode.

## Tagging

Set the app and widget `MARKETING_VERSION` to the same `major.minor.patch` value and merge the change into `main`. The local checkout must be clean and match `origin/main`.

Run the preflight checks, then create a stable release tag:

```bash
./scripts/tag-version.sh --dry-run
./scripts/tag-version.sh
```

The script prints the build number the release will carry.

Pushing the tag starts `.github/workflows/release.yml`, which builds, signs, notarizes, and publishes the macOS release. The workflow rejects tags that do not match the Xcode marketing version, build numbers that are not newer than the published appcast's, and artifacts whose app or widget build number differs from the commit count.

See `docs/sparkle-updates.md` for Sparkle configuration details.

This workflow publishes the direct-download build. See
`docs/mac-app-store.md` for the separate Mac App Store archive process.
