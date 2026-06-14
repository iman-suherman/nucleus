import type { Metadata } from "next";
import { Hero } from "@/components/Hero";
import { FeatureShowcase } from "@/components/FeatureShowcase";
import { CtaBanner } from "@/components/CtaBanner";
import { VersionHistoryShowcase } from "@/components/VersionHistoryShowcase";
import { OpenSourceSection } from "@/components/OpenSourceSection";

export const metadata: Metadata = {
  title: "Nucleus — Personal Operating System for macOS",
  description:
    "Unify Gmail, Google Calendar, clipboard intelligence, and markdown notes across multiple Google accounts.",
};

export default function HomePage() {
  return (
    <>
      <Hero />
      <FeatureShowcase />
      <VersionHistoryShowcase />
      <OpenSourceSection />
      <CtaBanner />
    </>
  );
}
