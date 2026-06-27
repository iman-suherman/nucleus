#!/usr/bin/env bash
# Pre-submission validation for Nucleus iOS App Store resubmission (Guideline 5.2.5).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
IOS_APP="$ROOT/nucleus-apple/Apps/NucleusIOS"
IOS_SRC="$IOS_APP/NucleusIOS"
ENTITLEMENTS="$IOS_SRC/entitlements.ios.plist"
INFO_PLIST="$IOS_SRC/Info.plist"
PBXPROJ="$IOS_APP/NucleusIOS.xcodeproj/project.pbxproj"
PROJECT_YML="$IOS_APP/project.yml"

HAS_RG=0
if command -v rg >/dev/null 2>&1; then
  HAS_RG=1
fi

file_contains() {
  local pattern="$1"
  local file="$2"
  if [[ "$HAS_RG" -eq 1 ]]; then
    rg -q "$pattern" "$file"
  else
    grep -qE "$pattern" "$file"
  fi
}

text_matches_icase() {
  local text="$1"
  local pattern="$2"
  if [[ "$HAS_RG" -eq 1 ]]; then
    echo "$text" | rg -qi "$pattern"
  else
    echo "$text" | grep -Eiq "$pattern"
  fi
}

search_weather_hits() {
  local pattern='WeatherKit|Apple Weather|com\.apple\.developer\.weatherkit|WeatherService'
  if [[ "$HAS_RG" -eq 1 ]]; then
    rg -i "$pattern" \
      "$IOS_APP" "$ROOT/nucleus-apple/Packages" \
      --glob '!{.build,DerivedData,node_modules,build}/**' \
      --glob '!**/dSYMs/**' \
      --glob '!app-store-connect/**' 2>/dev/null || true
  else
    grep -RInE "$pattern" \
      "$IOS_APP" "$ROOT/nucleus-apple/Packages" \
      --exclude-dir=.build --exclude-dir=DerivedData --exclude-dir=node_modules \
      --exclude-dir=build --exclude-dir=dSYMs --exclude-dir=app-store-connect 2>/dev/null || true
  fi
}

search_trademark_hits() {
  local pattern='Apple ID|Apple Weather|WeatherKit|\biCloud\b|\bmacOS\b|\biOS\b|iPadOS|\bMac\b|\biPhone\b|\biPad\b|Siri|Apple Intelligence'
  local exclude='iCloudSync|refreshICloud|ICloudSync|ICloudAccount|CloudKit|import |#if|ForEach|normalizedForIOS|iCloudKeychain|UIImage|UIApplication|UIColor|UISupported|UIInterface|WKWeb|systemName: "icloud|checkmark\.icloud|icloud\.fill|icloud\.slash|Label\("Cloud sync"'
  if [[ "$HAS_RG" -eq 1 ]]; then
    rg -i "$pattern" \
      "$IOS_SRC" "$ROOT/nucleus-apple/Packages/NucleusUI/Sources" \
      --glob '*.swift' \
      --glob '!*Tests*' 2>/dev/null \
      | rg -v "$exclude" \
      || true
  else
    grep -RInE "$pattern" \
      "$IOS_SRC" "$ROOT/nucleus-apple/Packages/NucleusUI/Sources" \
      --include='*.swift' \
      --exclude='*Tests*' 2>/dev/null \
      | grep -Ev "$exclude" \
      || true
  fi
}

read_project_version() {
  if [[ "$HAS_RG" -eq 1 ]]; then
    rg 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | awk '{print $2}'
  else
    grep 'CURRENT_PROJECT_VERSION:' "$PROJECT_YML" | head -1 | awk '{print $2}'
  fi
}

search_payload_weather() {
  local dir="$1"
  local pattern='WeatherKit|com\.apple\.developer\.weatherkit|WeatherService'
  if [[ "$HAS_RG" -eq 1 ]]; then
    rg -ri "$pattern" "$dir" 2>/dev/null
  else
    grep -RInE "$pattern" "$dir" 2>/dev/null
  fi
}

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
DIM='\033[2m'
NC='\033[0m'

failures=0
warnings=0

fail() {
  echo -e "${RED}FAIL${NC}: $1" >&2
  failures=$((failures + 1))
}

