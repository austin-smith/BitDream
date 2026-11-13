# Mac App Store Distribution

BitDream has separate distribution targets that share the same Swift sources
and assets:

- `BitDream` and `BitDreamWidgetsExtension` produce the direct-download build.
  The app target links Sparkle and the release workflow signs both targets with
  Developer ID identities.
- `BitDreamAppStore` and `BitDreamWidgetsAppStoreExtension` produce the Mac App
  Store build. Neither target links Sparkle, and both use automatic App Store
  signing.

The `BitDreamAppStore` scheme builds the complete App Store target graph. Code
and UI that depend on Sparkle are guarded with `canImport(Sparkle)`, so they are
compiled only when the direct-download target supplies the package product.
`BitDream/Info-AppStore.plist` contains no Sparkle configuration.

## Validation

Before submission, build the App Store scheme without creating the local
Sparkle settings file. Verify that the built app:

- embeds the App Store widget extension;
- contains no Sparkle files;
- has no executable linked to Sparkle; and
- contains no Sparkle `SU...` keys in its Info.plist.

Run the same compile check locally from the repository root:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project BitDream.xcodeproj \
  -scheme BitDreamAppStore \
  -configuration Debug \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## Archiving

Archive with the script from the repository root. It requires a clean working
tree with full git history whose `HEAD` is on `origin/main`, builds the
embedded Tailscale framework, archives the `BitDreamAppStore` scheme with the
commit count as its build number, and opens the archive in Organizer:

```bash
./scripts/archive-app-store.sh macos
```

Archive the commit of the release tag, so the App Store build carries the same
version and build number as the direct-download release. The script warns when
`HEAD` has no release tag, and refuses commits that are not on `main`:
App Store Connect rejects a build number that is not higher than earlier
uploads of the same version, and only commits on `main` are guaranteed to have
lower commit counts than later commits on `main`. See `docs/releases.md` for
how build numbers are assigned. Use `./scripts/archive-app-store.sh ios` to
archive the iOS app the same way.

**Product > Archive** in Xcode cannot set the build number, so the
`Verify Build Number` phase fails those archives.

In Organizer, confirm that the archive lists the expected version and build
number, then choose **Distribute App > Custom > App Store Connect > Upload**.
The default distribution options don't show the build number setting. Confirm
that Xcode selects the App Store provisioning profiles for both the app and
widget extension, and turn off **Manage Version and Build Number**. Xcode
otherwise may replace the build number in the uploaded copy, and App Store
Connect would no longer match the archive or the commit. If App Store Connect
rejects the build number as already used, that commit has already been
uploaded; archive a newer commit instead of letting Xcode change the number.

Keep `MARKETING_VERSION` synchronized between the App Store app and widget
targets. The direct-download release remains managed by
`.github/workflows/release.yml` and its Sparkle appcast workflow.
