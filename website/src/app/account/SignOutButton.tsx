"use client";

import { useRouter } from "next/navigation";

export function SignOutButton() {
  const router = useRouter();

  return (
    <button
      type="button"
      className="btn-secondary"
      onClick={async () => {
        await fetch("/api/auth/signout", { method: "POST" });
        router.push("/account/signin");
        router.refresh();
      }}
    >
      Sign out
    </button>
  );
}
