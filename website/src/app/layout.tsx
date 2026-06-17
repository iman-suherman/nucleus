import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { BRAND_NAME, BRAND_TAGLINE } from "@/lib/brand";
import { SHARE_IMAGE, SITE_URL } from "@/lib/site";

const inter = Inter({ subsets: ["latin"] });

const defaultDescription = `${BRAND_TAGLINE}. Unify Gmail, Google Chat, Calendar, bills, notes, passwords, clipboard intelligence, and Funky alerts across multiple Google accounts — with a Dashboard that greets you, shows today's weather, and summarizes your workspace at a glance.`;

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: BRAND_NAME,
    template: `%s · ${BRAND_NAME}`,
  },
  description: defaultDescription,
  icons: {
    icon: SHARE_IMAGE.path,
    apple: SHARE_IMAGE.path,
  },
  openGraph: {
    type: "website",
    siteName: BRAND_NAME,
    title: BRAND_NAME,
    description: defaultDescription,
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
    card: "summary",
    title: BRAND_NAME,
    description: defaultDescription,
    images: [SHARE_IMAGE.path],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.className} bg-[#0a0a0b] text-slate-100 antialiased`}>
        <Header />
        <main>{children}</main>
        <Footer />
      </body>
    </html>
  );
}
