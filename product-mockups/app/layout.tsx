import type { Metadata } from 'next';
import './globals.css';
import Script from 'next/script';
export const metadata: Metadata = {
  title: 'Zephra — Local AI Image & Video Generation for Mac',
  description:
    'Create AI images and videos locally on your Mac. Explore Wan 2.2 and LTX-2.5 with sound, plus image editing and upscaling. Built for Apple Silicon.',
  metadataBase: new URL('https://zephra.urandom.io'),
  alternates: { canonical: '/', types: { 'text/markdown': '/index.md' } },
  openGraph: {
    type: 'website',
    url: '/',
    siteName: 'Zephra',
    images: [
      {
        url: 'https://zephra.urandom.io/og.png',
        width: 1200,
        height: 630,
        alt: 'Zephra — Your Mac is the studio. Local AI images & video.',
      },
    ],
    title: 'Zephra — Your Mac is the studio',
    description:
      'Create AI images and short videos locally on Apple Silicon. Now with Wan 2.2 and LTX-2.5 video with sound.',
  },
  twitter: {
    card: 'summary_large_image',
    images: ['https://zephra.urandom.io/og.png'],
    title: 'Zephra — AI Images & Video for Mac',
    description:
      'Generate images, animate pictures, and create short videos locally on Apple Silicon.',
  },
  icons: {
    icon: [
      { url: '/images/icon-dark.png' },
      { url: '/images/icon-light.png', media: '(prefers-color-scheme: light)' },
      { url: '/images/icon-dark.png', media: '(prefers-color-scheme: dark)' },
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
      <head>
        <link rel="describedby" href="/llms.txt" type="text/plain" />
      </head>
      <body>
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              '@context': 'https://schema.org',
              '@type': 'WebSite',
              name: 'Zephra',
              url: 'https://zephra.urandom.io/',
              description:
                'Local AI image and video generation for Apple Silicon Macs.',
            }),
          }}
        />
        {children}
        <Script src="/analytics.js" strategy="afterInteractive" />
      </body>
    </html>
  );
}
