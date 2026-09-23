# The app target's shape

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

## The app target's shape

The app is one window — a `Window("Zephra", id: "main")` scene, not a
`WindowGroup` — beside Settings and the two windows About leads to (`AboutScenes`,
below). Everything a window would own (`WorkspaceSelection`,
the caches, the canvas's `current`) is app-wide state built once in `ZephraApp`, so
a second window would only mirror the first; ⌘W closes it and a click on the Dock
icon brings it back, with the Window menu listing it by itself, and
`.defaultLaunchBehavior(.presented)` opens it on every launch, so a session that quit
with the window closed does not come back with none. Per-window state is a ROADMAP
item. It is one process too: `Support/SingleInstance`, from `AppLifecycle`'s
`applicationWillFinishLaunching`, brings a copy already running forward and exits
before a window is up. The system launches an app by bundle identifier when a
notification is clicked and takes whichever copy LaunchServices has registered,
which beside a `make run` build is often the Debug one, and two Zephras over one
library would write over each other. A launch that owns neither folder is exempt —
the `ZEPHRA_PREVIEW_STATE` screenshot builds and the app-hosted tests, which run
beside a real one on purpose, and a `ZEPHRA_FRESH_START` one, which has a models
folder, a library and a preferences domain of its own; `SingleInstanceTests` pins
the rule. `FreshStart` (`Support/`) is that launch: `AppSettings.store` is the one
`UserDefaults` every preference is read and written through, `UserDefaults.standard`
ordinarily and a throwaway suite under a fresh start, handed to the views by
`.defaultAppStorage` at the root, and the two folder defaults answer with the fresh
directory's `Models` and `Images` in place of Application Support and
`~/Pictures/Zephra`. The Hugging Face cache is deliberately not redirected: it is a
read-only fallback a real new Mac may equally have. `make run-fresh` asks for it.

Six directories, by what a file is rather than what screen it is on:

- `Style/` — the chrome. The tokens themselves are one package up, in
  `Packages/ZephraStyle` (SwiftUI and `ZephraCore`, macOS and iOS), because the
  companion app has to be drawn from the same numbers rather than from numbers
  that look like them; what stays in this directory is the chrome that is
  AppKit-bound or names an app type. In the package: `ZephraChrome`'s radii,
  hairlines and heights
  (`fieldRadius`, `fieldHeight`, `barHeight` beside the radii), the colours
  laid over things in `ZephraChrome+Washes` (`badgeForeground` and
  `badgeBackdrop` for a glyph on a picture, `safelightWash` and
  `safelightTint` for the run's surfaces, `hoverWash` over a wall square under
  the pointer, `warningWash` and `warningStroke`
  for `ChromePanel`'s warning, `wellFill`, `wellFillHovered` and
  `wellFillTargeted` for the reference well's empty drop target and
  `wellDash` for its dashed hairline (`ReferencePlaceholder`), `captionShadowOpacity`),
  the palette's colour sets in `Color+Palette` read from the package's own
  bundle, and `Chip`, `ModelDot`, `UpscaleBadge` and `VideoBadge`, which are
  nothing but those numbers. Here: `ChromePanel`,
  `SectionHeader`, `CountBadge`, `KeyValueRow`, `WrappingHStack`;
  `FactsRow` and `FactsTable`, the one line and the one column every inspector's
  facts are drawn from; `SearchFieldChrome`, the modifier that dresses the
  sidebar's search and the reference picker's alike; and `MenuChevron`, the
  inline chevron a capsule menu's title ends with (a `Menu` reads its label the
  way `Label` does, so a chevron drawn as a view lands in front of the title or
  nowhere, and `.menuIndicator` draws nothing under `.accessoryBar` outside a
  toolbar). A view that reaches for a literal radius or a raw colour belongs
  here instead. Safelight amber means "only while the model works" and appears
  nowhere else. The radii step down by what a thing is: 16 for the capsule, 10
  for the picture in the reference well, 8 for a card or a thumbnail, 6 for a
  field, 5 for a square on the sidebar's wall, so a card reads as a thing to
  act on and a square as a thing to look at.
- `Workspace/` — which pane is up, which query the library is showing, whether
  the inspector is open, and the labels those enums draw themselves with.
  `WorkspaceSelection` is one `@Observable`, injected by the composition root
  and persisted through `AppSettings`. `reveal(_ item:)` is how something
  outside the window asks for one picture to be shown — a click on its
  notification, and nothing else so far. It takes the item rather than a name
  because the hard part is the query: a person who walked away with Favorites
  up, or with something typed in the search field, comes back to a grid that
  does not list what they clicked on, and a selection nothing shows is a click
  that did nothing. So `LibraryQuery.matches` is asked, and a query that
  answers no is replaced with one over everything at the same sort — the sort
  hides nothing. Past that it moves the pane, drops `viewing` explicitly (the
  pane's own observer only does it when the pane actually moves, and the notice
  may well arrive with the library already up), clears `paneBeforeSearch`, and
  publishes `revealing` with a bumped `revealToken`, the twin of the two focus
  tokens: a token rather than a flag, so asking for the same picture twice is
  heard the second time. Neither is cleared when it is read, because the pane
  that reads it is usually built *after* the ask. What happens instead is that
  the ask is **consumed**: `markRevealConsumed(_:)` records the token that was
  answered, and `unansweredReveal` — the picture, or nil once the token has
  been consumed — is the only thing either reader looks at. Clearing `revealing`
  would break the ordinary case, which is the pane arriving late; leaving the
  ask standing broke everything after it, because the pane is torn down and
  rebuilt on every pane change and both readers watch with `initial: true`, so
  one notification click made every later visit to the Library select that
  picture and scroll three screens back to it for the rest of the session. A
  token that is no longer the newest consumes nothing, so a second ask made
  while the first is being answered is still heard.
