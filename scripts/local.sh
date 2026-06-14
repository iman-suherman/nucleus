#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Building Nucleus (debug)"
bash "$ROOT_DIR/scripts/build.sh"

echo "==> Launching Nucleus locally"
bash "$ROOT_DIR/scripts/run-app.sh"
