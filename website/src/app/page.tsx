import type { Metadata } from "next";
import { Hero } from "@/components/Hero";
import { AppPreview } from "@/components/AppPreview";
import { WorkspacesShowcase } from "@/components/WorkspacesShowcase";
import { DashboardShowcase } from "@/components/DashboardShowcase";
import { FeatureShowcase } from "@/components/FeatureShowcase";
import { CtaBanner } from "@/components/CtaBanner";
import { VersionHistoryShowcase } from "@/components/VersionHistoryShowcase";
import { OpenSourceSection } from "@/components/OpenSourceSection";
import { SHARE_IMAGE, SITE_URL } from "@/lib/site";

const homeTitle = "Nucleus — Personal Workspace";
const homeDescription =
  "Native macOS workspace for Gmail, bills, clipboard, notes, passwords, Apple Music, and embedded tmux — with a Dashboard that analyses your day, breaking news alerts, Nucleus AI, and sync through Nucleus Cloud or iCloud.";

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
      <WorkspacesShowcase />
      <DashboardShowcase />
      <FeatureShowcase />
      <VersionHistoryShowcase />
      <OpenSourceSection />
      <CtaBanner />
    </>
  );
}
