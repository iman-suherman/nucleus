#!/usr/bin/env bash
# Create a commit with the repository's required author identity.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: bash scripts/git-commit.sh \"commit message\"" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MSG="$1"
if [[ "$MSG" == *$'\n'* ]]; then
  GIT_COMMITTER_NAME="Iman Suherman" \
  GIT_COMMITTER_EMAIL="iman.suherman@gmail.com" \
  git commit --author="Iman Suherman <iman.suherman@gmail.com>" -m "$MSG"
else
  GIT_COMMITTER_NAME="Iman Suherman" \
  GIT_COMMITTER_EMAIL="iman.suherman@gmail.com" \
  git commit --author="Iman Suherman <iman.suherman@gmail.com>" -m "$MSG"
fi

bash "$ROOT/scripts/rewrite-commit-identity.sh"
