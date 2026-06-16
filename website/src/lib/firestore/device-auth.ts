import type { DocumentData } from "@google-cloud/firestore";
import { COLLECTIONS, getFirestore } from "@/lib/firestore/client";
import type { DeviceAuthorizationRecord } from "@/lib/firestore/types";

function mapDeviceAuthorization(deviceId: string, data: DocumentData): DeviceAuthorizationRecord {
  return {
    deviceId,
    deviceName: String(data.deviceName ?? "Nucleus"),
    status: String(data.status ?? "pending"),
    userId: data.userId ? String(data.userId) : undefined,
    plainToken: data.plainToken ? String(data.plainToken) : null,
    expiresAt: data.expiresAt?.toDate?.() ?? new Date(data.expiresAt),
    createdAt: data.createdAt?.toDate?.() ?? new Date(data.createdAt),
  };
}

export async function upsertDeviceAuthorization(
  deviceId: string,
  deviceName: string,
  expiresAt: Date,
): Promise<void> {
  const ref = getFirestore().collection(COLLECTIONS.deviceAuthorizations).doc(deviceId);
  const existing = await ref.get();
  await ref.set({
    deviceId,
    deviceName,
    status: "pending",
    userId: null,
    plainToken: null,
    expiresAt,
    createdAt: existing.exists
      ? existing.data()?.createdAt ?? new Date()
      : new Date(),
  });
}

export async function getDeviceAuthorization(
  deviceId: string,
): Promise<DeviceAuthorizationRecord | null> {
  const doc = await getFirestore().collection(COLLECTIONS.deviceAuthorizations).doc(deviceId).get();
  if (!doc.exists) return null;
  return mapDeviceAuthorization(deviceId, doc.data() ?? {});
}

export async function markDeviceAuthorizationExpired(deviceId: string): Promise<void> {
  await getFirestore()
    .collection(COLLECTIONS.deviceAuthorizations)
    .doc(deviceId)
    .set({ status: "expired" }, { merge: true });
}

export async function approveDeviceAuthorization(
  deviceId: string,
  userId: string,
  plainToken: string,
): Promise<void> {
  await getFirestore().collection(COLLECTIONS.deviceAuthorizations).doc(deviceId).set(
    {
      status: "approved",
      userId,
      plainToken,
    },
    { merge: true },
  );
}

export async function clearDeviceAuthorizationToken(deviceId: string): Promise<void> {
  await getFirestore()
    .collection(COLLECTIONS.deviceAuthorizations)
    .doc(deviceId)
    .set({ plainToken: null }, { merge: true });
}
