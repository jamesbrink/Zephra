import chapters from './chapters.json';
import { chapterMetadata } from './guide-metadata';
export const metadata = chapterMetadata({ slug: '', title: 'Create with Zephra', description: 'A friendly guide to making images, editing photos, and generating video with Zephra on your Mac.' });
export default function Page() {
  return <>
    <p className="eyebrow">A LITTLE GUIDANCE. MORE ROOM TO CREATE.</p>
    <h1>Create with Zephra.</h1>
    <p className="guide-lead">Make your first image, give a photo a new direction, or bring a scene to life. Start with what you want to do. You can learn the settings as you go.</p>
    <a className="guide-start" href="/guide/first-image/"><span>New here?</span><h2>Make your first image</h2><p>Install, choose one model, and turn a few words into something you can keep.</p><strong>Start here →</strong></a>
    <h2 className="guide-section-title">What would you like to do?</h2>
    <div className="guide-cards">{chapters.slice(1).map(chapter => <a href={`/guide/${chapter.slug}/`} key={chapter.slug}><h3>{chapter.title}</h3><p>{chapter.description}</p></a>)}</div>
    <p className="guide-edition">For Zephra 0.1.0, including Qwen-Image 2.1, Wan 2.2, and LTX-2.5 with sound. Updated September 23, 2026. <a href="/guide.md">Read as Markdown</a>.</p>
  </>;
}
