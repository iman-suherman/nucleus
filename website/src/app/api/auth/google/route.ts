import { randomBytes } from "node:crypto";
import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { buildGoogleAuthUrl } from "@/lib/auth/google";
import { OAUTH_RETURN_COOKIE, OAUTH_STATE_COOKIE } from "@/lib/auth/oauth-cookies";
import { authCookieOptions } from "@/lib/auth/request-origin";

export async function GET(request: Request) {
  const url = new URL(request.url);
  const returnTo = url.searchParams.get("returnTo") ?? "/account";
  const state = randomBytes(16).toString("hex");
  const cookieOptions = authCookieOptions();

  const cookieStore = await cookies();
  cookieStore.set(OAUTH_STATE_COOKIE, state, cookieOptions);
  cookieStore.set(OAUTH_RETURN_COOKIE, returnTo, cookieOptions);

  return NextResponse.redirect(buildGoogleAuthUrl(state));
}
