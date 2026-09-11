'use client';
import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { Switch } from '@/components/ui/switch';
import chapters from './chapters.json';

export default function GuideShell({ children }: { children: React.ReactNode }) {
  const [dark, setDark] = useState(true);
  const pathname = usePathname().replace(/\/$/, '');
  const contents = <nav aria-label="Guide chapters">
    <a href="/guide/" aria-current={pathname === '/guide' ? 'page' : undefined}>Guide overview</a>
    {chapters.map((chapter, index) => <a key={chapter.slug} href={`/guide/${chapter.slug}/`}
      aria-current={pathname === `/guide/${chapter.slug}` ? 'page' : undefined}>
      <span className="chapter-number">{String(index + 1).padStart(2, '0')}</span>{chapter.title}
    </a>)}
  </nav>;
  return <div className="safelight guide-shell" data-theme={dark ? 'dark' : 'light'}>
    <a className="skip-link" href="#guide-content">Skip to guide content</a>
    <header className="guide-header">
      <a className="brand" href="/"><span className="brand-mark" aria-hidden="true" />Zephra</a>
      <a href="/guide/" className="guide-home">User guide</a>
      <label className="theme-control" htmlFor="guide-theme"><span>Dark mode</span>
        <Switch id="guide-theme" checked={dark} onCheckedChange={setDark} aria-label="Dark mode" />
      </label>
    </header>
    <div className="guide-layout">
      <aside className="guide-sidebar"><p className="eyebrow">THE ZEPHRA GUIDE</p>{contents}</aside>
      <details className="guide-mobile-nav"><summary>Browse the guide</summary>{contents}</details>
      <main id="guide-content" className="guide-main">{children}</main>
    </div>
    <footer className="guide-footer"><a href="/">Back to Zephra</a><span>© 2026 James Brink.</span>
      <a href="mailto:dev.urandom.io@gmail.com?subject=Zephra%20support">Get help</a>
    </footer>
  </div>;
}
