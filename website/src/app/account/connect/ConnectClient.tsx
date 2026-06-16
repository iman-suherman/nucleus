"use client";

import Image from "next/image";
import { useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { BRAND_NAME } from "@/lib/brand";

type ConnectState = "checking" | "needs_signin" | "ready" | "approving" | "approved" | "error";

export function ConnectClient() {
  const searchParams = useSearchParams();
  const deviceId = searchParams.get("device_id") ?? "";
  const deviceName = searchParams.get("device_name") ?? "Nucleus";
  const [state, setState] = useState<ConnectState>("checking");
  const [deepLink, setDeepLink] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!deviceId) {
      setState("error");
      setError("Missing device_id.");
      return;
    }

    async function checkSession() {
      const response = await fetch("/api/v1/account");
      if (response.ok) {
        setState("ready");
      } else {
        setState("needs_signin");
      }
    }

    void checkSession();
  }, [deviceId]);

  async function approveDevice() {
    setState("approving");
    setError(null);

    const response = await fetch("/api/v1/auth/device", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ deviceId, deviceName }),
    });

    if (!response.ok) {
      const payload = (await response.json().catch(() => null)) as { error?: string } | null;
      setState("error");
      setError(payload?.error ?? "Failed to authorize device.");
      return;
    }

    const payload = (await response.json()) as { deepLink?: string };
    setDeepLink(payload.deepLink ?? null);
    setState("approved");
  }

  if (!deviceId) {
    return (
      <div className="mx-auto max-w-lg px-4 py-16 text-center text-red-300">
        This link is missing a device identifier.
      </div>
    );
  }

  return (
    <div className="mx-auto flex min-h-[70vh] max-w-lg flex-col justify-center px-4 py-16">
      <div className="card p-8">
        <div className="mb-6 flex items-center gap-3">
          <Image src="/app-icon.png" alt="" width={48} height={48} className="rounded-[22%]" />
          <div>
            <h1 className="text-2xl font-bold text-white">Connect {deviceName}</h1>
            <p className="text-sm text-slate-400">
              Authorize this Mac to sync with {BRAND_NAME} Cloud.
            </p>
          </div>
        </div>

        {state === "checking" ? (
          <p className="text-slate-400">Checking your session…</p>
        ) : null}

        {state === "needs_signin" ? (
          <div className="space-y-4">
            <p className="text-sm text-slate-300">
              Sign in with Google to link <strong>{deviceName}</strong> to your Nucleus Cloud
              account.
            </p>
            <a
              href={`/api/auth/google?returnTo=${encodeURIComponent(`/account/connect?device_id=${encodeURIComponent(deviceId)}&device_name=${encodeURIComponent(deviceName)}`)}`}
              className="btn-primary w-full"
            >
              Continue with Google
            </a>
          </div>
        ) : null}

        {state === "ready" ? (
          <div className="space-y-4">
            <p className="text-sm text-slate-300">
              Allow <strong>{deviceName}</strong> to sync notes, bills, settings, and dashboard data
              with your Nucleus Cloud account?
            </p>
            <button type="button" className="btn-primary w-full" onClick={() => void approveDevice()}>
              Authorize Device
            </button>
          </div>
        ) : null}

        {state === "approving" ? <p className="text-slate-400">Authorizing device…</p> : null}

        {state === "approved" ? (
          <div className="space-y-4">
            <p className="text-sm text-green-300">
              Device authorized. Return to the Nucleus app to finish setup.
            </p>
            {deepLink ? (
              <a href={deepLink} className="btn-secondary w-full">
                Open Nucleus
              </a>
            ) : null}
          </div>
        ) : null}

        {state === "error" && error ? (
          <div className="rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-200">
            {error}
          </div>
        ) : null}
      </div>
    </div>
  );
}
