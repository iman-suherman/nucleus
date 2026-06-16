import Image from "next/image";
import Link from "next/link";
import { redirect } from "next/navigation";
import { getSessionUser } from "@/lib/auth/session";
import { BRAND_NAME } from "@/lib/brand";
import { SignOutButton } from "./SignOutButton";

export default async function AccountPage() {
  const user = await getSessionUser();
  if (!user) {
    redirect("/account/signin");
  }

  return (
    <div className="mx-auto max-w-3xl px-4 py-16">
      <div className="card p-8">
        <div className="mb-8 flex items-center gap-4">
          {user.avatarUrl ? (
            <Image
              src={user.avatarUrl}
              alt=""
              width={64}
              height={64}
              className="rounded-full"
            />
          ) : (
            <div className="flex h-16 w-16 items-center justify-center rounded-full bg-brand-blue/20 text-xl font-bold text-brand-blue">
              {user.name.slice(0, 1).toUpperCase()}
            </div>
          )}
          <div>
            <h1 className="text-2xl font-bold text-white">{user.name || user.email}</h1>
            <p className="text-slate-400">{user.email}</p>
          </div>
        </div>

        <div className="space-y-6">
          <section>
            <h2 className="text-lg font-semibold text-white">Nucleus Cloud Sync</h2>
            <p className="mt-2 text-sm text-slate-400">
              Your {BRAND_NAME} workspace syncs through Nucleus Cloud — notes, bills, dashboard
              layouts, settings, and account metadata. Google OAuth tokens remain on your Mac in
              Keychain.
            </p>
          </section>

          <section className="rounded-xl border border-white/10 bg-white/[0.03] p-5">
            <h3 className="font-medium text-white">Connect a new Mac</h3>
            <p className="mt-2 text-sm text-slate-400">
              Open Nucleus → Settings → Nucleus Cloud → Connect Account. The app will open this page
              to authorize your device.
            </p>
            <Link href="/account/connect" className="btn-secondary mt-4 inline-flex">
              Manual device connect
            </Link>
          </section>

          <SignOutButton />
        </div>
      </div>
    </div>
  );
}
