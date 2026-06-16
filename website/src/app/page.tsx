import type { Metadata } from "next";
import { Hero } from "@/components/Hero";
import { AppPreview } from "@/components/AppPreview";
import { FeatureShowcase } from "@/components/FeatureShowcase";
import { CtaBanner } from "@/components/CtaBanner";
import { VersionHistoryShowcase } from "@/components/VersionHistoryShowcase";
import { OpenSourceSection } from "@/components/OpenSourceSection";

export const metadata: Metadata = {
  title: "Nucleus — Personal Operating System for macOS",
  description:
    "Unify Gmail, Google Chat, Calendar, bills, clipboard intelligence, markdown notes, and Funky alerts across multiple Google accounts — with a Dashboard that summarizes your workspace at a glance.",
};

export default function HomePage() {
  return (
    <>
      <Hero />
      <AppPreview />
      <FeatureShowcase />
      <VersionHistoryShowcase />
      <OpenSourceSection />
      <CtaBanner />
    </>
  );
}
