import { NextResponse } from "next/server";
import { getSessionUser } from "@/lib/auth/session";
import { authenticateApiRequest } from "@/lib/auth/api-token";

export async function GET(request: Request) {
  const apiUser = await authenticateApiRequest(request.headers.get("authorization"));
  if (apiUser) {
    return NextResponse.json({
      authenticated: true,
      source: "api",
      user: {
        id: apiUser.id,
        email: apiUser.email,
        name: apiUser.name,
        avatarUrl: apiUser.avatarUrl,
      },
      device: {
        id: apiUser.deviceId,
        name: apiUser.deviceName,
      },
    });
  }

  const sessionUser = await getSessionUser();
  if (sessionUser) {
    return NextResponse.json({
      authenticated: true,
      source: "session",
      user: sessionUser,
    });
  }

  return NextResponse.json({ authenticated: false }, { status: 401 });
}
