import type { Metadata } from "next";
import { Hero } from "@/components/Hero";
import { AppPreview } from "@/components/AppPreview";
import { DashboardShowcase } from "@/components/DashboardShowcase";
import { FeatureShowcase } from "@/components/FeatureShowcase";
import { CtaBanner } from "@/components/CtaBanner";
import { VersionHistoryShowcase } from "@/components/VersionHistoryShowcase";
import { OpenSourceSection } from "@/components/OpenSourceSection";
import { SHARE_IMAGE, SITE_URL } from "@/lib/site";

const homeTitle = "Nucleus — Personal Operating System for macOS";
const homeDescription =
  "Unify Gmail, bills, clipboard intelligence, markdown notes, password vault, and Funky alerts across multiple Google accounts — with a Dashboard that analyses your day, surfaces productivity insights from clipboard activity, and summarizes what needs attention at a glance.";

export const metadata: Metadata = {
  title: homeTitle,
  description: homeDescription,
  openGraph: {
    title: homeTitle,
    description: homeDescription,
    url: SITE_URL,
    images: [
      {
        url: SHARE_IMAGE.path,
        width: SHARE_IMAGE.width,
        height: SHARE_IMAGE.height,
        alt: SHARE_IMAGE.alt,
      },
    ],
  },
  twitter: {
    title: homeTitle,
    description: homeDescription,
    images: [SHARE_IMAGE.path],
  },
};

export default function HomePage() {
  return (
    <>
      <Hero />
      <AppPreview />
      <DashboardShowcase />
      <FeatureShowcase />
      <VersionHistoryShowcase />
      <OpenSourceSection />
      <CtaBanner />
    </>
  );
}
