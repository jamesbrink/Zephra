import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  title: 'Zephra — Your Mac is the studio',
  description:
    'Generate, edit, upscale, and organize images locally on your Mac. A native image studio for Apple Silicon.',
  icons: { icon: '/images/icon.png' },
};
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
