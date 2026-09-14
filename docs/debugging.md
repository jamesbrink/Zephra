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

- `ZEPHRA_PREVIEW_STATE=ready|image|editing|tucked|clip|generating|starting|queued|watching|finishing|batch|library|viewer|picker|welcome|downloading|building|update|failed`
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
  legible, and `failed` is a download that gave up. `update` sits over a picture for the same
  reason: the banner is a strip across the top of the window, and a window with nothing in it
  says nothing about how the strip reads over the panes. Its checker is
  `UpdateChecker.frozen(.available(...))` — a made-up release, no timer, no feed, and
  `UpdateChecker.start()` returns before anything else while a preview state is set, so a
  screenshot build never reaches the update server any more than it opens a link road.
- `ZEPHRA_FRESH_START=<directory>` launches the app as a Mac that has never run it: its
  preferences go to a suite of their own, its models folder is `<directory>/Models` and its
  library `<directory>/Images`, and the single-instance guard lets it run beside a real
  Zephra. `make run-fresh` is the way in; `FreshStart` in `Support/` is the whole of it.

  The suite is **one per directory**, `io.zephra.Zephra.fresh.<fingerprint of the path>`
  (FNV-1a over the standardized path, written out because Swift's own hashing is seeded per
  process and a domain named from it would be a new domain at every launch). It was one name
  for every fresh start until two of them ran at once — a screenshot build beside a UAT one,
  two agents, a second directory launched by hand — and the second launch opened on the
  first's answers: chooser already answered, model already chosen, and on the day it happened
  that "new Mac" began downloading a model nobody had picked. Which directory a launch uses is
  what a fresh start is, so the directory names the preferences.

  The reset stays the shell's `rm -rf` of the directory, and the domain follows it through a
  stamp: `.zephra-fresh-preferences` inside the directory, written the first time that
  directory's preferences are opened. No stamp means nobody has launched here since the folder
  was made, so `FreshStart.preferences()` empties the domain before a single preference is
  read; a stamp means `FRESH_RESET=0`, the session resumed without fetching gigabytes again.
  Launching by hand therefore needs no `defaults delete` at all — a new directory is a new Mac
  on its own.
- `ZEPHRA_UPDATE_FEED=<url>` and `ZEPHRA_UPDATE_BUILD=<stamp>` are the updater's two hooks,
  read once at the composition root into `UpdateEnvironment` and handed down as a value, the
  way `InferenceEnvironment` is. The first points the check at another manifest; the second
  makes this build claim to be an older one, so a published release reads as newer without a
  ship being made for the test. Both are `#if DEBUG` inside `UpdateEnvironment.current`, for
  the reason `ZEPHRA_PREVIEW_STATE` is: a shipped, signed Zephra has no business fetching its
  next version from wherever an environment variable happens to point.

  Either one set also lifts one rule — `UpdateEligibility`'s "must be in `/Applications`" —
  because the hand run is exactly a Debug build in `build/Debug` pointed at a local feed. The
  other two rules stand: a translocated copy is still refused, and so is a build whose number
  is not a twelve-digit stamp, which is every ordinary Debug build. So the hand run needs
  both hooks, not just the feed:

  ```
  make build CONFIG=Debug
  ditto build/Debug/Zephra.app /tmp/zephra-update/Zephra.app   # a copy to sacrifice
  ( cd /tmp/feed && python3 -m http.server 8000 )              # holding releases/latest.json
  open -n --env ZEPHRA_UPDATE_FEED=http://127.0.0.1:8000/releases/latest.json \
          --env ZEPHRA_UPDATE_BUILD=202601010000 /tmp/zephra-update/Zephra.app
  ```

  The manifest's `url` points at a DMG the same server holds and its `sha256` is that file's;
  the installer refuses anything else long before it copies. A locally signed copy is refused
  at `spctl` — that is the check doing its job — so the swap itself is only ever exercised
  end to end against a notarized build.
