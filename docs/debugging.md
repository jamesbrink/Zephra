# Debugging hooks

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

## Debugging hooks

Every `ZEPHRA_*` switch below that the inference path honours — the VAE tile, the stream
depth, the DiT dtype, the preview interval, the residency override, and the three memory
limits — is read **once at launch**, into `InferenceEnvironment` (`ZephraCore/Runtime`), by
the composition root (`ZephraApp.swift`) or by `ZephraBench/main.swift`, and handed down as a
value: the kits take what they need on their requests, the backends hold the rest as instance
state, and nothing below the root reads `ProcessInfo`. Changing a variable after launch
changes nothing. (`ZephraQuantize` honours none of them, so it reads nothing.)
`ZEPHRA_WEIGHT_RESIDENCY` reaches the Performance tab's picker the same way: the root hands
`InferenceEnvironment.weightResidency` down as the `\.weightResidencyOverride` environment
value, and `AppSettings.residencyPolicy(mode:budget:override:)` is pure, so the picker applies
the same override the store runs under without a second read of the process environment.

- `ZEPHRA_PREVIEW_STATE=ready|image|editing|tucked|clip|generating|starting|queued|watching|finishing|batch|library|viewer|picker|welcome|downloading|building|failed`
  launches a Debug build frozen in that state with no model, for screenshots (`make screenshot`).
  `tucked` is `image` with the canvas's floating prompt slid down to its lip.
  `welcome` opens the first-launch model chooser over a frozen engine, whatever this Mac's
  preferences say (`InterfacePreview.wantsWelcome`, read by `WelcomeGate` in `init`, since the
  chooser has to be up before the first frame rather than raised after it).
  `viewer` opens the library pane on its first image full size; `picker` runs the
  `editing` build with the reference picker sheet forced open, through
  `InterfacePreview.wantsReferencePicker` — the one flag the well reads on its own,
  since a `@State` local to a view cannot be set from the composition root the way
  `workspace.viewing` can.
  `clip` stands the store up on `PreviewModel.video` — an invented model that makes clips
  and reads a picture, for the well, the length control and the strength slider — with the
  well filled and the canvas showing `PreviewImages.sample(frames:modelID:)` stamped with
  the catalog's own `ModelCatalog.ltx2Distilled4bit` rather than the invented model: the
  inspector's `ReferenceRole` reads the *record's* model, and an id the catalog does not
  carry would fall back to `.reference` ("Edited from") instead of "First frame". `frames`
  past 1 is what makes `GeneratedImage.isVideo` true; there is no drawn MP4 behind it, only
  a poster, so the canvas shows the picture rather than `ClipPlayerView` — the same as a
  real clip before its file has landed, and legible enough for the well's caption and the
  inspector's "First frame" row.
  `generating`, `queued` and `watching` all stand a run up with a made-up frame from it, so
  the live preview is on screen without a model: the first two are following the run, and
  `watching` is the one that is not — the model working while an earlier picture stays on the
  canvas, which is what the running card's ring being off says. `starting` is the same run at
  its first step with no frame yet, which is where `RunPlaceholderView` shows. `finishing` is
  a clip run after its last step, the latents being developed: the bar full and
  `FinishingNote` over the frame.
  `downloading` and `failed` sit over a picture, since that is where they must stay
  legible, and `failed` is a download that gave up.
- `ZEPHRA_FRESH_START=<directory>` launches the app as a Mac that has never run it: its
  preferences go to a suite of their own, its models folder is `<directory>/Models` and its
  library `<directory>/Images`, and the single-instance guard lets it run beside a real
  Zephra. `make run-fresh` is the way in; `FreshStart` in `Support/` is the whole of it.
- Debug only: `ZEPHRA_DOWNLOAD_TEST_HUB=http://127.0.0.1:<port>` uses the real
  downloader and UI with an unloaded exercise backend for disposable HTTP fixtures.
  Use a separate bundle identifier/preferences domain and models folder. No such hook
  exists in Release; ordinary Debug launches still use real backends.
- `ZEPHRA_PREVIEW_STATE=settings` freezes the engine but uses a live library index
  at the configured `imagesDirectory`, for native folder-change UAT with temporary fixtures.
