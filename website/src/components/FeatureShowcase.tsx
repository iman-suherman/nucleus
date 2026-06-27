"use client";

import { BRAND_NAME } from "@/lib/brand";

const features = [
  {
    title: "Nucleus Cloud & iCloud sync",
    description:
      "Sync notes, bills, dashboard analysis, and settings through Nucleus Cloud. iCloud CloudKit keeps notes and bills on your Apple devices — with manual sync and status on the Dashboard.",
    icon: "☁️",
  },
  {
    title: "Smart notifications",
    description:
      "Per-message email alerts with sender and subject, bill due reminders, breaking news banners, and clipboard password prompts — with per-account Funky, Nucleus Mail, or system sounds.",
    icon: "🔔",
  },
  {
    title: "Breaking news alerts",
    description:
      "Urgent headlines slide in as a macOS-style top banner from any workspace — with Open story, auto-dismiss, and mood-aware news cards on the Dashboard.",
    icon: "🚨",
  },
  {
    title: "Incoming mail overlays",
    description:
      "New mail while you are on Dashboard, Notes, Music, or Terminal shows the same modal overlay — preview the sender and jump to Inbox without losing your place.",
    icon: "📬",
  },
  {
    title: "Nucleus AI",
    description:
      "Optional Dashboard panel for AI-assisted answers — collapsible with settings toggles, slow auto-scroll for long responses, and IPv4 fallback when local DNS misbehaves.",
    icon: "🤖",
  },
  {
    title: "News feed",
    description:
      "Headlines from your location and holiday countries, with mood-aware color coding, plain-language In brief summaries, and short notes on why each story feels urgent, concerning, or positive.",
    icon: "📰",
  },
  {
    title: "Menu bar companion",
    description:
      "Optional menu bar item for recent clips and passwords, password-save prompts, and clipboard access without bringing the main window forward.",
    icon: "📎",
  },
  {
    title: "Reorderable sidebar",
    description:
      "Drag workspace items to match your daily flow — like DiskWise. Compact sidebar mode saves horizontal space; badges show unread mail, bills, notes, tmux sessions, and now playing.",
    icon: "↕️",
  },
  {
    title: "Window layout memory",
    description:
      "Nucleus remembers window size, position, and which monitor you used — including external displays — across relaunch and app switches.",
    icon: "🪟",
  },
  {
    title: "Isolated Google sessions",
    description:
      "Each Gmail account gets its own WKWebView cookie jar on your Mac. Web sessions stay local; external links open in your default browser.",
    icon: "🔒",
  },
  {
    title: "Sparkle auto-updates",
    description:
      "Signed and notarized releases with in-app Check for Updates. What's New appears after each upgrade with highlights from the release notes.",
    icon: "⬆️",
  },
  {
    title: "Native macOS polish",
    description:
      "SwiftUI shell with dock badges, hourly beep, refreshed Nucleus app icon, five-minute idle return to Dashboard (except Notes, Music, and Terminal), and Accessibility-aware clipboard hotkeys.",
    icon: "🍎",
  },
];

export function FeatureShowcase() {
  return (
    <section id="features" className="mx-auto max-w-7xl px-4 py-16 sm:px-6">
      <div className="max-w-3xl">
        <h2 className="text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
          Platform features across every workspace
        </h2>
        <p className="mt-4 text-lg text-slate-400">
          Beyond the seven sidebar panes, {BRAND_NAME} layers sync, alerts, AI, news, and macOS-native
          polish so the app stays useful whether you are in mail, music, or a tmux session.
        </p>
      </div>
      <div className="mt-10 grid gap-6 md:grid-cols-2 lg:grid-cols-3">
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
