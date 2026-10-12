#!/bin/bash
# Build only the disposable simulator design preview; no signing or installation.
set -euo pipefail
preview_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_output="$preview_root/.build/design/BuddyCheckDesign.app"
preview_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
preview_arch="$(uname -m)"
mkdir -p "$preview_output" "$preview_root/.build/design/module-cache"
xcrun --sdk iphonesimulator swiftc \
  -parse-as-library -swift-version 6 \
  -target "${preview_arch}-apple-ios18.0-simulator" \
  -sdk "$preview_sdk" \
  -module-cache-path "$preview_root/.build/design/module-cache" \
  "$preview_root/design/BuddyCheckPreview.swift" \
  -o "$preview_output/BuddyCheckDesign"
cat > "$preview_output/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.wipost165.buddychecks.designpreview</string>
<key>CFBundleName</key><string>Buddy Check Design</string>
<key>CFBundleDisplayName</key><string>Buddy Check Design</string>
<key>CFBundleExecutable</key><string>BuddyCheckDesign</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1</string>
<key>MinimumOSVersion</key><string>18.0</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST
printf 'Built simulator design preview: %s\n' "$preview_output"
