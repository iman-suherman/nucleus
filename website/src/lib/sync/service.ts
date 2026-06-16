import type { CollectionReference, DocumentData, DocumentReference } from "@google-cloud/firestore";
import {
  toEpochMs,
  toIso,
  userBillPaymentsCollection,
  userBillsCollection,
  userGoogleAccountsCollection,
  userNotesCollection,
  userSyncDoc,
} from "@/lib/firestore/client";

export type SyncNotePayload = {
  clientId: string;
  title: string;
  markdown: string;
  folderRaw: string;
  driveFileId?: string | null;
  updatedAt: string;
  deletedAt?: string | null;
  version: number;
};

export type SyncBillPayload = {
  clientId: string;
  name: string;
  amount: number;
  currencyCode?: string | null;
  categoryRaw: string;
  recurrenceRaw: string;
  customIntervalDays?: number | null;
  dueDayOfMonth?: number | null;
  nextDueDate: string;
  iconName: string;
  notes: string;
  isArchived: boolean;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  version: number;
};

export type SyncBillPaymentPayload = {
  clientId: string;
  billClientId: string;
  amount: number;
  paidAt: string;
  note: string;
  updatedAt: string;
  deletedAt?: string | null;
  version: number;
};

export type SyncGoogleAccountPayload = {
  clientId: string;
  email: string;
  displayName: string;
  avatarUrl: string;
  isPrimary: boolean;
  isPrimaryNotesAccount: boolean;
  authMode: string;
  sortOrder: number;
  createdAt: string;
  updatedAt: string;
  deletedAt?: string | null;
  version: number;
};

export type SyncPushPayload = {
  notes?: SyncNotePayload[];
  bills?: SyncBillPayload[];
  billPayments?: SyncBillPaymentPayload[];
  settings?: { payload: unknown; updatedAt: string; version: number } | null;
  dashboard?: {
    payload: unknown;
    analyzedAt: string;
    updatedAt: string;
    version: number;
  } | null;
  googleAccounts?: SyncGoogleAccountPayload[];
};

export type SyncPullResponse = SyncPushPayload & {
  serverTime: string;
};

function parseDate(value: string): Date {
  return new Date(value);
}

function isAfterSince(updatedAt: unknown, sinceMs: number): boolean {
  return toEpochMs(updatedAt) > sinceMs;
}

async function listChangedDocs<T>(
  collection: CollectionReference,
  sinceMs: number,
  mapDoc: (id: string, data: DocumentData) => T | null,
): Promise<T[]> {
  const snapshot = await collection.get();
  const items: T[] = [];
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (!isAfterSince(data.updatedAt, sinceMs)) {
      continue;
    }
    const mapped = mapDoc(doc.id, data);
    if (mapped) items.push(mapped);
  }
  return items;
}

