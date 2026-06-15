#!/usr/bin/env bash
set -euo pipefail

MSG="$(python3 - <<'PY'
import subprocess

msg = subprocess.check_output(["git", "log", "-1", "--format=%B"], text=True)
lines = [
    line
    for line in msg.splitlines()
    if line != "Co-authored-by: Cursor <cursoragent@cursor.com>"
]
while lines and not lines[-1].strip():
    lines.pop()
print("\n".join(lines), end="" if lines else "")
PY
)"

if [[ -z "${MSG//[[:space:]]/}" ]]; then
  echo "rewrite-commit-identity: refusing to create an empty commit message" >&2
  exit 1
fi

GIT_COMMITTER_NAME="Iman Suherman" \
GIT_COMMITTER_EMAIL="iman.suherman@gmail.com" \
git commit --amend --author="Iman Suherman <iman.suherman@gmail.com>" -m "$MSG"