- Debug only: `ZEPHRA_DOWNLOAD_TEST_HUB=http://127.0.0.1:<port>` uses the real
  downloader and UI with an unloaded exercise backend for disposable HTTP fixtures.
  Use a separate bundle identifier/preferences domain and models folder. No such hook
  exists in Release; ordinary Debug launches still use real backends.
- `ZEPHRA_PREVIEW_STATE=settings` freezes the engine but uses a live library index
  at the configured `imagesDirectory`, for native folder-change UAT with temporary fixtures.
- The phone has the same switch and a shorter list. `make run-ios PREVIEW=<state>` hands it to
  the simulator as `SIMCTL_CHILD_ZEPHRA_PREVIEW_STATE`, and `MobilePreviewState` is
  `pairing`, `ready`, `generating`, `capsule`, `library`, `viewer`, `today`, `offline` and
  `settings`: the Mac's list is longer because the Mac has an engine to freeze, while here
  there are only two axes — which surface is up, and whether the wire is live. Every state but
  `pairing` is a `LinkClient.frozen` over two JSON fixtures, with no road under it, so nothing
  reconnects behind a screenshot and the catalog writes nothing. `docs/mobile.md` has the
  rest. A frozen *Mac* build opens no road either: `startCompanion` refuses while
  `InterfacePreview.requestedState` is set.
- `ZEPHRA_FORCE_RELAY=1` shuts every road on the phone but the relay, so a simulator sitting on
  the Mac's own Wi-Fi pairs and connects the way a phone in another country does: the browse
  finishes empty and every LAN endpoint fails, and `connect()` and `pair(with:)` walk their list
  down to `connectRelay`. `make run-ios FORCE_RELAY=1` hands it over as
  `SIMCTL_CHILD_ZEPHRA_FORCE_RELAY`. `RelayOnlyRoads` reads it once at launch, Debug only, and
  Settings says "Live through relay" when it worked. The Mac needs its relay switch on as well
  (Settings > Companion), or there is no host in the room to reach.
- `make logs` streams `os.Logger` output for subsystem `io.zephra`, which is where the
  device-error boundary's "MLX device error: …" line lands (or "MLX error outside any run: …"
  for a fault no boundary was open for) — the only trace of a GPU fault the boundary caught,
  since it never reaches a crash report. `make logs` runs under make's own `/bin/sh`, so
  nothing there shadows the `log` binary; see "Diagnosing a GPU fault by hand" below for the
  hand-typed form, where a shell's own `log` function does shadow it.
- A locally built Zephra — every `make run`, `make build` and any other ad-hoc
  signature — keeps its companion identity and pairings in
  `~/Library/Application Support/Zephra/Companion/` (`identity` and
  `devices.json`), never in a keychain, because the login keychain identifies an
  app by its signature and a local build has a new one every time it is built:
  the old arrangement asked for the keychain password at launch and on every
  pairing write, and "Always Allow" lasted until the next rebuild. Delete that
  folder to forget every phone and pair again; the log line at launch names which
  store is in use. A `ZEPHRA_FRESH_START` launch keeps its own under
  `<directory>/Companion`.
- A **signed** build (Developer ID, so a stable designated requirement) still
  keeps them in the keychain under `io.zephra.link`, and touches it at most once a
  launch. Clear it with
  `security delete-generic-password -s io.zephra.link -a identity` and the same
  for `-a devices`, then pair again.
- `make screenshot` photographs the app's window by its CoreGraphics id, so it captures the
  window rather than the rectangle of screen it sits in, and it fails rather than falling back
  when there is no window: a region or full-screen grab returns whatever is in front of Zephra,
  which on a shared machine means somebody else's windows end up in `out/`. With no argument
  it takes the largest window; `make screenshot WINDOW=General` takes the one titled
  "General" — the Settings window is titled after its tab — through the optional title
  argument of `scripts/window-id.swift`. `make screenshot-ios` is the simulator's equivalent;
  it captures into a temporary directory and copies into `build/` afterwards, because `simctl`
  is refused a write onto the external volume this repository lives on.
