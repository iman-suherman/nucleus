import { NextResponse } from "next/server";
import { clearSessionCookie, revokeWebSessions } from "@/lib/auth/session";
import { getSessionUser } from "@/lib/auth/session";

export async function POST() {
  const user = await getSessionUser();
  if (user) {
    await revokeWebSessions(user.id);
  }
  await clearSessionCookie();
  return NextResponse.json({ ok: true });
}
