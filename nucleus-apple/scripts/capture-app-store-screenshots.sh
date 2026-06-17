#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IOS_APP="$ROOT/nucleus-apple/Apps/NucleusIOS"
PHONE_DEVICE="${PHONE_SIMULATOR:-iPhone 17 Pro Max}"
IPAD_DEVICE="${IPAD_SIMULATOR:-iPad Pro 13-inch (M5)}"
OUT_ROOT="$ROOT/nucleus-apple/AppStoreScreenshots"
IPHONE_APP_STORE_WIDTH=1284
IPHONE_APP_STORE_HEIGHT=2778

resize_iphone_screenshots() {
  local dir="$1"
  for file in "$dir"/*.png; do
    [[ -f "$file" ]] || continue
    local tmp="${file%.png}.resized.png"
    sips -z "$IPHONE_APP_STORE_HEIGHT" "$IPHONE_APP_STORE_WIDTH" "$file" --out "$tmp" >/dev/null
    mv "$tmp" "$file"
  done
}

capture_for_device() {
  local device_name="$1"
  local output_subdir="$2"

  local output_dir="$OUT_ROOT/$output_subdir"
  rm -rf "$output_dir"
  mkdir -p "$output_dir"

  echo "Capturing App Store screenshots on \"$device_name\" → $output_dir"

  (
    cd "$IOS_APP"
    xcodegen generate >/dev/null

    SCREENSHOT_OUTPUT_DIR="$output_dir" xcodebuild test \
      -project NucleusIOS.xcodeproj \
      -scheme NucleusIOS \
      -sdk iphonesimulator \
      -destination "platform=iOS Simulator,name=$device_name" \
      -only-testing:NucleusIOSScreenshots/AppStoreScreenshotTests/testCaptureAppStoreScreenshots \
      2>&1 | tail -25

    if [[ "$(find "$output_dir" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')" -lt 5 \
      && -d /tmp/nucleus-app-store-screenshots ]]; then
      cp /tmp/nucleus-app-store-screenshots/*.png "$output_dir/"
    fi
  )

  local count
  count=$(find "$output_dir" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
  if [[ "$count" -lt 5 ]]; then
    echo "error: expected at least 5 screenshots in $output_dir, found $count" >&2
    exit 1
  fi

  local upload_dir="$output_dir/upload"
  rm -rf "$upload_dir"
  mkdir -p "$upload_dir"
  local curated=(
    "01-dashboard.png"
    "03-notes-detail.png"
    "04-passwords-detail.png"
    "05-bills.png"
    "07-settings-notifications.png"
  )
  for file in "${curated[@]}"; do
    if [[ -f "$output_dir/$file" ]]; then
      cp "$output_dir/$file" "$upload_dir/$file"
    fi
  done

  if [[ "$output_subdir" == "iPhone-6.5-inch" ]]; then
    resize_iphone_screenshots "$output_dir"
    resize_iphone_screenshots "$upload_dir"
    echo "Resized iPhone screenshots to ${IPHONE_APP_STORE_WIDTH}×${IPHONE_APP_STORE_HEIGHT}"
  fi

  echo "Saved $count screenshots to $output_dir"
  echo "Upload set: $upload_dir"
}

echo "Building packages…"
swift build --package-path "$ROOT/nucleus-apple/Packages/NucleusCore" >/dev/null

capture_for_device "$PHONE_DEVICE" "iPhone-6.5-inch"
capture_for_device "$IPAD_DEVICE" "iPad-13-inch"

echo
echo "App Store screenshot sets:"
echo "  iPhone: $OUT_ROOT/iPhone-6.5-inch"
echo "  iPad:   $OUT_ROOT/iPad-13-inch"
echo
echo "Upload the iPhone PNGs to App Store Connect → 6.5\" Display."
echo "Upload the iPad PNGs to App Store Connect → iPad 13\" Display."
