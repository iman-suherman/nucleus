import type { Metadata } from "next";
import { Inter } from "next/font/google";
import "./globals.css";
import { Header } from "@/components/Header";
import { Footer } from "@/components/Footer";
import { BRAND_NAME, BRAND_TAGLINE } from "@/lib/brand";

const inter = Inter({ subsets: ["latin"] });

export const metadata: Metadata = {
  title: BRAND_NAME,
  description: `${BRAND_TAGLINE}. Unify Gmail, Google Calendar, notes, and clipboard intelligence across multiple Google accounts.`,
  icons: {
    icon: "/app-icon.png",
    apple: "/app-icon.png",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body className={`${inter.className} bg-brand-navy text-slate-100 antialiased`}>
        <Header />
        <main>{children}</main>
        <Footer />
      </body>
    </html>
  );
}
