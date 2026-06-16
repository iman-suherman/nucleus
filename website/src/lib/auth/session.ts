import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";
import {
  generateSessionToken,
  hashToken,
  SESSION_COOKIE,
  sessionExpiryDate,
} from "@/lib/auth/tokens";
import { createWebSessionRecord, getWebSessionByHash, revokeWebSessionRecords } from "@/lib/firestore/sessions";
import { getUserById } from "@/lib/firestore/users";
import { authCookieOptions, deleteAuthCookie } from "@/lib/auth/request-origin";

const encoder = new TextEncoder();

function authSecret(): Uint8Array {
  const secret = process.env.AUTH_SECRET;
  if (!secret) {
    throw new Error("AUTH_SECRET is not configured");
  }
  return encoder.encode(secret);
}

export type SessionUser = {
  id: string;
  email: string;
  name: string;
  avatarUrl: string;
};

export async function createWebSession(userId: string): Promise<string> {
  const token = generateSessionToken();
  const tokenHash = hashToken(token);
  const expiresAt = sessionExpiryDate();

  await createWebSessionRecord(userId, tokenHash, expiresAt);

  const jwt = await new SignJWT({ sid: tokenHash })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuedAt()
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(authSecret());

  return jwt;
}

export async function setSessionCookie(token: string) {
  const cookieStore = await cookies();
  cookieStore.set(SESSION_COOKIE, token, authCookieOptions(30 * 24 * 60 * 60));
}

export async function clearSessionCookie() {
  const cookieStore = await cookies();
  deleteAuthCookie(cookieStore, SESSION_COOKIE);
}

export async function getSessionUser(): Promise<SessionUser | null> {
  const cookieStore = await cookies();
  const token = cookieStore.get(SESSION_COOKIE)?.value;
  if (!token) return null;

  try {
    const { payload } = await jwtVerify(token, authSecret());
    const userId = payload.sub;
    const sid = payload.sid;
    if (!userId || typeof sid !== "string") return null;

    const session = await getWebSessionByHash(sid);
    if (!session || session.expiresAt <= new Date()) {
      return null;
    }

    const user = await getUserById(userId);
    if (!user) return null;

    return {
      id: user.id,
      email: user.email,
      name: user.name,
      avatarUrl: user.avatarUrl,
    };
  } catch {
    return null;
  }
}

export async function revokeWebSessions(userId: string) {
  await revokeWebSessionRecords(userId);
}
