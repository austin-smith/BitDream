#!/bin/bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/tag-version.sh [--dry-run] [--prerelease SUFFIX]

Create and push a release tag based on the app's MARKETING_VERSION.

Options:
  --dry-run            Run every preflight check without creating or pushing a tag.
  --prerelease SUFFIX  Append a prerelease suffix, for example beta.1.
  -h, --help           Show this help text.
EOF
}

dry_run=false
prerelease_suffix=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=true
      shift
      ;;
    --prerelease)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--prerelease requires a suffix." >&2
        usage >&2
        exit 2
      fi
      prerelease_suffix="$2"
      shift 2
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

if [[ -n "$prerelease_suffix" && ! "$prerelease_suffix" =~ ^[0-9A-Za-z]+([.-][0-9A-Za-z]+)*$ ]]; then
  echo "Prerelease suffix must contain alphanumeric identifiers separated by dots or hyphens: $prerelease_suffix" >&2
  exit 2
fi

for command in git xcodebuild; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(git -C "$script_directory" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "The release script must be located inside the BitDream repository." >&2
  exit 1
}
cd "$repository_root"

if [[ ! -f BitDream.xcodeproj/project.pbxproj ]]; then
  echo "The release script must be located inside the BitDream repository." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "The working tree must be clean before creating a release tag." >&2
  git status --short >&2
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "The repository does not have an origin remote." >&2
  exit 1
fi

if [[ ! -f Config/BuildSettings.local.xcconfig ]]; then
  echo "Missing Config/BuildSettings.local.xcconfig." >&2
  echo "Create it from Config/BuildSettings.example.local.xcconfig before tagging a release." >&2
  exit 1
fi

echo "Fetching origin/main and release tags..."
git fetch origin refs/heads/main:refs/remotes/origin/main --tags

head_commit="$(git rev-parse HEAD)"
main_commit="$(git rev-parse refs/remotes/origin/main)"

if [[ "$head_commit" != "$main_commit" ]]; then
  echo "HEAD must match origin/main before creating a release tag." >&2
  echo "HEAD:        $head_commit" >&2
  echo "origin/main: $main_commit" >&2
  exit 1
fi

versions="$({
  xcodebuild \
    -project BitDream.xcodeproj \
    -scheme BitDream \
    -configuration Release \
    -destination "generic/platform=macOS" \
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

tag="v$version"
if [[ -n "$prerelease_suffix" ]]; then
  tag="$tag-$prerelease_suffix"
fi

if git show-ref --verify --quiet "refs/tags/$tag"; then
  echo "Tag already exists: $tag" >&2
  exit 1
fi

if ! remote_tag="$(git ls-remote --tags origin "refs/tags/$tag")"; then
  echo "Unable to check whether $tag already exists on origin." >&2
  exit 1
fi

if [[ -n "$remote_tag" ]]; then
  echo "Tag already exists on origin: $tag" >&2
  exit 1
fi

short_commit="$(git rev-parse --short HEAD)"
echo
echo "Release version: $version"
if [[ -n "$prerelease_suffix" ]]; then
  echo "Prerelease:      $prerelease_suffix"
fi
echo "Tag:             $tag"
echo "Commit:          $short_commit"

if [[ "$dry_run" == true ]]; then
  echo
  echo "Dry run complete. No tag was created or pushed."
  exit 0
fi

echo
if ! read -r -p "Create and push $tag to origin? [y/N] " response; then
  echo >&2
  echo "Release cancelled." >&2
  exit 1
fi

case "$response" in
  y|Y|yes|YES|Yes) ;;
  *)
    echo "Release cancelled."
    exit 0
    ;;
esac

git tag "$tag"

if ! git push origin "refs/tags/$tag"; then
  echo "Tag push failed; removing the newly created local tag." >&2
  git tag -d "$tag" >/dev/null
  exit 1
fi

origin_url="$(git remote get-url origin)"
case "$origin_url" in
  https://github.com/*)
    repository_url="${origin_url%.git}"
    ;;
  git@github.com:*)
    repository_url="https://github.com/${origin_url#git@github.com:}"
    repository_url="${repository_url%.git}"
    ;;
  *)
    repository_url=""
    ;;
esac

echo
echo "Pushed $tag. The GitHub release workflow has started."
if [[ -n "$repository_url" ]]; then
  echo "$repository_url/actions/workflows/release.yml"
fi
