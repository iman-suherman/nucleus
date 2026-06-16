# Share Extension (Phase 3)

Planned capability: **Save to Nucleus** from the iOS share sheet.

## Flow

1. User shares text/URL from Safari, Mail, or another app
2. Share extension receives `NSExtensionItem`
3. Extension writes captured content via app group + `NotesMetadataService.captureText`
4. Optionally syncs to Google Drive when OAuth account is connected

## Requirements

- App Group: `group.net.suherman.nucleus`
- Share extension target in `NucleusIOS.xcodeproj`
- `Info.plist` activation rules for text and URLs

## macOS note

Automatic clipboard history remains macOS-only. Mobile capture is explicit (share sheet or manual save).
