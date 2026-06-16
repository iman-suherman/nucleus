export function getPublicOrigin(request?: Request): string {
  const configured =
    process.env.WEBSITE_BASE_URL?.trim() || process.env.NUCLEUS_SYNC_PUBLIC_URL?.trim();
  if (configured) {
    return configured.replace(/\/$/, "");
  }

  if (request) {
    const forwardedHost = request.headers.get("x-forwarded-host");
    const forwardedProto = request.headers.get("x-forwarded-proto") || "https";
    if (forwardedHost) {
      const host = forwardedHost.split(",")[0]?.trim();
      if (host) {
        return `${forwardedProto}://${host}`;
      }
    }

    const host = request.headers.get("host");
    if (host && !host.includes("localhost") && !host.includes("127.0.0.1")) {
      const proto = host.includes(".run.app") ? "https" : forwardedProto;
      return `${proto}://${host}`;
    }
  }

  if (request) {
    const origin = new URL(request.url).origin;
    if (!origin.includes("localhost") && !origin.includes("127.0.0.1")) {
      return origin;
    }
  }

  return "http://127.0.0.1:3000";
}

type CookieOptions = {
  httpOnly: boolean;
  secure: boolean;
  sameSite: "lax";
  path: string;
  maxAge: number;
  domain?: string;
};

export function authCookieOptions(maxAge = 600): CookieOptions {
  const isProduction = process.env.NODE_ENV === "production";
  const options: CookieOptions = {
    httpOnly: true,
    secure: isProduction,
    sameSite: "lax",
    path: "/",
    maxAge,
  };

  if (isProduction) {
    options.domain = process.env.OAUTH_COOKIE_DOMAIN?.trim() || ".suherman.net";
  }

  return options;
}

export function deleteAuthCookie(
  cookieStore: Awaited<ReturnType<typeof import("next/headers").cookies>>,
  name: string,
) {
  const options = authCookieOptions();
  cookieStore.delete({ name, path: "/" });
  if (options.domain) {
    cookieStore.delete({ name, path: "/", domain: options.domain });
  }
}
