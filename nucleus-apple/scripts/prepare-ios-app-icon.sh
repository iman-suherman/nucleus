#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ICONSET="$ROOT/nucleus-apple/Apps/NucleusIOS/NucleusIOS/Assets.xcassets/AppIcon.appiconset"
APP_LOGO_SET="$ROOT/nucleus-apple/Apps/NucleusIOS/NucleusIOS/Assets.xcassets/AppLogo.imageset"
VENV="$ROOT/.venv"

if [[ ! -f "$ROOT/app/Nucleus/Assets/AppIconSource.png" && ! -f "$ROOT/app/Nucleus/Assets/AppIconSource.raw.png" ]]; then
  echo "error: missing source icon under app/Nucleus/Assets/"
  echo "Run: npm run prepare:icon"
  exit 1
fi

if [[ ! -x "$VENV/bin/python3" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r "$ROOT/requirements.txt"
elif ! "$VENV/bin/python3" -c "import PIL" 2>/dev/null; then
  "$VENV/bin/pip" install -q -r "$ROOT/requirements.txt"
fi

# Refresh macOS dock-safe source, then render a separate full-bleed iOS icon.
bash "$ROOT/scripts/prepare-app-icon.sh"

mkdir -p "$ICONSET" "$APP_LOGO_SET"
"$VENV/bin/python3" "$ROOT/scripts/prepare-app-icon.py" \
  --ios-output "$ICONSET/AppIcon-1024.png" \
  --ios-logo-output "$APP_LOGO_SET/AppLogo.png"

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
echo "Prepared in-app logo at $APP_LOGO_SET/AppLogo.png"
