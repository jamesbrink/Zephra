# Zephra — Safelight

The selected product page supports dark and light appearances through its Dark
mode switch. The earlier website layouts and historical app mockups are removed.

The product copy was checked against the current repository on 2026-09-06; see
`CONTENT-AUDIT.md`. No public download, price, or release date is promised.

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
