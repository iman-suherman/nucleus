import { BRAND_NAME } from "@/lib/brand";

const dashboardModules = [
  {
    title: "Your day",
    eyebrow: "Clipboard productivity analysis",
    description:
      "Every 30 minutes, Nucleus reviews today's clipboard captures and turns them into a personal productivity brief — category breakdown, a plain-language summary, data-driven insights, and concrete suggestions to improve how you work.",
    bullets: [
      "See capture counts by category: notes & drafts, admin & text, communication, development, and more",
      "Productivity insights surface dominant work modes, top source apps, context-switching patterns, and capture pace",
      "Suggestions to improve recommend focused blocks — consolidate draft snippets, batch terminal commands, or process shared links in one pass",
      "Apple Intelligence enhances the narrative on macOS 26+; a rule-based engine keeps analysis useful everywhere",
    ],
    accent: "from-brand-green/15 to-brand-blue/10",
  },
  {
    title: "Intelligent insight",
    eyebrow: "Workspace status at a glance",
    description:
      "A dated narrative that weaves together unread mail, saved passwords, upcoming bills, and clipboard trends — so you know what needs attention before opening a single tab.",
    bullets: [
      "Collapsible sections keep the dashboard scannable when you only need a quick read",
      "Manual Analyse Now with automatic refresh every 30 minutes",
      "Tuned for direct, second-person language — no markdown noise or vague advice",
    ],
    accent: "from-brand-purple/20 to-brand-blue/10",
  },
  {
    title: "Productivity chart",
    eyebrow: "Seven-day clipboard trends",
    description:
      "A bar chart breaks the last week of clipboard activity into Development, Communication, Research, Notes & drafts, Admin & text, and Data & numbers — making it easy to spot where your attention actually goes.",
    bullets: [
      "Compare categories day by day to see shifts in focus",
      "Pairs with Your day analysis for both long-range patterns and today's behavior",
    ],
    accent: "from-brand-green/15 to-brand-blue/10",
  },
  {
    title: "Everything else on one screen",
    eyebrow: "Context without clutter",
    description:
      "Weather, live CPU and memory for Nucleus, Nucleus Cloud and iCloud sync status, the next public holiday, a scrolling news feed, breaking news banners, optional Nucleus AI and Apple Music panels, summary metrics, and payment preparation — all configurable from Settings → Dashboard.",
    bullets: [
      "Jump straight into mail, passwords, or bills from summary tiles",
      "Payment preparation groups bills due in the next two weeks by category and currency",
      "Incoming mail overlay and breaking news alerts appear without leaving your current workspace",
      "Toggle any section on or off to match how you start your day",
    ],
    accent: "from-brand-blue/15 to-brand-purple/10",
  },
] as const;

export function DashboardShowcase() {
  return (
    <section id="dashboard" className="mx-auto max-w-7xl px-4 py-16 sm:px-6">
      <div className="max-w-3xl">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          {BRAND_NAME} Dashboard
        </p>
        <h2 className="mt-2 text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
          More than a summary — a read on how you work.
        </h2>
        <p className="mt-4 text-lg leading-8 text-slate-400">
          The Dashboard greets you with a daily quote, then layers intelligent workspace insight with
          clipboard-powered productivity analysis. It learns from what you copy throughout the day —
          not to store secrets, but to reveal patterns: where your attention goes, which apps you
          bounce between, and what is still sitting unfinished in your clipboard queue.
        </p>
      </div>

      <div className="mt-12 grid gap-6 lg:grid-cols-2">
        {dashboardModules.map((module) => (
          <article
            key={module.title}
            className="card relative overflow-hidden p-6 sm:p-8"
          >
            <div
              aria-hidden
              className={`pointer-events-none absolute inset-0 bg-gradient-to-br ${module.accent} opacity-60`}
            />
            <div className="relative">
              <p className="text-xs font-semibold uppercase tracking-wide text-brand-blue">
                {module.eyebrow}
              </p>
              <h3 className="mt-2 text-xl font-semibold text-slate-100 sm:text-2xl">
                {module.title}
              </h3>
              <p className="mt-3 text-sm leading-7 text-slate-400 sm:text-base">
                {module.description}
              </p>
              <ul className="mt-5 space-y-2.5 text-sm leading-relaxed text-slate-400">
                {module.bullets.map((bullet) => (
                  <li key={bullet} className="flex gap-2.5">
                    <span aria-hidden className="mt-2 h-1.5 w-1.5 shrink-0 rounded-full bg-brand-green" />
                    <span>{bullet}</span>
                  </li>
                ))}
              </ul>
            </div>
          </article>
        ))}
      </div>
    </section>
  );
}
