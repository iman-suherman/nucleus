import { createHash, randomBytes } from "node:crypto";

export const SESSION_COOKIE = "nucleus_session";
export const API_TOKEN_PREFIX = "nuc_";

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function generateSessionToken(): string {
  return randomBytes(32).toString("base64url");
}

export function generateApiToken(): string {
  return `${API_TOKEN_PREFIX}${randomBytes(32).toString("base64url")}`;
}

export function generateDeviceId(): string {
  return randomBytes(16).toString("hex");
}

export function sessionExpiryDate(): Date {
  return new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
}

export function apiTokenExpiryDate(): Date {
  return new Date(Date.now() + 365 * 24 * 60 * 60 * 1000);
}

export function deviceAuthorizationExpiryDate(): Date {
  return new Date(Date.now() + 15 * 60 * 1000);
}
