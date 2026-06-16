#!/usr/bin/env bash
# Initialize CloudKit Development schema from SwiftData models (includes CD_entityName etc.).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_OUT="${1:-$ROOT_DIR/cloudkit/nucleus-development.ckdb}"
CKTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/cktool"
TEAM_ID="${APPLE_TEAM_ID:-Q3TXW887NM}"
CONTAINER_ID="${NUCLEUS_ICLOUD_CONTAINER:-iCloud.net.suherman.nucleus}"

echo "==> Initialize CloudKit Development schema from SwiftData"
echo "    Container: $CONTAINER_ID"
echo "    Output:    $SCHEMA_OUT"
echo

echo "==> Building Nucleus (Debug, Development CloudKit entitlements)…"
xcodebuild \
  -project "$ROOT_DIR/app/Nucleus.xcodeproj" \
  -scheme Nucleus \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGN_ENTITLEMENTS="$ROOT_DIR/app/Nucleus/entitlements.mac.development.plist" \
  build \
  | tail -5

APP="$(
  xcodebuild \
    -project "$ROOT_DIR/app/Nucleus.xcodeproj" \
    -scheme Nucleus \
    -configuration Debug \
    -destination 'platform=macOS' \
    CODE_SIGN_ENTITLEMENTS="$ROOT_DIR/app/Nucleus/entitlements.mac.development.plist" \
    -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/TARGET_BUILD_DIR/ { dir=$2 } /FULL_PRODUCT_NAME/ { name=$2 } END { print dir "/" name }'
)"

if [[ ! -d "$APP" ]]; then
  echo "Build failed — Nucleus.app not found at: $APP" >&2
  exit 1
fi

echo "==> Running initializeCloudKitSchema via $APP"
NUCLEUS_SEED_CLOUDKIT_SCHEMA=1 "$APP/Contents/MacOS/Nucleus" &
APP_PID=$!
sleep 10
kill "$APP_PID" 2>/dev/null || true
wait "$APP_PID" 2>/dev/null || true

echo "==> Exporting Development schema from CloudKit"
if [[ -n "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ]]; then
  "$CKTOOL" export-schema \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment development \
    --output-file "$SCHEMA_OUT"
  echo "Exported → $SCHEMA_OUT"
  echo
  echo "Next: deploy Development → Production in CloudKit Console, or run:"
  echo "  CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/seed-cloudkit-development.sh"
  echo "  then Deploy Schema Changes → Production"
else
  echo "Set CLOUDKIT_MANAGEMENT_TOKEN to export schema to $SCHEMA_OUT"
  echo "Or export manually from CloudKit Console → Development → Export Schema"
fi
