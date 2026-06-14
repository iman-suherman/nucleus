#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/DerivedData/Build/Products/Release/Nucleus.app"
OUTPUT_DMG="$ROOT_DIR/Nucleus.dmg"

echo "==> Building Nucleus release app"
bash "$ROOT_DIR/scripts/build.sh" release

if [[ ! -d "$APP_PATH" ]]; then
  echo "Release build failed — Nucleus.app not found at:"
  echo "$APP_PATH"
  exit 1
fi

echo "==> Ad-hoc signing for local install"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --verbose "$APP_PATH"

echo "==> Creating DMG installer"
bash "$ROOT_DIR/scripts/create-dmg.sh" "$APP_PATH" "$OUTPUT_DMG"

echo ""
echo "Done."
echo "  DMG: $OUTPUT_DMG"
echo "  Open the disk image, drag Nucleus.app to Applications, then launch from /Applications."
echo ""

open "$OUTPUT_DMG"
