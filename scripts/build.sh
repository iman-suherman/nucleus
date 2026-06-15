#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
CONFIGURATION="${1:-debug}"

echo "==> Building Nucleus packages"
cd "$ROOT_DIR"
swift build -c "$CONFIGURATION"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required to generate the app project."
  echo "Install with: brew install xcodegen"
  exit 1
fi

echo "==> Preparing app icon (rounded corners)"
bash "$ROOT_DIR/scripts/prepare-app-icon.sh"

echo "==> Bundling release notes"
node "$ROOT_DIR/scripts/bundle-release-notes.cjs"

echo "==> Generating app icon sizes from AppIconSource.png"
swift "$ROOT_DIR/scripts/generate-app-icon.swift" \
  "$APP_DIR/Nucleus/Assets.xcassets/AppIcon.appiconset" \
  "$APP_DIR/Nucleus/Assets/AppIconSource.png"

echo "==> Generating Xcode project"
cd "$APP_DIR"
xcodegen generate

XCODE_CONFIG="Debug"
case "$CONFIGURATION" in
  [Rr][Ee][Ll][Ee][Aa][Ss][Ee])
    XCODE_CONFIG="Release"
    ;;
esac

echo "==> Building Nucleus.app ($XCODE_CONFIG)"
XCODEBUILD_ARGS=(
  -project Nucleus.xcodeproj
  -scheme Nucleus
  -configuration "$XCODE_CONFIG"
  -derivedDataPath "$ROOT_DIR/.build/DerivedData"
)

if [[ "$XCODE_CONFIG" == "Release" ]]; then
  # Build unsigned; Developer ID signing + iCloud entitlements happen in scripts/sign.sh.
  XCODEBUILD_ARGS+=(
    CODE_SIGNING_ALLOWED=NO
    CODE_SIGN_ENTITLEMENTS=
  )
fi

XCODEBUILD_ARGS+=(build)

if ! xcodebuild "${XCODEBUILD_ARGS[@]}"; then
  echo "xcodebuild failed. If this is a fresh Xcode install, run: npm run setup:xcode"
  exit 1
fi

APP_PATH="$ROOT_DIR/.build/DerivedData/Build/Products/$XCODE_CONFIG/Nucleus.app"
if [[ -d "$APP_PATH" ]]; then
  ICNS_SOURCE="$APP_DIR/Nucleus/Assets/AppIcon.icns"
  if [[ -f "$ICNS_SOURCE" ]]; then
    cp "$ICNS_SOURCE" "$APP_PATH/Contents/Resources/AppIcon.icns"
  fi
  touch "$APP_PATH"
  /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$APP_PATH"
  echo "Built: $APP_PATH"
else
  echo "Build finished. Locate Nucleus.app under .build/DerivedData/Build/Products/"
fi
