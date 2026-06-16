export type UserRecord = {
  id: string;
  googleSub: string;
  email: string;
  name: string;
  avatarUrl: string;
  createdAt: Date;
  updatedAt: Date;
};

export type WebSessionRecord = {
  id: string;
  userId: string;
  tokenHash: string;
  expiresAt: Date;
  createdAt: Date;
};

export type ApiTokenRecord = {
  id: string;
  userId: string;
  tokenHash: string;
  deviceId: string;
  deviceName: string;
  expiresAt: Date;
  lastUsedAt?: Date;
  createdAt: Date;
};

export type DeviceAuthorizationRecord = {
  deviceId: string;
  deviceName: string;
  status: string;
  userId?: string;
  plainToken?: string | null;
  expiresAt: Date;
  createdAt: Date;
};
