#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/release-env.sh"
export NUCLEUS_RELEASE_DEFAULTS=1

IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Huge Shop Pty Ltd (Q3TXW887NM)}"
ENTITLEMENTS="$ROOT_DIR/app/Nucleus/entitlements.mac.plist"
PROVISIONING_PROFILE="${MACOS_DEVELOPER_ID_PROVISIONING_PROFILE:-$ROOT_DIR/app/Nucleus/Nucleus_DeveloperID.provisionprofile}"
if [[ "$PROVISIONING_PROFILE" != /* ]]; then
  PROVISIONING_PROFILE="$ROOT_DIR/$PROVISIONING_PROFILE"
fi

BUILD_DIR="$ROOT_DIR/.build/weatherkit-test"
mkdir -p "$BUILD_DIR"

echo "==> Compiling WeatherKit test tool"
swiftc \
  -O \
  -target arm64-apple-macos14.0 \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -framework WeatherKit \
  -framework CoreLocation \
  "$ROOT_DIR/scripts/test-weatherkit.swift" \
  -o "$BUILD_DIR/test-weatherkit"

echo "==> Signing WeatherKit test tool"
codesign \
  --force \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  --timestamp \
  "$BUILD_DIR/test-weatherkit"

if [[ -f "$PROVISIONING_PROFILE" ]]; then
  cp "$PROVISIONING_PROFILE" "$BUILD_DIR/test-weatherkit.provisionprofile"
fi

echo "==> Running WeatherKit test (Sydney coordinates)"
if "$BUILD_DIR/test-weatherkit"; then
  echo "WeatherKit authentication and fetch succeeded."
else
  echo "WeatherKit test failed — App Services may still be propagating on Apple's side."
  exit 1
fi
