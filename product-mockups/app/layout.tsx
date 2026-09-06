import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  title: 'Zephra — Product page concepts',
  description:
    'Explore three directions for Zephra, a native macOS app for local image generation on Apple Silicon.',
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
