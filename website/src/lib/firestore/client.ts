import { Firestore, Timestamp } from "@google-cloud/firestore";

const globalForFirestore = globalThis as unknown as {
  firestore?: Firestore;
};

function clearLocalCredentialsInCloudRun() {
  if (!process.env.K_SERVICE) return;
  // Cloud Run uses the attached service account, not a local credentials file.
  delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
}

export function getFirestore(): Firestore {
  if (!globalForFirestore.firestore) {
    clearLocalCredentialsInCloudRun();
    const projectId = process.env.GCP_PROJECT_ID || process.env.GOOGLE_CLOUD_PROJECT;
    globalForFirestore.firestore = new Firestore(projectId ? { projectId } : undefined);
  }
  return globalForFirestore.firestore;
}

export async function ensureFirestore(): Promise<void> {
  await getFirestore().collection("_health").doc("ping").get();
}

export function toDate(value: unknown): Date {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === "string" || typeof value === "number") {
    return new Date(value);
  }
  return new Date(0);
}

export function toIso(value: unknown): string {
  return toDate(value).toISOString();
}

export function toEpochMs(value: unknown): number {
  return toDate(value).getTime();
}

export const COLLECTIONS = {
  users: "nucleus_sync_users",
  usersByGoogleSub: "nucleus_sync_users_by_google_sub",
  webSessions: "nucleus_sync_web_sessions",
  webSessionByHash: "nucleus_sync_web_session_by_hash",
  apiTokens: "nucleus_sync_api_tokens",
  apiTokenByDevice: "nucleus_sync_api_token_by_device",
  deviceAuthorizations: "nucleus_sync_device_authorizations",
} as const;

export function userNotesCollection(userId: string) {
  return getFirestore().collection(COLLECTIONS.users).doc(userId).collection("notes");
}

export function userBillsCollection(userId: string) {
  return getFirestore().collection(COLLECTIONS.users).doc(userId).collection("bills");
}

export function userBillPaymentsCollection(userId: string) {
  return getFirestore().collection(COLLECTIONS.users).doc(userId).collection("bill_payments");
}

export function userGoogleAccountsCollection(userId: string) {
  return getFirestore().collection(COLLECTIONS.users).doc(userId).collection("google_accounts");
}

export function userSyncDoc(userId: string, kind: "settings" | "dashboard") {
  return getFirestore()
    .collection(COLLECTIONS.users)
    .doc(userId)
    .collection("sync")
    .doc(kind);
}
