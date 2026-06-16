#!/usr/bin/env bash
# Import Nucleus schema (including bills) into CloudKit Development, verify Production, deploy via Console.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="$ROOT_DIR/cloudkit/nucleus-development.ckdb"
TEAM_ID="${APPLE_TEAM_ID:-Q3TXW887NM}"
CONTAINER_ID="${NUCLEUS_ICLOUD_CONTAINER:-iCloud.net.suherman.nucleus}"
CKTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/cktool"
CONSOLE_URL="https://icloud.developer.apple.com/dashboard/database/teams/${TEAM_ID}/containers/iCloud.net.suherman.nucleus"

REQUIRED_TYPES=(
  CD_NoteRecord
  CD_GoogleAccountRecord
  CD_SyncedSettingsRecord
  CD_ClipboardItemRecord
  CD_BillRecord
  CD_BillPaymentRecord
)

echo "==> Nucleus CloudKit schema → Production (bills included)"
echo "    Container: $CONTAINER_ID"
echo "    Team:      $TEAM_ID"
echo "    Schema:    $SCHEMA_FILE"
echo

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Missing schema file: $SCHEMA_FILE" >&2
  exit 1
fi

if [[ ! -x "$CKTOOL" ]]; then
  echo "cktool not found. Install Xcode command line tools." >&2
  exit 1
fi

echo "==> Verifying local schema file includes bill record types"
missing_local=0
for type in "${REQUIRED_TYPES[@]}"; do
  if ! rg -q "RECORD TYPE $type" "$SCHEMA_FILE"; then
    echo "  MISSING in local file: $type" >&2
    missing_local=1
  fi
done
if [[ "$missing_local" -ne 0 ]]; then
  echo "Local schema is incomplete. Run: bash scripts/initialize-cloudkit-schema.sh" >&2
  exit 1
fi
echo "  All required CD_* types present locally (including bills)."
echo

print_production_deploy_steps() {
  cat <<EOF
==> Deploy Development schema to Production (required for release app bill sync)

Apple only allows Production schema deploy through CloudKit Console:

  1. Open: $CONSOLE_URL
  2. Select environment: Development (left sidebar)
  3. Schema → Record Types — confirm these exist:
     - CD_BillRecord
     - CD_BillPaymentRecord
     - CD_NoteRecord, CD_GoogleAccountRecord, CD_SyncedSettingsRecord, CD_ClipboardItemRecord
  4. Footer → "Deploy Schema Changes…"
  5. Review changes (should list CD_BillRecord / CD_BillPaymentRecord if new)
  6. Deploy to Production

After deploy:
  - Restart Nucleus on each Mac (release build uses Production CloudKit)
  - Bills → Sync (or wait for automatic export on launch)
  - Settings → iCloud sync log should show no BillRecord schema errors

EOF
}

if [[ -z "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ]]; then
  cat <<EOF
No CLOUDKIT_MANAGEMENT_TOKEN — import Development schema manually first:

  1. Open: $CONSOLE_URL
  2. Development → Footer → Import Schema…
  3. Choose: $SCHEMA_FILE
  4. Confirm import

Then deploy to Production (steps below).

Optional CLI (after creating a Management Token in CloudKit Console → Settings → API Access):
  CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/deploy-cloudkit-production-schema.sh

EOF
  print_production_deploy_steps
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "==> Importing schema into Development"
"$CKTOOL" import-schema \
  --token "$CLOUDKIT_MANAGEMENT_TOKEN" \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment development \
  --validate \
  --file "$SCHEMA_FILE"
echo "  Development import complete."
echo

echo "==> Validating schema against Development"
"$CKTOOL" validate-schema \
  --token "$CLOUDKIT_MANAGEMENT_TOKEN" \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment development \
  --file "$SCHEMA_FILE"
echo "  Development validation passed."
echo

echo "==> Exporting Production schema for comparison"
prod_schema="$tmpdir/production.ckdb"
"$CKTOOL" export-schema \
  --token "$CLOUDKIT_MANAGEMENT_TOKEN" \
  --team-id "$TEAM_ID" \
  --container-id "$CONTAINER_ID" \
  --environment production \
  --output-file "$prod_schema"

missing_prod=0
for type in "${REQUIRED_TYPES[@]}"; do
  if rg -q "RECORD TYPE $type" "$prod_schema"; then
    echo "  Production has: $type"
  else
    echo "  Production MISSING: $type"
    missing_prod=1
  fi
done
echo

if [[ "$missing_prod" -eq 0 ]]; then
  echo "Production already includes all required record types (including bills)."
  echo "If bills still do not sync, use Bills → Sync on the Mac that owns the data."
  exit 0
fi

echo "Production is missing bill (or other) record types — deploy Development → Production."
print_production_deploy_steps
