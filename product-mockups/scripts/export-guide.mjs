// Keep the Markdown guide and discovery links in sync with the rendered chapters.
import { readFileSync, writeFileSync } from 'node:fs';
const read = path => JSON.parse(readFileSync(new URL(path, import.meta.url), 'utf8'));
const chapters = read('../app/guide/chapters.json');
const origin = 'https://zephra.urandom.io';
let markdown = '# Zephra user guide\n\nBeginner-friendly workflows for Zephra 0.1.0. Updated September 11, 2026.\n\n';
for (const entry of chapters) {
  const chapter = read(`../app/guide/_content/${entry.slug}.json`);
  markdown += `## ${chapter.title}\n\n${chapter.description}\n\n[Read this chapter](${origin}/guide/${chapter.slug}/)\n\n`;
  for (const section of chapter.sections) {
    markdown += `### ${section.title}\n\n`;
    for (const paragraph of section.paragraphs) markdown += `${paragraph}\n\n`;
    for (const [index, step] of (section.steps ?? []).entries()) markdown += `${index + 1}. ${step}\n`;
    if (section.steps) markdown += '\n';
    for (const item of section.items ?? []) markdown += `- ${item}\n`;
    if (section.items) markdown += '\n';
    if (section.prompt) markdown += `Try this prompt:\n\n> ${section.prompt}\n\n`;
    if (section.note) markdown += `${section.note}\n\n`;
    for (const link of section.links ?? []) markdown += `- [${link.label}](${link.url.startsWith('/') ? origin + link.url : link.url})\n`;
    if (section.links) markdown += '\n';
  }
}
writeFileSync(new URL('../public/guide.md', import.meta.url), markdown.trimEnd() + '\n');
const routes = ['/', '/guide/', ...chapters.map(chapter => `/guide/${chapter.slug}/`)];
writeFileSync(new URL('../public/sitemap.xml', import.meta.url), `<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n${routes.map(route => `  <url><loc>${origin}${route}</loc></url>`).join('\n')}\n</urlset>\n`);
const llmsFile = new URL('../public/llms.txt', import.meta.url);
const llms = readFileSync(llmsFile, 'utf8').split('\n## User guide')[0].trimEnd();
writeFileSync(llmsFile, llms + `\n\n## User guide\n\n- [Guide overview](${origin}/guide/): Choose a workflow.\n- [Complete guide in Markdown](${origin}/guide.md): All chapters in a single document.\n` + chapters.map(chapter => `- [${chapter.title}](${origin}/guide/${chapter.slug}/): ${chapter.description}`).join('\n') + '\n');
