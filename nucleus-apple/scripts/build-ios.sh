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

if rg -q 'nucleus\.ios' "$IOS_APP"; then
  echo "error: forbidden bundle id net.suherman.nucleus.ios found under $IOS_APP"
  exit 1
fi

if ! rg -q 'PRODUCT_BUNDLE_IDENTIFIER: net\.suherman\.nucleus' "$IOS_APP/project.yml"; then
  echo "error: iOS app must use PRODUCT_BUNDLE_IDENTIFIER net.suherman.nucleus"
  exit 1
fi

echo "Building NucleusIOS (requires iOS Simulator runtime in Xcode)…"
xcodebuild \
  -project "$IOS_APP/NucleusIOS.xcodeproj" \
  -scheme NucleusIOS \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  build

echo "Done."
