# Library and gallery mock

The reference design for the three-column Zephra window: a full-height sidebar
(search, scope chips, queue, sources, today's images), a Canvas/Library pane
toggle in the toolbar, and an inspector beside the Library grid.

- `library-and-gallery.html` — two 1440 x 900 frames. Frame 3a is the Canvas
  pane, frame 3b the Library pane. Open it in a browser; it is self-contained.
- `img/` — placeholder images the frames use.
- `uploads/current-app-canvas.png` — the app as it was before the redesign.
- `uploads/sidebar-detail.png` — a close-up of the sidebar's search, chips,
  queue, and day-grouped history.

The mock is a guide, not a pixel target. Where it names a colour, the app uses
the matching system material or the `Safelight` and `CanvasBackground` colour
sets so that light mode comes for free.
