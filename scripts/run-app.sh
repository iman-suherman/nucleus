#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/DerivedData/Build/Products/Debug/Nucleus.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "==> Nucleus.app not found. Building debug app..."
  npm run build:app --prefix "$ROOT_DIR"
fi

echo "==> Launching Nucleus"
osascript -e 'tell application "Nucleus" to quit' >/dev/null 2>&1 || true
pkill -x Nucleus >/dev/null 2>&1 || true
sleep 0.5
open "$APP_PATH"