- `make logs` streams `os.Logger` output for subsystem `io.zephra`.
- `make screenshot` photographs the app's window by its CoreGraphics id, so it captures the
  window rather than the rectangle of screen it sits in, and it fails rather than falling back
  when there is no window: a region or full-screen grab returns whatever is in front of Zephra,
  which on a shared machine means somebody else's windows end up in `out/`. With no argument
  it takes the largest window; `make screenshot WINDOW=General` takes the one titled
  "General" — the Settings window is titled after its tab — through the optional title
  argument of `scripts/window-id.swift`.
- `swift scripts/ax-press.swift "<title>" [role]` presses the control with that `AXTitle` or
  `AXDescription` in the running Zephra through the accessibility tree, without activating the
  app, moving the mouse, or posting an event, so it can open Settings > Models or click a
  button while a person keeps working; `--dump [depth]` prints the tree for finding titles.
  The terminal needs Accessibility in System Settings > Privacy & Security. Together with the
  background launch (`open -g --env ZEPHRA_PREVIEW_STATE=settings build/Debug/Zephra.app`)
  and the titled screenshot, this is how a Settings tab is photographed hands-off; the tab
  strip's controls are `AXButton`s titled after their tab, so `ax-press.swift Performance`
  switches tabs. Menu items are controls too (`ax-press.swift "About Zephra"
  AXMenuItem` runs the item without opening the menu), and with a person's Zephra up beside
  the preview launch, `ZEPHRA_PID=<pid>` says which copy to drive; the titled screenshot
  needs no such hint, since only the preview copy has that window. The one `Window` scene is presented on every launch
  (`.defaultLaunchBehavior(.presented)`), so a session that quit with the window closed no
  longer comes back without one; `--args -ApplePersistenceIgnoreState YES` on the launch is
  still the way to drop the last session's window frame and pane.
- `make bench ARGS="--size 1024 --steps 9 --runs 3 --json"` measures load, s/step, and peak memory
  headlessly; benchmark on an idle machine, Release only. `--reference IMAGE` measures the
  editing path on a model that has one.
- `make bench ARGS="--reference /path/to/reference.png --strength 0.6"` adds the strength, on a
  model that starts from a noised copy; the report says which step the loop began at and how
  many steps actually ran, so a run that took a third of the seconds is not mistaken for a
  model that got three times faster.
- `make bench ARGS="--micro --size 1024"` times the DiT's individual MLX kernels at that size's
  token count without loading any weights, so a slow generation can be attributed to a primitive
  rather than guessed at.
- `make bench ARGS="--preview --size 1024"` turns the live preview frames on for the run and
  reports how many were made and the mean milliseconds one took, and writes the last frame
  beside the image as `<stem>.preview.png` — a frame unpacked on the wrong axis is noise of
  exactly the right size, so it wants looking at and not only timing. Frames are off in the
  benchmark otherwise, so a step time measured without the flag is the model's own and stays
  comparable with the figures already recorded here. `ZEPHRA_PREVIEW_INTERVAL_MS` is the switch
  underneath: milliseconds between frames, and 0 switches them off, which is what the benchmark
  does to its own `InferenceEnvironment` without the flag. Measured at 1024 pixels on an M4 Max, mean over the frames of one run: 43 ms for klein
  4-bit, 130 ms for Qwen-Image 4-bit, 192 ms for Z-Image 8-bit, against 0.5 to 8 s for the same
  models' full decodes (`BENCHMARKS.md`; the last two were taken on a busy machine).
- `make bench ARGS="--model ltx-2.5-distilled-4bit --size 768x512 --frames 49"` measures a
  clip: `--size` takes `WxH` as well as one number, `--frames` is rounded down to the model's
  ladder and ignored by a picture model, and the clip is written to `--out` with its extension
  changed to `.mp4` and its first frame as a PNG beside it (`BenchRunner+Output`). The report
  carries the frame count; `--stream` works as for Qwen-Image, and `--micro` still refuses
  every family but Z-Image.
