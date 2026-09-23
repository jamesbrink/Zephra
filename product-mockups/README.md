# Zephra — Safelight

The selected product page supports dark and light appearances through its Dark
mode switch. The earlier website layouts and historical app mockups are removed.

The product copy was checked against the current repository on 2026-09-23; see
`CONTENT-AUDIT.md`. The page links the verified notarized DMG recorded in `app/release.json`.

## Images and identity

- `public/images/app.png`: genuine Zephra window capture on 2026-09-06, showing the
  finished copper robot image in the maximized window. No simulated generation or altered
  app interface. The visible timing is that image's recorded run, not a benchmark
  or performance promise.
- `public/images/robot.png`: FLUX.2 klein 4B (4-bit) output generated through the real
  Zephra app on 2026-09-06, 1024×1024, 4 steps, seed 4528588147396822612.
  Both original outputs and generation metadata are in `../design/website/`.
  Its caption is an editorial description, not a verbatim prompt.
- The approved Zephyr originals, light/dark concept board, reusable transparent
  masters, and prompt provenance live in `../design/branding/zephyr/`.
  `make icon` at the repository root exports the app icons and website assets.
  The website uses the flat mark as a theme-colored mask; favicons follow system
  appearance. The app and DMG retain the same selected identity.

Run `npm run dev` for development and `npm run build` for the Sites build.

## Deployment workflow

Iterations and modifications are previewed on ChatGPT Sites first. **Deploy to
production** means AWS at https://zephra.urandom.io. Both use this same source.

- `npm ci` in this directory installs the pinned dependencies (Node 22+).
- `make website-build` from the repository root exports static HTML and browser
  assets to `product-mockups/dist/client` without the Sites runtime.
- `make deploy-production` builds, uploads to `zephra-site-urandom-io`, invalidates
  CloudFront `ETNI7JSPHMJRF`, waits, and verifies every published file by SHA-256.
  Locally it uses `WEBSITE_PROFILE=dev.urandom.io`; use `WEBSITE_PROFILE=` for OIDC
  or environment credentials. Old hashed chunks are retained for existing tabs.
- A push to `main` that changes `product-mockups/**` or the website deployment
  scripts runs the **Deploy production website** GitHub Actions workflow. It
  invokes the same target using the existing OIDC role. The workflow can also
  be started manually.
- Ordinary `npm run build` retains the ChatGPT Sites Worker build and publication
  flow. Never upload its server output to S3.

`make publish-release VERSION=0.1.0 BUILD_NUMBER=<unique-number>` builds and
notarizes on macOS, uploads the DMG, downloads it again, verifies it, and updates
`app/release.json`. For an already notarized local build, use `make release-upload`.
Release keys are immutable; use a new build number for each publication. Deploy
the resulting page update to ChatGPT Sites first, then AWS production.

Signed, notarized app downloads belong in the separate assets bucket under
`releases/`; the website bucket contains only the site.

## Marketing assets and product guidance

The hero uses 480, 768, and 1024 px WebP derivatives of the preserved `robot.png`.
Regenerate with `cwebp -q 82 -resize <width> <width> public/images/robot.png -o
public/images/robot-<width>.webp`. No new artwork or generation metadata is added.

The sharing card (`public/og.png`) uses the approved identity and app capture as
imagegen references; its original and brief live in `../design/website/social/`.
Open Graph and X metadata use the canonical AWS image URL.

`app/getting-started.tsx` holds first-launch guidance, compatibility and model disk
sizes, and concise release highlights. Check figures against `ModelCatalog*.swift`
when models change. Keep `public/index.md` consistent and review release highlights
when shipping; the displayed version/build track `app/release.json` automatically.
Qwen-Image 2.1 replaced Qwen-Image-2512: update its model name, research license,
ordered reference-picture limit, Guidance and negative-prompt advice across the
product page and guide together. The current catalog defaults are 40 Steps and
Guidance 1; Guidance above 1 has an effect only with a nonempty negative prompt.
Support goes to the owner-provided `dev.urandom.io@gmail.com` address.

### User guide

`app/guide/` contains the guide shell and nine static chapter routes. Chapter text
lives in `_content/*.json`; the navigation index is `chapters.json`. Keep labels and
capabilities grounded in the app, not generic upstream tutorials. After editing
chapters, run `node scripts/export-guide.mjs` from this directory to regenerate
`public/guide.md`, `sitemap.xml`, and the guide links in `llms.txt`.

`npm run build` regenerates guide discovery files. For AWS, the post-build script
`prepare-static-export.mjs` validates all guide routes and moves the exported HTML
into directories because the CloudFront viewer function
maps `/guide/topic/` to `/guide/topic/index.html`. Each chapter has its own canonical
URL, page title, description, and matching social metadata.
