import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";
import "./globals.css";

const outfit = localFont({
  src: "./fonts/outfit-latin.woff2",
  variable: "--font-outfit",
  display: "swap",
  weight: "100 900",
});

export const metadata: Metadata = {
  metadataBase: new URL(process.env.KEEP_SITE_URL || "http://localhost:3000"),
  title: "Keep | Make room for focus",
  description: "A free native Mac workspace for focus timers, Timesheet, Calendar, habits, goals, a music player, your own wallpapers, and exports.",
  applicationName: "Keep",
  openGraph: {
    title: "Keep | Make room for focus",
    description: "Focus, review your week, build habits, and export your progress. Every Keep feature is free.",
    type: "website",
    images: [{ url: "/screenshots/focus-light.webp", width: 1920, height: 1440, alt: "Keep’s native Mac focus workspace" }],
  },
  twitter: { card: "summary_large_image" },
};

export const viewport: Viewport = {
  themeColor: "#faf8f4",
  colorScheme: "light",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en" className={outfit.variable}><body>{children}</body></html>;
}
