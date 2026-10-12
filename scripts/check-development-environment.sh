#!/bin/bash
# Read-only toolchain check. This does not build or test the application.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf '%s\n' 'iOS development requires macOS with Xcode.' >&2
  exit 1
fi

# Use the full Xcode installation without changing the system-wide selection.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  printf 'Full Xcode was not found at %s. Set DEVELOPER_DIR to its Developer directory.\n' "$DEVELOPER_DIR" >&2
  exit 1
fi

printf 'Using %s\n' "$DEVELOPER_DIR"
/usr/bin/xcodebuild -version
if ! /usr/bin/xcodebuild -checkFirstLaunchStatus; then
  printf '%s\n' 'Open Xcode, review its license, and complete first-run component installation.' >&2
  exit 1
fi

/usr/bin/xcrun swift --version
/usr/bin/xcrun --sdk iphoneos --show-sdk-version
/usr/bin/xcrun --sdk iphonesimulator --show-sdk-version
runtimes="$(/usr/bin/xcrun simctl list runtimes)"
printf '%s\n' "$runtimes"
if ! printf '%s\n' "$runtimes" | awk '/^iOS / && $0 !~ /unavailable/ { found = 1 } END { exit !found }'; then
  printf '%s\n' 'Install an iOS Simulator runtime in Xcode Settings > Components.' >&2
  exit 1
fi
/usr/bin/xcrun simctl list devices available
printf '%s\n' 'Toolchain checks passed. App builds, simulator launches, signing, and physical-device behavior require separate verification.'
