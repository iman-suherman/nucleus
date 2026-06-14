#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$ROOT_DIR/.venv"

ensure_python_env() {
  if [[ ! -x "$VENV/bin/python3" ]]; then
    echo "==> Creating Python venv for icon tooling"
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install -q -r "$ROOT_DIR/requirements.txt"
  elif ! "$VENV/bin/python3" -c "import PIL" 2>/dev/null; then
    "$VENV/bin/pip" install -q -r "$ROOT_DIR/requirements.txt"
  fi
}

ensure_python_env
exec "$VENV/bin/python3" "$ROOT_DIR/scripts/prepare-app-icon.py" "$@"