- `swift scripts/ax-press.swift "<title>" [role]` presses the control with that `AXTitle` or
  `AXDescription` in the running Zephra through the accessibility tree, without activating the
  app, moving the mouse, or posting an event, so it can open Settings > Models or click a
  button while a person keeps working; a `Toggle` or static text in a SwiftUI `Form` that
  carries neither of its own matches through the label linked by `AXTitleUIElement` or
  `AXServesAsTitleForUIElements` instead. `--dump [depth]` prints the tree for finding titles,
  with that linked label alongside where the control has one.
  The same script also sizes and places the window for a screenshot without activating
  it: `--resize W H`, `--move X Y`, and `--reveal "<title>"`, which performs
  `AXScrollToVisible` on a control found the way `--press` finds one — the first-launch
  chooser's greyed cards sort last and are otherwise below the fold at the sizes worth
  photographing. `make screenshot` shoots the window by its CoreGraphics id, so the
  window has to already be the size the picture is meant to show, and a drag or a
  keyboard chord takes the focus off whoever is at the keyboard. Two things a window can
  do to a resize are reported rather than hidden: a tiled or zoomed window keeps its own
  frame whatever is written, and an AX size counts the title bar, so the app's 880 x 560
  content floor reads back as 880 x 592. The command says what the window settled at
  either way, since a screenshot of a window that quietly ignored the size is worse than
  no screenshot.
  `swift scripts/ax-type.swift "<label>" "<text>"` is its sibling for a field: it sets the
  value of the text field with that accessibility label and performs `AXConfirm`, what Return
  does in it, which is how the Size menu's "Custom size" field is typed into hands-off.
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
- `make bench ARGS="--extend CLIP.mp4 [--context N]"` measures carrying a clip on the way the
  app's Extend Clip does: the clip's last frames (`--context` of them, else the model's own
  default — 17 on LTX-2.5, 1 on Wan 2.2) are read and held at the head of every timed run,
  `--strength` defaults to the model's own default for an extended run rather than the plain
  editing default, the report says `extended` with the frames held, and the run is written
  joined onto the source clip as `<stem>-extended.mp4` beside `--out` so the seam can be
  looked at.
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
  what one step read and how fast; `--stream-depth N` sweeps the window. Every family takes
  it — `ZImageStreaming`, `Flux2Streaming` and `WanStreaming` beside those two — and a family
  with no measured streamed figure would load resident whatever either says, which nothing in
  the catalog is any more. The report is `WeightStreamMeter`'s last pass, so a family that
  streams more than one stack reports the last one its forward ran: Z-Image's main stack, and
  klein's single-stream blocks.
