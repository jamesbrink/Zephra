# Zephra — Safelight

The selected product page supports dark and light appearances through its Dark
mode switch. The earlier website layouts and historical app mockups are removed.

The product copy was checked against the current repository on 2026-09-06; see
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
- The manual **Deploy production website** GitHub Actions workflow invokes that
  same target using the existing OIDC role. Pushes do not deploy automatically.
- Ordinary `npm run build` retains the ChatGPT Sites Worker build and publication
  flow. Never upload its server output to S3.

`make publish-release VERSION=0.1.0 BUILD_NUMBER=<unique-number>` builds and
notarizes on macOS, uploads the DMG, downloads it again, verifies it, and updates
`app/release.json`. For an already notarized local build, use `make release-upload`.
Release keys are immutable; use a new build number for each publication. Deploy
the resulting page update to ChatGPT Sites first, then AWS production.

Signed, notarized app downloads belong in the separate assets bucket under
`releases/`; the website bucket contains only the site.
