"use client";

import Link from "next/link";
import { AppHeroIcon } from "@/components/AppHeroIcon";
import { BRAND_NAME, BRAND_TAGLINE } from "@/lib/brand";
import { DownloadButton } from "@/components/DownloadButton";
import { useLatestVersion } from "@/hooks/useRegistry";
import { flattenReleaseNotes, formatBytes, publishedAtToIso } from "@/lib/registry";
import { LocalReleaseDate } from "@/components/LocalReleaseDate";

export function Hero() {
  const { data: latest, loading } = useLatestVersion();
  const versionLabel = latest?.version;
  const releasedAtIso = publishedAtToIso(latest?.publishedAt);
  const highlights = flattenReleaseNotes(latest?.releaseNotes).slice(0, 3);

  return (
    <section id="home" className="relative mx-auto max-w-7xl overflow-visible px-4 py-10 sm:px-6 md:py-14 lg:py-20">
      <div className="relative grid gap-8 lg:grid-cols-2 lg:items-center lg:gap-10">
        <div>
          <span className="inline-flex rounded-full bg-brand-blue/15 px-3 py-1 text-xs font-semibold uppercase tracking-wide text-brand-blue sm:px-4 sm:py-1.5 sm:text-sm">
            {BRAND_TAGLINE}
          </span>
          <h1 className="mt-4 max-w-4xl text-balance text-3xl font-bold leading-[1.15] tracking-tight text-slate-50 sm:mt-6 sm:text-4xl md:text-5xl lg:text-[3.25rem] xl:text-6xl">
            Your daily workspace for{" "}
            <span className="gradient-text">mail, chat, calendar, bills, and clips.</span>
          </h1>
          <p className="mt-4 max-w-3xl text-base leading-7 text-slate-400 sm:mt-6 sm:text-lg sm:leading-8 md:text-xl md:leading-9">
            Nucleus unifies Gmail, Google Chat, Calendar, clipboard intelligence, markdown notes,
            monthly bills, and Funky alerts across multiple Google accounts — with a Dashboard that
            summarizes what needs attention before you dive in.
          </p>

          <div id="download" className="mt-6 flex flex-col gap-3 sm:mt-8">
            <div className="flex flex-col gap-3 sm:flex-row sm:flex-nowrap sm:items-center sm:gap-2 lg:gap-3">
              <DownloadButton
                latest={latest}
                loading={loading}
                className="btn-primary w-full shrink-0 whitespace-nowrap px-5 py-3 text-sm sm:w-auto sm:px-6 sm:py-3 lg:px-5"
              />
              <Link
                href="/versions"
                className="btn-secondary w-full shrink-0 whitespace-nowrap px-5 py-3 text-sm sm:w-auto sm:px-6 sm:py-3 lg:px-5"
              >
                View release history
              </Link>
              <Link
                href="/install"
                className="btn-secondary w-full shrink-0 whitespace-nowrap px-5 py-3 text-sm sm:w-auto sm:px-6 sm:py-3 lg:px-5"
              >
                Install guide
              </Link>
            </div>
            {releasedAtIso && (
              <LocalReleaseDate iso={releasedAtIso} className="text-base text-slate-500" />
            )}
          </div>

          <div className="mt-6 flex flex-wrap gap-x-6 gap-y-2 text-sm text-slate-500 sm:mt-8 sm:gap-x-8 sm:text-base">
            <span>Dashboard</span>
            <span>Multi-account Gmail</span>
            <span>Google Chat</span>
            <span>Monthly bills</span>
          </div>
        </div>

        <div className="relative mx-auto flex w-full max-w-md items-center justify-center overflow-visible lg:mx-0 lg:max-w-lg">
          <div
            aria-hidden
            className="pointer-events-none absolute left-1/2 top-1/2 h-[130%] w-[130%] -translate-x-1/2 -translate-y-1/2 rounded-full bg-[radial-gradient(circle,rgba(0,122,255,0.2)_0%,rgba(88,86,214,0.12)_38%,transparent_72%)] blur-3xl"
          />
          <div
            aria-hidden
            className="pointer-events-none absolute left-1/2 top-1/2 h-[95%] w-[95%] -translate-x-1/2 -translate-y-1/2 rounded-full bg-gradient-to-br from-brand-blue/25 via-brand-purple/15 to-brand-green/10 blur-[72px]"
          />
          <AppHeroIcon priority className="relative w-full max-w-[320px]" />
        </div>
      </div>

      {!loading && latest && (
        <aside aria-label="Latest release" className="mt-8 border-t border-white/10 pt-8">
          <p className="text-xs font-semibold uppercase tracking-wider text-brand-blue/80">
            Latest release
          </p>
          <p className="mt-3 text-base font-semibold leading-snug text-slate-100 sm:text-lg">
            {latest.summary ?? `${BRAND_NAME} ${versionLabel}`}
          </p>
          <p className="mt-2 text-sm text-slate-500">
            {formatBytes(latest.sizeBytes)} · macOS 14+ · Universal binary
          </p>
          {highlights.length > 0 && (
            <ul className="mt-5 space-y-2.5 text-sm leading-relaxed text-slate-400">
              {highlights.map((note) => (
                <li key={note} className="flex gap-2">
                  <span aria-hidden className="shrink-0 text-slate-600">
                    •
                  </span>
                  <span>{note}</span>
                </li>
              ))}
            </ul>
          )}
        </aside>
      )}
    </section>
  );
}
