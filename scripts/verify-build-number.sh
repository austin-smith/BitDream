#!/bin/bash

# Fails an archive whose build number is not the commit count.
#
# The app targets run this as an Xcode build phase marked "For install builds
# only", so it runs when archiving and never during ordinary builds. Shipping
# builds take CURRENT_PROJECT_VERSION from `git rev-list --count HEAD`: the
# release workflow and scripts/archive-app-store.sh pass it to xcodebuild. An
# archive made any other way keeps the project's placeholder and fails here.

set -euo pipefail

fail() {
  echo "error: $*" >&2
  exit 1
}

if ! git -C "${SRCROOT:?}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  fail "Cannot verify the build number: $SRCROOT is not a git checkout."
fi

if [[ "$(git -C "$SRCROOT" rev-parse --is-shallow-repository)" == "true" ]]; then
  fail "Cannot verify the build number: the git checkout is shallow. Fetch the full history."
fi

expected_build_number="$(git -C "$SRCROOT" rev-list --count HEAD)"

if [[ "${CURRENT_PROJECT_VERSION:-}" != "$expected_build_number" ]]; then
  fail "The build number is ${CURRENT_PROJECT_VERSION:-empty}, but archives must use the commit count, $expected_build_number. Archive with scripts/archive-app-store.sh, or pass CURRENT_PROJECT_VERSION=$expected_build_number to xcodebuild."
fi

if [[ -n "$(git -C "$SRCROOT" status --porcelain)" ]]; then
  echo "warning: Build $expected_build_number identifies commit $(git -C "$SRCROOT" rev-parse --short HEAD), but the working tree has uncommitted changes." >&2
fi
