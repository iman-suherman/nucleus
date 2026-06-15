"use client";

import Image from "next/image";
import Link from "next/link";
import { useState } from "react";
import { BRAND_NAME, GITHUB_REPO_URL } from "@/lib/brand";

const nav = [
  { href: "/", label: "Home" },
  { href: "/install", label: "Install" },
  { href: "/versions", label: "Download" },
  { href: "/#features", label: "Features" },
  { href: GITHUB_REPO_URL, label: "GitHub", external: true },
];

export function Header() {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header className="sticky top-0 z-50 border-b border-white/10 bg-brand-navy/85 backdrop-blur-xl">
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-3 px-4 py-3 sm:px-6 sm:py-4">
        <Link href="/" className="flex min-w-0 items-center gap-2 sm:gap-3">
          <Image
            src="/app-icon.png"
            alt=""
            width={48}
            height={48}
            priority
            className="app-icon-mark h-10 w-10 rounded-[22%] object-contain sm:h-12 sm:w-12"
          />
          <span className="hidden truncate text-sm font-bold leading-snug tracking-tight text-slate-50 min-[420px]:block sm:text-base lg:text-lg">
            {BRAND_NAME}
          </span>
        </Link>

        <nav className="hidden items-center gap-6 text-sm font-medium text-slate-400 md:flex lg:gap-8">
          {nav.map((item) =>
            "external" in item && item.external ? (
              <a
                key={`${item.href}-${item.label}`}
                href={item.href}
                className="transition hover:text-brand-blue"
                target="_blank"
                rel="noopener noreferrer"
              >
                {item.label}
              </a>
            ) : (
              <Link
                key={`${item.href}-${item.label}`}
                href={item.href}
                className="transition hover:text-brand-blue"
              >
                {item.label}
              </Link>
            ),
          )}
        </nav>

        <div className="flex shrink-0 items-center gap-2">
          <Link href="/install" className="btn-primary hidden md:inline-flex">
            Get Nucleus
          </Link>
          <button
            type="button"
            onClick={() => setMenuOpen((open) => !open)}
            className="inline-flex h-10 w-10 items-center justify-center rounded-lg border border-white/15 bg-white/[0.06] text-slate-200 transition hover:border-brand-blue/40 hover:text-brand-blue md:hidden"
            aria-expanded={menuOpen}
            aria-controls="mobile-nav"
            aria-label={menuOpen ? "Close menu" : "Open menu"}
          >
            {menuOpen ? "×" : "☰"}
          </button>
        </div>
      </div>

      {menuOpen && (
        <nav
          id="mobile-nav"
          className="border-t border-white/10 bg-brand-navyLight px-4 py-4 shadow-soft md:hidden"
        >
          <ul className="space-y-1">
            {nav.map((item) => (
              <li key={`${item.href}-${item.label}-mobile`}>
                {"external" in item && item.external ? (
                  <a
                    href={item.href}
                    className="block rounded-lg px-3 py-2.5 text-sm font-medium text-slate-200 transition hover:bg-brand-blue/10 hover:text-brand-blue"
                    target="_blank"
                    rel="noopener noreferrer"
                    onClick={() => setMenuOpen(false)}
                  >
                    {item.label}
                  </a>
                ) : (
                  <Link
                    href={item.href}
                    className="block rounded-lg px-3 py-2.5 text-sm font-medium text-slate-200 transition hover:bg-brand-blue/10 hover:text-brand-blue"
                    onClick={() => setMenuOpen(false)}
                  >
                    {item.label}
                  </Link>
                )}
              </li>
            ))}
          </ul>
          <Link
            href="/install"
            className="btn-primary mt-4 w-full"
            onClick={() => setMenuOpen(false)}
          >
            Get Nucleus
          </Link>
        </nav>
      )}
    </header>
  );
}
