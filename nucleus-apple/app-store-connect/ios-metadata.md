# App Store Connect — iOS metadata & resubmission checklist

Use when resubmitting Nucleus after Guideline 5.2.5 rejection.

**Version:** 1.0.1 · **Build:** 3 (increment for each new upload)

## App information

| Field | Value |
|-------|-------|
| **App Name** | Nucleus - Personal OS |
| **Subtitle** | Personal Workspace |

## Avoid in subtitle, promo text, screenshots, description, keywords

Do **not** use: Apple, iOS, macOS, iCloud, Siri, Apple Intelligence, Apple Mail, Apple Calendar, Finder, Spotlight, WeatherKit, Apple Weather, Mac, iPhone, iPad, Face ID (in marketing copy).

Use vendor-neutral wording: *cloud sync*, *computer*, *phone and tablet*, *biometric unlock*, *account*.

---

## Phase 1 — Verify project is clean

```bash
# Optional: clean Xcode cache
rm -rf ~/Library/Developer/Xcode/DerivedData

# Automated checks (from nucleus repo root)
npm run validate:ios-app-store
```

Manual grep (Swift/plists/project only — excludes this doc):

```bash
rg -i "WeatherKit|Apple Weather|com.apple.developer.weatherkit|WeatherService" \
  nucleus-apple/Apps/NucleusIOS nucleus-apple/Packages \
  --glob '!{.build,DerivedData}/**'
```

Expected: no results.

**Info.plist:** no `NSLocationWhenInUseUsageDescription` (weather removed).

**entitlements.ios.plist:** no `com.apple.developer.weatherkit`.

---

## Phase 2 — Verify the archive

1. Xcode → **Product → Archive**
2. **Window → Organizer → Archives** → Show in Finder
3. Open `Nucleus.xcarchive/Products/Applications/Nucleus.app`
4. Inspect signed entitlements:

```bash
codesign -d --entitlements :- /path/to/Nucleus.app
```

Confirm: **no** `com.apple.developer.weatherkit`, bundle id `net.suherman.nucleus`.

Or run (includes source checks + repo archive .app when present):

```bash
npm run validate:ios-app-store
```

Custom .app or IPA path:

```bash
npm run validate:ios-app-store -- /path/to/Nucleus.app
npm run validate:ios-app-store -- '' /path/to/Nucleus.ipa
```

---

## Phase 3 — Inspect uploaded IPA (recommended)

Export IPA from Organizer, then:

```bash
npm run validate:ios-app-store -- '' /path/to/Nucleus.ipa
```

Or manually:

```bash
unzip -q Nucleus.ipa -d /tmp/nucleus-ipa
rg -i WeatherKit /tmp/nucleus-ipa/Payload/
```

Expected: no results.

---

## Phase 4 — Validate App Store metadata

Search every field in App Store Connect for trademark terms listed above:

- App Name, Subtitle, Description, Promotional Text, Keywords
- Support URL, Marketing URL, What's New
- Screenshot captions, preview videos

---

## Phase 5 — Verify screenshots

Regenerate if any screenshot shows old copy:

```bash
npm run capture:ios-screenshots
```

Review PNGs in `nucleus-apple/AppStoreScreenshots/*/upload/` for OCR-risk text before uploading.

---

## Phase 6–7 — Xcode capabilities & frameworks

**Signing & Capabilities:** iCloud (CloudKit) only — **no WeatherKit**.

**Build Phases → Link Binary With Libraries:** no `WeatherKit.framework`.

---

## Phase 8 — Build number

Do **not** re-upload build 1 after rejection. Current repo build: **2**.

---

## Phase 9 — Upload

Archive → Validate → Distribute → Upload. Wait for processing, then select **build 3** for review.

---

## Phase 10 — App Review Information → Notes

```
This build removes all WeatherKit functionality and does not use Apple Weather data. WeatherKit is not enabled as a capability and the app does not display weather information.

We have updated the app subtitle to "Personal Workspace" and revised in-app copy and metadata to remove terminology that could be interpreted as referring to Apple products or services.
```

---

## Phase 11 — Reply to reviewer

Reply to the **existing** App Review thread (do not open a new one):

```
Hello App Review Team,

Thank you for the review.

We have submitted build 3 with the following changes:
- Removed all WeatherKit functionality, entitlements, and linked frameworks
- Removed weather UI and location usage for forecasts
- Updated the app subtitle to "Personal Workspace"
- Revised in-app copy and metadata to avoid terminology that could be interpreted as referring to Apple products or services

Nucleus does not use WeatherKit or Apple Weather data. The app does not provide weather functionality.

We have added this clarification to App Review Information notes.

Thank you.
```

---

## Quick checklist

- [ ] `npm run validate:ios-app-store` passes
- [ ] Archive entitlements: no WeatherKit
- [ ] IPA inspection: no WeatherKit in Payload/
- [ ] Subtitle = **Personal Workspace**
- [ ] Build = **3** (or higher)
- [ ] Screenshots regenerated and reviewed
- [ ] Review notes pasted in App Store Connect
- [ ] New build selected → **Resubmit to App Review**
- [ ] Reply posted to existing review thread
