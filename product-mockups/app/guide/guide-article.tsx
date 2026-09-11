import chapters from './chapters.json';
type Section = { id: string; title: string; paragraphs: string[]; steps?: string[];
  items?: string[]; prompt?: string; note?: string; links?: { label: string; url: string }[] };
type Chapter = { slug: string; title: string; description: string; sections: Section[] };
export default function GuideArticle({ chapter }: { chapter: Chapter }) {
  const index = chapters.findIndex(item => item.slug === chapter.slug);
  const next = chapters[index + 1];
  const previous = chapters[index - 1];
  return <article className="guide-article">
    <p className="guide-breadcrumb"><a href="/guide/">User guide</a> / {String(index + 1).padStart(2, '0')}</p>
    <h1>{chapter.title}</h1><p className="guide-lead">{chapter.description}</p>
    <nav className="guide-toc" aria-label="On this page"><strong>On this page</strong>
      {chapter.sections.map(section => <a key={section.id} href={`#${section.id}`}>{section.title}</a>)}
    </nav>
    {chapter.sections.map(section => <section key={section.id} id={section.id}>
      <h2>{section.title}</h2>
      {section.paragraphs.map(text => <p key={text}>{text}</p>)}
      {section.steps && <ol className="guide-steps">{section.steps.map(step => <li key={step}>{step}</li>)}</ol>}
      {section.items && <ul>{section.items.map(item => <li key={item}>{item}</li>)}</ul>}
      {section.prompt && <div className="guide-prompt"><span>Try this prompt</span><p>{section.prompt}</p></div>}
      {section.note && <aside className="guide-callout"><p>{section.note}</p></aside>}
      {section.links && <ul className="guide-links">{section.links.map(link => <li key={link.url}><a href={link.url}>{link.label}</a></li>)}</ul>}
    </section>)}
    <nav className="guide-pagination" aria-label="Continue reading">
      <a href={previous ? `/guide/${previous.slug}/` : '/guide/'}><span>Previous</span>{previous?.title ?? 'Guide overview'}</a>
      {next && <a href={`/guide/${next.slug}/`}><span>Next</span>{next.title}</a>}
    </nav>
  </article>;
}
