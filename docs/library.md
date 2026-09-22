# The library

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

## The library

`~/Pictures/Zephra` is the default library. Settings > General can select another
folder and optionally migrate images, sources, albums, and Recently Deleted.
`AppSettings.imageLibrary()` supplies the same persisted root to the store and index.
`GenerationStore.changeImageDirectory` gates work and drains writes while
`LibraryIndex` pauses mutations and scans; only a successful change is persisted.
Migration moves owned PNGs and manifests without overwriting destination files.
Keep in Place switches the visible library and leaves the old folder untouched.

The selected folder is the library. There is no database: the folder is the
truth, and everything the app knows about an image is inside that image's own
PNG. Move a file, rename it, or copy it to another Mac and its prompt, its
favourite, and its tags go with it. `ZephraEngine/Library/` is that folder read
as an index, and it is Foundation only, so `make test` covers all of it.

- Two owners, and the reference owner may hold ten chunks.
  `zephra:generation` is provenance —
  `GenerationRecord`, written once when the image is saved, never edited. A PNG
  without it was not made here and is skipped, so a folder can hold more
  pictures than the library lists. `zephra:library` is `LibraryAnnotation`: favourite,
  tags, albums — the things a person changes afterwards. Anything mutable goes
  in the second chunk; nothing rewrites the first. The record also carries the
  `batchID` of the press of Generate that made the image, so a run survives the
  session that made it: the canvas sidebar's timeline groups by it after a
  relaunch, and falls back to adjacency for files written before the field
  existed.
- **The reference pictures an edit was made from are numbered from the second.**
  The first stays in `zephra:reference`, unsuffixed — there is deliberately no
  `.1` — and the rest go in `zephra:reference.2` through `zephra:reference.10`,
  base64, one picture a chunk. Ten is `ReferenceLimits.maximumPictures` for
  exactly this reason: the keywords stop there.
  `GenerationRecord.referenceByteCounts` and `referenceOrigins` are written
  **only when there is more than one picture**, so a one-picture edit's file is
  byte for byte what it always was and every PNG written before several were
  possible reads the same as it did; a reader without those fields falls back to
  `[referenceBytes]` and `[referenceOrigin]`. Reading stops at the first chunk
  that is missing or whose bytes are not the length the record claims, so a file
  whose fourth chunk went bad is an edit of three pictures rather than of none.
  An upscale copies the reference chunks across verbatim, which is what keeps
  the counts matching on the child.
- `PNGHeader` reads a file's header in one seeking walk and answers three
  questions from it: its text, its size, and whether its pixels carry alpha. A
  chunk's body is read when it is under 64 KiB and **seeked past** otherwise,
  and the walk stops at the first IDAT. That replaced a prefix-growing read of
  64 KiB, then 256 KiB, then a megabyte, which a picture carrying a 1024-pixel
  reference defeated at all three sizes — a reference chunk is about 1.4 MB of
  base64 — so every edit in the library was falling back to `Data(contentsOf:)`,
  the whole file, on every scan that re-read it. A grid of two thousand images
  is two thousand small reads, not two thousand full decodes and not two
  thousand whole files. `PNGTextChunks.read(fromHeaderOf:)` is that walk's text
  under its old signature, so no caller moved.
  `PNGTextChunks+Replacing` writes one back by splicing before IDAT and
  dropping the same keyword, so repeated writes do not grow the file.
- **Transparency comes from the file, not from a record.** `PNGHeader.hasAlpha`
  is the IHDR colour type — 4 or 6 — or the presence of a `tRNS` chunk, which is
  how a palette picture somebody imported carries it. The scan sets it on
  `LibraryItem.hasAlpha` beside the provenance, in the same read, and
  `ImageFacts.isTransparent` is the inspector's one "Transparent" row, drawn
  only when it is true. A `GenerationRecord` flag was considered and rejected:
  it would be wrong for an imported file, wrong for everything written before
  the field existed, and a second place to keep true. What is *drawn* asks the
  decoded picture instead — `CGImage.hasTransparency`, free, already in hand
  wherever a bitmap is — and `DrawnPicture` is what carries that answer out of
  both Mac caches so no view decodes anything in `body`.
