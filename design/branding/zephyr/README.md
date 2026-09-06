# Zephyr identity

The flowing copper Z is the selected direction from `concept-light-dark.png`.
These 1254×1254 PNG masters were isolated using built-in image generation:

- `icon-dark.png`: charcoal tile and sculptural gold Z; canonical macOS icon.
- `icon-light.png`: ivory tile and copper Z; light website favicon.
- `mark.png`: clean, flat copper emblem with transparency. The website uses its
  alpha as a CSS mask, colored by the page theme, so light and dark share geometry.

`make icon` resizes these sources into all ten macOS app-icon slots plus the
website's 256-pixel icons and mark. Resizing uses CoreGraphics and ImageIO; it
preserves alpha and writes sRGB PNGs without redrawing the artwork.

`create-dmg.sh` takes `AppIcon.icns` from the built app for both the mounted-volume
icon and the DMG file's custom icon, before signing. `verify-dmg.sh` compares the
mounted icon to the app and checks the volume custom-icon flag. The mounted
volume branding is inside the image and survives download. Finder's custom icon
on the outer DMG file is filesystem metadata, so a service that strips resource
forks can remove it without changing the installer or its volume branding.

`PROMPTS.json` records generation and rejected edits. The original light master
has faint isolated alpha pixels outside its tile; subsequent image-generation
cleanup attempts produced opaque checkerboards and were rejected. The shipped
256-pixel favicon has been visually inspected; no checkerboard outputs are used.
