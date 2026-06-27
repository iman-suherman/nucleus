import Link from "next/link";
import { BRAND_NAME } from "@/lib/brand";

export function CtaBanner() {
  return (
    <section className="mx-auto max-w-7xl px-4 py-16 sm:px-6">
      <div className="card flex flex-col items-start justify-between gap-6 p-8 md:flex-row md:items-center">
        <div>
          <h2 className="text-2xl font-bold text-slate-50 sm:text-3xl">
            Ready to open one workspace every morning?
          </h2>
          <p className="mt-3 max-w-2xl text-slate-400">
            Download {BRAND_NAME} for macOS and open one Dashboard for Gmail, bills, clipboard,
            notes, passwords, Apple Music, tmux, and alerts — with Your day productivity analysis,
            breaking news, Nucleus AI, and sync through Nucleus Cloud or iCloud.
          </p>
        </div>
        <Link href="/install" className="btn-primary shrink-0">
          Get {BRAND_NAME}
        </Link>
      </div>
    </section>
  );
}
