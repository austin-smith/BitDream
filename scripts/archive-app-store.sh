#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/archive-app-store.sh <macos|ios>

Archive BitDream for App Store Connect with the commit count as its build
number, then open the archive in Xcode's Organizer for upload.

Platforms:
  macos       Archive the Mac App Store target (BitDreamAppStore).
  ios         Archive the iOS app (BitDream).
EOF
}

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi

platform="$1"
case "$platform" in
  macos)
    scheme="BitDreamAppStore"
    destination="generic/platform=macOS"
    ;;
  ios)
    scheme="BitDream"
    destination="generic/platform=iOS"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

cd "$(dirname "$0")/.."

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The working tree must be clean, so the build number identifies the archived source." >&2
  git status --short >&2
  exit 1
fi

if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "The checkout is shallow, so the commit count is incomplete. Fetch the full history." >&2
  exit 1
fi

# App Store Connect rejects a build number that is not higher than earlier
# uploads of the same version. Commit counts increase only along main, so a
# commit that never reaches main could claim a number that later commits on
# main cannot exceed.
git fetch --quiet origin main
if ! git merge-base --is-ancestor HEAD FETCH_HEAD; then
  echo "HEAD must be a commit on origin/main, so its build number stays below later commits on main." >&2
  exit 1
fi

build_number="$(git rev-list --count HEAD)"

if [[ -z "$(git tag --points-at HEAD --list 'v*')" ]]; then
  echo "warning: HEAD has no release tag. Archive the tagged commit when submitting a release." >&2
fi

scripts/build-tailscale.sh

archive_path="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/BitDream $platform $build_number $(date +%H.%M.%S).xcarchive"

xcodebuild archive \
  -project BitDream.xcodeproj \
  -scheme "$scheme" \
  -configuration Release \
  -destination "$destination" \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build_number"

echo
echo "Archived build $build_number at:"
echo "$archive_path"
echo
echo "In Organizer, choose Distribute App > Custom > App Store Connect > Upload,"
echo "and turn off \"Manage Version and Build Number\" so the build stays $build_number."
open "$archive_path"
