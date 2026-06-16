import { randomUUID } from "node:crypto";
import type { DocumentData } from "@google-cloud/firestore";
import type { GoogleProfile } from "@/lib/auth/google";
import { COLLECTIONS, getFirestore } from "@/lib/firestore/client";
import type { UserRecord } from "@/lib/firestore/types";

function mapUser(id: string, data: DocumentData): UserRecord {
  return {
    id,
    googleSub: String(data.googleSub ?? ""),
    email: String(data.email ?? ""),
    name: String(data.name ?? ""),
    avatarUrl: String(data.avatarUrl ?? ""),
    createdAt: data.createdAt?.toDate?.() ?? new Date(data.createdAt),
    updatedAt: data.updatedAt?.toDate?.() ?? new Date(data.updatedAt),
  };
}

export async function getUserById(userId: string): Promise<UserRecord | null> {
  const doc = await getFirestore().collection(COLLECTIONS.users).doc(userId).get();
  if (!doc.exists) return null;
  return mapUser(doc.id, doc.data() ?? {});
}

export async function upsertUserFromGoogle(profile: GoogleProfile): Promise<UserRecord> {
  const db = getFirestore();
  const lookup = await db.collection(COLLECTIONS.usersByGoogleSub).doc(profile.sub).get();

  const now = new Date();

  if (lookup.exists) {
    const userId = String(lookup.data()?.userId ?? "");
    const userRef = db.collection(COLLECTIONS.users).doc(userId);
    await userRef.set(
      {
        googleSub: profile.sub,
        email: profile.email,
        name: profile.name ?? "",
        avatarUrl: profile.picture ?? "",
        updatedAt: now,
      },
      { merge: true },
    );
    const updated = await userRef.get();
    return mapUser(updated.id, updated.data() ?? {});
  }

  const userId = randomUUID();
  const userRef = db.collection(COLLECTIONS.users).doc(userId);
  await userRef.set({
    googleSub: profile.sub,
    email: profile.email,
    name: profile.name ?? "",
    avatarUrl: profile.picture ?? "",
    createdAt: now,
    updatedAt: now,
  });
  await db.collection(COLLECTIONS.usersByGoogleSub).doc(profile.sub).set({ userId });

  const created = await userRef.get();
  return mapUser(created.id, created.data() ?? {});
}
