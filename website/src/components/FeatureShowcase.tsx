"use client";

import { BRAND_NAME } from "@/lib/brand";

const features = [
  {
    title: "Multi-account Gmail",
    description:
      "Category tabs for Personal, Work, and Client inboxes. Unread badges, per-message alerts, dock badge sync, and external links open in your browser.",
    icon: "✉️",
  },
  {
    title: "Google Chat workspace",
    description:
      "Dedicated Chat sidebar with per-account tabs, green unread badges, background polling, and Funky alert sounds when new messages arrive.",
    icon: "💬",
  },
  {
    title: "Unified calendar",
    description:
      "Embedded Google Calendar, upcoming meeting list, join links, on-demand Sync, and Funky reminders before meetings start.",
    icon: "📅",
  },
  {
    title: "Upcoming meetings bar",
    description:
      "See the next meetings across all accounts at the top of the app with quick Join actions and calendar navigation.",
    icon: "⏰",
  },
  {
    title: "Smart notifications",
    description:
      "Per-message email alerts with sender and subject, chat notifications, and calendar reminders — all with the custom Funky chime.",
    icon: "🔔",
  },
  {
    title: "Clipboard memory",
    description:
      "Automatic clipboard history with search, pinning, and save-to-notes. Paste from history with a keyboard shortcut.",
    icon: "📋",
  },
  {
    title: "Markdown notes",
    description:
      "Capture meeting notes, daily logs, and clipboard saves to Markdown files on your primary Google Drive account.",
    icon: "📝",
  },
  {
    title: "Native macOS workspace",
    description:
      "SwiftUI shell with web Gmail sign-in, Sparkle auto-updates, and a refreshed Nucleus app icon.",
    icon: "🖥️",
  },
];

export function FeatureShowcase() {
  return (
    <section id="features" className="mx-auto max-w-7xl px-4 py-16 sm:px-6">
      <div className="max-w-3xl">
        <h2 className="text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
          Everything added since launch
        </h2>
        <p className="mt-4 text-lg text-slate-400">
          {BRAND_NAME} started as a unified Gmail and calendar cockpit and has grown into a daily
          operating system for mail, chat, meetings, clipboard, notes, and alerts — all in one
          native macOS app.
        </p>
      </div>
      <div className="mt-10 grid gap-6 md:grid-cols-2">
        {features.map((feature) => (
          <article key={feature.title} className="card p-6">
            <div className="text-2xl">{feature.icon}</div>
            <h3 className="mt-4 text-xl font-semibold text-slate-100">{feature.title}</h3>
            <p className="mt-2 text-slate-400">{feature.description}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
