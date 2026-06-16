import { randomUUID } from "node:crypto";
import { hashToken } from "@/lib/auth/tokens";
import { COLLECTIONS, getFirestore } from "@/lib/firestore/client";

export async function createWebSessionRecord(
  userId: string,
  tokenHash: string,
  expiresAt: Date,
): Promise<void> {
  const db = getFirestore();
  const sessionId = randomUUID();

  await db.collection(COLLECTIONS.webSessions).doc(sessionId).set({
    userId,
    tokenHash,
    expiresAt,
    createdAt: new Date(),
  });

  await db.collection(COLLECTIONS.webSessionByHash).doc(tokenHash).set({
    userId,
    sessionId,
    expiresAt,
  });
}

export async function getWebSessionByHash(tokenHash: string): Promise<{
  userId: string;
  sessionId: string;
  expiresAt: Date;
} | null> {
  const doc = await getFirestore().collection(COLLECTIONS.webSessionByHash).doc(tokenHash).get();
  if (!doc.exists) return null;

  const data = doc.data() ?? {};
  return {
    userId: String(data.userId),
    sessionId: String(data.sessionId),
    expiresAt: data.expiresAt?.toDate?.() ?? new Date(data.expiresAt),
  };
}

export async function revokeWebSessionRecords(userId: string): Promise<void> {
  const db = getFirestore();
  const snapshot = await db
    .collection(COLLECTIONS.webSessions)
    .where("userId", "==", userId)
    .get();

  const batch = db.batch();
  for (const doc of snapshot.docs) {
    const tokenHash = String(doc.data().tokenHash ?? "");
    batch.delete(doc.ref);
    if (tokenHash) {
      batch.delete(db.collection(COLLECTIONS.webSessionByHash).doc(tokenHash));
    }
  }
  await batch.commit();
}

export { hashToken };