- **A picture Zephra writes may be RGBA.** Qwen-Image 2.1 decodes four channels,
  so `PixelBuffer` packs straight alpha with `CGImageAlphaInfo.last` rather than
  premultiplying: that channel came out of the autoencoder in −1 to 1 like the
  other three, and premultiplying would lose colour in every near-transparent
  pixel. Wherever such a picture is drawn, `TransparencyGround` goes behind it —
  the canvas, the live preview, a library cell, the viewer, a reference tile,
  and the phone's canvas, grid, viewer and well — and **only** behind one that
  has alpha, since a checkerboard under every opaque picture would be a change
  to every model that came before this one. The 44-point wall squares keep their
  plain fill: at that size a checkerboard is noise.
- **Where a picture leaves as a JPEG it is composited first**, because a JPEG
  has no alpha and the alternative is black. `CheckerboardComposite`
  (`ZephraLinkHost`) is that one rule, used by `CompanionThumbnails` for the
  phone's grid and by the link's `PreviewEncoder` for a live frame; it returns
  an opaque picture untouched and draws the rest over the same checkerboard the
  interface draws, rows flipped so the light square lands in the picture's **top
  left** whichever way the bitmap context counts. The two greys are the light
  appearance's on purpose: what a JPEG carries is fixed when it is encoded, and
  the Mac cannot know which appearance the phone reading it will be in.
- `LibraryScan` fingerprints the directory from one `contentsOfDirectory` and
  re-reads only the paths whose (mtime, size) moved. `LibraryFolderWatch` is a
  `DispatchSource` on the directory, debounced, and re-opens the fd when the
  folder is renamed away and back.
- `LibraryIndex` (`@MainActor @Observable`) is what the UI observes, split by
  concern the way `GenerationStore` is. Mutations take a set of ids, apply
  optimistically, queue onto one serial chain, and revert by re-reading the one
  file that failed — unless a newer change for that file is still `pending`, in
  which case the older write neither overwrites what is on screen nor reverts
  nor reports: the newer write is about to land and speaks for itself.
  `LibraryQuery` holds the scope, the text, and the sort, and
  `sections` are recomputed when it changes — the view never filters.
- Undo. Every edit to the annotation chunk — a favourite, the tags, album
  membership — and every album made, renamed or deleted registers its inverse
  on `LibraryIndex.undoManager`, an optional `UndoManager` (Foundation, so the
  engine stays Foundation-only) that the app sets from the window's own through
  `LibraryUndoRegistration` in `Sources/Zephra/Support/`; nil, which a test or
  the preview index leaves it at, records nothing. The index registers rather
  than the call sites because it is the one thing that still knows every
  touched image's previous annotation, and it registers only what changed, so a
  favourite set on a picture already favourite leaves no "Undo" that does
  nothing. `LibraryIndex+Undo` is the whole of it: putting annotations back is
  an ordinary `annotate`, which records the redo on its way. The menu names
  are "Favorite", "Tag", "Album", "New Album", "Rename Album" and "Delete
  Album"; deleting an album is one entry covering the album and its members'
  memberships, and each inverse carries its name through, so "Undo New Album"
  redoes as "Redo New Album" rather than as the deletion it ran. Changing the
  images folder empties the stack, since every entry names files no longer
  indexed. Recently Deleted stays out on purpose: a delete already has thirty
  days of Put Back. No `CommandGroup` replaces `.undoRedo`, which is what lets
  the standard Edit items reach the window's manager whenever a text field is
  not first responder. `LibraryUndoTests` pins all of it.
- Deleting moves the file to `Recently Deleted/` with a `deletedAt` and an
  `origin` (the root or `Sources/`) in that folder's own manifest, and a scan
  purges anything older than thirty days (`ImageLibrary+Purge`). Both kinds of
  picture are deleted into it and listed there, a generated one by its record
  and an imported one by its `SourceRecord`; Put Back returns each to the folder
  it came from — the manifest's word, else the file's own header for a manifest
  written before origins were recorded. The purge rechecks that a file is ours
  for every candidate, entry or not, since a name can be reused by somebody
  else's picture, and drops the stale entry rather than the picture; Delete
  Immediately forgets the entry too, so a later file under that name gets its
  own thirty days. Nothing is unlinked on the user's behalf before then.
