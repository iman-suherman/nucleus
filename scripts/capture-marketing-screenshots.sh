#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/DerivedData/Build/Products/Debug/Nucleus.app"
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
sleep 0.5

for pane in "${PANES[@]}"; do
  output="$RAW_DIR/workspace-$pane.png"
  rm -f "$output"

  echo "==> Capturing $pane → $output"
  open -n "$APP_PATH" --args \
    -marketingScreenshotMode \
    -marketingScreenshotPane "$pane" \
    -marketingScreenshotExport "$output"

  for _ in $(seq 1 60); do
    if [[ -f "$output" ]]; then
      break
    fi
    sleep 0.5
  done

  if [[ ! -f "$output" ]]; then
    echo "error: timed out waiting for $output" >&2
    exit 1
  fi

  sleep 0.3
done

echo "==> Processing screenshots for website/public"
swift "$ROOT_DIR/scripts/prepare-website-screenshots.swift"

echo "==> Done. Website assets:"
for pane in "${PANES[@]}"; do
  echo "  website/public/workspace-$pane.png"
done