- `Support/` — caches, exports, pickers, previews. `ModalHost` is where every
  alert and every file panel in the app is raised: it answers with the window to
  hang a sheet from — the key window, which is already the Settings window when a
  Settings row raised the panel, so there is nothing to detect — and wraps
  `beginSheetModal`, keeping `runModal()` only as the fallback for the case with
  no window at all, which a single-window app reaches whenever ⌘W has closed it.
  A question about a window belongs on that window. `NSAlert` rather than
  SwiftUI's `.alert` is still right, and for the reason it always was — a menu
  command is not a view and has nowhere to hang a presentation binding — but that
  was never a reason to run one application-modal. `ModalHost.warning` is also
  the one place button order and key equivalents are decided, because `NSAlert`
  gives the *first* button added the Return key and `hasDestructiveAction` only
  tints, so an alert built naively confirms the destructive answer on Return.
  Reordering is not the fix and the rule is written down there once — for a
  two-button alert `["Cancel", "Delete"]` leaves Return on nothing at all, since
  a button titled Cancel takes Escape and never Return — so a three-answer
  question is reordered and a two-answer one has Return lifted off the dangerous
  button instead. The thumbnail pipeline lives
  here: `ThumbnailKey` names a baked file by path, mtime, size and edge,
  `ThumbnailFolder` is an actor that bakes off the main thread, four at a time
  through a gate that hands a finished bake's slot straight to the next waiter
  (`ThumbnailFolderTests` pins the four), and `ThumbnailCache` coalesces the
  in-flight requests; `ThumbnailRequest`, the identity of a cell's task, names
  the file's mtime and size as well as its path and bucket, so a rewritten file
  bakes again while the old picture stays up. Beside it, `ImageCache` is the
  same shape for the pictures this session made: `cached` for the first frame,
  `load` decoding in a detached task and coalesced by image id and kind
  (`ImageCache+Decoding` is the Image I/O half, injectable for
  `ImageCacheTests`), and `referenceThumbnail` digesting and decoding the
  reference bytes off the main actor. `Views/Canvas/SessionImage` is the one
  view over it — the canvas, the fresh-image inspector and the filmstrip all
  draw through it, holding the request's aspect until the pixels land and
  fading only the canvas's whole picture in — and `Views/ReferenceThumbnail` is
  the well's, keyed on `GenerationStore.referenceChoice`, the ticket every way
  of choosing a picture moves, so nothing hashes the bytes in `body`. Nothing
  decodes an image on the main actor: a drop, the file chooser and every library
  door hand `adoptReference` a closure and the read runs in its detached task.
  `AppSettings` is the one list of preference keys and
  starting values; a preference is bound with `@AppStorage` at its picker and
  read outside a view through `AppSettings`'s helpers. `DirectoryRow` is the
  labelled path with an Open button that General and Models both show, plus
  whatever else that folder can be done to — which in Models is `Change…` and
  `Use Default`, in `ModelsDirectoryRow`. The appearance
  preference is applied by `AppearanceApplier`, set on `NSApp` from the
  composition root rather than as a colour scheme on a scene, so the Settings
  window, the menus, and the alerts change with the main window.
  `CommandTarget` is what the menu bar's file commands — Export, Share, Copy,
  Reveal, Delete, Use as Reference, Animate, Upscale — are about: the canvas's picture while the
  canvas pane is showing one (not while it follows a run, which has no file
  yet), the grid's focused selection filtered to the sections on screen, and
  otherwise nothing, which greys them all out; there is no fallback from an
  empty library selection to the picture hidden behind it. `singlePicture` is
  the one question Animate reads beyond what Use as Reference does: nil for
  none or for several, and otherwise whether the one picture or clip is a
  clip, which is what `animateTitle` says "Animate from Last Frame" from —
  and `ZephraCommands+Library`'s `canAnimateTarget` excludes Recently Deleted
  the same way the two Upscale items do. `StepProgress` is
  the step bar's reading — the loop's own total once it reports, the run in
  flight's steps before that, the next run's only with nothing running — read
  through `GenerationStore.stepProgress` by the capsule, its lip and the
  running card, so the bar never counts the slider. `ReferenceRole`
  (`ZephraCore`) is the one place every string a reference picture's role
  changes — the well's caption and help, its accessibility label, the open
  panel's message, the strength slider's help, and the inspector's row label
  — is spelled, derived from a model's `ModelCapabilities`
  (`.firstFrame` when it makes clips, `.startFrom` when it adjusts reference
  strength, `.reference` otherwise, in that order, since LTX-2.5 is both a
  clip model and a strength-adjusting one and the clip reading wins).
  `ReferenceImageWell`, `ReferenceStrengthControl` and `ReferenceImagePicker`
  all read it from `store.descriptor.capabilities`; `ReferencePlaceholder`
  itself stays a plain view in `Style/` that only takes the words it is given.
  `ModelLoadNote` (`Support/`) is what `GenerateButton`'s tooltip and
  `AnimateButton`'s share: what pressing Generate costs first when the model
  that would run is not the one resident, read against an arbitrary target
  rather than only `store.descriptor`, since Animate's tooltip has to say
  this before Animate has been pressed and the clip model chosen.
