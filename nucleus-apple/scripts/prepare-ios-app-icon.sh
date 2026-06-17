#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE="$ROOT/app/Nucleus/Assets/AppIconSource.png"
ICONSET="$ROOT/nucleus-apple/Apps/NucleusIOS/NucleusIOS/Assets.xcassets/AppIcon.appiconset"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if [[ ! -f "$SOURCE" ]]; then
  echo "error: missing source icon at $SOURCE"
  echo "Run: npm run prepare:icon"
  exit 1
fi

bash "$ROOT/scripts/prepare-app-icon.sh"
swift "$ROOT/scripts/generate-app-icon.swift" "$TMP_DIR" "$SOURCE"

mkdir -p "$ICONSET"
cp "$TMP_DIR/icon_512x512@2x.png" "$ICONSET/AppIcon-1024.png"

VENV="$ROOT/.venv"
if [[ ! -x "$VENV/bin/python3" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r "$ROOT/requirements.txt"
elif ! "$VENV/bin/python3" -c "import PIL" 2>/dev/null; then
  "$VENV/bin/pip" install -q -r "$ROOT/requirements.txt"
fi

ICON_PATH="$ICONSET/AppIcon-1024.png" "$VENV/bin/python3" - <<'PY'
from pathlib import Path
import os
from PIL import Image

path = Path(os.environ["ICON_PATH"])
img = Image.open(path).convert("RGBA")
bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
bg.paste(img, mask=img.split()[3])
bg.convert("RGB").save(path)
PY

cat > "$ICONSET/Contents.json" <<'EOF'
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "Prepared iOS app icon at $ICONSET/AppIcon-1024.png"
