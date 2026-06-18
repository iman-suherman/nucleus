"use client";

import { BRAND_NAME } from "@/lib/brand";

const features = [
  {
    title: "Your day",
    description:
      "Clipboard-powered productivity analysis refreshes every 30 minutes. See today's capture breakdown, behavioral insights — dominant categories, source apps, context switching — and concrete suggestions to consolidate drafts, batch commands, or reduce copy-paste fragmentation.",
    icon: "📊",
  },
  {
    title: "Dashboard",
    description:
      "A morning greeting with daily quote, intelligent insight, Your day analysis, today's weather, live resource usage, Cloud sync, public holidays, news feed, summary metrics, payment preparation, and a seven-day productivity chart — with toggles for every section in Settings.",
    icon: "✨",
  },
  {
    title: "Intelligent insight",
    description:
      "Rule-based analysis turns unread mail, passwords, bills, and clipboard captures into a dated workspace narrative. Collapsible on the Dashboard with manual Analyse Now and automatic refresh every 30 minutes.",
    icon: "🧠",
  },
  {
    title: "Monthly bills",
    description:
      "Track recurring bills in multiple currencies, log full or partial payments, import and export CSV, and get local reminders before due dates. Payment preparation on the Dashboard groups what's due soon by category.",
    icon: "💳",
  },
  {
    title: "Multi-account Gmail",
    description:
      "Category tabs for Personal, Work, and Client inboxes with isolated web sessions per account. Unread badges, per-message alerts, dock badge sync, and external links open in your browser.",
    icon: "✉️",
  },
  {
    title: "Clipboard memory",
    description:
      "Automatic clipboard history with search, pinning, and save-to-notes. Paste from history with ⌘⇧V. Intelligent clipboard detects password-like content and offers to save it to your vault — and feeds Your day productivity analysis on the Dashboard.",
    icon: "📋",
  },
  {
    title: "Notes & passwords",
    description:
      "Markdown notes with optional Google Drive upload, plus a structured password vault with username, email, URL, and password fields. Quick copy from the menu bar popover.",
    icon: "🔐",
  },
  {
    title: "Cloud sync",
    description:
      "Nucleus Cloud syncs notes, bills, dashboard analysis, and settings across devices. iCloud CloudKit keeps notes and bills on your Apple devices — with manual sync and status on the Dashboard.",
    icon: "☁️",
  },
  {
    title: "Smart notifications",
    description:
      "Per-message email alerts with sender and subject, bill due reminders, and clipboard password prompts — with per-account Funky, Nucleus Mail, or system sounds.",
    icon: "🔔",
  },
  {
    title: "Menu bar companion",
    description:
      "Optional menu bar item for recent clips and passwords, password-save prompts, and clipboard access without bringing the main window forward.",
    icon: "📎",
  },
  {
    title: "Native macOS workspace",
    description:
      "SwiftUI shell with web Gmail sign-in, Sparkle auto-updates, dock badges for mail and bills, hourly beep, and a refreshed Nucleus app icon.",
    icon: "🖥️",
  },
];

export function FeatureShowcase() {
  return (
    <section id="features" className="mx-auto max-w-7xl px-4 py-16 sm:px-6">
      <div className="max-w-3xl">
        <h2 className="text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
          Everything in one workspace
        </h2>
        <p className="mt-4 text-lg text-slate-400">
          {BRAND_NAME} started as a unified Gmail cockpit and has grown into a daily operating
          system — mail, bills, clipboard, notes, passwords, cloud sync, and alerts in one native
          macOS app.
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
