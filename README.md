# Nucleus

**Personal Operating System for macOS**

Nucleus is a native macOS workspace that centralises communication, scheduling, knowledge capture, and daily execution into a single app.

Instead of switching between Gmail, Google Chat, Google Calendar, clipboard managers, and scattered notes, Nucleus brings everything together while keeping Google Workspace as the source of truth.

Built for professionals who manage multiple Google accounts, Nucleus is a unified command center for email, chat, meetings, reminders, clipboard history, and personal notes.

## Features

### Mail & accounts
- Multi-account Gmail with category tabs (Personal, Work, Client, and more)
- Web-session sign-in with isolated cookies per account, or Google OAuth API sync
- Unread badges on sidebar, account tabs, toolbar, and the macOS dock
- Per-message email notifications with sender, account, and subject
- Direct inbox loading when already signed in (no login flash)
- External links open in your default browser

### Google Chat
- Dedicated Chat workspace with per-account tabs
- Blue mail and green chat unread badges shown separately in the toolbar and sidebar
- Background unread polling even when Chat is not the active tab
- Funky alert sound for new chat messages

### Calendar & meetings
- Embedded Google Calendar week view for web-session accounts
- Upcoming meetings list across accounts with join links
- Upcoming meetings bar at the top of the app with quick Join actions
- Manual **Sync Calendar** button to refresh events and meeting reminders
- Calendar sync from OAuth API, iCal feeds, and the embedded calendar web view
- Funky alert sound for upcoming meeting reminders
- Sidebar badge for today’s upcoming meetings

### Clipboard & notes
- Automatic clipboard history with search and pinning
- Paste from clipboard history with **⌘⇧V**
- Save clips to Markdown notes on your primary Google Drive account
- Markdown notes workspace for meeting logs and daily capture

### Notifications & polish
- Custom Funky alert sound for mail, chat, and calendar reminders
- Background mail, chat, and calendar pollers keep counts and alerts current
- Sparkle auto-updates with signed and notarized releases
- OAuth tokens stored in the Apple Keychain
- Refreshed Nucleus app icon

## Stack

| Component | Choice |
|-----------|--------|
| Language | Swift |
| UI | SwiftUI + AppKit |
| Web | WKWebView (Gmail, Chat, Calendar) |
| Database | SwiftData + SQLite |
| Auth | Google OAuth 2.0 + web session |
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
├── website/                # Marketing site
└── Package.swift
```

## Core modules

- **AccountKit** — Google OAuth, token refresh, multi-account management
- **MailKit** — Gmail API sync, web-session unread detection, quick reply
- **CalendarKit** — unified timeline, iCal sync, meeting reminders
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

## Releases

Download the latest build from the [Nucleus website](https://nucleus.suherman.net) or check **Nucleus → Check for Updates** in the app.

Current release: **0.1.12**

## Phase roadmap

| Phase | Modules |
|-------|---------|
| 1 | Gmail, Calendar, Clipboard, Notes, Chat |
| 2 | Contacts, Tasks, Meeting Assistant, AI Search |
| 3 | Slack, Teams, Jira, Confluence, GitHub |
| 4 | Local AI Assistant, Knowledge Graph, Automation |

## License

Copyright © 2026 Iman Suherman
