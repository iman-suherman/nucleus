import { NextResponse } from "next/server";
import { requireApiUser, jsonError } from "@/lib/api";
import { pullChanges } from "@/lib/sync/service";

export async function GET(request: Request) {
  const { user, response } = await requireApiUser(request);
  if (!user || response) {
    return response!;
  }

  const url = new URL(request.url);
  const since = url.searchParams.get("since") ?? undefined;

  try {
    const payload = await pullChanges(user.id, since);
    return NextResponse.json(payload);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Pull failed";
    return jsonError(message, 500);
  }
}
