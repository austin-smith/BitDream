# Tailscale

This module embeds Tailscale in BitDream so the app can connect to Transmission
over a tailnet without requiring the Tailscale companion app.

## Build

Install Go and select Xcode 26 or later. From the repository root, run:

```sh
scripts/build-tailscale.sh
```

Run this before opening a fresh checkout in Xcode, and again after changing the
Go code or its dependencies. The script uses a pinned Go toolchain, verifies
dependency checksums, and builds for macOS, iOS, and the iOS simulator.

The output is `Packages/TailscaleCore/TailscaleCore.xcframework`, which is ignored
by Git. The [TailscaleCore package](../Packages/TailscaleCore/Package.swift) makes
it available to the Swift app. CI and release workflows run the same build script.

## Code layout

- [main.go](main.go): embedded node lifecycle, connection status, and authenticated SOCKS proxy.
- [TailscaleCore.h](TailscaleCore.h): C interface used by Swift.
- [BitDream/Tailscale](../BitDream/Tailscale): Swift bridge and connection service.
- [go.mod](go.mod) and [go.sum](go.sum): dependency versions and checksums.

The app routes Transmission requests through the embedded node using a dedicated
URLSession. Connections are limited to machines visible in the tailnet; subnet
routes are not supported. Node identity is stored in the app's Application Support
directory and excluded from backups.

## Tests

From the repository root:

```sh
go -C Tailscale test -race ./...
```

The Go tests use local network fixtures. Swift integration tests are part of the
BitDream test suite.

## Updating dependencies

Update `go.mod` and `go.sum`, then rebuild the framework and run the Go and app
tests. Keep the Go toolchain version consistent across the build script, notices
script, and GitHub Actions workflows.

The proxy uses `NetstackDialTCP` directly to prevent fallback to the system
network. Check this integration when upgrading Tailscale.

Regenerate the bundled license notices after dependency updates:

```sh
scripts/update-tailscale-notices.sh
```

Review the resulting changes to
[BitDream/Resources/TailscaleNotices.txt](../BitDream/Resources/TailscaleNotices.txt).
