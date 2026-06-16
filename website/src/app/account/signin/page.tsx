import { Suspense } from "react";
import { SignInClient } from "./SignInClient";

export default function SignInPage() {
  return (
    <Suspense fallback={<div className="px-4 py-16 text-center text-slate-400">Loading…</div>}>
      <SignInClient />
    </Suspense>
  );
}
