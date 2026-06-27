import { BRAND_NAME } from "@/lib/brand";

const workspaces = [
  {
    title: "Dashboard",
    eyebrow: "Morning command center",
    icon: "✨",
    description:
      "Start every day with a greeting, daily quote, and a read on what needs attention — unread mail, bills, passwords, clipboard patterns, weather, news, and payment prep on one screen.",
    bullets: [
      "Your day analyses clipboard captures into productivity insights every 30 minutes",
      "Intelligent insight weaves inbox, vault, bills, and clips into plain-language status",
      "Seven-day productivity chart, summary metrics, and toggles for every section",
    ],
  },
  {
    title: "Inbox",
    eyebrow: "Multi-account Gmail",
    icon: "✉️",
    description:
      "Category tabs for Personal, Work, Client, and more — each Google account gets an isolated web session so personal, work, and school inboxes stay separate.",
    bullets: [
      "Unread badges on sidebar, toolbar, account tabs, and the macOS dock",
      "Per-message notifications with sender, account, and subject",
      "Direct inbox loading when already signed in; external links open in your browser",
    ],
  },
  {
    title: "Clipboard",
    eyebrow: "Capture memory",
    icon: "📋",
    description:
      "Automatic clipboard history with search, pinning, and quick paste — without leaving the app you are working in.",
    bullets: [
      "Paste from history with ⌘⇧V; global Carbon hotkey works from Cursor and other apps",
      "Password-like content triggers a save-to-vault prompt",
      "Save clips to Markdown notes and feed Dashboard productivity analysis",
    ],
  },
  {
    title: "Notes & passwords",
    eyebrow: "Knowledge vault",
    icon: "🔐",
    description:
      "Markdown notes for meeting logs and daily capture, plus a structured password vault with username, email, URL, and password fields.",
    bullets: [
      "Auto-save as you type with Edit / Preview modes",
      "Optional Google Drive upload on your primary account",
      "Folder counts, context-menu moves, and quick copy from the menu bar popover",
    ],
  },
  {
    title: "Bills",
    eyebrow: "Monthly cash flow",
    icon: "💳",
    description:
      "Track recurring bills in multiple currencies, log full or partial payments, and see what is still due this month.",
    bullets: [
      "CSV import and export; local reminders before due dates",
      "Monthly summary with calendar dots, due-soon totals, and OK to spend",
      "Payment preparation on the Dashboard groups upcoming bills by category",
    ],
  },
  {
    title: "Music",
    eyebrow: "Apple Music & AirPlay",
    icon: "🎵",
    description:
      "Search Apple Music, play tracks from the catalog, view synced karaoke lyrics, and control playback from the header mini player or Now Playing panel.",
    bullets: [
      "MusicKit catalog streaming; Music.app library control with Automation permission",
      "LRCLib lyric search and synced karaoke lyrics while a track plays",
      "AirPlay routing, local audio files, queue playback, and a Playing badge in the sidebar",
    ],
  },
  {
    title: "Terminal",
    eyebrow: "tmux inside Nucleus",
    icon: "🖥️",
    description:
      "Browse active tmux sessions, attach interactively inside an embedded terminal, and detach without losing running work.",
    bullets: [
      "Draggable session cards with attach, copy-command, and destroy actions",
      "New tmux or shell sessions; scrollback history with trackpad scroll",
      "Detach with F12 or ⌘⇧D; sidebar badge shows active session count",
    ],
  },
] as const;

export function WorkspacesShowcase() {
  return (
    <section id="workspaces" className="mx-auto max-w-7xl px-4 py-16 sm:px-6">
      <div className="max-w-3xl">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          Seven workspaces
        </p>
        <h2 className="mt-2 text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
          One sidebar for everything you open every day.
        </h2>
        <p className="mt-4 text-lg leading-8 text-slate-400">
          {BRAND_NAME} is organized around native workspace panes — not buried settings menus.
          Drag sidebar items to match your routine; Settings and Accounts stay fixed at the bottom.
        </p>
      </div>

      <div className="mt-12 grid gap-6 md:grid-cols-2 xl:grid-cols-3">
        {workspaces.map((workspace) => (
          <article key={workspace.title} className="card flex flex-col p-6 sm:p-7">
            <div className="flex items-start gap-3">
              <span className="text-2xl" aria-hidden>
                {workspace.icon}
              </span>
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-brand-blue">
                  {workspace.eyebrow}
                </p>
                <h3 className="mt-1 text-xl font-semibold text-slate-100">{workspace.title}</h3>
              </div>
            </div>
            <p className="mt-4 flex-1 text-sm leading-7 text-slate-400">{workspace.description}</p>
            <ul className="mt-5 space-y-2 text-sm leading-relaxed text-slate-400">
              {workspace.bullets.map((bullet) => (
                <li key={bullet} className="flex gap-2.5">
                  <span
                    aria-hidden
                    className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-brand-green"
                  />
                  <span>{bullet}</span>
                </li>
              ))}
            </ul>
          </article>
        ))}
      </div>
    </section>
  );
}
