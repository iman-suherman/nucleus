# Nucleus

**Personal Operating System for macOS**

Nucleus is a native macOS workspace that centralises communication, scheduling, knowledge capture, and daily execution into a single app.

Instead of switching between Gmail, Google Chat, Google Calendar, clipboard managers, and scattered notes, Nucleus brings everything together while keeping Google Workspace as the source of truth.

Built for professionals who manage multiple Google accounts, Nucleus is a unified command center for email, chat, meetings, reminders, clipboard history, and personal notes.

## Features

### Mail & accounts
- Multi-account Gmail with category tabs (Personal, Work, Client, and more)
- Web sign-in with isolated cookies per account — works for personal, work, and school Google accounts
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
- Calendar sync from iCal feeds and the embedded calendar web view
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
- Web sessions stored locally in isolated cookie jars on your Mac
- Refreshed Nucleus app icon

## Stack

| Component | Choice |
|-----------|--------|
| Language | Swift |
| UI | SwiftUI + AppKit |
| Web | WKWebView (Gmail, Chat, Calendar) |
| Database | SwiftData + SQLite |
| Auth | Google web sign-in (WKWebView sessions) |
| Secrets | Apple Keychain (legacy API tokens, if any) |
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

- **AccountKit** — account persistence and legacy token storage
- **MailKit** — web-session unread detection and Gmail feed sync
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

### Add a Gmail account

1. Open **Accounts** in the sidebar
2. Click **Add Gmail (Web Sign-In)**
3. Enter the Gmail address and category name
4. Open **Inbox** and sign in to Gmail for that account

Each account gets its own isolated web session for Gmail, Chat, and Calendar.

## Releases

Download the latest build from the [Nucleus website](https://nucleus.suherman.net) or check **Nucleus → Check for Updates** in the app.

Current release: **0.1.13**

## Phase roadmap

| Phase | Modules |
|-------|---------|
| 1 | Gmail, Calendar, Clipboard, Notes, Chat |
| 2 | Contacts, Tasks, Meeting Assistant, AI Search |
| 3 | Slack, Teams, Jira, Confluence, GitHub |
| 4 | Local AI Assistant, Knowledge Graph, Automation |

## License

Copyright © 2026 Iman Suherman
