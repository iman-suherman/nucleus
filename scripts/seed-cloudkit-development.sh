#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_FILE="$ROOT_DIR/cloudkit/nucleus-development.ckdb"
TEAM_ID="${APPLE_TEAM_ID:-Q3TXW887NM}"
CONTAINER_ID="${NUCLEUS_ICLOUD_CONTAINER:-iCloud.net.suherman.nucleus}"
CKTOOL="/Applications/Xcode.app/Contents/Developer/usr/bin/cktool"

echo "==> Nucleus CloudKit Development schema seed"
echo "    Container: $CONTAINER_ID"
echo "    Team:      $TEAM_ID"
echo

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "Schema file not found: $SCHEMA_FILE"
  exit 1
fi

if [[ -n "${CLOUDKIT_MANAGEMENT_TOKEN:-}" ]]; then
  echo "==> Importing schema with cktool (management token)"
  "$CKTOOL" import-schema \
    --token "$CLOUDKIT_MANAGEMENT_TOKEN" \
    --team-id "$TEAM_ID" \
    --container-id "$CONTAINER_ID" \
    --environment development \
    --validate \
    --file "$SCHEMA_FILE"
  echo
  echo "Done. Open CloudKit Console → Development → Schema → Record Types to verify."
  echo "Then use footer → Deploy Schema Changes… → Production."
  exit 0
fi

cat <<EOF
No CLOUDKIT_MANAGEMENT_TOKEN found. Import manually:

1. Open https://icloud.developer.apple.com/
2. CloudKit Database → $CONTAINER_ID → Development
3. Footer → Import Schema…
4. Choose: $SCHEMA_FILE
5. Confirm import, then check Schema → Record Types for:
   - CD_GoogleAccountRecord
   - CD_NoteRecord
   - CD_SyncedSettingsRecord
   - CD_ClipboardItemRecord
   - CD_BillRecord (includes CD_currencyCode)
   - CD_BillPaymentRecord
   - CD_DashboardAnalysisRecord
6. Footer → Deploy Schema Changes… → deploy to Production

For the full CLI workflow (import Development + verify Production):
  CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/deploy-cloudkit-production-schema.sh

Optional Development-only import:
  CloudKit Console → Settings → API Access → Create Management Token
  CLOUDKIT_MANAGEMENT_TOKEN=... bash scripts/seed-cloudkit-development.sh

Alternative (automatic schema from SwiftData):
  open $ROOT_DIR/app/Nucleus.xcodeproj
  Xcode → Settings → Accounts → sign in with Huge Shop team
  Select Nucleus target → Signing & Capabilities → ensure iCloud + CloudKit
  Product → Run (Debug). SwiftData will create Development schema on first launch.
  Then deploy Development → Production in the console.

After Development schema exists, re-sign release builds with Production entitlements:
  npm run build:app:release && npm run sign
EOF
