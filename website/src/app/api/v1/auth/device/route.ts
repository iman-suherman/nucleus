import { NextResponse } from "next/server";
import { createApiToken } from "@/lib/auth/api-token";
import { deviceAuthorizationExpiryDate } from "@/lib/auth/tokens";
import { getSessionUser } from "@/lib/auth/session";
import {
  approveDeviceAuthorization,
  clearDeviceAuthorizationToken,
  getDeviceAuthorization,
  markDeviceAuthorizationExpired,
  upsertDeviceAuthorization,
} from "@/lib/firestore/device-auth";
import { jsonError } from "@/lib/api";

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as
    | { deviceId?: string; deviceName?: string }
    | null;

  const deviceId = body?.deviceId?.trim();
  const deviceName = body?.deviceName?.trim() || "Nucleus";

  if (!deviceId) {
    return jsonError("deviceId is required");
  }

  const expiresAt = deviceAuthorizationExpiryDate();
  await upsertDeviceAuthorization(deviceId, deviceName, expiresAt);

  const baseUrl = process.env.WEBSITE_BASE_URL ?? new URL(request.url).origin;

  return NextResponse.json({
    deviceId,
    verificationUrl: `${baseUrl}/account/connect?device_id=${encodeURIComponent(deviceId)}&device_name=${encodeURIComponent(deviceName)}`,
    expiresAt: expiresAt.toISOString(),
  });
}

export async function GET(request: Request) {
  const url = new URL(request.url);
  const deviceId = url.searchParams.get("device_id")?.trim();

  if (!deviceId) {
    return jsonError("device_id is required");
  }

  const authorization = await getDeviceAuthorization(deviceId);
  if (!authorization) {
    return jsonError("Device authorization not found", 404);
  }

  if (authorization.expiresAt <= new Date() && authorization.status === "pending") {
    await markDeviceAuthorizationExpired(deviceId);
    return NextResponse.json({ status: "expired" });
  }

  if (authorization.status !== "approved" || !authorization.plainToken) {
    return NextResponse.json({ status: authorization.status });
  }

  const token = authorization.plainToken;
  await clearDeviceAuthorizationToken(deviceId);

  return NextResponse.json({
    status: "approved",
    token,
  });
}

export async function PUT(request: Request) {
  const user = await getSessionUser();
  if (!user) {
    return jsonError("Sign in required", 401);
  }

  const body = (await request.json().catch(() => null)) as
    | { deviceId?: string; deviceName?: string }
    | null;

  const deviceId = body?.deviceId?.trim();
  const deviceName = body?.deviceName?.trim() || "Nucleus";

  if (!deviceId) {
    return jsonError("deviceId is required");
  }

  const authorization = await getDeviceAuthorization(deviceId);
  if (!authorization || authorization.expiresAt <= new Date()) {
    return jsonError("Device authorization expired", 410);
  }

  const plainToken = await createApiToken(user.id, deviceId, deviceName);
  await approveDeviceAuthorization(deviceId, user.id, plainToken);

  return NextResponse.json({
    status: "approved",
    deepLink: `net.suherman.nucleus:/cloud-sync?token=${encodeURIComponent(plainToken)}`,
  });
}
