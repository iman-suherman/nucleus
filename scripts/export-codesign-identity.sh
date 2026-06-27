#!/usr/bin/env bash
# Export Developer ID Application identity (cert + private key) to a local .p12 file.
# Run in Terminal on a Mac that already has the identity in Keychain (not over plain SSH).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/release-env.sh"

IDENTITY="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Huge Shop Pty Ltd (Q3TXW887NM)}"
OUTPUT_REL="${MACOS_DEVELOPER_ID_CODESIGN_P12:-config/Nucleus_DeveloperID.codesign.p12}"
OUTPUT_PATH="${OUTPUT_REL}"
if [[ "$OUTPUT_PATH" != /* ]]; then
  OUTPUT_PATH="$ROOT_DIR/$OUTPUT_PATH"
fi
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
SEED_AFTER="${1:-}"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$IDENTITY"; then
  echo "export-codesign: identity not found in Keychain: $IDENTITY" >&2
  exit 1
fi

PASS="${NUCLEUS_DEVELOPER_ID_CODESIGN_P12_PASSWORD:-}"
if [[ -z "$PASS" ]]; then
  PASS="$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)"
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
rm -f "$OUTPUT_PATH"

echo "==> Exporting codesign identity"
echo "    Identity: $IDENTITY"
echo "    Output:   $OUTPUT_PATH"

if ! security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$PASS" -o "$OUTPUT_PATH"; then
  echo "export-codesign: export failed." >&2
  echo "Run this script in Terminal.app on the Mac that holds the certificate (Keychain must be unlocked)." >&2
  echo "Remote SSH sessions cannot export private keys without GUI keychain access." >&2
  exit 1
fi

chmod 600 "$OUTPUT_PATH"
echo "export-codesign: wrote $(wc -c < "$OUTPUT_PATH" | tr -d ' ') bytes"

if [[ "$SEED_AFTER" == "--seed" || "$SEED_AFTER" == "-s" ]]; then
  echo "==> Seeding GCP Secret Manager"
  NUCLEUS_DEVELOPER_ID_CODESIGN_P12_PASSWORD="$PASS" node "$ROOT_DIR/scripts/seed-codesign-identity.cjs"
else
  echo ""
  echo "Next: seed to Secret Manager with:"
  echo "  NUCLEUS_DEVELOPER_ID_CODESIGN_P12_PASSWORD='$PASS' npm run seed:codesign-identity"
fi
