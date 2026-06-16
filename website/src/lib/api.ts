import { NextResponse } from "next/server";
import { authenticateApiRequest } from "@/lib/auth/api-token";

export async function requireApiUser(request: Request) {
  const user = await authenticateApiRequest(request.headers.get("authorization"));
  if (!user) {
    return {
      user: null,
      response: NextResponse.json({ error: "Unauthorized" }, { status: 401 }),
    };
  }
  return { user, response: null };
}

export function jsonError(message: string, status = 400) {
  return NextResponse.json({ error: message }, { status });
}
