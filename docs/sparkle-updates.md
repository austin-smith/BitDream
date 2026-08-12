# Sparkle Update Configuration

## App Configuration

`BitDream/Info.plist` contains the public Sparkle configuration:

- `SUFeedURL`: Sparkle feed URL.
- `SUPublicEDKey`: Sparkle public EdDSA key.

Local, pull request, and release builds all use these tracked values. The
release workflow verifies that the archived app contains the same values.

## Release Signing

The Sparkle private EdDSA key is stored in the GitHub Actions secret
`SPARKLE_PRIVATE_KEY_BASE64`. The release workflow uses it to sign appcast
entries. Never commit the private key.
