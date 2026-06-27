#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/DerivedData/Build/Products/Debug/Nucleus.app"
APP_BIN="$APP_PATH/Contents/MacOS/Nucleus"
RAW_DIR="$ROOT_DIR/website/.screenshots-raw"
PUBLIC_DIR="$ROOT_DIR/website/public"

PANES=(dashboard inbox clipboard notes bills media terminal)

if [[ ! -d "$APP_PATH" ]]; then
  echo "==> Building debug Nucleus.app…"
  npm run build:app --prefix "$ROOT_DIR"
fi

mkdir -p "$RAW_DIR" "$PUBLIC_DIR"

echo "==> Quitting any running Nucleus instances"
osascript -e 'tell application "Nucleus" to quit' >/dev/null 2>&1 || true
pkill -x Nucleus >/dev/null 2>&1 || true
for _ in $(seq 1 20); do
  pgrep -x Nucleus >/dev/null || break
  sleep 0.25
done
sleep 1

capture_pane() {
  local pane="$1"
  local output="$2"
  rm -f "$output"

  echo "==> Capturing $pane → $output"
  for attempt in 1 2; do
    env \
      NUCLEUS_MARKETING_SCREENSHOT=1 \
      NUCLEUS_MARKETING_SCREENSHOT_PANE="$pane" \
      NUCLEUS_MARKETING_SCREENSHOT_EXPORT="$output" \
      open -n -W "$APP_PATH" || true

    if [[ -f "$output" ]]; then
      return 0
    fi

    echo "warn: attempt $attempt failed for $pane; retrying…" >&2
    pkill -x Nucleus >/dev/null 2>&1 || true
    sleep 1
  done

  echo "error: missing screenshot at $output" >&2
  return 1
}

for pane in "${PANES[@]}"; do
  output="$RAW_DIR/workspace-$pane.png"
  capture_pane "$pane" "$output" || exit 1
  sleep 0.8
done

echo "==> Processing screenshots for website/public"
swift "$ROOT_DIR/scripts/prepare-website-screenshots.swift"

echo "==> Done. Website assets:"
for pane in "${PANES[@]}"; do
  echo "  website/public/workspace-$pane.png"
done
