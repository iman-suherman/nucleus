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

## Music workspace

Search Apple Music, play tracks from the catalog, view synced lyrics, and control playback from the header mini player or the Music workspace.

### Enable music control

Nucleus needs **two macOS permissions** before search, play, pause, and skip work reliably:

| Permission | System Settings path | What it enables |
|------------|----------------------|-----------------|
| **Media & Apple Music** | Privacy & Security → Media & Apple Music → Nucleus | Apple Music catalog search and in-app streaming (MusicKit). Mini player and Now Playing pause/skip for catalog tracks. |
| **Automation (Nucleus → Music)** | Privacy & Security → Automation → Nucleus → Music | Control Music.app for your library, AirPlay speaker routing, and fallback playback. |

**Setup steps**

1. Open **Music** in the Nucleus sidebar.
2. Set the source picker to **Music App** (not Nucleus Player).
3. In the **Music Access** card, click **Set Up Access** and allow the macOS prompts.
4. If either permission stays denied, click **Open Settings** or **Fix** on the row that needs attention:
   - **Media & Apple Music:** enable **Nucleus**
   - **Automation:** expand **Nucleus** and enable **Music**
5. Click **Recheck Access** until both rows show **Allowed**.
6. Search for a song, click a result, then use the header mini player or **Now Playing** controls to pause or skip.

**Playback modes**

- **Apple Music catalog** (search results labeled “Apple Music catalog”) — streams inside Nucleus via MusicKit. Pause and skip use the in-app controls; AirPlay to HomePods requires **Play via Music.app for AirPlay** in the AirPlay menu.
- **Your Music library** — plays through Music.app; requires the Automation permission above.
- **Nucleus Player** — local audio files only; use **Open Files** in the Music workspace header.

An active **Apple Music subscription** is required for catalog streaming. Install **Music.app** from the App Store if Automation reports it missing.

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
