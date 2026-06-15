#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_SRC="$ROOT/scripts/git-hooks"
HOOKS_DST="$(git -C "$ROOT" rev-parse --git-dir)"
HOOKS_DST="$(cd "$ROOT/$HOOKS_DST" && pwd)/hooks"

mkdir -p "$HOOKS_DST"

for hook in prepare-commit-msg commit-msg post-commit; do
  install -m 755 "$HOOKS_SRC/$hook" "$HOOKS_DST/$hook"
  echo "installed $hook"
done

echo "Git hooks installed in $HOOKS_DST"
