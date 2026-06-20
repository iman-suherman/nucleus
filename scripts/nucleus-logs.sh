#!/usr/bin/env bash
# Tail Nucleus unified logs (macOS log stream).
#
# Usage:
#   bash scripts/nucleus-logs.sh app       # Nucleus app diagnostics (default)
#   bash scripts/nucleus-logs.sh all       # Full Nucleus process stream
#   bash scripts/nucleus-logs.sh network   # CFNetwork / MediaPlayer (music debugging)
set -euo pipefail

MODE="${1:-app}"

case "$MODE" in
  app)
    exec /usr/bin/log stream \
      --style compact \
      --predicate 'process == "Nucleus" AND subsystem == "net.suherman.nucleus"'
    ;;
  all)
    exec /usr/bin/log stream \
      --style compact \
      --predicate 'process == "Nucleus"'
    ;;
  network)
    exec /usr/bin/log stream \
      --style compact \
      --predicate 'process == "Nucleus" AND (subsystem == "com.apple.CFNetwork" OR subsystem == "com.apple.network" OR subsystem == "com.apple.amp.mediaplayer" OR subsystem == "com.apple.amp.iTunesCloud")'
    ;;
  -h | --help | help)
    cat <<'EOF'
Tail Nucleus logs from the macOS unified log.

Modes:
  app       Nucleus diagnostics (subsystem net.suherman.nucleus) — default
  all       Everything from the Nucleus process (verbose)
  network   CFNetwork / MediaPlayer / iTunesCloud (music playback debugging)

Examples:
  npm run logs
  npm run logs:all
  npm run logs:network
EOF
    ;;
  *)
    echo "error: unknown mode '$MODE' (use app, all, or network)" >&2
    exit 1
    ;;
esac
