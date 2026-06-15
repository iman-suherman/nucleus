"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { LocalReleaseDate } from "@/components/LocalReleaseDate";
import { useAllVersions } from "@/hooks/useRegistry";
import {
  formatBytes,
  groupedReleaseNotes,
  hasReleaseNotes,
  publishedAtToIso,
  toPublicDownloadUrl,
  type AppVersion,
} from "@/lib/registry";

const PAGE_SIZE = 10;

function ReleaseNotesDetail({
  version,
  defaultOpen,
}: {
  version: AppVersion;
  defaultOpen: boolean;
}) {
  const sections = groupedReleaseNotes(version.releaseNotes);
  const markdown = version.releaseNotesMarkdown?.trim();

  if (sections.length === 0 && !markdown) {
    return null;
  }

  return (
    <details
      className="group mt-4 rounded-xl border border-white/10 bg-slate-900/40"
      open={defaultOpen}
    >
      <summary className="flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-3 text-sm font-medium text-slate-200 marker:content-none [&::-webkit-details-marker]:hidden">
        <span>Release details</span>
        <span
          className="text-xs text-slate-500 transition group-open:rotate-180"
          aria-hidden
        >
          ▾
        </span>
      </summary>
      <div className="space-y-4 border-t border-white/10 px-4 py-4">
        {sections.map((section) => (
          <div key={section.label}>
            <h4 className="text-xs font-semibold uppercase tracking-wide text-brand-blue">
              {section.label}
            </h4>
            <ul className="mt-2 space-y-1.5 text-sm text-slate-300">
              {section.items.map((item) => (
                <li key={item} className="flex gap-2">
                  <span className="text-slate-500" aria-hidden>
                    •
                  </span>
                  <span>{item}</span>
                </li>
              ))}
            </ul>
          </div>
        ))}
        {markdown && (
          <div className="prose prose-invert prose-sm max-w-none text-slate-300">
            {sections.length > 0 && (
              <h4 className="text-xs font-semibold uppercase tracking-wide text-brand-blue">
                Full notes
              </h4>
            )}
            <pre className="mt-2 whitespace-pre-wrap font-sans text-sm leading-relaxed text-slate-300">
              {markdown}
            </pre>
          </div>
        )}
      </div>
    </details>
  );
}

function ReleaseCard({
  version,
  isLatest,
}: {
  version: AppVersion;
  isLatest: boolean;
}) {
  const releasedAtIso = publishedAtToIso(version.publishedAt);
  const showNotes = hasReleaseNotes(version);

  return (
    <article className="card p-6">
      <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-3">
            <h3 className="text-xl font-semibold text-slate-100">v{version.version}</h3>
            {isLatest && (
              <span className="rounded-full bg-brand-blue/15 px-2 py-0.5 text-xs font-semibold text-brand-blue">
                Latest
              </span>
            )}
          </div>
          <p className="mt-2 text-sm text-slate-400">
            {version.summary ?? "Nucleus release"}
          </p>
          <p className="mt-2 text-xs text-slate-500">
            {releasedAtIso ? (
              <>
                <LocalReleaseDate iso={releasedAtIso} />
                {" · "}
                {formatBytes(version.sizeBytes)}
              </>
            ) : (
              <>Released — · {formatBytes(version.sizeBytes)}</>
            )}
          </p>
          {showNotes ? (
            <ReleaseNotesDetail version={version} defaultOpen={isLatest} />
          ) : (
            <p className="mt-4 text-sm text-slate-500">
              No detailed release notes for this version.
            </p>
          )}
        </div>
        <a href={toPublicDownloadUrl(version)} className="btn-primary shrink-0">
          Download DMG
        </a>
      </div>
    </article>
  );
}

function LoadingSkeleton() {
  return (
    <div className="mt-6 space-y-4" aria-busy="true" aria-label="Loading releases">
      {[0, 1, 2].map((key) => (
        <div key={key} className="card p-6">
          <div className="h-6 w-24 animate-pulse rounded bg-slate-700" />
          <div className="mt-3 h-4 w-2/3 animate-pulse rounded bg-slate-800" />
          <div className="mt-2 h-3 w-1/3 animate-pulse rounded bg-slate-800" />
          <div className="mt-4 h-10 w-full animate-pulse rounded-xl bg-slate-800/80" />
        </div>
      ))}
    </div>
  );
}

function Pagination({
  currentPage,
  totalPages,
  totalCount,
  onPageChange,
}: {
  currentPage: number;
  totalPages: number;
  totalCount: number;
  onPageChange: (page: number) => void;
}) {
  const start = (currentPage - 1) * PAGE_SIZE + 1;
  const end = Math.min(currentPage * PAGE_SIZE, totalCount);

  return (
    <nav
      className="mt-8 flex flex-col gap-4 border-t border-white/10 pt-6 sm:flex-row sm:items-center sm:justify-between"
      aria-label="Release pagination"
    >
      <p className="text-sm text-slate-400">
        Showing {start}–{end} of {totalCount} releases
      </p>
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => onPageChange(currentPage - 1)}
          disabled={currentPage <= 1}
          className="btn-secondary disabled:cursor-not-allowed disabled:opacity-50"
          aria-label="Previous page"
        >
          Previous
        </button>
        <span className="px-2 text-sm font-medium text-slate-300">
          Page {currentPage} of {totalPages}
        </span>
        <button
          type="button"
          onClick={() => onPageChange(currentPage + 1)}
          disabled={currentPage >= totalPages}
          className="btn-secondary disabled:cursor-not-allowed disabled:opacity-50"
          aria-label="Next page"
        >
          Next
        </button>
      </div>
    </nav>
  );
}

export function VersionHistory() {
  const { data: versions, loading } = useAllVersions();
  const searchParams = useSearchParams();
  const router = useRouter();

  const totalCount = versions.length;
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));
  const rawPage = Number.parseInt(searchParams.get("page") ?? "1", 10);
  const currentPage =
    Number.isFinite(rawPage) && rawPage >= 1 ? Math.min(rawPage, totalPages) : 1;
  const pageVersions = versions.slice(
    (currentPage - 1) * PAGE_SIZE,
    currentPage * PAGE_SIZE,
  );

  function goToPage(page: number) {
    const nextPage = Math.max(1, Math.min(page, totalPages));
    const params = new URLSearchParams(searchParams.toString());
    if (nextPage <= 1) {
      params.delete("page");
    } else {
      params.set("page", String(nextPage));
    }
    const query = params.toString();
    router.push(query ? `/versions?${query}` : "/versions", { scroll: false });
  }

  return (
    <section id="versions" className="mx-auto max-w-7xl px-4 py-8 sm:px-6 sm:py-10">
      <div>
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          All releases
        </p>
        <h2 className="mt-2 text-3xl font-bold text-slate-50">Download any version</h2>
        <p className="mt-2 max-w-2xl text-slate-400">
          Browse past releases, expand release details, and grab the DMG you need.
        </p>
      </div>

      {loading ? (
        <LoadingSkeleton />
      ) : versions.length === 0 ? (
        <div className="card mt-6 p-8 text-center text-slate-400">
          No releases are available yet. Check back soon for the first download.
        </div>
      ) : (
        <>
          <div className="mt-6 space-y-4">
            {pageVersions.map((version, index) => (
              <ReleaseCard
                key={version.version}
                version={version}
                isLatest={currentPage === 1 && index === 0}
              />
            ))}
          </div>
          {totalPages > 1 && (
            <Pagination
              currentPage={currentPage}
              totalPages={totalPages}
              totalCount={totalCount}
              onPageChange={goToPage}
            />
          )}
        </>
      )}
    </section>
  );
}
