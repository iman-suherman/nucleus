import { GITHUB_REPO_URL } from "@/lib/brand";

export function OpenSourceSection() {
  return (
    <section id="opensource" className="mx-auto max-w-7xl px-4 py-16 sm:px-6">
      <div className="card p-8">
        <h2 className="text-2xl font-bold text-slate-50 sm:text-3xl">Open source</h2>
        <p className="mt-4 max-w-3xl text-slate-400">
          Nucleus is built in Swift with modular kits for mail, calendar, clipboard, and notes. Contributions and issue reports are welcome on GitHub.
        </p>
        <a
          href={GITHUB_REPO_URL}
          className="mt-6 inline-flex text-brand-blue transition hover:text-[#3395ff]"
          target="_blank"
          rel="noopener noreferrer"
        >
          github.com/iman-suherman/nucleus
        </a>
      </div>
    </section>
  );
}
