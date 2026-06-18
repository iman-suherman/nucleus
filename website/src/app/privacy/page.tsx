import type { Metadata } from "next";
import Link from "next/link";
import { BRAND_NAME } from "@/lib/brand";
import { SITE_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: `How ${BRAND_NAME} for iOS and macOS handles your data — notes, passwords, bills, iCloud sync, location, and notifications.`,
  alternates: {
    canonical: `${SITE_URL}/privacy`,
  },
};

const sections = [
  {
    title: "Overview",
    paragraphs: [
      `${BRAND_NAME} is a personal productivity app. The iOS and iPadOS app is a mobile companion to the macOS app. Your data is stored on your devices and, when you sign in to iCloud, synced through Apple's CloudKit using your Apple ID.`,
      "We do not sell your data, run advertising, or embed third-party analytics SDKs in the app.",
    ],
  },
  {
    title: "Data you create in the app",
    bullets: [
      "Notes and password entries you write in the app",
      "Bills and payment records you enter",
      "Dashboard preferences and notification settings",
      "Device security preferences such as Face ID or passcode lock settings",
    ],
    footer:
      "This content is stored locally on your device. When iCloud is enabled, it is synced to your private CloudKit container (iCloud.net.suherman.nucleus) tied to your Apple ID.",
  },
  {
    title: "iCloud and CloudKit sync",
    bullets: [
      "Notes, passwords, bills, and synced settings can sync between your iPhone, iPad, and Mac when you use the same Apple ID",
      "Sync traffic goes through Apple's iCloud infrastructure; we do not operate a separate cloud database for your note or bill content",
      "If you are not signed in to iCloud, data remains on the device only",
    ],
  },
  {
    title: "Location",
    paragraphs: [
      "If you use today's weather on the Dashboard, the app requests Location When In Use to fetch a local forecast through Apple's WeatherKit. Location is used only for that feature and is not stored on our servers.",
    ],
  },
  {
    title: "Biometric and device lock",
    paragraphs: [
      "You can require Face ID, Touch ID, or your device passcode to unlock the app. Authentication is handled by iOS; we do not receive or store your biometric data.",
    ],
  },
  {
    title: "Notifications",
    bullets: [
      "Bill due reminders are scheduled as local notifications on your device based on bills you track in the app",
      "Email notification toggles sync with your Mac settings but do not deliver remote push notifications on iOS unless a separate push service is configured by you",
    ],
  },
  {
    title: "Google accounts (macOS)",
    paragraphs: [
      "The macOS app connects Gmail through Google sign-in in an embedded web session. Google OAuth tokens can optionally sync via iCloud Keychain when that setting is enabled on your Mac.",
      "The iOS companion app does not include a Mail workspace and does not require Google sign-in.",
    ],
  },
  {
    title: "What we do not collect",
    bullets: [
      "No advertising identifiers",
      "No cross-app tracking",
      "No sale of personal data",
      "No upload of your notes, passwords, or bills to developer-operated servers",
    ],
  },
  {
    title: "Children",
    paragraphs: [
      `${BRAND_NAME} is not directed at children under 13, and we do not knowingly collect personal information from children.`,
    ],
  },
  {
    title: "Changes",
    paragraphs: [
      "We may update this policy when app features change. The effective date below will be revised when updates are published.",
    ],
  },
  {
    title: "Contact",
    paragraphs: [
      "Questions about privacy can be sent via GitHub issues on the open-source repository or through the support contact listed on the App Store listing.",
    ],
  },
];

export default function PrivacyPage() {
  return (
    <article className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
      <p className="text-sm font-semibold uppercase tracking-wide text-brand-blue">Legal</p>
      <h1 className="mt-2 text-3xl font-bold tracking-tight text-slate-50 sm:text-4xl">
        Privacy Policy
      </h1>
      <p className="mt-4 text-sm text-slate-400">Effective date: 17 June 2026</p>
      <p className="mt-6 text-base leading-7 text-slate-300">
        This policy describes how {BRAND_NAME} handles information in the iOS, iPadOS, and macOS
        apps published by Iman Suherman.
      </p>

      <div className="mt-10 space-y-10">
        {sections.map((section) => (
          <section key={section.title}>
            <h2 className="text-xl font-semibold text-slate-100">{section.title}</h2>
            {section.paragraphs?.map((paragraph) => (
              <p key={paragraph} className="mt-3 text-sm leading-7 text-slate-400 sm:text-base">
                {paragraph}
              </p>
            ))}
            {section.bullets ? (
              <ul className="mt-3 list-disc space-y-2 pl-5 text-sm leading-7 text-slate-400 sm:text-base">
                {section.bullets.map((item) => (
                  <li key={item}>{item}</li>
                ))}
              </ul>
            ) : null}
            {section.footer ? (
              <p className="mt-3 text-sm leading-7 text-slate-400 sm:text-base">{section.footer}</p>
            ) : null}
          </section>
        ))}
      </div>

      <p className="mt-12 text-sm text-slate-500">
        <Link href="/" className="text-brand-blue transition hover:text-[#3395ff]">
          Back to home
        </Link>
      </p>
    </article>
  );
}
