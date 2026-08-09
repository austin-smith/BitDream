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

Select the `BitDreamAppStore` scheme in Xcode, choose **Any Mac** as the run
destination, and use **Product > Archive**. Confirm that Xcode selects the Mac
App Store provisioning profiles for both the app and widget extension before
uploading the archive through Organizer.

Keep `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` synchronized between the
App Store app and widget targets. The direct-download release remains managed by
`.github/workflows/release.yml` and its Sparkle appcast workflow.
