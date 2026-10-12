#!/bin/bash
# Capture fictional review scenarios on an already booted simulator.
set -euo pipefail
preview_device="${1:?Pass the UDID of a booted simulator}"
preview_root="$(cd "$(dirname "$0")/.." && pwd)"
preview_capture_dir="${2:-$preview_root/design/review}"
preview_bundle=org.wipost165.buddychecks.designpreview
mkdir -p "$preview_capture_dir"
for preview_screen in home people person outcome reminder saved followups followup resume denied; do
  xcrun simctl terminate "$preview_device" "$preview_bundle" 2>/dev/null || true
  xcrun simctl launch "$preview_device" "$preview_bundle" --screen "$preview_screen" >/dev/null
  sleep "${PREVIEW_RENDER_WAIT_SECONDS:-4}"
  xcrun simctl io "$preview_device" screenshot "$preview_capture_dir/$preview_screen.png" >/dev/null
done
for preview_screen in home person outcome reminder saved followup; do
  xcrun simctl terminate "$preview_device" "$preview_bundle" 2>/dev/null || true
  xcrun simctl launch "$preview_device" "$preview_bundle" --screen "$preview_screen" --accessibility-max >/dev/null
  sleep "${PREVIEW_RENDER_WAIT_SECONDS:-4}"
  xcrun simctl io "$preview_device" screenshot "$preview_capture_dir/$preview_screen-accessibility.png" >/dev/null
done
printf 'Captured design scenarios in %s\n' "$preview_capture_dir"
