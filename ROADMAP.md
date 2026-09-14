# Roadmap

What Zephra should build next, in order, and what was deliberately left out of the
work already done. The order was set on 3 September 2026 after FLUX.2 klein and
reference-picture editing landed; the survey behind it lives in the session notes.

Standing decisions: **a push to `main` ships.**
`.github/workflows/release.yml` gates, notarizes and publishes the Mac app,
uploads the companion to TestFlight and deploys the link relay, every step a
Makefile target, with no manual step and no version to type. Pull requests run the fast gates before merge; only main can publish. The push gate is the
minutes' worth — `doctor`, `lint-layers`, `test`, `relay-test`, `test-ios`;
`test-app` and `test-mlx` are the hour and run under `workflow_dispatch` with
`full_gates: true`, and locally before a merge as they always have.
`deploy-website.yml` stays manual, because production goes out when James says
so. See "Build & run" in AGENTS.md and the CI section of
`docs/build-and-release.md`.

## Next steps, in order

1. **Upscale with Real-ESRGAN** (shipped, PR #7). A post-process beside the
   backends; see `Packages/ZephraUpscaleRealESRGAN` and the follow-ups below.
2. **Several reference pictures at once.** klein assigns each picture its own image
   index on the rotary embedding, so this is mostly plumbing: `referenceImage` becomes
   a list capped by a new capability, the well beside the prompt becomes a row, and the
   record stores every picture. Measure the peak first; one 512 reference already lifts
   a 1024 edit to 19.2 GB.
3. **Qwen-Image-Edit-2511 with Lightning.** The strongest editor with a clean license,
   on the transformer the clean-room port already runs. Needs the Qwen2.5-VL vision
   tower the port skips today. 32 GB Macs only. Reference from mflux or mlx-gen (MIT),
   never `mzbac/qwen.image.swift` (GPL-3.0).
4. **Z-Image base**, for guidance and a negative prompt. One to three days, but 28 to
   50 steps with two passes each is about eight minutes per 1024 image on an M4 Max:
   a quality mode, not a daily one. Do it when those controls matter as features.
5. **Runtime LoRA.** Adapters are merged at build time today. A low-rank delta at
   matmul time on the quantized transformer, an adapter slot on the settings and in
   the record, a picker in the capsule. Start with klein, the smallest transformer.
6. **Hygiene.** Rerun `make bench` idle for every catalog entry and refresh the figures
   (the Qwen entry has not been re-measured since its VAE encoder was added, and every
   Qwen figure predates the stream running in bfloat16 — it ran in float32 by accident
   until the 2026-09-05 audit, so resident and `--stream` at 1024 are both due; klein's
   edit figures, 66 s and 19227 MB from a 512 reference, likewise predate the reference
   tokens being cast to the stream's dtype). Try 6-bit or mxfp8 on Qwen-Image's 6.8B
   modulation weights, which cost 3.4 GB at 8-bit. Qwen-Image's reference rounds the
   timestep to the stream's dtype, and its own `get_timestep_embedding` rounds the
   frequency ladder to it too, before the float32 sinusoid; the port keeps both float32,
   the way the float32 fixtures see them. Decide whether to match, as klein now does for
   its timestep, with a bfloat16 fixture. One `MemoryUnits` in `ZephraCore` for the
   megabyte: `InferenceTuning.bytesPerMB` and `ZephraBench`'s reading of
   `ZEPHRA_WIRED_LIMIT_MB` both count 2^20 today and each says so in a comment, which is
   two places to keep agreeing.

7. **A CDN source for packed variants** (shipped: `ModelDescriptor.mirror`,
   `ModelAcquisition.fetchPrebuilt`, `make mirror` and `make mirror-sync`). Saves about
   127 GB of disk and 82 GB of transfer over the five picture entries installed today,
   and another 69 GB of disk and 50 GB of transfer for LTX-2.5. Left out
   for now: a Settings row saying where a variant came from (mirror or built here), a
   `mirror` field in the record, and any way to prefer building over fetching. Z-Image,
   Qwen-Image and klein are Apache 2.0, so hosting the packed derivatives needs the
   attribution `THIRD_PARTY_NOTICES.md` already carries and nothing more; LTX-2.5's
   packed variant carries the pack's `LICENSE.md` beside its files, as its licence asks.
   One rule the mirror imposes on a plan change: a variant's `source` in `index.json` is
   the descriptor's identity, patterns included, and the released app matches it word for
   word. So a rebuilt variant is synced with `make ship` and not before, or the released
   app silently falls back to the 69 GB pack and a local build while `availability` still
   promises the mirror's 19.8 GB. LTX-2.5's variant with the video encoder was the one
   waiting; it went with the 2026-09-08 ship, and `index.json` in the bucket is now byte
   for byte the one in `MIRROR_DIR`, so nothing is owed.
8. **LTX-2.5 video** (`docs/research/ltx-2.5.md` has the reading). Shipped first: the
   video-only distilled transformer at four bits, packed from the ungated
   `mlx-community/ltx-2.5-mlx` bf16 pack — Lightricks' own repositories are gated and
   Zephra sends no token — with a poster PNG carrying the record and the MP4 beside it.
   Left out, in order of value:
   - **Audio**: shipped 2026-09-10 as a second entry, `ltx-2.5-distilled-audio-4bit`,
     the plan with the lane, the audio decoder and the vocoder, the kit's audio lane,
     heads, connector, decoder and BigVGAN-v2 vocoder pinned by diffusers fixtures, and
     an AAC track in the MP4 (`MP4Writer` feeds both inputs at once from
     `requestMediaDataWhenReady`; polling either one stalls the writer at the first
     interleave). Still out: audio conditioning and the audio encoder (nothing to hold
     an earlier clip's sound at a join, so a chained or extended clip made with sound
     carries each pass's own track, joined at the seam without a crossfade); a volume
     control and a mute in the player beyond the file's own track; an 8-bit audio
     variant; the wall stays silent by design; and the audio's per-step noise keys are
     this port's own, so the lane's sound for a seed is not the reference's.
   - **More than one held frame**: shipped 2026-09-10 as Extend Clip, holding the `1 + 8k`
     last frames of an earlier clip as `k + 1` clean latent frames at the head
     (`LTX2HeldFrames`; the reference's multi-frame condition at latent index 0). Still
     out: a keyframe at any *other* latent frame, a strength that ramps across the held
     frames rather than standing at one value, and the reference's re-compression of the
     held frames at CRF 18 before encoding. The join re-encodes both parts once through
     `MP4Writer`; a passthrough splice of the two H.264 streams was left out because the
     parts would have to have been encoded alike. A variation queued from an extended
     clip runs clamped to one pass, since the record's `frameCount` is the whole clip.
     Wan continues from its last frame alone, and **that is what a chained Wan clip looks
     like**: one still frame carries no motion, so every pass re-establishes the model's
     own and a twenty-second clip reads as four clips cut together. Holding a run of
     latent frames is the obvious answer and was measured on 2026-09-11; it is worse.
     Wan's `expand_timesteps` mask takes any number of frames and holds them exactly (the
     segment's first 13 frames came back as the source's last 13 at an RMSE of 0.010 to
     0.013, the autoencoder's own round trip), but the frame right after the held run
     jumps, and the jump grows with the run. Mean absolute frame-to-frame difference over
     a joined clip, 832 x 480, 49 frames a pass, the frame before the seam against the
     frames around it: a fast scene went 10.7 held-1, 17.8 held-5, 29.7 held-13 against a
     local 13 to 15; a slow scene went 10.6 held-1 and 23.3 held-13 against a local 4.
     Holding more does match the source's motion better after the seam (5.5 against 6.5
     on the slow scene, where the source ran at 4.0), but it buys that with a visible pop
     at the boundary, so the shipped behaviour stands. The way out is training, not
     masking: `TheDenk/wan2.2-video-continuation` (Apache-2.0) is a LoRA that teaches the
     multi-frame hold, and packing it is the open item (issue #43) — the catalog change behind it is
     `continuationFrames` and `defaultContinuationFrames` on the Wan entry. Until then a
     long clip that has to be continuous belongs on LTX-2.5, which holds 17 frames and
     was trained to. Longer clips are chains of passes (`ChainPlan`, up to four);
     left out: a Stop that keeps the passes made so far as a shorter clip (today it drops
     them, as it drops a single run), a record field counting the passes, the batch
     control's pending count while a chain queues its next pass, and audio across a
     chain once LTX makes any.
   - **The first frame is not re-compressed**: the reference image-to-video pipeline puts
     the picture through H.264 at CRF 18 before encoding it, so the model sees the
     compression artefacts it was trained beside. This port encodes the picture as it is,
     as the MLX Swift port does. Worth measuring against a re-compressed first frame before
     deciding it matters.
   - **A duration head**, DFR refinement, the 8-bit variant, temporal chunking of the
     decode past ~121 frames at 1024, the prompt enhancer, and a `ModelSource` for a
     mirror-only model should the ungated pack ever be gated too. The two-stage path is
     in (item 9); the temporal upsampler, the rational resampler and the tone map are not.
   - **The M5 question**: LTX runs bfloat16 on every GPU; if an M5 shows the split-K
     symptom klein works around, `ZEPHRA_DIT_DTYPE=f32` is the bisection lever.
   - **Small things the first cut leaves out**: an exported clip carries no record (the
     favourite, tags and albums stay in the poster PNG); Copy puts the clip's file alone on
     the pasteboard; the batch control queues N clips
     as it queues N pictures; the running-run inspector shows steps but not the clip's
     length; no `ZEPHRA_PREVIEW_STATE` stands a clip up for `make screenshot`; the warm-up
     run is an eight-step nine-frame clip plus an MP4 encode, about ten seconds, where the
     picture families pay for one step; an MP4 whose poster is gone sits in Recently Deleted
     undated, since the purge walks PNGs; a clip whose MP4 was removed by hand still reads
     as a clip (`LibraryItem.videoURL` is derived, not checked).

9. **Speed on video** (2026-09-10; the reading is in the session note behind
   `docs/research/ltx-2.5.md`). LTX 2.3 is not faster than 2.5: both are the same 22B
   transformer with the same eight-step distilled ladder, so the levers are elsewhere.
   Shipped: every model offers a custom size and its presets grouped by cost, a clip takes
   its picture's own shape at the budget in force, **Wan 2.2 TI2V-5B** (FastWan's
   three-step distillation, Apache-2.0) as a second, smaller video family that Animate
   picks because it is listed first, and **LTX's two-stage path** (`LTX2StagePlan`: the
   eight-step ladder at half the size, the pack's spatial upsampler doubling the latent,
   three steps at the full size) for every frame of 512 or more on the short edge that
   halves onto the grid. The mirror carries the Wan variant since 2026-09-10 and, since
   2026-09-13, the LTX-2.5 variant with the upsampler and the entry with sound
   (`ltx-2.5-distilled-audio-4bit`), both matching build 202609120813's descriptors word
   for word. A Mac that holds the earlier LTX variant rebuilds it whole (20.8 GB written,
   with the old variant still on the volume for the free-space check), or re-downloads
   the 70 GB pack if the pack was deleted; an upsampler-only top-up was not written. Left
   out, in order of value:
   - **Fewer steps on a fixed ladder**: LTX's stage two runs a subset of the distilled
     sigmas, which says the checkpoint tolerates one; a Draft choice walking five of the
     nine from noise might be worth its speed. Unknown until someone looks at the clips,
     so `stepBounds` stays `8...8` and `StepsControl` stays hidden for it.
   - **Wan's audio**: none; the model has none. **Wan's other sizes**: FastWan reports the
     model runs any size with quality falling off away from 1280 x 704 at 121 frames;
     the presets stop at the trained size and the quick ones are unmeasured for quality.
   - **A strength for Wan's first frame**: the picture is held exactly; a held-then-released
     first frame (the mask ramping over the first latent frames) is the same change as
     LTX's "more than one held frame" above.

Deferred: **ERNIE-Image-Turbo** (eight to twelve days for legible in-image text at
16 GB; the Mistral3 encoder is the new work), **Boogu-Image-0.1-Turbo** (a credible
Qwen-Image successor for 32 GB Macs, still at a few hundred downloads), and
**Z-Image-Edit** (unreleased; would share the Z-Image backend).

## First launch: left out on purpose

- **The chooser lists models, not a way to fetch several.** `resumeDownload(_:)`
  already starts a background transfer for a model that is not the selected one, so
  checking klein and LTX-2.5 and letting both land is a small change on top of what is
  here. It is left out because `ModelTransfers` runs two physical repository transfers
  at a time and the first five minutes of the app are not where a queue of them
  belongs. The way in exists today: pick one, then pick the other from the model menu.
- **No per-model "what it is good at" beyond one line.** A card carries a sentence
  from `ModelPortrait`, its download size and its memory verdict. Steps, native size,
  prompt length and whether it reads a reference are all on `ModelCapabilities` and
  none of them are shown: four more facts on a card is a spec sheet, and the decision
  a first launch actually makes is size against what runs. A "Compare models" sheet
  over `FactsTable` is the shape if it is ever wanted.
- **The sample pictures are made by hand and checked in.** `scripts/make-samples.sh`
  needs every packed variant on the Mac running it — 61 GB — so the set is regenerated
  deliberately rather than in CI, and `ModelPortraitTests` is what catches a model
  added without one. A model whose weights change under the same catalog id would keep
  a stale picture until somebody reran the script; the samples are an illustration of
  the model's hand, not a claim about a particular build. No notice is owed for them:
  three of the four families are Apache-2.0, and LTX-2.x's community license says in
  so many words that the licensor claims no rights in the output (Section 5).
- **The wait after choosing is still the bare download screen.** Pressing the button
  lands on the canvas with `CanvasStateView`'s headline, bar and Cancel — the same
  screen a mid-session download gets. The prompt capsule is live and typing into it
  works, but nothing says so, and `CanvasEmptyState`'s invitation is not shown until
  the model is ready. A line under the bar saying the prompt can be written now is the
  obvious small addition; it was left out of the chooser's change so the change stayed
  about the choice.
- **The chooser is not offered again after a model is downloaded.** `reopen()` is
  wired to the canvas's idle state alone, which is where a person who skipped or
  cancelled lands. Someone who has klein and wants to see what Qwen-Image would cost
  reads the model menu, which says it. A Settings > Models "Add a Model" gallery over
  the same cards is the obvious next home for it.
- **The recommendation is memory alone.** `ModelCatalog.default(fitting:)` takes the
  first catalog entry that runs at its default size with its weights resident — then
  the first that runs streamed, since a model read off the disk every step is how a
  Mac runs what it cannot hold rather than what it should open on — so the ordering in
  `ModelCatalog.all` is the whole of the editorial judgement. Download size, step
  count and speed do not enter it; a 48 GB Mac is recommended the 13.3 GB Z-Image
  8-bit over the 5.4 GB klein because it is listed first and fits. Whether that is
  the right first model for someone on a slow connection is a question the catalog
  order answers today and a real recommendation would not. Only the bottom of the
  range is decided on anything else: a Mac nothing fits is offered the entry with the
  smallest `leanestPeakBytes`, because there the catalog's own order named the
  heaviest model of the six.
- **No 8 GB Mac has been measured.** Every figure in the catalog was taken on a 16 GB
  M4 mini or a 48 GB M4 Max, and nothing in the catalog fits an 8 GB machine's ~6.4 GB
  working set — klein 4-bit, the leanest, wants 7.7 GB with the decode tiled. Since
  2026-09-13 such a Mac is recommended nothing and every card on it is greyed with what
  it needs, rather than pointed at the nearest entry and refused on press. Whether Zephra is usable at all on
  8 GB, at a smaller size than the default with the decode tiled, is unanswered and
  wants one measured session on the hardware.
- **The disk is not checked for room before the download starts.** `ModelTransfers`
  reserves per-volume space when the transfer begins and fails with a reason, which is
  the same behaviour every other download path has. The chooser could say "21.6 GB,
  and this volume has 12" on the card before it is pressed.

## Downloads and model storage: left out on purpose

- **The 4-bit Z-Image variant is derived from the 32.9 GB bf16 release, not from the
  13.3 GB 8-bit download.** Both entries are the same weights at different
  precisions, and a Mac that already has the 8-bit model has to fetch two and a half
  times as much again to get the smaller one. Repacking 8-bit to 4-bit would need a
  quantized-source reader in the packer: dequantize each `.scales`/`.biases` group
  back to float, repack at the new width, and carry the manifest across. It also
  compounds the error of two quantizations, which is worth measuring against a
  straight 4-bit build before shipping. The bf16 source is the honest input, and
  disk is the cost: 32.9 GB in, 7.1 GB out, and the packer spills at 4 GB resident, so
  it runs on a 16 GB Mac but wants 40 GB free.
- **`ZephraQuantize`'s refusals are exercised by hand.** The tool has no test target:
  `QuantizeOptions.parse` exits on a bad line and `main.swift` is top-level code, so the
  overlap, adapter-required and precision-name refusals are checked from a shell
  (`--out` inside `--source`, `--family qwen-image` without `--lora`) rather than by a
  suite. The checks underneath them — `SnapshotQuantizer.requireDisjoint`,
  `LoRAAdapter`'s zero-match refusal — are tested in `ZephraQuantizationTests`. A test
  target would need the parser to return errors instead of exiting.
- **A build by hand is stamped with provenance only under a catalog name.** `ZephraQuantize`
  writes `.zephra-packed-source` when `--out`'s last component is a catalog descriptor's id,
  and nothing otherwise, since there is no descriptor to describe it; a build under another
  name is still a snapshot the bench's `--snapshot` can time.
- **A build cannot be resumed.** `SnapshotBuild` writes into a `.partial` directory
  and removes it when the build is stopped, so a Qwen-Image build interrupted at
  nineteen of its twenty-one gigabytes starts over. Keeping it and skipping the
  components already written would need the manifest to be written per component
  rather than at the end, which is also what makes a half-built directory
  unmistakably incomplete today.
- **A download is one file at a time.** `ModelDownloader` walks the listing in
  order, so a fast connection is not saturated the way two or three concurrent
  transfers would saturate it. Sixteen gigabytes from the hub already runs near
  the line's limit here; the fix, if a slow link ever argues for it, is a task
  group with a small concurrency and one shared byte tally.
- **Only sizes are checked, not hashes.** The tree endpoint carries each LFS
  file's sha256 in `lfs.oid`, and a finished file is compared against the listed
  length and nothing else. A file that arrives complete but corrupt therefore
  loads and fails at the loader. Hashing sixteen gigabytes costs seconds, not
  minutes, so this is worth doing; it wants a streaming digest as the bytes are
  written rather than a second pass.
- **Changing the models folder asks: Move Models, Keep in Place, or Cancel.**
  Keep in Place remembers the last few roots (`ModelLocations.previous`), so what
  was downloaded or built under them is still found, listed and loaded, and only
  new downloads and builds go to the new folder. Move copies into staging,
  verifies byte for byte, publishes, then removes the originals, and refuses a
  collision rather than overwrite. What is still left out: merging two roots that
  both hold a copy of one model (the move refuses instead).
- **Deleting a model never asks the engine to unload it first.** Deletion goes
  through `GenerationStore.deleteModelStorage`, which refuses while the directory is
  resident, requested, or queued and closes admission while it runs; the row is
  disabled for the loaded model and choosing another model frees it. What is left
  out is a Delete that unloads on the user's behalf.
- **Sizes are measured by walking, every time the tab opens.** Twenty files per
  model makes that instant; a cache of a thousand small repositories would not be.

## Library viewer: left out on purpose

- **Zoom and pan.** The viewer fits the whole picture to the pane, the way the canvas
  does; there is no way to look closer at one part of it. A pinch or scroll-to-zoom
  gesture, with the fitted view as the reset, is the natural next step once someone
  asks for it.
- **A filmstrip of thumbnails along the bottom**, the way Photos and Preview both
  offer, instead of only the bar's "n of N" and the prev/next buttons.

## About: left out on purpose

- **A License Agreement button.** The About window has Acknowledgments and Website;
  Xcode's has License Agreement beside them. Zephra's own terms are the copyright
  line's "All rights reserved" for now, and no `LICENSE` file is bundled — the
  repository's is for the source. When terms for the app are decided, they become a
  bundled resource and a third button opening them the way Acknowledgments does.

## One window: left out on purpose

- **A second window, with state of its own.** The app is one `Window` scene: the
  pane, the query, the viewer, the selection and the canvas are all app-wide, and
  two windows sharing one pane and one canvas — which is what the old `WindowGroup`
  gave, with New Window already off the File menu — is worse than one. Making that
  state per-window means a `WorkspaceSelection` and an `ImageCache` per scene and a
  canvas that is still one `GenerationStore.current` underneath, so the second window
  would either mirror the first or need a store of its own. Do it when someone wants
  the library on one screen and the canvas on another.

## Library editing: left out on purpose

- **Dragging several pictures out at once.** A drag from the grid carries one
  image: SwiftUI's `draggable` takes one `Transferable`, and a drop of several
  files on the Finder wants an `NSFilePromiseProvider` per file from an
  `NSViewRepresentable` drag source over the cell. ⌘C over the selection and
  Share… already move several at once, which is what a batch usually wants.

- **Undo for Delete.** Favourites, tags and albums undo from the Edit menu
  (`LibraryIndex+Undo`); moving a picture to Recently Deleted does not. It already
  has thirty days of Put Back, and an undo entry that races the folder's purge, or
  a Delete Immediately made in between, would have to say what it could not do. Add
  it as a `moveToRecentlyDeleted` inverse that checks the manifest still lists the
  file, when someone reaches for ⌘Z after a delete.

## Reference picker: left out on purpose

- **Choosing more than one picture at once.** The sheet is single-selection, and
  the well takes one reference; this waits on "several reference pictures at
  once" above, which is what would give a second picture somewhere to go.
- **Scoping the grid to an album, favourites, or a model**, the way the library
  grid's own sidebar does. The sheet always searches `.all`: a picture is picked
  here by what it looks like, and the free-text search already narrows a library
  of any size well enough to be worth the simplicity of skipping the rest of
  `LibraryQuery` for now.

## Wording: left out on purpose

- **A strings catalog.** Every user-facing string is a literal in the view that shows
  it, in US spelling and macOS casing (see "Conventions" in AGENTS.md). A
  `Localizable.xcstrings` with `String(localized:)` at the hundred-odd literals is a
  day's mechanical work, and it was left until after the wording pass so the catalog
  is made once from settled strings rather than twice.

  This section used to claim the US-spelling half was already true. It was not: the
  September 2026 audit found six shipped literals in British spelling, the worst of
  them a day heading counting "6 favourites" directly under a sidebar row reading
  Favorites. `make lint-layers` enforces it now rather than the prose promising it.

## Menu shortcuts: left out on purpose

- **Two Edit menu items carry ⌘A.** `CommandGroupPlacement.pasteboard` synthesizes
  Select All, and `LibraryCommands` adds "Select All Images" after it. At most one is
  ever enabled, because the built-in is nil-targeted at `selectAll:` and disables
  itself when nothing in the responder chain implements that selector — which nothing
  under `LibraryGrid` does — so ours is the one that fires. That works, and it rests
  on SwiftUI's internal responder implementation rather than on anything we control.

  Every way out costs more than it buys, which is why the duplicate stays. A
  responder-chain `selectAll:` cannot be reached from a shim in the grid's
  `.background`: nil-targeted dispatch walks first responder, then its superviews,
  then the window, and never siblings, so getting into that chain means re-hosting
  the grid inside an `NSHostingView`. `.onKeyPress` would make the chord work while
  leaving every menu item showing it greyed, which inverts the reason the menu bar
  carries these at all. And `CommandGroup(replacing: .pasteboard)` means re-declaring
  Cut, Copy, Paste and Delete without AppKit's validation, permanently enabled and
  silently inert in every text field in the app. `ZephraCommands`' Copy Image dodges
  the same collision by taking ⇧⌘C instead, but Select All has no second chord anyone
  would look for. Revisit if a SwiftUI release ever implements `selectAll:` on its
  focusable view, at which point ⌘A over the grid stops working and nothing catches it.

- **⌘. reaches Stop Generating while the prompt has the caret**, because an
  `NSTextView` maps it to `cancelOperation:` and a menu key equivalent is matched
  first. Kept deliberately: a global Stop is worth more than cancelling field editing.
  ⌘⌫ was the same class of collision and was not acceptable, since it deleted the
  picture; see `CommandTarget.whileTyping(_:)`.

## The window's floor: left out on purpose

- **A floor that follows what is actually on screen.** `ZephraApp` sets one minimum
  for the window and it cannot see what is showing, so it is the least the window is
  *usable* at rather than the least it ever needs: 880x560, which assumes the sidebar
  and the inspector are both out and leaves the canvas pane 320 points, well under
  the 584 its prompt capsule wants laid out properly. At the floor the answer is ⌃⌘S
  or the inspector toggle, either of which hands the pane those 320 points back.

  The first attempt was the other way round — a floor built from the full
  three-column layout, 1146x690 — and it was wrong in a way worth remembering,
  because it is the same mistake the Settings window had: a minimum larger than a
  supported screen. A Mac on a larger-text scaled resolution such as 1024x640 could
  never have made the window fit, controls stranded off the edge, which is worse than
  a cramped pane. A floor is about what may be dragged to, not about what is
  comfortable, and both windows now say so in their own comments.

  A floor that actually followed the chrome would mean lifting `WorkspaceSplitView`'s
  `columns` and the inspector's visibility into state the composition root can read,
  and neither is there today. It would buy a little room back at the bottom end; it
  would not change the rule above.

## Live preview: left out on purpose

- **Latent-to-RGB factor tables.** The cheap way to show a run in progress is a 16x3
  (or 128x3) matrix that turns a latent cell straight into a pixel — no autoencoder,
  microseconds a frame, and blurry. It was not taken because the published tables are
  in GPL code (ComfyUI's `latent_preview`) and cannot be copied, so ours would have to
  be fitted: decode a few hundred latents through each family's own VAE and
  least-squares the mapping, once per family, checked in as numbers with a script
  beside them. Worth doing if the pooled decode ever proves too dear on a smaller Mac,
  or if a frame per step rather than one every 0.75 s is wanted.
- **A frame every step.** The throttle is what keeps the preview at a few percent of a
  run. Per-step frames would need the factor tables above, not a faster decode.
- **Previewing the reference-image path's first frames.** A run that starts from a
  noised copy of a picture skips the steps before its entry point, so its first frame
  is already most of the way there. Nothing is wrong with that; it is just not the
  progress bar a person expects.
- **A frame during the real decode.** The last step is deliberately not previewed: the
  full decode follows immediately, and a pooled one in front of it would be a second
  pass through the autoencoder for a picture the user is about to see properly.
- **A wall clock on the running run.** `RunningRunInspector`'s Elapsed is the steps
  that have finished at the pace they took, so it counts the loop and not the text
  encode before it, and it says nothing until the first step lands. A real clock means
  a start `Date` somewhere it survives a view being rebuilt — the store, most likely,
  which would be the first piece of interface bookkeeping in it. Not worth that for a
  line that is already right to within a step.
- **Keeping a run's frames.** Only the newest is held, and it is put down the moment
  the run ends. Scrubbing back through a run's frames, or leaving the last one up
  under the finished picture as it fades in, would mean the store keeping a strip of
  them: a quarter of a megabyte each, for something nobody has asked to look at twice.

## Dependencies: waiting on upstream

- **Bump to the first mlx-swift that tracks mlx >= 0.32.0 (mlx#3810), then delete
  klein's M5 gate.** mlx-swift up to 0.31.6 JIT-compiles the bfloat16 split-K steel
  GEMM with the wrong dtype on M5-class GPUs (mlx#3797), and klein's single-stream
  `to_out` sits inside the kernel's window. Done partway (2026-09-14): every package
  pins mlx-swift main at revision `ea8a179690170ca891a97bc0473198ab1ecda5f4`
  (carrying mlx v0.32.2) rather than a tagged release, for a different fix on the
  same bump — mlx#3810 was not the reason to move, mlx commit a025496c8 ("Catch
  error in CommandBuffer and poison the events", mlx#3523) was: a GPU reset is now
  rethrown on the calling thread instead of aborting inside Metal's completion
  handler. Two things still wait: a tagged mlx-swift release to pin by version
  instead of by revision, once one exists, and an M5 to run the probes on.
  `Flux2ActivationPrecision` in `ZephraBackendFlux2` still runs the
  stream float32 when `GPUGeneration.isM5Class`, at three times the step time — the
  gate is unverified under the new pin the same way it was under the old one: no
  project Mac is an M5. When one is available, run `Flux2Tests/TransformerParityTests`
  (both probes — the dense GEMM and the packed 4- and 8-bit `quantizedMM` (renamed
  from `quantizedMatmul` under the current pin; the vendored `ZImageKit` keeps the
  old spelling on purpose, see its `VENDORED.md`) the catalog variants take) on it
  under the current pin and then under mlx >= 0.32.0,
  and `make bench ARGS="--model flux2-klein-4b-4bit --size 1024"` with and without
  `ZEPHRA_DIT_DTYPE=f32`. Both probes green on mlx >= 0.32.0 is the signal to delete
  the gate and `GPUGeneration` with it.

## Streamed weights and the GPU limit: left out on purpose

- **A privileged helper to set `iogpu.wired_limit_mb` from Settings.** The row shows
  the command and copies it; running it wants an administrator's password and
  `SMAppService`, for a setting that hands macOS's share of RAM to the GPU. A
  person typing it at a prompt knows what they did.
- **A budget reserve.** Issue #45 proposed holding back a slice of the working set
  so the catalog's verdicts left room for the rest of the Mac. Measured against the
  figures we have, an eighth of RAM and a sixteenth both flip 16 GB verdicts that
  are correct — klein 4-bit and Z-Image 4-bit run on bender and would be greyed —
  so the reserve would cost every 16 GB Mac the models it actually runs to protect
  it from a case the live `MemoryGuard` now catches with a sentence. `MemoryBudget.bytes`
  stays Metal's `recommendedMaxWorkingSetSize`. Worth revisiting at 32 GB and above,
  and only if a panic recurs with the guard in place.
- **`.never` residency is refused, not greyed.** A model that fits only streamed,
  with Settings > Performance set to Never, is held whole by a choice rather than by
  the machine, so the pickers still offer it and the live guard refuses the load with
  the remedy that names the preference. Greying is a function of the machine alone,
  which is what keeps one model's row from meaning two different things.
- **`QwenEncoder.forwardCausal` is not streamed.** Z-Image's prompt enhancer runs the
  encoder stack once per generated token with a KV cache the stream knows nothing
  about. Zephra never enables it, so the path keeps its plain loop and stays
  non-throwing; enabling the enhancer means teaching the stream about the cache
  first, or accepting one read of the stack per token.
- **`WeightStreamMeter` records the last stream's pass only.** It is a process-wide
  slot, written at the end of every pass, so a family that streams more than one
  stack reports whichever ran last: Z-Image's gigabytes a step are its main stack's
  and not the two refiners' besides, and klein's are its single-stream blocks'. Good
  enough to tell a read-bound step from a slow GPU, which is what it is for; a
  per-stack reading would want a keyed meter and a report that names the stacks.
- **A run estimate measured at more than one size.** `MemoryGuard.runShortfall`
  scales the measured transient — the peak less the weights — linearly with pixels
  times frames from each model's own default size, which is honest at that size and
  optimistic a long way from it. A second measured size per family is what would
  replace the arithmetic with a reading. The guard also does not cover upscales:
  `GenerationStore+Upscale` runs a tiled network whose peak is set by the tile, and
  nothing about it is charged against the machine.
- **Prefetching block 0 of the next step during the decode**, a small win that needs
  a "last step" flag through the transformer; **per-block cancellation** is in, but
  the text encoder's pass still stops only at its end; a **custom `mlx_io_reader`**
  (needs `Cmlx`, which `ZephraMLX` should not import); `F_NOCACHE` on the shards or
  wiring the window, unless the bench's read rate shows the read, not the GPU, is
  what a step waits on with a built-in SSD.
- **The `mlx-flash`-style paced reader.** It meters `pread` with a token bucket so
  reads never slow the GPU's own memory traffic. MLX's four-thread reader has not
  shown the need; the bench's step time against the resident figure would.
- **A streamed step and the rest of the GPU.** On the 16 GB M4 mini a streamed
  Qwen-Image step with the app's own canvas animating over it ended in a GPU
  restart every time (2026-09-04, three launches; the placeholder is still now and
  `make lint-layers` keeps it so). Zephra can only keep its own window quiet:
  another application animating at sixty frames a second on the same 16 GB Mac may
  trip the same restart. The abort that used to follow is gone — 2026-09-14's
  device-error boundary (`InferenceRuntime.catchingDeviceErrors`, `AGENTS.md`
  under "How a generation runs") turns a discarded command buffer into
  `BackendError.deviceFailed` and cancels only the task that armed the
  boundary, rather than letting MLX end the process; a fault raised off that
  task is recorded and logged instead, not cancelled. What is still open is
  *why* a streamed step plus compositing trips
  the restart at all, which the boundary does not explain, only survives; a
  restart still costs every app sharing the GPU that minute, this one included,
  a lost run being the best case rather than a lost process. Not reproduced on
  the bench, which has no window, nor with the wired limit off, so it is the
  compositing and not the residency set. What would narrow it: the same launch on
  a 48 GB Mac, resident against streamed with the same animation, and `F_NOCACHE`
  on the shards to take sixteen gigabytes a step out of the page cache. Two
  smaller follow-ups the boundary opens rather than closes: pin mlx-swift by
  released version instead of by revision once a tagged release carries
  mlx >= 0.32 (see "Dependencies: waiting on upstream" above), and consider
  surfacing `BackendError.generationFailed`'s own reason to the log the way
  `.deviceFailed` already logs its raw Metal text, so a non-device generation
  failure is exactly as legible as a device one.
- **A GPU fault on demand.** 2026-09-14, headless 16 GB M4 mini (bender): tried a
  Debug-only hook to provoke a real GPU fault by hand and prove the device-error
  boundary against it directly. Five kernels, none of which Metal reported as a
  fault: an infinite loop (the compiler deletes it as undefined behaviour, with
  and without a store in the body), a bounded kernel of hours of hash work (ran
  nine minutes with no watchdog ending it, the app stuck inside `eval`), a read
  256 GB past a four-byte buffer (returned 0 in 0.3 s) and a write 64 TB past it
  (same). The hook was removed; the boundary is proven instead by
  `MLXDeviceErrorTests`, `DeviceFaultTests` and `CombinedRuntimeDeviceErrorTests`
  driving a real MLX error through the same handler, plus upstream mlx's own test
  of the completion-handler rethrow (mlx#3523). Worth trying next: a Mac with a
  display attached, where the display's own watchdog is what ends a hung command
  buffer headless GPUs have none of; or a fault injected at the runtime seam
  (`InferenceRuntime.catchingDeviceErrors`'s own call site) rather than through
  the GPU itself.

## Upscaler follow-ups

Left out of the first pass on purpose, each a small change to one file unless noted:

- The **wdn denoise blend** and a strength slider. The weight loader already takes a
  second state dict and a blend weight; bundle `realesr-general-wdn-x4v3` and add the
  control to the inspector.
- **Download-on-demand weights** instead of the bundled 2.4 MB, if the bundle ever
  needs to shrink. Needs an availability state and a host for a converted safetensors.
- **Lanczos 2x** instead of the exact 2x2 box mean, which is what the reference tool
  does with `--outscale`. Slightly sharper, one more code path.
- **Alpha carried through.** The network is run on RGB only and the result is written
  opaque, which loses nothing for the library's own PNGs.
- **Upscaling a multi-selection**, one after another on the inference queue.
- **A sidebar timeline entry** for an upscale, beside the runs.
- **Float16 compute** if a 2048 input is measurably slow; the switch is one cast at
  load and one on the input.
- **Row-by-row joining in `TiledDecode`** for 4096 inputs, so the peak stops growing
  with the output.
- **A bench flag**, `make bench ARGS="--upscale IMAGE"`, for the same measurements the
  models get.
- **The DIV2K training-data terms.** Real-ESRGAN's repository is BSD-3-Clause and the
  weights are taken to inherit it, but the training set's own terms were not verified.
  Check before any commercial release.

## Download follow-ups

- Persist and automatically resume background download intent across relaunch. Current
  partial files are resumable when the user selects the model again.
- More than two simultaneous repository transfers, after memory and disk measurements
  justify increasing the bound.
- Concurrent quantization: currently intentionally serialized with all inference work
  because builds and resident weights share the same large Metal allocator.
- Coalesce differing file-pattern requests for the same repository revision. Identical
  dependency sets share now; differing sets serialize until current readers finish.
- **Borrow by identity rather than by count.** `DownloadRequest.borrowers` is an
  integer, and the audit's E1 fix keeps it one by never borrowing twice (Retry on a
  resident model answers ready without touching the pool; a load that reaches a lease
  the store holds reuses it; `unloadModel` asserts the request is gone after its one
  release). The fuller change is `borrowedBy: UUID?` (the load identity), `acquire`
  refusing a second borrow rather than counting it, and `release` requiring the
  matching identity. `RepositoryTransfer.owners` and `ModelTransfers.claims` would
  stay: they are per physical part and per claim, not the foreground borrow, and
  folding the three together would move `ModelTransfers` bookkeeping onto the main
  actor. Not worth it for a defect the invariant now catches in Debug.
- **A mock backend that really fetches through its acquisition.** `MockBackend`
  records the `TransferAcquisition` id it is handed and never calls `fetch`, because
  the engine test target has no stub hub (`StubHub` lives in `ZephraSnapshotTests`).
  A `fetchesThroughAcquisition` dial that does call it would let the claim accounting
  be tested end to end with the real `ModelTransfers.fetch`; it needs `StubHub`
  moved into `ZephraTestSupport` first. None of the current engine tests need it.

## Image library location: left out on purpose

- **Merging existing libraries.** Folder migration
  refuses destinations containing images or album/deletion metadata. A merge
  needs explicit choices for duplicate pictures, album identities, and deletion dates.
  For now, move into an empty folder, or keep both libraries in place and switch
  between their folders in Settings.

## The phone's viewer: left out on purpose

- **Paging past a zoomed picture's edge is UIKit's.** Dragging a zoomed
  picture past its edge chains the pan to the pager, which is what Photos
  does; nothing here decides it, so nothing here tunes it.

## The companion link: left out on purpose

- **A bulk lane beside the interactive one on a relay road.** `RelayCadence`
  paces every slice a road writes at 120 messages a second, because the account's
  throttle is 500 a second shared by every invocation and a picture's six hundred
  slices written back to back arrive as a burst whose tail is refused. One
  ordered lane is what the channel's counter is: frames are sealed in the order
  they are queued, so a delta sealed behind a clip's chunks waits behind all of
  them — up to about 21 seconds for a 40 MB clip. Splitting transfers onto a lane
  of their own means a second channel with a counter of its own, a second
  `OrderedInbox`, and a rule for which lane each message kind rides; the relay's
  `send` would have to carry a lane id, which is the Lambda's contract and the
  same change as guest ids. Worth it the day somebody watches a clip cross and
  minds that the queue on screen is stale while it does. On the local network
  nothing is paced.

- **Eight phones in one relay room.** `RelayListener` serves several phones now —
  the relay writes `from` on every frame it hands a host and the host writes `to`
  on every frame it sends, and `RelayListener+Guests` keeps a session per id — but
  `MAX_GUESTS` in the Lambda caps a room at eight. The slots are one string set on
  the host's row, claimed by a conditional `ADD` under a `size` check, so lifting
  the cap is a row that grows rather than a contract that changes; eight is a
  household's phones and a bound on the fan-out a host leaving has to write. The
  local network has no cap at all.
- **Sixteen phones on the relay allow-list.** The host's `join` carries the
  signing keys the relay admits a guest out of, and `RelayJoin.allowLimit` is 16:
  a longer list is `bad allow` and closes the connection, so
  `CompanionHost.relayAllowList` sends the sixteen seen most recently and trims
  the rest. A Mac with more paired phones than that still reaches every one of
  them on the local network, and any of them over the relay as soon as it is in
  the sixteen. Lifting it means a paged or hashed set in the relay's own
  contract, which is the Lambda's to change and not worth it for a limit no
  household meets.
- **A revoked phone keeps a relay slot it already holds.** The allow-list governs
  future joins only, so `CompanionHost.revoke` closes that guest's session itself
  with `revoked`, which is what it has always done. Evicting from the relay's side
  as well means a message that names a guest, which the contract has no room for
  until guests have ids at all — the same change as several guests above.
- **A phone revoked while it was away keeps trying, over the relay.** The relay's
  `not allowed` on a reconnect is `LinkClientError.notAdmitted` now — a wait, not
  a revocation — because that list is the Mac's and a Mac that has just restarted
  is a beat behind it, and a phone that forgot its Mac over that needed a new code
  for a pairing nobody withdrew. The cost is the other way round: a phone revoked
  while it was not connected, and which can only reach its Mac through the relay,
  retries on `LinkBackoff` and is never told. A phone that was connected is told
  at once (`CompanionHost.revoke` closes that session with `revoked`), and one on
  the same network learns it from the Mac's own handshake on the next attempt.
  Telling the other case means a refusal the relay can state about this device
  without becoming an oracle for anybody who knows a room id — the same shape as
  the "this room has never existed" answer the phone would like for a Mac whose
  identity changed.
- **A phone cannot start a download.** `Command` has no case for one and
  `CompanionHost` refuses anything it does not know. Fetching a model is
  gigabytes onto somebody else's Mac, over their network, and the person holding
  the phone is not always the person paying for either. The phone watches
  transfers (`DownloadDTO`) and that is all. If it is ever offered it wants a
  confirmation on the Mac, not on the phone.
- **A paired device cannot be renamed on the Mac.** The name in the list is the
  phone's own, out of its `Hello`. A list whose names could be edited here is a
  list nobody could match to a phone in a drawer, and the phone already has a
  field for it.
- **No notification when a phone connects.** `BackgroundNotices` is about a run
  and a download, which are things a person walked away from; a session opening
  is not. A Mac that announced every reconnection would announce one every two
  hours, which is what the relay's connection lifetime makes of a phone left on a
  desk.
- **The phone is woken by the session ending, not by the state that says so.**
  `LinkReconnect` awaits `LinkClient.sessionEndings()`, which every way a session
  ends yields on, so a dead road is reconnected to at once. What is left is the
  fallback: where that stream has finished it asks `LinkClient.connection` every
  couple of seconds, because the sequence that would wake a task on an
  observation (`Observations`) is iOS 26 and the target is 18. One enum read on
  the main actor while the app is in front, so the cost is nothing; the day the
  floor moves, both the wait and the fallback are one `for await` over the state.
- **`RelayRoad`'s ending of a dead join's guests has no suite.** `RelayListener`
  ending the guest its own road carried is pinned in `ZephraLinkTransportTests`
  against the in-process relay; the same rule one level up, in the app target,
  would need that relay fixture inside the test host, and the host is where a
  socket left open is worst. Worth doing the day `Tests/ZephraTests` grows a road
  fixture of its own.
- **`MobileKeychain` has no suite.** A keychain item needs an access group, and a
  unit-test bundle hosted in the simulator's app has none, so every call answers
  `errSecMissingEntitlement` and a suite over it would be a suite over that. It
  is exercised by running the app and pairing. A device test target with an
  entitlement would pin it properly.
- **The library pull reads the whole folder, not what changed.** A pull that is
  interrupted carries on across a resync now, and a new session still asks for
  every page from nothing — a few dozen round trips for a library of a few
  thousand, most of them entries the phone already holds and can tell are
  unchanged (`CachedEntry.isStale(against:)`). The fix is a `modifiedAfter`
  cursor on `Command.libraryPage`: the phone sends the newest
  `contentModifiedAt` it holds and the Mac answers only what moved since, with
  the count still saying whether anything was removed. It is a wire change on
  both ends, so it waits for a library big enough to be worth one.
- **The phone dials every road on every attempt.** `LocalRoadRace` gives the
  local network `lanWindow` (3 s) before the relay is tried, on every reconnect,
  which away from home is three seconds of nothing before the road that was
  always going to work. Remembering the road the last session was on — and
  trying that one first, with the rest behind it — would take most of that back.
  What it must not become is a phone that has moved and keeps dialling the road
  it used at home, so the memory has to be beaten by a `LinkPathMark` that says
  the network is a different one.
- **The phone's cache is not built.** `CacheRow` in Settings says so in as many
  words. It is one file, so whoever builds the library's cache replaces it rather
  than editing a settings screen around it.
- **The Mac's local road is not re-opened when the network changes.**
  `TCPListener` keeps its port across a Wi-Fi change, and Bonjour re-advertises;
  what goes stale is the address list inside a pairing code already on screen.
  Since a code lasts two minutes, showing it again is the whole remedy. The
  phone watches `NWPathMonitor` itself now (`LinkPathWatch`); doing the same on
  the Mac, to re-open the road, is a real improvement only once somebody reports
  a Mac that stopped answering after moving networks.
- **Nothing on the phone saves a picture to the camera roll.** `Photos` is
  linked and the fetched bytes are in hand, so it is a menu item and a
  permission string, but the canvas has no such menu yet; it belongs with the
  library surface's own share and export, not beside the capsule.

## Updates: left out on purpose

The updater is in AGENTS.md under "Updates"; the reasoning is in
`docs/build-and-release.md`. What it deliberately does not do:

- **Delta updates.** Every update is the whole disk image, a few hundred
  megabytes. A binary diff needs a patch published beside each release, a
  patcher, and a fallback when the local bytes are not what the patch expects —
  and the saving is invisible next to a thirteen-gigabyte model download the
  same Mac has already made.
- **Fetching before the click.** A release found by the six-hourly check sits on
  the banner and nothing is fetched. Downloading it in the background would make
  Update Now instant, and would also spend a few hundred megabytes of somebody's
  connection for a button they may never press.
- **Sparkle.** The reasons are in `docs/build-and-release.md`; the day delta
  updates or a privileged install are wanted, Sparkle is the answer and this is
  a week's work to replace.
- **A persisted skip.** Later hides a release for the session. With every build
  at `0.1.0` a skip written to disk is either useless (the next build is a
  different stamp) or too strong (a Mac that has quietly stopped updating). The
  General toggle is the honest way to switch checks off.
- **`AuthorizationExecuteWithPrivileges` for a read-only `/Applications`.** A
  managed Mac is answered with the drag-it-yourself sentence and Show in Finder
  on the verified disk image. A privileged install is a helper tool, an
  authorization right and a second signing story, for a case where the user is
  not allowed to install software anyway.
- **`notes` and `minimumSystemVersion` in the manifest.** Release notes would
  want somewhere to write them per build and a view to show them; a minimum
  system version would want the publish script to read the deployment target and
  the app to refuse an update it cannot run. Both are additive fields the reader
  ignores today (`ReleaseManifest` decodes what it names and no more), so
  neither is a migration when they arrive.
- **Resuming a stopped download.** `UpdateDownload` starts the file over, up to
  `DownloadRetry.attempts` times. A release is one file and a minute, and a
  `Range` request against a mutable CDN object is the correctness problem
  `ModelDownloader` needed `ETag` and `If-Range` to solve — worth it for
  thirteen gigabytes of shards, not for this.
- **A signature over the manifest itself.** The manifest is served over HTTPS
  from the bucket only a release can write, and nothing in it is trusted: the
  image is checked against the published SHA-256, then `codesign`, then `spctl`,
  then the team identifier, then the `Info.plist`'s own build. A forged manifest
  can at most point at a Zephra Apple notarized and we signed. Signing it would
  add a key to keep, and would defend the step that is already the most checked.

## Multi-host iOS companion

Implemented architecture and validation are in
[Multi-host companion](docs/multi-host.md), with design history in
[the multi-host plan](docs/plans/multi-host-ios.md). The companion combines
host-owned libraries and supports explicit destinations plus Auto selection
using model readiness, workload and host capability.

Deferred beyond that release: automatic model downloads/builds for Auto, batch
splitting, moving accepted jobs between hosts, library replication/content
deduplication, cross-host versions of source-local edit operations, and
unattended dispatch while the phone is in the background. These require their
own ownership, resource and recovery policies; pairing multiple Macs does not
imply them.