export async function pullChanges(userId: string, since?: string): Promise<SyncPullResponse> {
  const sinceMs = since ? parseDate(since).getTime() : 0;

  const [noteRows, billRows, paymentRows, settingsDoc, dashboardDoc, accountRows] =
    await Promise.all([
      listChangedDocs(userNotesCollection(userId), sinceMs, (id, data) => ({
        clientId: String(data.clientId ?? id),
        title: String(data.title ?? ""),
        markdown: String(data.markdown ?? ""),
        folderRaw: String(data.folderRaw ?? "notes"),
        driveFileId: data.driveFileId ? String(data.driveFileId) : null,
        updatedAt: toIso(data.updatedAt),
        deletedAt: data.deletedAt ? toIso(data.deletedAt) : null,
        version: Number(data.version ?? 0),
      })),
      listChangedDocs(userBillsCollection(userId), sinceMs, (id, data) => ({
        clientId: String(data.clientId ?? id),
        name: String(data.name ?? ""),
        amount: Number(data.amount ?? 0),
        currencyCode: data.currencyCode ? String(data.currencyCode) : "AUD",
        categoryRaw: String(data.categoryRaw ?? "other"),
        recurrenceRaw: String(data.recurrenceRaw ?? "monthly"),
        customIntervalDays:
          data.customIntervalDays === undefined ? null : Number(data.customIntervalDays),
        dueDayOfMonth: data.dueDayOfMonth === undefined ? null : Number(data.dueDayOfMonth),
        nextDueDate: toIso(data.nextDueDate),
        iconName: String(data.iconName ?? ""),
        notes: String(data.notes ?? ""),
        isArchived: Boolean(data.isArchived),
        sortOrder: Number(data.sortOrder ?? 0),
        createdAt: toIso(data.createdAt),
        updatedAt: toIso(data.updatedAt),
        deletedAt: data.deletedAt ? toIso(data.deletedAt) : null,
        version: Number(data.version ?? 0),
      })),
      listChangedDocs(userBillPaymentsCollection(userId), sinceMs, (id, data) => ({
        clientId: String(data.clientId ?? id),
        billClientId: String(data.billClientId ?? ""),
        amount: Number(data.amount ?? 0),
        paidAt: toIso(data.paidAt),
        note: String(data.note ?? ""),
        updatedAt: toIso(data.updatedAt),
        deletedAt: data.deletedAt ? toIso(data.deletedAt) : null,
        version: Number(data.version ?? 0),
      })),
      userSyncDoc(userId, "settings").get(),
      userSyncDoc(userId, "dashboard").get(),
      listChangedDocs(userGoogleAccountsCollection(userId), sinceMs, (id, data) => ({
        clientId: String(data.clientId ?? id),
        email: String(data.email ?? ""),
        displayName: String(data.displayName ?? ""),
        avatarUrl: String(data.avatarUrl ?? ""),
        isPrimary: Boolean(data.isPrimary),
        isPrimaryNotesAccount: Boolean(data.isPrimaryNotesAccount),
        authMode: String(data.authMode ?? "webSession"),
        sortOrder: Number(data.sortOrder ?? 0),
        createdAt: toIso(data.createdAt),
        updatedAt: toIso(data.updatedAt),
        deletedAt: data.deletedAt ? toIso(data.deletedAt) : null,
        version: Number(data.version ?? 0),
      })),
    ]);

  const response: SyncPullResponse = {
    serverTime: new Date().toISOString(),
    notes: noteRows,
    bills: billRows,
    billPayments: paymentRows,
    googleAccounts: accountRows,
  };

  if (settingsDoc.exists) {
    const data = settingsDoc.data() ?? {};
    if (isAfterSince(data.updatedAt, sinceMs)) {
      response.settings = {
        payload: data.payload,
        updatedAt: toIso(data.updatedAt),
        version: Number(data.version ?? 0),
      };
    }
  }

  if (dashboardDoc.exists) {
    const data = dashboardDoc.data() ?? {};
    if (isAfterSince(data.updatedAt, sinceMs)) {
      response.dashboard = {
        payload: data.payload,
        analyzedAt: toIso(data.analyzedAt),
        updatedAt: toIso(data.updatedAt),
        version: Number(data.version ?? 0),
      };
    }
  }

  return response;
}

async function upsertVersionedDoc(
  ref: DocumentReference,
  payload: Record<string, unknown>,
  incomingVersion: number,
): Promise<void> {
  const existing = await ref.get();
  if (existing.exists) {
    const currentVersion = Number(existing.data()?.version ?? 0);
    if (currentVersion > incomingVersion) {
      return;
    }
  }
  await ref.set(payload, { merge: true });
}

async function upsertNote(userId: string, item: SyncNotePayload) {
  const updatedAt = parseDate(item.updatedAt);
  await upsertVersionedDoc(
    userNotesCollection(userId).doc(item.clientId),
    {
      clientId: item.clientId,
      title: item.title,
      markdown: item.markdown,
      folderRaw: item.folderRaw,
      driveFileId: item.driveFileId ?? null,
      updatedAt,
      updatedAtMs: updatedAt.getTime(),
      deletedAt: item.deletedAt ? parseDate(item.deletedAt) : null,
      version: item.version,
    },
    item.version,
  );
}