warn() {
  echo -e "${YELLOW}WARN${NC}: $1" >&2
  warnings=$((warnings + 1))
}

note() {
  echo -e "${DIM}$1${NC}" >&2
}

pass() {
  echo -e "${GREEN}OK${NC}: $1"
}

DEFAULT_APP_PATH="$IOS_APP/build/NucleusIOS.xcarchive/Products/Applications/NucleusIOS.app"

resolve_app_bundle_path() {
  local requested="${1:-}"
  local -a candidates=()
  local path

  if [[ -n "$requested" ]]; then
    candidates+=("$requested")
  fi
  if [[ -z "$requested" || "$requested" != "$DEFAULT_APP_PATH" ]]; then
    candidates+=("$DEFAULT_APP_PATH")
  fi

  for path in "${candidates[@]}"; do
    if [[ -d "$path" ]]; then
      echo "$path"
      return 0
    fi
  done
  return 1
}

echo "=== Phase 1 — Project cleanliness ==="
echo

echo "1. WeatherKit / Apple Weather references (Swift + plists + Xcode project)"
weather_hits=$(search_weather_hits)
if [[ -n "$weather_hits" ]]; then
  echo "$weather_hits"
  fail "WeatherKit-related references remain in iOS source tree"
else
  pass "No WeatherKit references in iOS app sources"
fi

echo
echo "2. Info.plist location usage"
if plutil -extract NSLocationWhenInUseUsageDescription raw "$INFO_PLIST" 2>/dev/null; then
  loc_msg=$(plutil -extract NSLocationWhenInUseUsageDescription raw "$INFO_PLIST" 2>/dev/null)
  if text_matches_icase "$loc_msg" 'weather|forecast'; then
    fail "NSLocationWhenInUseUsageDescription still mentions weather: $loc_msg"
  else
    warn "NSLocationWhenInUseUsageDescription is present — confirm another feature needs location"
  fi
else
  pass "No NSLocationWhenInUseUsageDescription (weather location removed)"
fi

echo
echo "3. Source entitlements (entitlements.ios.plist)"
if plutil -extract com.apple.developer.weatherkit raw "$ENTITLEMENTS" 2>/dev/null; then
  fail "com.apple.developer.weatherkit still in $ENTITLEMENTS"
else
  pass "No weatherkit entitlement in source entitlements"
fi

echo
echo "4. Xcode project — linked frameworks"
if file_contains 'WeatherKit\.framework' "$PBXPROJ"; then
  fail "WeatherKit.framework still linked in project.pbxproj"
else
  pass "No WeatherKit.framework in Link Binary With Libraries"
fi

echo
echo "5. Build number (must be > 1 for resubmission)"
build_plist=$(plutil -extract CFBundleVersion raw "$INFO_PLIST" 2>/dev/null || echo "0")
build_yml=$(read_project_version)
if [[ "$build_plist" -lt 2 ]]; then
  fail "CFBundleVersion is $build_plist — increment to 2+ before upload"
else
  pass "CFBundleVersion = $build_plist"
fi
if [[ "$build_yml" -lt 2 ]]; then
  fail "CURRENT_PROJECT_VERSION in project.yml is $build_yml — increment to 2+"
else
  pass "CURRENT_PROJECT_VERSION = $build_yml"
fi

echo
echo "6. Bundle identifier"
if file_contains 'PRODUCT_BUNDLE_IDENTIFIER: net\.suherman\.nucleus' "$PROJECT_YML"; then
  pass "Bundle ID net.suherman.nucleus"
else
  fail "Unexpected bundle identifier in project.yml"
fi

echo
echo "=== Phase 4/5 — User-visible trademark terms (screenshot OCR risk) ==="
echo

trademark_hits=$(search_trademark_hits)
if [[ -n "$trademark_hits" ]]; then
  echo "$trademark_hits"
  fail "Trademark terms in user-visible Swift strings (regenerate screenshots after fixing)"
else
  pass "No risky trademark terms in iOS UI strings"
fi

echo
echo "=== Signed binary / IPA inspection ==="
echo

APP_PATH="${1:-}"
IPA_PATH="${2:-}"

# Default npm run validate:ios-app-store includes the repo Archive .app path.
if [[ -z "$APP_PATH" && -z "$IPA_PATH" ]]; then
  APP_PATH="$DEFAULT_APP_PATH"
