const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo";

export const GOOGLE_OAUTH_SCOPES = ["openid", "email", "profile"];

export type GoogleProfile = {
  sub: string;
  email: string;
  name: string;
  picture?: string;
};

function requiredEnv(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is not configured`);
  }
  return value;
}

export function getGoogleOAuthConfig() {
  return {
    clientId: requiredEnv("GOOGLE_OAUTH_CLIENT_ID"),
    clientSecret: requiredEnv("GOOGLE_OAUTH_CLIENT_SECRET"),
    redirectUri: requiredEnv("GOOGLE_OAUTH_REDIRECT_URI"),
  };
}

export function buildGoogleAuthUrl(state: string): string {
  const { clientId, redirectUri } = getGoogleOAuthConfig();
  const params = new URLSearchParams({
    client_id: clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    scope: GOOGLE_OAUTH_SCOPES.join(" "),
    access_type: "online",
    prompt: "select_account",
    state,
  });
  return `${GOOGLE_AUTH_URL}?${params.toString()}`;
}

export async function exchangeGoogleCode(code: string): Promise<GoogleProfile> {
  const { clientId, clientSecret, redirectUri } = getGoogleOAuthConfig();

  const tokenResponse = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: clientId,
      client_secret: clientSecret,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
    }),
  });

  if (!tokenResponse.ok) {
    const detail = await tokenResponse.text();
    throw new Error(`Google token exchange failed: ${detail}`);
  }

  const tokenPayload = (await tokenResponse.json()) as { access_token: string };
  const profileResponse = await fetch(GOOGLE_USERINFO_URL, {
    headers: { Authorization: `Bearer ${tokenPayload.access_token}` },
  });

  if (!profileResponse.ok) {
    const detail = await profileResponse.text();
    throw new Error(`Google userinfo failed: ${detail}`);
  }

  const profile = (await profileResponse.json()) as GoogleProfile;
  if (!profile.sub || !profile.email) {
    throw new Error("Google profile is missing required fields");
  }

  return profile;
}
