# Creating a Release

Set the app and widget `MARKETING_VERSION` to the same `major.minor.patch` value and merge the change into `main`. The local checkout must be clean and match `origin/main`.

Run the preflight checks, then create a stable release tag:

```bash
./scripts/tag-version.sh --dry-run
./scripts/tag-version.sh
```

Pushing the tag starts `.github/workflows/release.yml`, which builds, signs, notarizes, and publishes the macOS release. The workflow rejects tags that do not match the Xcode marketing version.

See `docs/sparkle-updates.md` for Sparkle configuration details.

This workflow publishes the direct-download build. See
`docs/mac-app-store.md` for the separate Mac App Store archive process.