fi

inspect_app_entitlements() {
  local app="$1"
  local label="$2"
  if [[ ! -d "$app" ]]; then
    return 1
  fi
  echo "Inspecting entitlements: $app"
  local ents
  ents=$(codesign -d --entitlements :- "$app" 2>/dev/null || true)
  local archived_build
  archived_build=$(plutil -extract CFBundleVersion raw "$app/Info.plist" 2>/dev/null || echo "?")
  if text_matches_icase "$ents" 'weatherkit'; then
    if plutil -extract com.apple.developer.weatherkit raw "$ENTITLEMENTS" 2>/dev/null; then
      fail "Signed $label contains com.apple.developer.weatherkit (matches source entitlements — remove capability)"
    else
      fail "Signed $label contains com.apple.developer.weatherkit but source entitlements.ios.plist does not"
      echo "  → Stale archive (build $archived_build; project expects $build_plist). Re-Archive in Xcode." >&2
      echo "  → Apple Developer → Identifiers → net.suherman.nucleus → disable WeatherKit if still enabled." >&2
      echo "  → rm -rf nucleus-apple/Apps/NucleusIOS/build && Product → Archive → Validate → Upload" >&2
    fi
  else
    pass "Signed $label has no weatherkit entitlement"
  fi
  if [[ "$archived_build" != "?" && "$archived_build" -lt "$build_plist" ]]; then
    warn "Archived build number ($archived_build) is older than project ($build_plist) — re-Archive before upload"
  elif [[ "$archived_build" == "$build_plist" ]]; then
    pass "Signed $label build number = $archived_build"
  fi
  local bid
  bid=$(defaults read "$app/Info" CFBundleIdentifier 2>/dev/null || plutil -extract CFBundleIdentifier raw "$app/Info.plist" 2>/dev/null || echo "")
  if [[ "$bid" == "net.suherman.nucleus" ]]; then
    pass "Signed $label bundle id = $bid"
  elif [[ -n "$bid" ]]; then
    fail "Signed $label bundle id is $bid (expected net.suherman.nucleus)"
  fi
  return 0
}

if [[ -n "$APP_PATH" ]]; then
  resolved_app=$(resolve_app_bundle_path "$APP_PATH" || true)
  if [[ -n "$resolved_app" ]]; then
    inspect_app_entitlements "$resolved_app" "app"
  else
    note "No signed .app at repo archive path — source checks complete"
    note "  Xcode → Product → Archive → then re-run: npm run validate:ios-app-store"
  fi
fi

if [[ -n "$IPA_PATH" ]]; then
  tmp_ipa=$(mktemp -d)
  trap 'rm -rf "$tmp_ipa"' EXIT
  unzip -q "$IPA_PATH" -d "$tmp_ipa"
  if search_payload_weather "$tmp_ipa/Payload"; then
    fail "WeatherKit references found inside IPA Payload/"
  else
    pass "No WeatherKit references in IPA Payload/"
  fi
  payload_app=$(find "$tmp_ipa/Payload" -maxdepth 2 -name '*.app' -type d | head -1)
  if [[ -n "$payload_app" ]]; then
    inspect_app_entitlements "$payload_app" "IPA app"
  fi
fi

echo
echo "=== Summary ==="
if [[ "$failures" -gt 0 ]]; then
  echo -e "${RED}$failures check(s) failed${NC}, $warnings warning(s)"
  exit 1
fi
if [[ "$warnings" -gt 0 ]]; then
  echo -e "${GREEN}All checks passed${NC} ($warnings warning(s))"
else
  echo -e "${GREEN}All checks passed${NC}"
fi
echo
echo "Manual steps before upload:"
echo "  • rm -rf ~/Library/Developer/Xcode/DerivedData  (optional clean build)"
echo "  • Xcode → Product → Archive → Validate → Upload"
echo "  • App Store Connect: subtitle = Personal Workspace, build = $build_plist"
echo "  • Paste review notes from nucleus-apple/app-store-connect/ios-metadata.md"
echo "  • npm run capture:ios-screenshots  (if screenshots need regeneration)"
echo "  • Reply to existing App Review thread after selecting new build"
