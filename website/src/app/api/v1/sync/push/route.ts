import { NextResponse } from "next/server";
import { requireApiUser, jsonError } from "@/lib/api";
import { pullChanges, pushChanges, type SyncPushPayload } from "@/lib/sync/service";

export async function POST(request: Request) {
  const { user, response } = await requireApiUser(request);
  if (!user || response) {
    return response!;
  }

  const body = (await request.json().catch(() => null)) as SyncPushPayload | null;
  if (!body) {
    return jsonError("Invalid JSON body");
  }

  try {
    await pushChanges(user.id, body);
    const snapshot = await pullChanges(user.id, "1970-01-01T00:00:00.000Z");
    return NextResponse.json({
      ok: true,
      serverTime: snapshot.serverTime,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Push failed";
    return jsonError(message, 500);
  }
}
