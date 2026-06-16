#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IOS_APP="$ROOT/nucleus-apple/Apps/NucleusIOS"

echo "Building NucleusCore packages…"
swift build --package-path "$ROOT/nucleus-apple/Packages/NucleusCore"

echo "Generating Xcode project…"
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen"
  exit 1
fi

(cd "$IOS_APP" && xcodegen generate)

echo "Building NucleusIOS (requires iOS Simulator runtime in Xcode)…"
xcodebuild \
  -project "$IOS_APP/NucleusIOS.xcodeproj" \
  -scheme NucleusIOS \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build

echo "Done."