- `ZEPHRA_FAULT_GPU_AT_STEP=N` (Debug only) trips a real GPU restart
  at step `N` of a Z-Image generation — the only family wired to it —
  through `GPUFaultProbe`, an `MLXFast.metalKernel` that reads 256 GB past a
  four-byte buffer, an address no page table maps, so the GPU takes an MMU
  fault (the field crash's own "MMU interrupt") and the driver resets the
  device. Not a kernel that never finishes: the Metal compiler deletes an
  infinite loop as undefined behaviour, and an M4 mini ran a bounded
  hours-long kernel for nine minutes with no watchdog ending it, the app
  stuck inside `eval`. The probe logs "GPU fault probe firing" and "returned
  after N s" under category `fault-probe`. Exactly the kind of reset
  a fault in another app's frame leaves Zephra's own buffer discarded by, as
  the innocent victim. Read once into `InferenceEnvironment.faultGPUAtStep`;
  never reachable in Release, and wired to no UI, so the only way to reach it
  is the shell. The one call site fires from `ZImageBackend.generate`'s own
  progress handler, and the one-step warm-up run
  (`InferenceActor+Preparation.warmUp`) calls that same `generate`, so a
  target of step 0 faults the warm-up rather than the run a launch means to
  probe.

  **Diagnosing a GPU fault by hand.** Save any open work; a real GPU restart
  can cost every app's unsaved state, not only Zephra's. On an idle Mac, after
  `make build CONFIG=Debug`, and with the saved model a Z-Image entry — the
  probe's one call site is `ZImageBackend`, so any other model's run
  completes and proves nothing:

  ```
  ZEPHRA_FAULT_GPU_AT_STEP=4 ZEPHRA_GENERATE_ON_LAUNCH="a lighthouse" \
    ./build/Debug/Zephra.app/Contents/MacOS/Zephra
  ```

  Expect, in order: the canvas showing "The GPU stopped responding and this
  run was lost. Try again.", the app still running (no crash report), Try
  Again producing a picture once the device has recovered, and a
  `gpuEvent-*.ips` in `/Library/Logs/DiagnosticReports/` naming Zephra as one
  of the processes the firmware blamed — the probe cost every app sharing the
  GPU that moment, this process included, which is the scenario the fix is
  for. `/usr/bin/log show --info` (spelled with the full path where a shell's
  own `log` function shadows the binary) carries Zephra's own line, "MLX
  device error: …", with the raw Metal text; that is the field crash's whole
  story with none of it hidden in a completion-handler abort.
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
- `ZEPHRA_GPU_WORKING_SET_MB=N` replays another Mac's GPU budget on this one, Debug builds
  only. Everything the app says about what a model costs comes out of a single number —
  Metal's recommended working set, which `MemoryBudget.gpuWorkingSet` carries — so a 16 GB
  Mac and a 48 GB one are two different apps: which chooser cards are disabled and what they
  say they need, whether the model menu offers Z-Image 8-bit and calls it "Streams from
  disk", what `WeightResidencyPolicy` loads it as, whether `VAETilingPolicy` tiles the
  decode, what a paired phone is told in `ModelSummary`, and the static half of
  `MemoryGuard`'s answer. The hand checks that matter are the small Mac's, and the small Mac
  is not always one that can be sat in front of, so this states the working set the way
  `ZEPHRA_PREVIEW_STATE` states which pane is up. `GPUWorkingSetOverride` (`Support/`) is the
  whole of it: `read(_:)` is pure and takes N mebibytes, and `replacing(_:environment:)`
  hands back the budget with **only** the working set moved — `physicalMemory` and
  `wiredLimitMB` stay this Mac's own, so the Performance tab's sysctl command still describes
  the machine, and `MemoryGuard`'s live half, which asks the kernel what is free right now,
  reads the real one. `ZephraApp` reads it once at launch over whatever
  `InterfacePreview.budget()` or `GPUMemoryBudget.forThisMachine` answered, and nothing below
  the root reads it. Anything that is not a positive whole number is nothing at all rather
  than a guess, since a zero budget fits no model and would look like a broken Mac.
  bender's figure is 12124: `ZEPHRA_GPU_WORKING_SET_MB=12124 ZEPHRA_FRESH_START=<dir>
  ./build/Debug/Zephra.app/Contents/MacOS/Zephra` is that Mac's first launch, on this one.
  What it cannot replay is a run: the weights, the peak and the time are this Mac's GPU
  still, so it answers questions about what the app *decides*, never about what it survives.
  Launch the app from a shell (`./build/Release/Zephra.app/Contents/MacOS/Zephra`) rather
  than with `open` when the point is the error text. That splits in two now. A C++ abort
  with no `catchingDeviceErrors` boundary around it — any of the process-wide corners the
  device-error handler only logs for, or a build that predates the fix — still prints the
  Metal error it dies of to stderr, and the crash report still carries only `abort() called`.
  A GPU fault *inside* a boundary — a build, a load, a warm-up, a generation, an upscale —
  never crashes at all: `InferenceRuntime.catchingDeviceErrors` turns it into
  `BackendError.deviceFailed`, the canvas says so, and the only place the raw Metal text
  survives is the `make logs` line ("MLX device error: …", see `ZEPHRA_FAULT_GPU_AT_STEP`
  above) — there is no crash report to read stderr from, because nothing crashed. Either way,
  the kernel's side of a GPU restart is in `log show` under `IOGPUFamily`, and the reports
  under `/Library/Logs/DiagnosticReports/gpuEvent-*.ips` say which process the firmware
  blamed — the one place that still names the fault when it was a full-process abort and the
  one place that names it when it was another app's frame Zephra was the innocent victim of.
