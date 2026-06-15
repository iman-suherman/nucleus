#!/usr/bin/env bash
# Notarize and staple a signed .app bundle (required for Sparkle ZIP updates).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/release-env.sh"

APP_PATH="${1:-$ROOT_DIR/.build/DerivedData/Build/Products/Release/Nucleus.app}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH"
  exit 1
fi

if ! should_notarize; then
  echo "App notarization skipped (set MACOS_NOTARIZE=1 and configure AC_NOTARY profile)."
  exit 0
fi

append_notary_auth_args
if [[ ${#NOTARY_AUTH_ARGS[@]} -eq 0 ]]; then
  echo "Notarization enabled but credentials missing."
  exit 1
fi

ZIP_PATH="$(mktemp -t nucleus-notarize.XXXXXX.zip)"
trap 'rm -f "$ZIP_PATH"' EXIT

echo "==> Submitting app for notarization"
echo "    App: $APP_PATH"
COPYFILE_DISABLE=1 ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

SUBMIT_JSON="$(mktemp)"
xcrun notarytool submit "$ZIP_PATH" "${NOTARY_AUTH_ARGS[@]}" --output-format json >"$SUBMIT_JSON"
SUBMISSION_ID="$(python3 -c "import json; print(json.load(open('$SUBMIT_JSON')).get('id',''))")"
rm -f "$SUBMIT_JSON"

if [[ -z "$SUBMISSION_ID" ]]; then
  echo "Notary submission did not return a submission id."
  exit 1
fi

echo "    Submission ID: $SUBMISSION_ID"
echo "==> Waiting for Apple notarization (usually 5–15 minutes)"
xcrun notarytool wait "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" --timeout 1h --progress || true

STATUS="$(xcrun notarytool info "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" --output-format json | python3 -c "import json,sys; print(json.load(sys.stdin).get('status',''))")"
if [[ "$STATUS" != "Accepted" ]]; then
  echo "Notarization failed with status: ${STATUS:-unknown}"
  xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" || true
  exit 1
fi

echo "==> Stapling notarization ticket to app"
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
echo "App notarized and stapled."
