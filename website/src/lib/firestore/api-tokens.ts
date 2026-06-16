import { randomUUID } from "node:crypto";
import type { DocumentData } from "@google-cloud/firestore";
import {
  apiTokenExpiryDate,
  generateApiToken,
  hashToken,
} from "@/lib/auth/tokens";
import { COLLECTIONS, getFirestore } from "@/lib/firestore/client";
import type { ApiTokenRecord } from "@/lib/firestore/types";
import { getUserById } from "@/lib/firestore/users";

function deviceDocId(userId: string, deviceId: string): string {
  return `${userId}__${deviceId}`;
}

function mapApiToken(id: string, data: DocumentData): ApiTokenRecord {
  return {
    id,
    userId: String(data.userId),
    tokenHash: String(data.tokenHash),
    deviceId: String(data.deviceId),
    deviceName: String(data.deviceName ?? "Nucleus"),
    expiresAt: data.expiresAt?.toDate?.() ?? new Date(data.expiresAt),
    lastUsedAt: data.lastUsedAt?.toDate?.() ?? undefined,
    createdAt: data.createdAt?.toDate?.() ?? new Date(data.createdAt),
  };
}

export async function createApiTokenRecord(
  userId: string,
  deviceId: string,
  deviceName: string,
): Promise<string> {
  const db = getFirestore();
  const plainToken = generateApiToken();
  const tokenHash = hashToken(plainToken);
  const expiresAt = apiTokenExpiryDate();
  const now = new Date();
  const tokenId = randomUUID();
  const deviceKey = deviceDocId(userId, deviceId);

  const existingDevice = await db.collection(COLLECTIONS.apiTokenByDevice).doc(deviceKey).get();
  if (existingDevice.exists) {
    const oldHash = String(existingDevice.data()?.tokenHash ?? "");
    if (oldHash) {
      await db.collection(COLLECTIONS.apiTokens).doc(oldHash).delete();
    }
  }

  await db.collection(COLLECTIONS.apiTokens).doc(tokenHash).set({
    id: tokenId,
    userId,
    tokenHash,
    deviceId,
    deviceName,
    expiresAt,
    lastUsedAt: now,
    createdAt: now,
  });

  await db.collection(COLLECTIONS.apiTokenByDevice).doc(deviceKey).set({
    tokenHash,
    userId,
    deviceId,
    deviceName,
    expiresAt,
    lastUsedAt: now,
    createdAt: now,
  });

  return plainToken;
}

export async function getApiTokenByPlainToken(plainToken: string): Promise<ApiTokenRecord | null> {
  const tokenHash = hashToken(plainToken);
  const doc = await getFirestore().collection(COLLECTIONS.apiTokens).doc(tokenHash).get();
  if (!doc.exists) return null;
  return mapApiToken(String(doc.data()?.id ?? doc.id), doc.data() ?? {});
}

export async function touchApiToken(tokenHash: string): Promise<void> {
  await getFirestore().collection(COLLECTIONS.apiTokens).doc(tokenHash).set(
    { lastUsedAt: new Date() },
    { merge: true },
  );
}

export type ApiAuthUser = {
  id: string;
  email: string;
  name: string;
  avatarUrl: string;
  deviceId: string;
  deviceName: string;
};

export async function authenticateApiToken(
  authorizationHeader: string | null,
): Promise<ApiAuthUser | null> {
  if (!authorizationHeader?.startsWith("Bearer ")) {
    return null;
  }

  const plainToken = authorizationHeader.slice("Bearer ".length).trim();
  if (!plainToken) return null;

  const tokenRow = await getApiTokenByPlainToken(plainToken);
  if (!tokenRow || tokenRow.expiresAt <= new Date()) {
    return null;
  }

  const user = await getUserById(tokenRow.userId);
  if (!user) return null;

  await touchApiToken(tokenRow.tokenHash);

  return {
    id: user.id,
    email: user.email,
    name: user.name,
    avatarUrl: user.avatarUrl,
    deviceId: tokenRow.deviceId,
    deviceName: tokenRow.deviceName,
  };
}
