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

Options:
  -h, --help  Show this help text.
EOF
}

platform=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    macos|ios)
      if [[ -n "$platform" ]]; then
        echo "Specify exactly one platform." >&2
        usage >&2
        exit 2
      fi
      platform="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$platform" ]]; then
  usage >&2
  exit 2
fi

case "$platform" in
  macos)
    scheme="BitDreamAppStore"
    destination="generic/platform=macOS"
    bundle_contents="Contents/"
    ;;
  ios)
    scheme="BitDream"
    destination="generic/platform=iOS"
    bundle_contents=""
    ;;
esac

for command in git xcodebuild; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(git -C "$script_directory" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "The archive script must be located inside the BitDream repository." >&2
  exit 1
}
cd "$repository_root"

if [[ ! -f BitDream.xcodeproj/project.pbxproj ]]; then
  echo "The archive script must be located inside the BitDream repository." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The working tree must be clean, so the build number identifies the archived source." >&2
  git status --short >&2
  exit 1
fi

if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
  echo "The checkout is shallow, so the commit count is incomplete. Fetch the full history." >&2
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "The repository does not have an origin remote." >&2
  exit 1
fi

echo "Fetching origin/main and release tags..."
git fetch origin refs/heads/main:refs/remotes/origin/main --tags

# App Store Connect rejects a build number that is not higher than earlier
# uploads of the same version. Commit counts increase only along main, so a
# commit that never reaches main could claim a number that later commits on
# main cannot exceed.
if ! git merge-base --is-ancestor HEAD refs/remotes/origin/main; then
  echo "HEAD must be a commit on origin/main, so its build number stays below later commits on main." >&2
  echo "HEAD: $(git rev-parse HEAD)" >&2
  exit 1
fi

# Package resolution, including reading build settings, needs the framework.
echo "Building embedded Tailscale..."
scripts/build-tailscale.sh
echo

versions="$({
  xcodebuild \
    -project BitDream.xcodeproj \
    -scheme "$scheme" \
    -configuration Release \
    -destination "$destination" \
    -showBuildSettings
} | awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3 }' | sort -u)"

version_count="$(printf '%s\n' "$versions" | awk 'NF { count++ } END { print count + 0 }')"
if [[ "$version_count" -ne 1 ]]; then
  echo "Expected exactly one MARKETING_VERSION, but found $version_count." >&2
  if [[ -n "$versions" ]]; then
    printf '%s\n' "$versions" >&2
  fi
  exit 1
fi

version="$versions"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "MARKETING_VERSION must use numeric major.minor.patch format: $version" >&2
  exit 1
fi

build_number="$(git rev-list --count HEAD)"
short_commit="$(git rev-parse --short HEAD)"

echo "Platform:        $platform"
echo "Release version: $version"
echo "Build number:    $build_number"
echo "Commit:          $short_commit"

if ! git tag --points-at HEAD | grep -Fx "v$version" >/dev/null; then
  echo
  echo "warning: HEAD is not the v$version release tag. Archive the tagged commit when submitting a release." >&2
fi

archive_directory="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
archive_path="$archive_directory/BitDream $version ($build_number) $platform.xcarchive"

if [[ -e "$archive_path" ]]; then
  echo "An archive already exists at $archive_path" >&2
  exit 1
fi

echo
echo "Archiving $scheme..."
mkdir -p "$archive_directory"
xcodebuild archive \
  -project BitDream.xcodeproj \
  -scheme "$scheme" \
  -configuration Release \
  -destination "$destination" \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build_number"

archived_version="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$archive_path/Info.plist")"
archived_build_number="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$archive_path/Info.plist")"
if [[ "$archived_version" != "$version" || "$archived_build_number" != "$build_number" ]]; then
  echo "The archive reports $archived_version ($archived_build_number), expected $version ($build_number)." >&2
  exit 1
fi

app_path="$(find "$archive_path/Products/Applications" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$app_path" ]]; then
  echo "No app found in $archive_path/Products/Applications" >&2
  exit 1
fi

for info_plist in "$app_path/${bundle_contents}Info.plist" "$app_path/${bundle_contents}PlugIns/"*.appex/"${bundle_contents}Info.plist"; do
  if [[ ! -f "$info_plist" ]]; then
    echo "Missing Info.plist at $info_plist" >&2
    exit 1
  fi

  bundle_build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")"
  if [[ "$bundle_build_number" != "$build_number" ]]; then
    echo "CFBundleVersion ($bundle_build_number) in $info_plist does not match the commit count ($build_number)." >&2
    exit 1
  fi
done

echo
echo "Archived BitDream $version ($build_number) for $platform:"
echo "$archive_path"
echo
echo "Opening the archive in Organizer. Choose Distribute App > Custom >"
echo "App Store Connect > Upload, and turn off \"Manage Version and Build Number\""
echo "so the uploaded build stays $build_number."
open "$archive_path"