- `Companion/` — everything the link needs that is the Mac's rather than the
  protocol's: `LinkKeychain` (this Mac's identity and its pairings, in two
  generic passwords), `CompanionThumbnails` (the baked thumbnail a phone asks
  for, read through the app's own folder), `CompanionEndpoints` (the addresses
  a QR code names), `CompanionRoads` (the LAN listener) and `RelayRoad` (the
  relay's), and `PairingQRCode`. It is the one place in the app target that may
  import `ZephraLinkTransport`, since a road is what it opens; `ZephraApp.swift`
  itself takes only `ZephraLinkHost`, which knows nothing of sockets. See
  `docs/companion.md`.
- `Views/` — one subfolder per surface (`Canvas/`, `Library/`,
  `Library/Inspector/`, `Library/Viewer/`, `ReferencePicker/`, `Sidebar/`,
  `Sidebar/Timeline/`, `Toolbar/`); the prompt capsule, its controls, the
  commands, and Settings
  sit at the top of `Views/` because they belong to no one surface. The
  three-stored-property rule is what keeps them small; a view that needs a
  fourth wants a subview — `LibraryPaneHeader` holds the filter bar's
  animations for `LibraryPane`, `LibraryGridKeyboard` the arrow keys for
  `LibraryGrid`, each honouring Reduce Motion, as `WorkspaceDetail` and
  `PromptTuckOverlay` do with `.animation(reduceMotion ? nil : .snappy,
  value:)`; the wall's hover wash does not fade at all. The wall's hover wash and its selection ring are `WallSquareChrome`, and both are
  `allowsHitTesting(false)`: a filled shape in an overlay is what the pointer hits, and the
  wash is up exactly when the pointer is over the square, so without that every click on the
  wall landed on the wash and the tile's button never fired — while an accessibility press,
  which goes straight to the action, still worked, so hands-off UAT did not catch it.
  `WallSquareChromeTests` clicks a hosted button through the chrome with a real mouse event,
  and `make lint-layers` keeps `hoverWash` out of every other file. `focusEffectDisabled()`
  on the library grid, the reference picker's grid and the viewer is the one
  exemption from the system's focus ring, deliberate: a ring round a whole pane
  says nothing, and the ring round the selected cell is what shows where the
  keyboard is — which is why an arrow key with nothing selected selects an end
  of the grid (`LibraryCursor`) rather than doing nothing. `SettingsView` is
  four tabs -- General, Performance, Models and Companion -- and `SettingsTab`
  says how wide the window opens and how tall each
  tab stands: the window opens 520 points wide at the tab's own height rather
  than standing at the tallest tab's for all four, and Escape does not close it,
  which is what every Settings window on the Mac does. The height a tab opens at
  is not the least the window may be dragged to — `minimumHeight` is, one
  number for all four, and it must fit the smallest display Sequoia runs on:
  Performance's content plus 88 points of chrome is well past the 876
  usable on a 13-inch MacBook Air M1. That floor, and never the tab's own
  height, is what `contentMinSize` holds to: AppKit clamps a window to the
  screen's visible frame only when the minimum it is holding to actually fits,
  and pinning the minimum at the tab's height is what left Performance's bottom
  off a 1728 x 1080-point display.
  Performance stands **1010** now, not the 820 it shipped at, because the
  Loading section arrived above the warm-up toggle and costs 158 points; the
  whole tab wants about 1110, which no Mac laptop display has. **The rule that
  Performance must not scroll is dead**, and it was already untrue at 820, where
  Peak since launch and VAE decode sat below the sill. 930 was measured first
  and showed no readout rows at all, which is worse than what shipped; 1010 is
  what a 1728 x 1010 workstation display allows and restores the reading 820
  gave, down to Cached. The live readout stays last on purpose, so what falls
  below the sill is the tail of one figure rather than a setting nobody would
  find, and the floor of 400 is what lets the tab open clamped and scrolling on
  a laptop instead of refusing to shrink.
  1010 is what the tab *asks* for. What it opens at, and what a tab switch
  grows the window to, is `SettingsWindowFit` (`Support/`, pure and tested in
  `SettingsWindowFitTests`): `min(tab height, visible frame - chrome)`, never
  under `minimumHeight`, the width untouched, and `grown(current:toward:)`
  which takes that target but never shrinks a window somebody made taller.
  `SettingsWindowFrame` asks the window itself for the chrome
  (`frameRect(forContentRect:)`) and the screen for the room, and after every
  size change runs `constrainFrameRect`, which keeps the title bar under the
  menu bar, and then `SettingsWindowFit.placed`, which moves the whole frame
  back inside the visible frame: a window grows from a corner without moving,
  and AppKit's own constraint says nothing about the bottom edge — measured on
  a 1728 x 1117-point display, Performance grown on a tab switch stood 39
  points below it. A frame larger than the display keeps its top-left corner on
  screen, and the two axes say that differently on purpose: y keeps the high
  edge, which carries the title bar, and x the low edge, which carries the
  traffic lights. Taking the high edge on both reads as symmetry and pushes the
  left of an over-wide window off the screen. So the Settings window is never
  taller than the display and never off it, on any tab, and Performance scrolls
  for the rest.
  The grow itself happens **only when the tab's target changes**.
  `SettingsWindowFrame.apply` runs from `layout()` and from every
  `updateNSView`, and re-growing on each pass meant a window dragged shorter
  than the tab's clamped height — which the 400-point `contentMinSize` now
  allows — snapped back to that height at the Models tab's next inventory
  refresh, or at any `@AppStorage` write. `Opening` keeps the last target it
  grew toward and compares; the first open is unchanged, and `grown` is still
  what refuses to shrink a window somebody made taller.
  Those figures are a floor
  and an opening size, not a fixed frame: the window resizes, keeps whatever size
  a person gave it as they step between tabs, and grows only for a tab whose
  floor is taller. `SettingsWindowFrame` is what says so, because no scene
  modifier can — `.windowResizability(.contentSize)` takes the content's maximum
  as the window's and pinned Settings fixed, `.contentMinSize` pins it too, and
  every content-driven value is re-imposed whenever a tab's state changes, which
  stripped the resizable flag off again a second after the Models tab's inventory
  refresh landed. So the window is configured from a zero-sized `NSView` inside
  it, and the flag is *observed* rather than set: the view watches `styleMask`
  and puts it back whenever SwiftUI takes it away, which is the one place that
  always has the last word. The opening size and the centring happen once per
  launch. About is two windows of its own rather than the
  standard panel, the Mac's own pattern (Xcode's and most apps'): `AboutScenes`
  declares `Window("About Zephra", id: "about")` — `Views/About/AboutView`, the
  icon, name, version line, what Zephra is in two sentences (`AppFacts` in
  `Support/`, the one place those strings, the website and the bundle's version
  and copyright are read), an Acknowledgments… button and a Website button, and
  the copyright — and `Window("Acknowledgments", id: "acknowledgments")`, which
  lays `THIRD_PARTY_NOTICES.md` out whole through `NoticesDocument` in `Support/`
  (the parser, with `NoticesParser` behind it, reading exactly the Markdown the
  file uses and keeping its fenced NOTICE and license texts verbatim) and
  `NoticesView`. Neither opens at launch nor is restored. `AboutCommands` points
  the application menu's About item at the first, and `HelpCommands` replaces the
  Help menu SwiftUI would otherwise synthesize — which carried one item leading to
  a help book that does not exist — with Zephra Help opening the website and
  Acknowledgments opening that second window. There is no Settings > About: a
  fourth tab once showed the same facts with the same two buttons, and a Settings
  tab duplicating a window that already exists is not what any other Mac app does,
  so it went. The notices file is written so it reads right in
  the app too: it names no `LICENSE` file, because none is bundled — the app's
  own terms are the copyright line's MIT, and the full text is the repository's
  `LICENSE`, which a third About button could open once it is a bundled
  resource (`ROADMAP.md`). A keyboard shortcut has one owner, the menu bar
  (`ZephraCommands`, `ModelCommands`, `WorkspaceCommands`, `LibraryCommands`,
  `ZoomCommands`); a button that shows a chord shows it as text, the
  way `GenerateButton` writes ⌘⏎, and never declares it too, because a chord
  declared twice is one stray SwiftUI change from firing twice. The two
  routes call one method, `generateFromInterface`, so what can part them is
  only the click itself: `GenerateClickTests` hosts `CanvasPane` in an
  off-screen window, idle and mid-run, sends a real mouse-down and mouse-up to
  the button's middle and expects the store to take the run, since an
  accessibility press goes straight to the action and would pass with the
  button under an overlay. The button reports where it is through the
  `GenerateButtonFrame` preference (`Support/`), because SwiftUI's controls are
  not views AppKit can find and its accessibility tree stays empty in-process.
  A press `generate(count:)` refuses logs which gate refused it, so `make logs`
  says whether a press that seemed to do nothing arrived. Return in the
  library belongs to the grid's `LibraryOpenCommand` alone. The only
  `.keyboardShortcut` outside the menu bar are a sheet's own `.defaultAction`
  and `.cancelAction`, which is a key loop of its own. File > "Stop
  Generating" is `EngineState.stopCommandTitle`, so the item names what it
  stops ("Cancel Download", "Stop Building", …), and File > "Export…" (⇧⌘E)
  is what was "Save as…": the picture is already on the disk, and nothing is
  a document with changes to keep. `SeedControl`'s label is `SeedLabel`, a
  button: it opens `SeedEntryPopover`, where a seed is typed as the number the
  tooltip shows or as the short hex label off another picture's inspector,
  and `SeedEntry` (`ZephraCore`) is the one parser — digits are decimal, a hex
  letter, a `0x` or the label's middle dot make it hex, eight hex digits are
  the label and come back as the seed's leading half over zeros, sixteen are
  the whole value, and any other count is refused rather than guessed at
  (`SeedEntryTests`). How a seed is spelled on screen is one preference,
  `AppSettings.seedFormat`, a `SeedFormat` in `ZephraCore` beside
  `SeedEntry` and `shortSeedLabel` — there rather than in the engine because
  the phone spells a seed too, and `SeedFormat.hex` is what it draws: the short
  hex label by default, or the whole number, set in General under "Show seeds
  as". `SizeMenu` is the same shape over sizes:
  the model's presets grouped by `SizeTier` (`ZephraCore`) — Faster under
  three quarters of the default's pixels, Larger over one and a half times,
  Standard between — with headings only when there is more than one group,
  then "Custom Size…", which opens `SizeEntryPopover`. With a picture in the
  well each tier also leads with that picture's own shape at the tier's cost,
  its first preset's pixel count, marked "Matches Picture" (`SizeChoice`,
  `Support/`), so a quick clip of a portrait photograph is one click and not a
  typed size; a shape that is a preset already marks the preset instead. A size is typed there
  as two numbers with anything between them (`800 × 512`, `800x512`, `800 by
  512`), a button turns the frame the other way, and `SizeEntry` (`ZephraCore`)
  is the one parser: it fits what was typed to the model's grid through
  `ModelCapabilities.fit`, and `SizeEntryHint` says what Return will keep when
  that differs from what was typed (`SizeEntryTests`). Every picture family
  offers a 768 x 768 quick preset and LTX-2.5 a 512 x 320, so a Faster group
  is there to be found. The root puts it in the environment as
  `\.seedFormat` through `SeedFormatPreference`, and every seed on screen —
  the chip, the popover's prefill (the whole value in that spelling, so
  Return keeps the seed it had) and its hint, `ImageFacts`' Seed row through
  `LibraryFactsView`, `FreshImageInspector` and `SharedFactsView`, and the
  running run's column — reads that one value. Nothing on disk follows it:
  the record, the file name and the search key keep the number, and the
  search key carries the label too (`SeedFormatTests`).
  `ImageFactsView`'s reference row is `ReferenceFactsRow`
  (`Library/Inspector/`): the source model's own `ReferenceRole` label
  ("First frame", "Started from", "Edited from"), a 40 pt thumbnail, the
  strength ("Strength 0.60", or "Held exactly" for a clip whose strength is
  0), and a "Show Source" button when `ImageFacts.referenceOrigin` names a
  file `LibraryIndex.item(named:)` still finds. `LibraryFactsView` and
  `FreshImageInspector` each work out the role from the *record's* model —
  `ModelCatalog.descriptor(id:)?.capabilities`, not the model currently
  chosen in the picker — and hand `ImageFactsView` a `ReferenceFactsRow.Source`
  naming either a `LibraryItem` or bytes already in memory; `ImageFactsView`
  itself stays at two stored properties, facts and that optional source. The
  thumbnail is never read on the main actor: `LibraryItem.referenceImages` is
  a synchronous whole-file read (and `referenceImage` beside it is the first of
  them, the alias every reader written before several pictures existed still
  takes), so `ReferenceFactsRow` runs it inside a
  detached task started from `.task(id:)` and hands the bytes to
  `ImageCache.referenceThumbnail(_:)` for the decode, the same door
  `ReferenceThumbnail` uses for the well; a session's own picture already has
  its bytes in memory and only needs that decode. `Support/BackgroundNotice` is what a change of engine
  state is worth telling the Mac about while another app is in front: a
  download that ended in a build, a load or a ready model finished, one that
  ended in a failure failed, and one the person stopped says nothing; it is a
  pure function over two states, pinned by `BackgroundNoticeTests`, and
  `BackgroundNoticeObserver` on `RootView` feeds it every transition. A saved
  image is the other notice, posted from the `onImageSaved` wiring in
  `ZephraApp+Library` through `BackgroundNotice.saved(at:image:)`, titled
  "Image Saved" or "Clip Saved" and carrying the prompt folded to one line and
  cut at a word (`BackgroundNotice.summary`), since the file name is a stamp
  and a seed and says nothing to a person who walked away. It carries that file
  name all the same, unsaid, because it is what a click on the banner needs;
  `saved(at:image:)` is a pure function rather than three expressions at the
  call site precisely so the name coming off `url.lastPathComponent` is tested. `BackgroundNotices.post` is the one place
  `UNUserNotificationCenter` is touched: it posts only when `NSApp` is not
  active and the General toggle (`AppSettings.backgroundNotifications`)
  allows, and asks permission the first time it has something to say rather
  than at launch. A published update is the third
  (`BackgroundNotice.updateAvailable`, posted by `UpdateChecker`), which is why
  the toggle's label names all three. What a click on one does is
  `AppLifecycle+Notifications`, which adopts `UNUserNotificationCenterDelegate`
  in `applicationDidFinishLaunching` and, on a response, activates the app and
  orders the main window front — without a delegate a Mac whose window had been
  closed with Command W gets a Dock icon and nothing else — and then goes
  wherever the notice said. Two of the three notices say nowhere: a finished
  download is about a model now on the disk and an update is about the banner
  in the window, and bringing that window forward is the whole of what they
  mean. The saved picture is the exception, because the thing it is about is a
  file. `NoticeDestination` (`Support/`) is how it travels: `case
  library(fileName:)`, a `userInfo` of two plain strings (all a notification
  may carry), and an `init?(userInfo:)` that reads it back, both halves in one
  file and neither importing UserNotifications, so the round trip is tested
  without one. Anything unrecognised — a notification posted by an older build
  and clicked after an update, a value of the wrong type — reads as nil, which
  is the honest answer and is the old behaviour. `BackgroundNotices.deliver`
  sets `content.userInfo` from `BackgroundNotice.destination`, which is non-nil
  for the saved picture alone. Where a destination goes is *not* decided in the
  delegate: `AppLifecycle.onNoticeOpened` is injected from the composition root
  the way `isInstalling` is, so that file names neither the library nor the
  workspace, and the destination is read off the notification's content on the
  system's own queue (two strings, so nothing that is not `Sendable` crosses
  into the main-actor task) and acted on only after the window is up. It goes
  through `AppLifecycle.deliver`, which calls the closure where there is one and
  holds the destination in `pendingNotice` where there is not; the closure's
  `didSet` drains it. The two arrive in that order whenever the click is what
  *launches* Zephra — the delegate is set in `applicationDidFinishLaunching` and
  the system calls back at once, while `onNoticeOpened` is assigned from the
  root view's `.task` — which is the case the destination is most for: a banner
  left in Notification Center overnight, clicked cold, used to bring the window
  up and reveal nothing. `AppLifecycleNoticeTests` pins both orders.
  `ZephraApp+Library.openNotice` is the answer, because that is the one place
  the index and the workspace are both in reach: `index.item(named:)` — which
  already skips Recently Deleted — then `WorkspaceSelection.reveal(item)`. A
  miss is answered with one `rescanNow()` and a second look before it is
  believed: a click that launched Zephra fires the delegate before the first
  scan has read the folder, so without the retry a cold click could never
  reveal anything. Only a picture still missing after that scan — gone since
  the banner was posted — gets the library pane and one line in `make logs`.
  `LibraryRevealScroll`, a modifier inside
  `LibraryGrid`'s `ScrollViewReader`, answers each reveal through one callback
  that selects the image and scrolls to it together. The pane has no separate
  reveal observer: a child observer consumes before its parent's observer runs,
  which previously left the old image selected when the target was already listed.
  The modifier watches the token with `initial: true` for a grid mounted after
  the ask, and watches `index.sections` for a widened query arriving later.
  `WorkspaceSelection.answerReveal(listed:)` consumes only when the sections
  hold the target, so a stale listing leaves the ask available for retry.
  `LibraryRevealSelectionTests` hosts the real grid and checks selection on
  mount, on an existing grid, and after a delayed listing, plus no replay after
  the user selects another image.
  `NoticeDestinationTests` pins the round trip and the refusals,
  `WorkspaceSelectionTests` the pane, the viewer, the widening, the token, and
  the answering: a stale listing consumes nothing, a listed picture is answered
  once, a newer ask is left standing. `Sidebar/CanvasSidebar` is the canvas sidebar,
  which builds today's runs once and hands them to `Sidebar/Timeline/` — a
  card per run still waiting, the running run's card in amber, and under those
  the wall of today's pictures in small squares — and to the "Today in
  Library" bar pinned at its foot. `SessionTimeline` in `ZephraEngine` works
  out the runs and lays the wall as one flow, newest run first, of finished
  pictures only (a block per run ended every batch's row early and made the
  wall ragged); a seed still to come has no square there at all, only the
  running card's own step segments above the wall, and its finished squares
  join the wall at the running run's head, adjacent, the moment they land.
  `TimelineRun.seedCount` is what a waiting run's card counts instead, since
  it has no tiles yet to count. Nothing here filters, groups, or sorts. The inspector is `WorkspaceInspector`, a
  fixed column `WorkspaceDetail` puts beside whichever pane is up, under the
  toolbar rather than splitting it, and only when it has something to
  describe: always in the library, on the canvas only while a picture is
  showing (`GenerationStore.hasPicture`, which the toolbar toggle and the menu
  read too). `Library/Inspector/` describes the grid's selection and
  `Canvas/CanvasInspector` the picture on the canvas, which is the library's
  own inspector once the file is indexed and `FreshImageInspector` until then.
  An empty canvas shows `CanvasEmptyState`, with the last three prompts from
  the index (`RecentPrompts`, nothing persisted) as chips. `CanvasStateView`
  is what the canvas says otherwise, centred, and in a floating panel when a
  picture is under it; the one state that steps aside is a model that simply
  is not loaded over a picture, which sits at the top edge with its Load
  Model button so a picture opened from the sidebar is seen and not covered.
  That button goes through `GenerationStore.loadModel()` and not through
  `retryFromInterface()`, which Try Again beside it still does: a plain load is
  not a retry. The link under it, "Choose a Model…", raises
  `ModelBrowserSheet` rather than `WelcomeGate.reopen()`, which is gone; the
  idle headline reads "X isn't loaded. Generate loads it first." rather than
  "isn't loaded yet.", since with on-demand loading that is the ordinary resting
  state of a Mac and the sentence has to say what to do about it. On Liquid Glass
  the window toolbar floats over content by default, so `RootView` forces
  its background visible (`.toolbarBackgroundVisibility(.visible, for:
  .windowToolbar)`), making it an opaque full-width strip with a hairline
  under it; `CanvasView` no longer ignores the vertical safe areas, and
  `WorkspaceDetail`'s `HStack` (the pane, its `Divider`, and the inspector)
  stays inside the top one too, so the sidebar, the pane, and the inspector
  all start below the strip rather than the divider cutting through it.

  The model's three controls sit at the trailing end of the toolbar and behind
  it. `ModelMenu` is the pull-down, and it lists **what is on this Mac** rather
  than the catalog: `ModelMenuRows` (pure, `Support/`) takes models whose
  files are here, the chosen model whatever its state, and any model whose
  transfer has something to say, in `ModelCatalog.ordered(for:)`'s order,
  checkmarks the chosen one, and puts "Loaded", "Streaming" or that
  transfer's own sentence after a name that needs it. The sentence comes in
  as a `[ModelDescriptor.ID: String]` map filled from
  `ModelDownloads.status(for:)`, which is what Settings > Models already
  draws — "Downloading 42%", "Download paused", "Download failed" — and that
  map is both the note and the reason a model is listed, so the two surfaces
  cannot come to differ about a transfer. A `Set` of live ids was the first
  shape and was wrong twice over: a paused transfer read "Downloading…" and
  a failed one left the menu entirely, which is the one thing the menu's own
  rule forbids.
  A model being merely undownloaded no longer closes a row — only
  memory greys one, which is what the greying means — and the catalog's rest is
  behind a Divider and More Models…, because what a model makes and what it
  downloads is a picture and three lines, not a menu row. A transfer somebody
  just started keeps its row, so the one menu in the window that names models
  never loses the model they are waiting for — a paused transfer and a failed
  one above all, since those are the two somebody has to come back to. A
  finished one answers nil and needs no rule: the model is `.available` by
  then.

  The menu's label carries the state word and **no `ModelDot`**: SwiftUI flattens
  a toolbar menu's label to its title and a menu item's to text plus a system
  image, so a dot beside the name is drawn nowhere. That was tried and
  photographed. The word survives because it is part of the title, which is the
  half that had to.

  `ModelLoadButton` stands beside the menu rather than inside it. A pill whose
  width moved with its state word would shift every item to its left in the
  trailing group, and a view holding the model, the load state and the rows at
  once would be past the three stored properties a view is allowed. It reads
  Load, Unload, Try Again or — over a lost GPU, where the word *is* the press
  rather than a label on somebody else's button — Relaunch, from
  `ModelLoadStatus`, the pure type that also gives the menu its word and the
  button its tooltip, so the two cannot disagree — and it **never leaves the
  toolbar**. A control that went away for the length
  of a load would slide the inspector toggle and Settings across and back, which
  is a bigger movement than the pill's own. While the weights are on their way
  in it still reads Load and is greyed, by `isPressable`: not the state word,
  because the menu's label immediately to its left already carries that, and
  "Z-Image Turbo · 8-bit · Downloading" with a greyed "Downloading" beside it
  says one thing twice in a strip that then changes width on every state. Load
  is the press somebody wants and cannot have yet, which is what a greyed button
  means. The progress itself is a determinate bar on the canvas, where its Stop
  is; a second, indeterminate one in the toolbar would be a repeating animation,
  which neither app target runs. Its tooltip is
  the sentence rather than the word, since this is the one place a press that
  unloads one model to load another can say so.

  `ModelBrowserSheet` (`Views/Models/`) is 760 x 560 over the window, presented
  once from `RootView` on `WorkspaceSelection.showsModelBrowser`, which is never
  persisted for the reason `promptTucked` is not: a dialog is something a person
  opened, not a place the window is. It lives on `WorkspaceSelection` rather
  than in a view because three places raise it and because one object has to
  arbitrate between it and `showsReferencePicker`, its twin and its rival for
  the one sheet a window has: `didSet` on each refuses to rise while the other
  is up, since a sheet raised over a sheet stacks and ⇧⌘M over the reference
  picker put the browser on top of it. The reference well writes the second flag
  rather than holding a `@State` of its own, which also retired the `onAppear`
  hook the `picker` screenshot build needed. Three doors raise it — More Models… in the
  pull-down, "Choose a Model…" on the canvas, and ⇧⌘M in the Model menu — and a
  sheet belongs to the window all three are in. 760 rather than the reference
  picker's 640: the grid's columns are 280 at their narrowest with 16 of spacing
  and 64 of padding, which is 640 exactly and would collapse to one column the
  moment a scroller appeared. It splits into `ModelBrowserHeader` and
  `ModelBrowserList` because the sheet would otherwise hold the budget, the
  selection, the store and `dismiss` at once; the list reuses `ModelChoiceGrid`
  untouched and seeds its selection from the chosen model, so the footer opens
  describing that rather than an arbitrary first card.

  `ModelBrowserFooter` draws one button, not a row of them, because which of
  Download N GB, Build Model, Use Model and Load Model applies is decided
  entirely by the disk and this Mac's memory. `ModelBrowserAction` (pure,
  `Support/`) is that decision and asks **memory first**: a model this Mac cannot
  hold says what it would take, since "Download 13.3 GB" over a disabled button
  offers a transfer nothing will load. Two answers draw no press at all.
  `.done` — the model that is chosen and already in — is `isDrawn` false, since
  Done is standing in the footer already and a second Done beside it would be
  two ways out of a dialog that has one. And a card judged before the survey has
  landed is `.pending(String)`: the word the button *will* say, disabled,
  because nil availability folded in with "it is here" put Load Model over a
  press that would have run the whole acquire chain and started a 13 GB
  download. Download and Build do not dismiss — the
  footer becomes that transfer's own `ModelDownloadRow`, with its Pause and
  Cancel Download, because sending somebody to Settings to stop what they just
  pressed in this dialog is the worse answer. Download goes through
  `downloadModel`, never `resumeDownload`, which would load the model already
  chosen. The footer is a fixed 112 points in every state, so pressing Download
  does not resize the grid under the card somebody has just chosen: 112 is what
  `ModelDownloadRow` needs down to its buttons, and the row is framed and
  clipped into it — its two trailing caption paragraphs cut — rather than
  forked, since two copies of Pause and Cancel Download would be two sets of
  disabled reasoning to keep in step.

  The grid is shared with the first-launch chooser and the body is deliberately
  not. `WelcomeView` carries layout that exists for the full-window case alone —
  the two spacers that centre it, the 1040-point content column, two pinned
  screenshots — and sharing a body would make this sheet's fixed frame the thing
  that decides the chooser's layout. One grid, two hosts, two chromes.

  `ModelCommands` (`Views/`) is the menu bar's half: a `CommandMenu("Model")`
  with Load Model (⌥⌘L), Unload Model (⇧⌥⌘L), a divider and More Models…
  (⇧⌘M). Its own menu rather than three more items in File, whose group is
  Generate, Stop and New Album — the things a person makes — while these three
  are about the engine that makes them and what is on the disk; putting Load
  Model directly under Generate would also sit the two items that now interact
  ("Generate loads it first") side by side, where they read as alternatives.
  Every item has a visible twin in the window and reads the same two answers,
  `canLoad(store.descriptor)` and `canUnload`. More Models… has a third
  condition of its own: it is greyed while `welcome.isShowing ||
  workspace.showsReferencePicker`, because the browser is a sheet on `RootView`
  — which is not in the hierarchy at all while the first-launch chooser is up,
  so the flag set there raised the browser the moment the chooser went — and
  because it and the picker are the two sheets one window has.

  `ModelLoadingSettings` (`Views/`) is the Loading section, first on the
  Performance tab: "Load models automatically" with a caption saying what each
  answer means, and "Unload after idle" over `IdleUnloadDelay`. The two keys are
  `loadModelsAutomatically` (false) and `idleUnloadMinutes` (0), and both are set
  on the store **in `ZephraApp` alone**, each with an `initial: true` `onChange`,
  so Settings applies to the next choice rather than the next launch. The same
  change took `warmsUpAfterLoad` there: four doors into a load each re-read that
  preference for themselves, which is four readers of one preference, and the
  assignments in `GenerationStore+Interface` are gone.

  A clip plays where its poster would be: `Canvas/ClipPlayerView`, an
  `NSViewRepresentable` over AVKit's `AVPlayerView` with no transport controls,
  fed by an `AVPlayerLooper`, muted unless the asset carries an audio track, over the MP4 beside the poster — on the
  canvas once the save has landed and `fileURL` says where (the poster shows
  until then), and in the library viewer through `Library/Viewer/LibraryViewerClip`
  for any item with a `videoURL`. Both play on while a run is in flight: H.264
  decode is the media engine's work and not the GPU's, and a clip that stopped
  the moment Generate was pressed read as broken. SwiftUI's
  `VideoPlayer` was tried first and rejected twice over: its controls take the
  click that tucks the prompt, and linked only through SwiftUI it aborted the
  first clip resolving its superclass, which is why `project.yml` still names
  `AVKit.framework` in the app's link rather than leaving it to autolink.
  `ZephraStyle`'s `VideoBadge` is the clip's mark on a grid cell and a sidebar square, in
  the corner `UpscaleBadge` uses, since a picture is one or the other. The
  capsule shows `DurationControl` — chrome over `ClipLength` (`ZephraCore`,
  because the phone's capsule draws the same menu): the shortest clip, then one
  choice per whole second, each snapped to the model's ladder (9, 25, 49, 73,
  97, 121 frames at 24 fps), then every five seconds up to
  `ChainPlan.maxFrames` as a chain of passes, labelled with how many passes make
  it — only when `frameBounds` is a range, and hides
  `StepsControl` when `stepBounds` is a single value, the way it already hides
  guidance: a slider over one value is not a slider, and LTX-2.5's eight steps
  are the checkpoint's. The inspector's Length row comes from `ImageFacts`.

  Every picture in the app wears the same right-click menu: `LibraryItemMenu`
  for anything indexed — the grid, the sidebar wall, the library viewer, and
  the canvas once the file has been indexed — and `FreshImageMenu` for a
  session's own picture before that indexing has caught up, both in
  `Views/Canvas/` beside `CanvasImageMenu`, which picks between them for
  whatever the canvas is showing. `LibraryItemMenu`'s `selection` is optional,
  taken only where there is a `LibrarySelection` to keep in step with the
  choice; the sidebar wall and the canvas have none and pass nil.
  `LibraryIndex.canvasItem(for:)` is the one lookup behind that choice and
  behind `CanvasInspector`, so the two never disagree about what the picture
  on the canvas is; deleting it from either fires
  `LibraryIndex.onRecentlyDeleted`, which `GenerationStore.forget(fileAt:)`
  answers by stepping the canvas to the next image in history.

  Animate sits beside Use as Reference everywhere a single picture's actions
  are offered — `LibraryItemMenu`, `FreshImageMenu`, `InspectorActions`,
  `FreshImageActions`, and the menu bar's own Animate item (⌥⌘A) — and both
  show **disabled rather than hidden** when the model, or this build, cannot
  take them, the macOS convention: a build with no clip model still shows
  Animate, greyed. `AnimateButton` (`Views/Library/`) is `LibraryItemMenu`'s
  and `InspectorActions`'s button, titled "Animate" for a picture and
  "Animate from Last Frame" for a clip (`item.isVideo`); `FreshImageMenu` and
  `FreshImageActions` wire the same rule inline, since neither has a
  `LibraryItem` to hand the button. Both paths go through
  `ReferenceAdoption.animate(_:into:)`, one overload per kind of picture,
  never `adopt(_:into:)`: an edit hands back its own source under `adopt`,
  and a clip's last frame is read through the store's injected `ClipEditing`
  (`GenerationStore.clips`) and re-encoded through `ReferenceImageEncoder`.
  Extend Clip sits beside Animate on the same surfaces, for clips only
  (`ExtendClipButton`, the fresh-image menu and actions, ⌥⌘X in the menu bar),
  greyed by `ActionAvailability.extendDisabledReason` — no reader in this
  build, the store busy, the clip not yet on disk, or a size the continuer's
  grid cannot draw — and wired through `ReferenceAdoption.extend(_:into:)`,
  which builds the `ContinuationSource` the store takes. While the capsule
  carries a continuation the well reads `ReferenceRole.continues`, whose
  strings sit beside the other roles', and the inspector's facts gain a
  "Continues" line from `ImageFacts.continued`,
  which is right for "use this as a reference" and wrong for Animate, which
  means exactly the picture in front of you. A clip's last frame — what
  Animate reads instead of the poster, since the poster is only the first
  frame — comes from `ClipEditing.tail`, the one `ClipEditing` implemented by
  `MP4Stitcher`/`ClipTail` in `ZephraMedia`, its bytes re-encoded through
  `ReferenceImageEncoder` like every other door into the well.

  A double-click in the grid, or Return on the selection, no longer opens the
  canvas — it opens `Library/Viewer/LibraryViewer`, the picture full size in
  the library pane itself, with `LibraryViewerBar` stacked above it ("Library"
  back, "n of N", previous/next) — stacked, not inset, so the picture is fitted
  to the height under the bar — `ViewerPlaceholder`, the grid's thumbnail at
  the picture's own aspect, standing in until the decode lands, and `LibraryViewerNavigation` underneath
  (Escape or a second double-click closes it; the arrow keys step, crossing
  day headings the way the grid's own do, through the pure arithmetic in
  `ZephraEngine`'s `LibraryViewerStep`). `WorkspaceSelection.viewing` names
  the one item shown, cleared whenever the pane changes; `LibraryPane` is the
  one place that keeps the grid's selection in step with it, so the inspector
  beside the viewer always describes what is on screen and closing scrolls
  the grid back to it. "Open in Canvas" — the `\.openLibraryItem` action, on
  the cell's menu, the sidebar wall, and the inspector's own button — is
  unchanged; the viewer answers to the twin `\.viewLibraryItem` instead.

  The viewer's picture and the canvas's still both **zoom**, through one view,
  `Zoom/ZoomablePicture`, and nothing else does: clips, the live preview,
  thumbnails and the inspector stay plain pictures. It is AppKit's own
  magnification rather than a SwiftUI `MagnifyGesture` over a scaled `Image`,
  because an `NSScrollView` with `allowsMagnification` gives what Preview gives
  for nothing — a pinch about the fingers, a two-finger double tap as smart zoom,
  momentum and rubber-banding — and a hand-rolled one would give none of it.
  `ZoomScrollView` lays its document out at the picture's **fitted** size, so
  magnification 1 is fit, the zoom survives a resize relative to fit, and a new
  key (another picture; a step in the viewer; the same file rewritten, keyed as
  the decode is) puts it back there. `CenteringClipView` keeps a picture smaller
  than the pane in its middle. `PictureDocumentView` draws the picture with high
  interpolation over `Checkerboard`'s squares when it has alpha, dividing the
  cell by the magnification so the squares stay eight points on screen, in
  `TransparencyGround`'s colour sets resolved for its appearance, and pans on a
  click-drag in a tracking loop of its own with the closed hand.

  The hard part was keeping the picture the picture. The canvas lays a single
  click (the tuck), a right-click menu and a drag-out on it, the viewer a
  double-click and its own menu and drag, and SwiftUI's gestures over a
  representable do not see an event the `NSView` under them takes. So at fit
  `ZoomScrollView.hitTest` answers nil for a mouse click, a right click and a
  drag — it asks `NSApp.currentEvent` which kind of event it is being
  hit-tested for — and the event falls to the hosting view, where SwiftUI's
  gestures are; a pinch, a smart zoom and a scroll are still its own, and a
  scroll at fit, which would move nothing, is handed to the next responder.
  Zoomed in, a left click is the pan's and a right click still goes to the menu.
  `AspectFitShape` is the content shape, so at fit those gestures answer over the
  picture and not over the graphite letterbox either side of it, as they did when
  the picture laid itself out at its aspect. `ZoomablePictureClickTests` proves it
  with real events, posted through the application's queue to an off-screen
  window rather than handed to it, since only the event loop sets
  `currentEvent`: a click on the picture tucks, one on the letterbox does not, a
  right click opens a menu at fit and zoomed, and a zoomed click does not tuck.

  The View menu's four zoom items are `ZoomCommands` — Zoom In ⌘+, Zoom Out ⌘−,
  Actual Size ⌘0, Zoom to Fit ⌘9 — over `PictureZoom`, the `@Observable` the
  picture publishes as the scene's `pictureZoom` and the scroll view keeps
  current on every bounds change, so a greyed item is the scroll view's own
  answer. `ZoomScale` (`Support/`, pure, `ZoomScaleTests`) is the arithmetic.
  Actual size is one pixel to a point, as Preview's is and as a dragged-out file
  opens elsewhere; one pixel to a device pixel would make Actual Size *smaller*
  than fit for a 1024-pixel picture on most Retina panes. The floor is fit, or
  actual size for a picture smaller than its pane, and the ceiling eight times
  fit, or actual size past that, so Actual Size is never a dead press. ⌘+ and ⌘−
  were already the thumbnails' (`ThumbnailSizeCommands`, "Zoom In"/"Zoom Out"),
  and a chord has one owner, so `ZoomCommands` took them over whole: the picture
  while one is up, the thumbnails (`ThumbnailSizeSteps`) while the grid is.

  What the canvas shows while the model works is decided by one question,
  `GenerationStore.isShowingRun`. While it is following, `CanvasView` draws
  `Canvas/LivePreviewView` — the run's own frames, a `CGImage` over the RGBA8
  bytes, `.medium` interpolation because a frame is an estimate, letterboxed
  into the run's own aspect so the finished picture lands in the rectangle its
  frames were filling. Before the first frame `Canvas/RunPlaceholderView` sits in
  that rectangle: a still safelight card, the system spinner, and the phase in
  words. Still on purpose, and `make lint-layers` keeps it so: **nothing in the
  app target may run a repeating animation**, because while the model works the
  GPU is the model's. A breathing opacity animation there, sixty composited
  frames a second over a streamed transformer step, took a 16 GB M4 mini's GPU
  down every time — a GPU restart the driver blamed on whichever command buffer
  was in flight, which MLX turned into an uncaught C++ exception on Metal's
  completion queue — no Swift `catch` reached it before mlx-swift 0.32.2 and
  the device-error boundary — so the app aborted a step in. Reduce Motion off,
  the same launch crashed at 38 s; on, it made its picture in 144 s. The system's
  indeterminate spinner stayed on screen through that run and is fine. There is
  no context menu and nothing to drag, because there is no file yet; a click
  still tucks the prompt away. The run is not over when the steps are: the
  backend reports `.decoding` while the latents are developed and, for a clip,
  `.saving` while the frames are encoded, tens of seconds on a 121-frame clip,
  and the last frame sits still meanwhile. `EngineState.isFinishing` is that
  stretch, and everything that reads the run reads it: `StepProgress` keeps
  the bar up and full, `Canvas/FinishingNote` floats the phase with the
  system spinner at the top of the frame (after a second, so a half-second
  decode flashes nothing), the inspector's Steps row says "8 of 8" and its
  Left row says the phase, and `StepTimer` lets the loop's pace ride on those
  events so Elapsed keeps its figure. The phase is worded for the kind of run
  (`detail(clip:)`, `generationPhase(clip:)`, `subtitle(for:clip:)`, from
  `GenerationStore.runMakesClip`): "Developing the clip" and "Encoding the
  clip" against "Developing the image" and "Saving". The capsule's `StepSegments` ride its top edge
  inset by `ZephraChrome.capsuleRadius`, on the lip too, so the corners' curve
  clips no segment; `StopButton` beside Generate is a bordered "Stop" in
  safelight; the size menu and the seed count show their chevrons, and the
  count says what it counts ("4 seeds"). The controls under the prompt stay
  live while the model works, as the prompt does: a run carries its own
  settings, so a size, seed or strength moved mid-run is the next run's, and
  Generate queues it. The tuck is `Canvas/PromptTuckHost`'s,
  and it is visual only: `PromptTuckOverlay` slides the capsule under a lip and
  the prompt's text view stays first responder underneath it — the host hands
  it the caret as the prompt tucks and never takes the keyboard itself — so
  whatever is typed lands in the real editor, composed input included, and the
  first change to the prompt brings the capsule back; Escape arrives as
  `cancelOperation:` through `onExitCommand`. It once focused itself and
  appended raw characters to the prompt, which broke every input method that
  composes.
  `Canvas/RunningRunInspector` is the column beside it: prompt, model, size,
  the step of how many, seed, elapsed and left — the last two from the pace
  `store.state` already measures rather than a clock of the view's own — and
  Stop. When it is *not* following, the picture is on the canvas at full
  strength even with the model running; the dim to 60 % went with the frames,
  which say "this is not the new one" properly.
  `Sidebar/Timeline/RunningRunCard` is the way back: a button calling
  `watchRun()`, which also puts the run's settings back in the capsule after a
  square on the wall (`RunTile`, through `GenerationStore.select(_ item:)`)
  replaced them with its picture's, still amber, wearing the accent ring the
  wall's squares wear when the canvas is showing the run — and no square wears
  it meanwhile —
  with `RunPreviewThumbnail`, the newest frame at 36 pt, at its leading edge,
  so a run is worth glancing at while you are looking at something else.
  `GenerationPreview.makeImage()` in `Support/` is the one place bytes become
  an image, and each view keeps the result until the bytes change: `body` runs
  on every progress update and frames arrive far more rarely.

The prompt is `PromptTextView`, an `NSTextView` of our own on TextKit 1 rather
than `TextEditor`, for one reason: a text view paints a selected line break out
to the trailing edge of its container, which in the capsule is the whole prompt
area, and `PromptLayoutManager` clips every selection rectangle to the line's
used width instead. `CapsuleTextView` underneath it stays as tall as its clip,
so a click in the empty part of the band still places the caret, and reports
focus from the responder chain rather than from the delegate's editing
callbacks, which are not sent for a click in and straight back out.

Albums are made and filed from the library sidebar, and both of those are worth
knowing about before touching `Sidebar/`:

- An album is made by `NewAlbumBar`, pinned at the foot under
  `RecentlyDeletedRow`, or by ⌘N, and it is named in its own row rather than in
  an alert. The album is created first, called "Untitled Album", and what
  follows is a rename of a real album — so `AlbumEdit` has one naming path
  instead of two, and Escape leaves the album behind the way the Finder leaves
  "untitled folder". `SidebarView` owns that one `AlbumEdit`, above both the
  list and the bar, because the making and the naming happen in different
  views. Only the deletion still asks in an alert.
- `AlbumNameField` enters its own focus in `.task`, after one `Task.yield()`.
  In a `List(selection:)` the first click selects the row rather than reaching
  the field, and focus set on the list's first pass — before the row is in a
  window — is dropped. `NSTextField` selects all on programmatic focus, which
  is what puts "Untitled Album" under the cursor ready to be typed over.
- Images are filed by dragging them from the grid onto an album row.
  `LibraryItem`'s `Transferable` exports `LibraryItemReference` first and the
  file second: a `FileRepresentation` cannot be received by a
  `dropDestination`, and inside the app the id is what is wanted anyway. The
  type is `io.zephra.library-item`, declared in
  `Sources/Zephra/Resources/Info.plist` under `UTExportedTypeDeclarations` —
  `UTType(exportedAs:)` is only the reading half of that. A drag that started
  inside the grid's selection files the whole selection, the rule
  `LibraryGrid.targets(for:)` already uses; `AlbumDropTarget` reads it through
  `@FocusedValue(\.librarySelection)`.
- ⌘N reaches `SidebarView`'s state through `@Entry var newAlbum` in
  `FocusedValues`, an action rather than a piece of state. The menu bar cannot
  see a view's `@State`, and putting album state in `ZephraEngine` or in
  `WorkspaceSelection` would put interface bookkeeping somewhere it does not
  belong. Publishing nothing on the canvas is what greys the menu item out.
