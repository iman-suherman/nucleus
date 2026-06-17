/** Public site origin — used for absolute Open Graph / Twitter card URLs. */
export const SITE_URL =
  process.env.NEXT_PUBLIC_SITE_URL?.trim() || "https://nucleus.suherman.net";

/** Same artwork as the hero section (`AppHeroIcon`). */
export const SHARE_IMAGE = {
  path: "/app-icon.png",
  width: 512,
  height: 512,
  alt: "Nucleus app icon",
} as const;
