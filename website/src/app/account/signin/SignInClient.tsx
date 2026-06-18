"use client";

import Image from "next/image";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import { BRAND_NAME } from "@/lib/brand";

export function SignInClient() {
  const searchParams = useSearchParams();
  const error = searchParams.get("error");
  const returnTo = searchParams.get("returnTo") ?? "/account";

  return (
    <div className="mx-auto flex min-h-[70vh] max-w-lg flex-col justify-center px-4 py-16">
      <div className="card p-8">
        <div className="mb-6 flex items-center gap-3">
          <Image src="/app-icon.png" alt="" width={48} height={48} className="rounded-[22%]" />
          <div>
            <h1 className="text-2xl font-bold text-white">Sign in to {BRAND_NAME} Cloud</h1>
            <p className="text-sm text-slate-400">
              Sync notes, bills, settings, and dashboard layouts across your devices.
            </p>
          </div>
        </div>

        {error ? (
          <div className="mb-4 rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-200">
            {error}
          </div>
        ) : null}

        <a
          href={`/api/auth/google?returnTo=${encodeURIComponent(returnTo)}`}
          className="btn-primary w-full"
        >
          Continue with Google
        </a>

        <p className="mt-6 text-center text-xs text-slate-500">
          Nucleus Cloud stores your workspace data. Google OAuth tokens for Gmail stay on your Mac
          in Keychain.
        </p>
      </div>
    </div>
  );
}