- `ZEPHRA_PROFILE_STEP=1` prints per-phase timings (text encode, per-step graph build, per-step
  eval, VAE decode, and Z-Image's preview decode) and MLX's active and peak allocation to stderr.
- Precision and padding switches, for bisecting a suspected regression without a rebuild:
  `ZEPHRA_DIT_DTYPE=f32` runs the transformer in float32 (and `bf16` runs klein's in bfloat16
  on an M5, over its device gate), `ZEPHRA_PAD_PROMPT=full` pads prompts to
  the 512-token limit, `ZEPHRA_KEEP_CACHE=1` stops handing MLX's scratch back after a generation,
  and `ZEPHRA_CACHE_LIMIT_MB=N` overrides the benchmark's MLX cache ceiling.
- `ZEPHRA_VIDEO_STAGES=1|2` forces LTX-2.5 to one stage or two for the launch, whatever
  `LTX2StagePlan` would say for the size, so a one-stage and a two-stage clip of the same
  frame can be measured against each other; a size that cannot be halved onto the grid
  still runs one stage.
- `ZEPHRA_VAE_TILE=<latent tile edge>` decodes the VAE in overlapping tiles and blends the seams,
  so the decode's peak is set by the tile rather than by the image (Wan 2.2's autoencoder
  reads the same edge in its own 16-pixel cells, so 64 is 512 pixels there too). 64 gives 512-pixel tiles and
  takes the 1024-pixel peak from 23.5 GB to 17.7 GB for a mean absolute pixel difference of 1 of
  255. `ZephraBench` sets it on the running family's runtime handle, so it is the tile the
  benchmark decodes at. In the app it only decides what the Performance tab reads before the
  first run: Settings > Performance holds a three-way preference (`AppSettings.vaeTiling`),
  the store keeps it as `vaeTilingPolicy`, and `InferenceActor` sets the tile through
  `InferenceRuntime.setVAETileSize` on its own queue as each run (and each warm-up) starts, for
  that run's own model — tiling under Automatic when that model's `peakBytes` is over what
  the GPU may keep resident (`MemoryBudget`). The handle writes the family's `VAETileSetting`,
  one locked slot per backend package that the backend reads as it builds the run's request
  and the kit takes as `decode(_:tile:)`; there is no static in any kit for it. A model
  chosen mid-run therefore never changes the running run's decode.
- `ZEPHRA_WEIGHT_RESIDENCY=streamed|resident` overrides the Performance tab's streaming
  preference for one launch, and `ZEPHRA_STREAM_DEPTH=N` says how many blocks a streamed load
  reads ahead (2 unless set; the backend hands it to `QwenImageStreaming(depth:)` or
  `LTX2Streaming(depth:)` at load).
  `make bench ARGS="--model qwen-image-2512-4bit --stream"` is the same with the report saying
  what one step read and how fast; `--stream-depth N` sweeps the window. A model whose family
  cannot stream loads resident whatever either says.
- `ZEPHRA_GENERATE_ON_LAUNCH=<prompt>` (Debug builds only; in Release it is inert, the same
  rule `ZEPHRA_PREVIEW_STATE` follows and for the same reason — a shipped, signed Zephra has no
  business starting a generation unattended because a stray variable happened to be set)
  presses Generate with that prompt and the saved settings
  as soon as the model is ready: one real generation in the app itself, window and all, from a
  shell on a Mac nobody is sitting at. The bench measures the model without the window; a
  failure that needs the window on screen, as the GPU reset above did, needs this instead.
  `ZEPHRA_REFERENCE_ON_LAUNCH=<path>` puts that picture in the well first, through
  `adoptReference` as a drop would, and Generate waits for it to land, so with LTX-2.5 chosen
  the pair is an image-to-video run from a shell; alone it does nothing.
  `ZEPHRA_WIRED_LIMIT_MB=N` overrides the wired limit the app sets from the working set for
  that launch (0 switches wiring off), and the bench reads the same variable together with
  `ZEPHRA_MEMORY_LIMIT_MB=N`, so a run in the app can be replayed headlessly under its limits.
  Every `_MB` here is `MemoryUnits.mebibyte`, the same 2^20 the Performance tab's preference
  is stored in.
  Launch the app from a shell (`./build/Release/Zephra.app/Contents/MacOS/Zephra`) rather
  than with `open` when the point is the error text: MLX prints the Metal error it dies of
  to stderr, and the crash report carries only `abort() called`. The kernel's side of a GPU
  restart is in `log show` under `IOGPUFamily`, and the reports under
  `/Library/Logs/DiagnosticReports/gpuEvent-*.ips` say which process the firmware blamed.
