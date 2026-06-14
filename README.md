# Nucleus

**Personal Operating System for macOS**

Nucleus is a native macOS personal operating system that centralises communication, scheduling, knowledge capture, and daily execution into a single workspace.

Instead of switching between Gmail, Google Calendar, Notes, clipboard managers, and meeting reminders, Nucleus brings everything together in one native Swift application while keeping Google Workspace as the source of truth.

Built specifically for professionals who manage multiple Google accounts, Nucleus provides a unified command center for email, meetings, notes, reminders, and personal knowledge management.

## Stack

| Component | Choice |
|-----------|--------|
| Language | Swift |
| UI | SwiftUI + AppKit |
| Web | WKWebView (Gmail) |
| Database | SwiftData + SQLite |
| Auth | Google OAuth 2.0 |
| Secrets | Apple Keychain |
| Notifications | UserNotifications |

## Repository layout

```
nucleus/
├── app/                    # SwiftUI desktop app
├── Sources/                # Swift packages (kits)
│   ├── NucleusKit/
│   ├── DatabaseKit/
│   ├── AccountKit/
│   ├── MailKit/
│   ├── CalendarKit/
│   ├── ClipboardKit/
│   └── NotesKit/
├── Tests/
├── scripts/
└── Package.swift
```

## Core modules

- **AccountKit** — Google OAuth, token refresh, multi-account management
- **MailKit** — Gmail API sync, unread badges, quick reply
- **CalendarKit** — unified timeline, meeting reminders
- **ClipboardKit** — clipboard history, search, pinning
- **NotesKit** — Markdown notes on Google Drive
- **DatabaseKit** — SwiftData models and persistence

## Development

### Prerequisites

- macOS 14+
- Xcode 15+ (`xcode-select --install`)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for project generation

### Development (VS Code / terminal)

```bash
npm run info    # colored starter guide
npm run dev:app # build, test, build app, launch on macOS
```

Package-only (without launching the app):

```bash
npm run build
npm run test
```

### Build or debug in Xcode

```bash
npm run setup:xcodegen   # once, if needed
npm run xcode            # build app + open Xcode
npm run run:app          # launch Nucleus.app only
```

### Google OAuth setup

1. Create a Google Cloud OAuth client (Desktop app type)
2. Open **Nucleus → Settings → Google OAuth**
3. Enter your Client ID
4. Add accounts from **Account Center**

Required scopes:

- `https://www.googleapis.com/auth/gmail.readonly`
- `https://www.googleapis.com/auth/gmail.send`
- `https://www.googleapis.com/auth/gmail.modify`
- `https://www.googleapis.com/auth/calendar.readonly`
- `https://www.googleapis.com/auth/drive.file`

## Phase roadmap

| Phase | Modules |
|-------|---------|
| 1 | Gmail, Calendar, Clipboard, Notes |
| 2 | Contacts, Tasks, Meeting Assistant, AI Search |
| 3 | Slack, Teams, Jira, Confluence, GitHub |
| 4 | Local AI Assistant, Knowledge Graph, Automation |

## License

Copyright © 2026 Iman Suherman
