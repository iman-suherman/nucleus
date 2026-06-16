# nucleus-apple

Shared Apple platform codebase for Nucleus: macOS workspace shell and iOS/iPadOS mobile companion.

## Structure

```
nucleus-apple/
├── Apps/
│   ├── NucleusIOS/          # Universal iPhone + iPad app
│   └── NucleusMac/          # → existing macOS app at ../../app/
├── Packages/
│   ├── NucleusCore/         # Shared domain logic (accounts, web workspace, sync, calendar)
│   └── NucleusUI/           # SwiftUI components for mobile
├── Extensions/
│   ├── ShareExtension/      # Phase 3: Save to Nucleus
│   └── NotificationServiceExtension/  # Phase 4: Rich push
└── Backend/
    └── optional-push-service/  # Phase 4: Gmail watch → APNs
```

The root `Sources/` kits (`NucleusKit`, `DatabaseKit`, `AccountKit`, etc.) remain the shared foundation. `NucleusCore` wraps them with mobile-specific modules.

## MVP phases

| Phase | Status | Scope |
|-------|--------|-------|
| 1 | **Implemented** | SwiftUI shell, WKWebView workspaces, iCloud settings, Keychain, iPad sidebar |
| 2 | Partial | Native calendar dashboard, meeting reminders, unread badge service stubs |
| 3 | Planned | Share extension, manual clipboard capture, notes capture |
| 4 | Planned | Gmail push backend, APNs, notification service extension |

## Build iOS app

```bash
# From repo root
npm run build:ios

# Or manually
cd nucleus-apple/Apps/NucleusIOS
xcodegen generate
xcodebuild -scheme NucleusIOS -destination 'platform=iOS Simulator,name=iPhone 16' build
```

## Product positioning

Nucleus for iPhone and iPad is the **mobile companion** to your personal operating system — not a feature-parity clone of macOS. Clipboard history and background polling remain macOS-only.

## macOS app

The production macOS app remains at `app/Nucleus/`. Future work can migrate it to `Apps/NucleusMac/` while sharing `NucleusCore`.
