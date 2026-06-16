#!/usr/bin/env bash
# Compare Nucleus expected CloudKit schema vs Development/Production containers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED="$ROOT_DIR/cloudkit/nucleus-development.ckdb"
TEAM_ID="${APPLE_TEAM_ID:-Q3TXW887NM}"
CONTAINER_ID="${NUCLEUS_ICLOUD_CONTAINER:-iCloud.net.suherman.nucleus}"
CKTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/cktool"

EXPECTED_TYPES=(
  CD_NoteRecord
  CD_GoogleAccountRecord
  CD_SyncedSettingsRecord
  CD_ClipboardItemRecord
  CD_BillRecord
  CD_BillPaymentRecord
)

echo "==> Nucleus CloudKit schema diagnosis"
echo "    Container: $CONTAINER_ID"
echo "    Team:      $TEAM_ID"
echo

echo "Expected record types (SwiftData / Nucleus):"
for type in "${EXPECTED_TYPES[@]}"; do
  echo "  - $type"
done
echo "Expected zone for synced data: com.apple.coredata.cloudkit.zone"
echo

if [[ ! -f "$EXPECTED" ]]; then
  echo "Missing expected schema file: $EXPECTED"
  exit 1
fi

echo "Local schema file record types in $EXPECTED:"
rg 'RECORD TYPE' "$EXPECTED" || true
echo

if [[ -z "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ]]; then
  cat <<EOF
No CLOUDKIT_MANAGEMENT_TOKEN — cannot export remote schema via cktool.

In CloudKit Console (https://icloud.developer.apple.com/), verify manually:

  PRODUCTION → Schema → Record Types
    Must include: CD_NoteRecord, CD_GoogleAccountRecord, CD_SyncedSettingsRecord, CD_ClipboardItemRecord, CD_BillRecord, CD_BillPaymentRecord
    Wrong types (without CD_ prefix) do NOT work: NoteRecord, SyncSettingsRecord, ClipboardItemRecord

  PRODUCTION → Data → Zones (Private Database)
    After successful Nucleus sync, expect: com.apple.coredata.cloudkit.zone
    Only _defaultZone means SwiftData never completed CloudKit setup.

Fix if CD_* types are missing:
  1. DEVELOPMENT → Schema → Import Schema → $EXPECTED
  2. DEVELOPMENT → Deploy Schema Changes → Production
  3. Restart Nucleus → Bills → Sync (or Settings → iCloud → Upload Notes to iCloud)

Full workflow:
  CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/deploy-cloudkit-production-schema.sh

To run this script against the live container:
  CloudKit Console → Settings → API Access → Create Management Token
  CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/diagnose-cloudkit-schema.sh
EOF
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

for env in development production; do
  out="$tmpdir/$env.ckdb"
  echo "==> Exporting $env schema…"
  "$CKTOOL" export-schema \
    --token "$CLOUDKIT_MANAGEMENT_TOKEN" \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment "$env" \
    --output-file "$out"

  echo "Record types in $env:"
  rg 'RECORD TYPE' "$out" || echo "  (none found)"
  echo

  missing=0
  for type in "${EXPECTED_TYPES[@]}"; do
    if ! rg -q "RECORD TYPE $type" "$out"; then
      echo "  MISSING in $env: $type"
      missing=1
    fi
  done

  if [[ "$missing" -eq 0 ]]; then
    echo "  All expected CD_* types present in $env."
  fi
  echo
done

echo "Validate local schema against development (dry-run):"
"$CKTOOL" validate-schema \
  --token "$CLOUDKIT_MANAGEMENT_TOKEN" \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment development \
  --file "$EXPECTED" || true

echo
echo "If CD_* types are missing in development, import then deploy:"
echo "  CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/deploy-cloudkit-production-schema.sh"
