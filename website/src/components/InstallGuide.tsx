"use client";

import Link from "next/link";
import { BRAND_NAME, GITHUB_REPO_URL } from "@/lib/brand";
import { DownloadButton } from "@/components/DownloadButton";
import { useLatestVersion } from "@/hooks/useRegistry";

const steps = [
  {
    title: "Download",
    description: "Get the latest Nucleus build, or pick a specific version from the release history page.",
  },
  {
    title: "Open the DMG",
    description: "Double-click the downloaded disk image to mount it.",
  },
  {
    title: "Install",
    description: "Drag Nucleus.app into your Applications folder.",
  },
  {
    title: "Launch Nucleus",
    description: "Open Nucleus from Applications or Spotlight.",
  },
  {
    title: "Connect Google accounts",
    description:
      "Open Account Center, add your Google OAuth Client ID, then sign in with each Gmail account you want to manage.",
  },
];

export function InstallGuide() {
  const { data: latest, loading } = useLatestVersion();

  return (
    <section className="mx-auto max-w-4xl px-4 py-16 sm:px-6">
      <h1 className="text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
        Install {BRAND_NAME} on macOS
      </h1>
      <p className="mt-4 text-lg text-slate-400">
        Requires macOS 14 or later. Nucleus uses Sparkle for automatic updates after the first install.
      </p>

      <div className="mt-8">
        <DownloadButton latest={latest} loading={loading} className="btn-primary" />
      </div>

      <ol className="mt-10 space-y-6">
        {steps.map((step, index) => (
          <li key={step.title} className="card p-6">
            <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
              Step {index + 1}
            </p>
            <h2 className="mt-2 text-xl font-semibold text-slate-100">{step.title}</h2>
            <p className="mt-2 text-slate-400">{step.description}</p>
          </li>
        ))}
      </ol>

      <div className="mt-10 flex flex-wrap gap-3">
        <Link href="/versions" className="btn-secondary">
          Browse all versions
        </Link>
        <Link href={GITHUB_REPO_URL} className="btn-secondary">
          View source on GitHub
        </Link>
      </div>
    </section>
  );
}
