import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import { exchangeGoogleCode } from "@/lib/auth/google";
import { OAUTH_RETURN_COOKIE, OAUTH_STATE_COOKIE } from "@/lib/auth/oauth-cookies";
import { deleteAuthCookie, getPublicOrigin } from "@/lib/auth/request-origin";
import { createWebSession, setSessionCookie } from "@/lib/auth/session";
import { upsertUserFromGoogle } from "@/lib/firestore/users";

export async function GET(request: Request) {
  const publicOrigin = getPublicOrigin(request);
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const error = url.searchParams.get("error");

  const cookieStore = await cookies();
  const expectedState = cookieStore.get(OAUTH_STATE_COOKIE)?.value;
  const returnTo = cookieStore.get(OAUTH_RETURN_COOKIE)?.value ?? "/account";

  deleteAuthCookie(cookieStore, OAUTH_STATE_COOKIE);
  deleteAuthCookie(cookieStore, OAUTH_RETURN_COOKIE);

  if (error) {
    return NextResponse.redirect(
      new URL(`/account/signin?error=${encodeURIComponent(error)}`, publicOrigin),
    );
  }

  if (!code || !state || !expectedState || state !== expectedState) {
    return NextResponse.redirect(
      new URL("/account/signin?error=invalid_state", publicOrigin),
    );
  }

  try {
    const profile = await exchangeGoogleCode(code);
    const user = await upsertUserFromGoogle(profile);
    const sessionToken = await createWebSession(user.id);
    await setSessionCookie(sessionToken);
    return NextResponse.redirect(new URL(returnTo, publicOrigin));
  } catch (callbackError) {
    const message =
      callbackError instanceof Error ? callbackError.message : "Authentication failed";
    return NextResponse.redirect(
      new URL(`/account/signin?error=${encodeURIComponent(message)}`, publicOrigin),
    );
  }
}
