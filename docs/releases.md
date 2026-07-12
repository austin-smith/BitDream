# Creating a Release

Set the app and widget `MARKETING_VERSION` to the same `major.minor.patch` value and merge the change into `main`. The local checkout must be clean, match `origin/main`, and have `Config/BuildSettings.local.xcconfig` configured.

Run the preflight checks, then create a stable release tag:

```bash
./scripts/tag-version.sh --dry-run
./scripts/tag-version.sh
```

For a prerelease, provide a suffix without the leading hyphen:

```bash
./scripts/tag-version.sh --dry-run --prerelease beta.1
./scripts/tag-version.sh --prerelease beta.1
```

Pushing the tag starts `.github/workflows/release.yml`, which builds, signs, notarizes, and publishes the macOS release. The workflow rejects tags that do not match the Xcode marketing version.

See `docs/build-settings.md` and `docs/sparkle-updates.md` for configuration details.
