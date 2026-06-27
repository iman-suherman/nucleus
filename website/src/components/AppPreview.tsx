import { BRAND_NAME } from "@/lib/brand";

export function AppPreview() {
  return (
    <section id="preview" className="mx-auto max-w-7xl px-4 py-6 sm:px-6 sm:py-8 md:py-10">
      <div className="mx-auto max-w-3xl text-center">
        <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">
          Native macOS app
        </p>
        <h2 className="mt-2 text-2xl font-bold text-slate-50 sm:text-3xl md:text-4xl">
          Open one cockpit every morning.
        </h2>
        <p className="mt-3 text-base leading-7 text-slate-400">
          {BRAND_NAME} keeps mail, bills, clipboard, notes, passwords, music, and tmux in one SwiftUI
          workspace — with a Dashboard that analyses your day and tells you what needs attention first.
        </p>
      </div>
    </section>
  );
}
