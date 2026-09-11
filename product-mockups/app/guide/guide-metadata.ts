import type { Metadata } from 'next';
export function chapterMetadata(chapter: { slug: string; title: string; description: string }): Metadata {
  const url = chapter.slug ? `/guide/${chapter.slug}/` : '/guide/';
  const title = `${chapter.title} — Zephra User Guide`;
  return {
    title, description: chapter.description,
    alternates: { canonical: url, types: { 'text/markdown': '/guide.md' } },
    openGraph: { title, description: chapter.description, url, type: 'article', siteName: 'Zephra',
      images: [{ url: 'https://zephra.urandom.io/og.png', width: 1200, height: 630 }] },
    twitter: { card: 'summary_large_image', title, description: chapter.description,
      images: ['https://zephra.urandom.io/og.png'] },
  };
}