- A clip is its poster. LTX-2.5 hands back `GeneratedMedia.video`: the MP4 and
  its first frame as a PNG, and the library indexes the PNG exactly as it
  indexes a picture — the record inside it carries `frameCount` and `frameRate`,
  which is all that says it is a clip — with the MP4 beside it under the same
  stem. `VideoSidecar` is the one rule for where the MP4 lives; the record never
  names the file, because Put Back may rename both. Everything that moves a PNG
  moves the pair: `ImageLibrary.write` (the MP4 first, so a scan never lists a
  clip whose file is not there), `moveToRecentlyDeleted`,
  `restoreFromRecentlyDeleted` (stepping both around a collision), `discard`
  (which the purge and Delete Immediately go through), and the migration's
  inventory. `LibraryItem.videoURL` and `videoSeconds` answer from the record;
  `LibraryItem.exportURL` in the app target is the clip for a clip and the
  picture otherwise, and Export, Copy, Share, drag and Reveal all go through it,
  in the library and on the canvas alike (`ImageExport.savedFile`, and a
  `Transferable` that exports an MP4 for a saved clip and a PNG otherwise). Two
  things a clip's export does not do yet: the record, the favourite, the tags
  and the albums stay in the poster and do not leave with the MP4, and Copy puts
  the file alone on the pasteboard, with no pixels and no promised TIFF
  (`ROADMAP.md`). Upscale is offered for pictures only, at every entry point.
  `ImageLibraryVideoTests` pins the pairs. A clip made by Extend Clip is a new
  pair whose poster is the source's first frame and whose record carries
  `continuedFrom` (the source's file name) and `contextFrames`; `frameCount`
  is the whole joined clip. `ImageLibrary.sourceClip(named:)` is how the join
  finds the source, in the folder or in Recently Deleted.
- `LibrarySelection` holds what is chosen; `LibraryCursor` is the pure
  arithmetic of moving through a grid, so keyboard navigation is tested without
  a window. `ImageFacts` formats the rows the inspector shows, the clip's Length
  among them ("2.0 s, 49 frames at 24 fps", and ", with sound" after it when
  the record says the file carries a track). Every span of seconds on screen — the countdown in the
  window subtitle and the running-run inspector, Elapsed, how long a run took, a
  clip's length in the inspector, the capsule and the badge — is a
  `DurationLabel` (`ZephraCore`): "45 s", "1 min 20 s", "12 min", "1 hr 5 min",
  with a decimal under a minute only where a fraction is a real answer (a clip's
  0.4 s). A per-step pace is a rate, not a span, and keeps its seconds
  ("7.0 s/step").
- Export copies the file, never the bytes in memory, once a picture has one:
  the file is where the favourite, the tags, the albums and the upscale record
  were written, and `ImageExport.exportData(for:)` reads it for Export, Copy
  and a drag alike, embedding the record into the session's bytes only before
  the save has landed. Every copy goes through `ExportPlan`
  (`Sources/Zephra/Support/`), a pure plan of copies, collisions and files
  that are already the file there, so a file is never copied onto itself — a
  save onto the source is a silent no-op — and a batch that would land on
  other files asks Keep Both (numbered the way the Finder does, the default),
  Replace, or Cancel through `ExportCollisionPrompt`. `copyReplacing` writes
  into a hidden sibling in the destination's folder and renames it into place
  (`replaceItemAt` over an existing file, a move otherwise), so the destination
  is whole or absent at every instant and the source is only ever read;
  remove-then-copy is what used to delete an original exported into its own
  folder. Failures are collected into one alert. `ExportPlanTests`,
  `ImageExportReplaceTests` and `ExportDataTests` in `Tests/ZephraTests` pin
  all of it, the middle one on the real filesystem under `Scratch`.
- Copy puts one picture on the pasteboard in every form a paste asks for:
  the file's URL, so the Finder pastes the file; the PNG bytes as they are;
  and a TIFF that is promised rather than written — `PasteboardImage` is an
  `NSPasteboardItemDataProvider` that makes the TIFF only when something asks
  for that type, since four megapixels uncompressed is tens of megabytes
  nobody may ever paste. Several files go on as URLs alone. Plain ⌘C over
  the grid is `LibraryGrid`'s `onCopyCommand`, the responder-chain hook,
  handing out `NSItemProvider`s for the selected files, so the Edit menu's
  own Copy reaches the grid only while the grid has the keyboard and still
  means the text in a field otherwise; ⇧⌘C stays the named "Copy Image".
  Share — the inspector's button, the context menu, and File > Share… — hands
  the same files to the system: `ShareLink` where there is a view to anchor
  on, and `SharePicker` (an `NSSharingServicePicker` over the key window's
  content view) for the menu item, which resolves through `CommandTarget`
  and is greyed out for a canvas picture that has no file yet.
  `PasteboardImageTests` pins the three forms on a private pasteboard.
