import type { Metadata } from "next";
import "./globals.css";
import Script from "next/script";
export const metadata: Metadata = {
  title: "Zephra — Your Mac is the studio",
  description:
    "Generate, edit, upscale, and organize images locally on your Mac. A native image studio for Apple Silicon.",
  icons: {
    icon: [
      { url: "/images/icon-dark.png" },
      { url: "/images/icon-light.png", media: "(prefers-color-scheme: light)" },
      { url: "/images/icon-dark.png", media: "(prefers-color-scheme: dark)" },
    ],
  },
};
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        {children}
        <Script src="/analytics.js" strategy="afterInteractive" />
      </body>
    </html>
  );
}
