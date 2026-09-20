#!/bin/bash
# Build all shipping architectures from the checked-in Go dependency lockfile.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root/Tailscale"
export GOTOOLCHAIN=go1.26.8
export CGO_ENABLED=1
export CC="$(xcrun --find clang)"
out="$root/.build/tailscale"
mkdir -p "$out/headers"
cp TailscaleCore.h "$out/headers/"
printf 'module TailscaleCore { header "TailscaleCore.h" export * }\n' > "$out/headers/module.modulemap"
go mod download
go mod verify
build() {
    local name="$1" os="$2" arch="$3" sdk="$4" target="$5"
    GOOS="$os" GOARCH="$arch" \
        CGO_CFLAGS="-target $target -isysroot $(xcrun --sdk "$sdk" --show-sdk-path)" \
        CGO_LDFLAGS="-target $target -isysroot $(xcrun --sdk "$sdk" --show-sdk-path)" \
        go build -mod=readonly -trimpath -buildvcs=false -buildmode=c-archive -o "$out/$name.a" .
}
build mac-arm64 darwin arm64 macosx arm64-apple-macos26.0
build mac-x86_64 darwin amd64 macosx x86_64-apple-macos26.0
build ios-arm64 ios arm64 iphoneos arm64-apple-ios26.0
build sim-arm64 ios arm64 iphonesimulator arm64-apple-ios26.0-simulator
build sim-x86_64 ios amd64 iphonesimulator x86_64-apple-ios26.0-simulator
xcrun lipo -create "$out/mac-arm64.a" "$out/mac-x86_64.a" -output "$out/libTailscaleCore-macos.a"
xcrun lipo -create "$out/sim-arm64.a" "$out/sim-x86_64.a" -output "$out/libTailscaleCore-simulator.a"
# Generate outside the package and replace only after every slice builds.
artifact="$out/TailscaleCore.xcframework"
if [ -d "$artifact" ]; then rm -rf "$artifact"; fi
xcodebuild -create-xcframework \
    -library "$out/libTailscaleCore-macos.a" -headers "$out/headers" \
    -library "$out/ios-arm64.a" -headers "$out/headers" \
    -library "$out/libTailscaleCore-simulator.a" -headers "$out/headers" \
    -output "$artifact"
destination="$root/Packages/TailscaleCore/TailscaleCore.xcframework"
if [ -d "$destination" ]; then rm -rf "$destination"; fi
cp -R "$artifact" "$destination"
