"use client";

import { BRAND_NAME } from "@/lib/brand";

const features = [
  {
    title: "Multi-account Gmail",
    description: "Native tabs for Personal, Work, and Client inboxes with unread badges and external link handling.",
    icon: "✉️",
  },
  {
    title: "Unified calendar",
    description: "See meetings across every Google account in one timeline with join links and reminders.",
    icon: "📅",
  },
  {
    title: "Clipboard memory",
    description: "Search copied commands, URLs, and snippets. Pin important clips and save them to notes.",
    icon: "📋",
  },
  {
    title: "Markdown notes",
    description: "Capture meeting notes, daily logs, and clipboard saves to your primary Google Drive account.",
    icon: "📝",
  },
];

export function FeatureShowcase() {
  return (
    <section id="features" className="mx-auto max-w-7xl px-4 py-16 sm:px-6">
      <div className="max-w-3xl">
        <h2 className="text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
          One cockpit for your daily work
        </h2>
        <p className="mt-4 text-lg text-slate-400">
          {BRAND_NAME} replaces browser tabs, clipboard tools, and scattered notes with a single native macOS workspace.
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
