#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh <Nucleus.app> <output.dmg>}"
OUTPUT_DMG="${2:?Usage: create-dmg.sh <Nucleus.app> <output.dmg>}"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

mkdir -p "$STAGING/Nucleus"
cp -R "$APP_PATH" "$STAGING/Nucleus/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "Nucleus" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  "$OUTPUT_DMG"

echo "Created: $OUTPUT_DMG"
