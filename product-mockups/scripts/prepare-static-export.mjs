// CloudFront serves clean URLs from <route>/index.html. Vinext's trailingSlash
// redirect currently makes prerendering skip non-root routes, so normalize the
// successfully exported files instead of changing its routing configuration.
import { existsSync, mkdirSync, readFileSync, renameSync } from 'node:fs';
import { dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

if (process.env.ZEPHRA_STATIC_EXPORT === '1') {
  const root = fileURLToPath(new URL('../dist/client/', import.meta.url));
  const chapters = JSON.parse(readFileSync(new URL('../app/guide/chapters.json', import.meta.url), 'utf8'));
  const routes = ['guide', ...chapters.map(chapter => `guide/${chapter.slug}`)];
  // Validate everything before moving anything; missing chapters must fail a build.
  for (const file of ['index.html', '404.html', ...routes.map(route => `${route}.html`)]) {
    if (!existsSync(`${root}/${file}`)) throw new Error(`Static export is missing ${file}`);
  }
  for (const route of routes) {
    const destination = `${root}/${route}/index.html`;
    mkdirSync(dirname(destination), { recursive: true });
    renameSync(`${root}/${route}.html`, destination);
  }
  console.log(`Prepared ${routes.length} guide pages for CloudFront.`);
}
