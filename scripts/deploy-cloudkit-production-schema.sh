#!/usr/bin/env bash
# Import Nucleus schema (including bills) into CloudKit Development, verify Production, deploy via Console.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="$ROOT_DIR/cloudkit/nucleus-development.ckdb"
TEAM_ID="${APPLE_TEAM_ID:-Q3TXW887NM}"
CONTAINER_ID="${NUCLEUS_ICLOUD_CONTAINER:-iCloud.net.suherman.nucleus}"
CKTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/cktool"
CONSOLE_URL="https://icloud.developer.apple.com/dashboard/database/teams/${TEAM_ID}/containers/iCloud.net.suherman.nucleus"

if [[ -z "${CLOUDKIT_MANAGEMENT_TOKEN:-}" && -f "$ROOT_DIR/.env" ]]; then
  CLOUDKIT_MANAGEMENT_TOKEN="$(grep -m1 '^CLOUDKIT_MANAGEMENT_TOKEN=' "$ROOT_DIR/.env" | cut -d= -f2-)"
  export CLOUDKIT_MANAGEMENT_TOKEN
fi

REQUIRED_TYPES=(
  CD_NoteRecord
  CD_GoogleAccountRecord
  CD_SyncedSettingsRecord
  CD_ClipboardItemRecord
  CD_BillRecord
  CD_BillPaymentRecord
  CD_CalendarEventRecord
  CD_DashboardAnalysisRecord
)

# Fields that must exist on specific record types (additive schema migrations).
REQUIRED_BILL_FIELDS=(
  CD_currencyCode
)

echo "==> Nucleus CloudKit schema → Production (calendar + bills)"
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

echo "==> Verifying local schema file includes bill record types and currency field"
missing_local=0
for type in "${REQUIRED_TYPES[@]}"; do
  if ! rg -q "RECORD TYPE $type" "$SCHEMA_FILE"; then
    echo "  MISSING in local file: $type" >&2
    missing_local=1
  fi
done
for field in "${REQUIRED_BILL_FIELDS[@]}"; do
  if ! schema_has_bill_field "$SCHEMA_FILE" "$field"; then
    echo "  MISSING on CD_BillRecord in local file: $field" >&2
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
==> Deploy Development schema to Production (required after bill currency / new fields)

Apple only allows Production schema deploy through CloudKit Console:

  1. Open: $CONSOLE_URL
  2. Select environment: Development (left sidebar)
  3. Schema → Record Types — confirm CD_CalendarEventRecord exists and CD_BillRecord includes CD_currencyCode (String)
  4. Also confirm these record types exist:
     - CD_BillRecord, CD_BillPaymentRecord, CD_CalendarEventRecord, CD_DashboardAnalysisRecord
     - CD_NoteRecord, CD_GoogleAccountRecord, CD_SyncedSettingsRecord, CD_ClipboardItemRecord
  5. Footer → "Deploy Schema Changes…"
  6. Review changes (e.g. CD_CalendarEventRecord added, CD_currencyCode added to CD_BillRecord)
  7. Deploy to Production

After deploy:
  - Quit and reopen Nucleus (release build uses Production CloudKit)
  - Settings → iCloud → Sync to iCloud (or Calendar workspace → Refresh)
  - Export should finish without CKError partialFailure (code 2)

See cloudkit/README.md for the full workflow.

EOF
}

schema_has_bill_field() {
  local schema_file="$1"
  local field="$2"
  awk -v field="$field" '
    /RECORD TYPE CD_BillRecord/ { in_bill=1; next }
    in_bill && /RECORD TYPE / { in_bill=0 }
    in_bill && $0 ~ field { found=1 }
    END { exit !found }
  ' "$schema_file"
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
missing_prod_fields=0
for type in "${REQUIRED_TYPES[@]}"; do
  if rg -q "RECORD TYPE $type" "$prod_schema"; then
    echo "  Production has: $type"
  else
    echo "  Production MISSING: $type"
    missing_prod=1
  fi
done
for field in "${REQUIRED_BILL_FIELDS[@]}"; do
  if schema_has_bill_field "$prod_schema" "$field"; then
    echo "  Production CD_BillRecord has: $field"
  else
    echo "  Production CD_BillRecord MISSING: $field"
    missing_prod_fields=1
  fi
done
echo

if [[ "$missing_prod" -eq 0 && "$missing_prod_fields" -eq 0 ]]; then
  echo "Production already includes all required record types and bill fields."
  echo "If bills still do not sync, use Settings → iCloud → Sync to iCloud on the Mac that owns the data."
  exit 0
fi

if [[ "$missing_prod_fields" -eq 1 && "$missing_prod" -eq 0 ]]; then
  echo "Production has bill record types but is missing new fields (e.g. CD_currencyCode)."
  echo "Import the updated schema into Development, then deploy Development → Production."
else
  echo "Production is missing record types — import Development schema, then deploy Development → Production."
fi
print_production_deploy_steps