async function upsertBill(userId: string, item: SyncBillPayload) {
  const updatedAt = parseDate(item.updatedAt);
  await upsertVersionedDoc(
    userBillsCollection(userId).doc(item.clientId),
    {
      clientId: item.clientId,
      name: item.name,
      amount: item.amount,
      currencyCode: item.currencyCode ?? "AUD",
      categoryRaw: item.categoryRaw,
      recurrenceRaw: item.recurrenceRaw,
      customIntervalDays: item.customIntervalDays ?? null,
      dueDayOfMonth: item.dueDayOfMonth ?? null,
      nextDueDate: parseDate(item.nextDueDate),
      iconName: item.iconName,
      notes: item.notes,
      isArchived: item.isArchived,
      sortOrder: item.sortOrder,
      createdAt: parseDate(item.createdAt),
      updatedAt,
      updatedAtMs: updatedAt.getTime(),
      deletedAt: item.deletedAt ? parseDate(item.deletedAt) : null,
      version: item.version,
    },
    item.version,
  );
}

async function upsertBillPayment(userId: string, item: SyncBillPaymentPayload) {
  const updatedAt = parseDate(item.updatedAt);
  await upsertVersionedDoc(
    userBillPaymentsCollection(userId).doc(item.clientId),
    {
      clientId: item.clientId,
      billClientId: item.billClientId,
      amount: item.amount,
      paidAt: parseDate(item.paidAt),
      note: item.note,
      updatedAt,
      updatedAtMs: updatedAt.getTime(),
      deletedAt: item.deletedAt ? parseDate(item.deletedAt) : null,
      version: item.version,
    },
    item.version,
  );
}

async function upsertGoogleAccount(userId: string, item: SyncGoogleAccountPayload) {
  const updatedAt = parseDate(item.updatedAt);
  await upsertVersionedDoc(
    userGoogleAccountsCollection(userId).doc(item.clientId),
    {
      clientId: item.clientId,
      email: item.email,
      displayName: item.displayName,
      avatarUrl: item.avatarUrl,
      isPrimary: item.isPrimary,
      isPrimaryNotesAccount: item.isPrimaryNotesAccount,
      authMode: item.authMode,
      sortOrder: item.sortOrder,
      createdAt: parseDate(item.createdAt),
      updatedAt,
      updatedAtMs: updatedAt.getTime(),
      deletedAt: item.deletedAt ? parseDate(item.deletedAt) : null,
      version: item.version,
    },
    item.version,
  );
}

export async function pushChanges(userId: string, payload: SyncPushPayload) {
  if (payload.notes?.length) {
    for (const item of payload.notes) {
      await upsertNote(userId, item);
    }
  }

  if (payload.bills?.length) {
    for (const item of payload.bills) {
      await upsertBill(userId, item);
    }
  }

  if (payload.billPayments?.length) {
    for (const item of payload.billPayments) {
      await upsertBillPayment(userId, item);
    }
  }

  if (payload.googleAccounts?.length) {
    for (const item of payload.googleAccounts) {
      await upsertGoogleAccount(userId, item);
    }
  }

  if (payload.settings) {
    const updatedAt = parseDate(payload.settings.updatedAt);
    await upsertVersionedDoc(
      userSyncDoc(userId, "settings"),
      {
        payload: payload.settings.payload,
        updatedAt,
        updatedAtMs: updatedAt.getTime(),
        version: payload.settings.version,
      },
      payload.settings.version,
    );
  }

  if (payload.dashboard) {
    const updatedAt = parseDate(payload.dashboard.updatedAt);
    await upsertVersionedDoc(
      userSyncDoc(userId, "dashboard"),
      {
        payload: payload.dashboard.payload,
        analyzedAt: parseDate(payload.dashboard.analyzedAt),
        updatedAt,
        updatedAtMs: updatedAt.getTime(),
        version: payload.dashboard.version,
      },
      payload.dashboard.version,
    );
  }
}
