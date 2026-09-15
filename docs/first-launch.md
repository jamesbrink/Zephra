# First launch

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

## First launch

A Mac that has never run Zephra opens on a chooser, not on a download. Until this
existed, `bootstrap()` loaded `ModelCatalog.default(fitting: budget)` before the
window had settled — a 13.3 GB transfer on a decision nobody made, in a catalog
where klein 4-bit is 5.4 GB and runs exactly rather than tiled. Everything needed
to say that was already computed and shown nowhere until a toolbar menu was found.

- `WelcomeGate` (`Support/`) is the whole of the decision, built by the composition
  root beside `WorkspaceSelection` and resolved from the preferences **synchronously
  in `init`**, so a first launch opens on the chooser rather than flashing the canvas
  first. `hasAnswered(in:)` is the rule: the `hasChosenModel` flag once it is
  written, and before that the presence of `selectedModelID` — which the root writes
  on every launch, first or not, so its absence is what a genuinely first launch
  looks like and an existing install never sees the chooser at all. The composition
  root does not write `selectedModelID` while the chooser is up, which is what stops
  quitting on that screen from looking, next launch, exactly like having answered it;
  it writes it once when the chooser goes down instead, since a chooser answered with
  the model the store was already pointing at moves nothing for the ordinary
  `rememberedModel` write to see.
  `settle(availability:budget:current:)` puts it away when the survey finds a model
  already here (`make prefetch`, a warm hub cache, a reinstall) and **answers which
  model to continue on**: the store is still pointing at `default(fitting:)`, which on
  such a Mac is often not what is actually here, so closing without saying would
  download a second model to sit beside the one already downloaded. It answers nil for
  a chooser that is already down, which is what keeps a Skip pressed while the survey
  was still running from turning into a download a moment later. `dismiss()` records
  the answer — a skip is an answer — and that is the last of it: **there is no way
  back to the chooser**. `reopen()` was removed with the model browser. The screen a
  person who skipped lands on is `CanvasStateView`'s idle state, and its "Choose a
  Model…" now raises `ModelBrowserSheet` instead. Two reasons. The chooser takes the
  whole window to ask a question this Mac has already answered, and writing that
  answer again is a preference write for a press that was only meant to go looking.
  And with models loaded on demand, going looking is something people do routinely
  rather than once: a dialog over the window is the right shape for it, and the
  chooser, which is a first-run screen, is not.
- `WelcomeHost` (`Views/Welcome/`) is the `Window` scene's root and shows either the
  chooser or `RootView`. `bootstrapFromInterface(loadingModel:)` is why: with the
  chooser up it runs `GenerationStore.surveyAvailability()` — the half of
  `bootstrap()` that reads the disk — and stops. Nothing is fetched while the chooser
  is up. Loading is asked for here rather than on `RootView` because on a first
  launch `RootView` is not built at all and the cards still need `availability`.
- The recommendation is `ModelCatalog.default(fitting:)`: the first catalog entry
  this Mac runs at its default size **with the weights resident**, then the first it
  runs streamed, then, where *nothing* fits, the entry with the smallest
  `ModelDescriptor.leanestPeakBytes`. So catalog order is the editorial judgement and
  memory is the filter — a 16 GB Mac is offered klein 4-bit where a 32 GB one is offered
  Z-Image 8-bit. The resident-first half of that order is new, and it exists because
  every entry carries a measured `streamedPeakBytes` now: Z-Image 8-bit is first in
  `all` and fits a 16 GB Mac streamed, so the plain "first that fits" would have flipped
  that Mac's first launch from a 5.4 GB download that runs exactly to a 13 GB one that
  reads itself off the disk on every step and takes minutes a picture. Streaming is how
  a Mac runs a model it cannot hold; it is not how a Mac should be started. The last
  half is for an 8 GB Mac, a machine no Zephra has been measured on: the leanest peak is
  the tiled one, or the streamed one where that is smaller, because the plain catalog
  default there named the largest download of the six and the one wanting the most
  working set. That card is greyed and says what it needs, so it is a statement of the
  distance rather than a promise that it runs.
- The cards are `ModelChoice.all(for:)` (`Support/`): every catalog entry, the ones
  that run at their default size here first (`ModelCatalog.ordered(for:)`), each
  carrying its `MemoryFit` and the sentence for it, judged once against one budget so
  a card holds three stored properties and never reads the budget itself. Nothing is
  hidden by memory and a model this Mac cannot hold is **disabled** by it, with its
  whole sentence as help. That reverses the first rule this screen shipped with —
  `ModelMenu`'s, that a model which pages at its default size still runs at a smaller
  one — because it does not: on 2026-09-13 a 16 GB mini asked for Z-Image 8-bit, whose
  tiled peak is 17.9 GB against a 12.7 GB working set, the kernel refused to wire the
  memory, and MLX threw from Metal's completion queue, where no Swift `catch`
  reached it before mlx-swift 0.32.2 and the device-error boundary.
  Nothing was drawn at any size. So the note became a gate: `ModelChoice.isSelectable`
  is `MemoryFit.isSelectable`, `isRecommended` requires it (an 8 GB Mac is recommended
  nothing rather than pointed at the card the chooser is about to refuse), the footer
  button goes out and is titled with the figure instead of with a transfer it cannot
  begin, and `WelcomeGate.readyModel` settles only on a model that is downloaded *and*
  holdable — a models folder carried over from a bigger Mac is otherwise a finished
  download of something greyed in every picker here.
- What a card states about size is `store.availability[id]?.label`, never
  `transferBytes`: every locally built variant is published ready-made on the mirror,
  so klein 4-bit transfers 5.4 GB against its release's 16 and Z-Image 4-bit
  transfers 7.1 against 32.9. Before the survey lands the catalog's own figure stands
  in by the same rule (`builtBytes` when `isPublishedPrebuilt`), so a card is never
  blank and never quotes a number the download contradicts.
- `MemoryFit+Label` in `ZephraCore` is where "Tiles the decode", "Streams from disk",
  "Needs 27 GB" and their long forms now live, the shape `ModelAvailability.label`
  and `reason` already had. They were `ModelMenu`'s private strings; a second reader
  would have been a second copy. `Needs N GB` rounds **up**, since the figure is a
  floor.
- `ModelPortrait` (`Support/`) is the one place a model's sample picture and its
  one line of copy live, keyed by descriptor id — presentation rather than a measured
  catalog fact, so it stays in the app rather than on `ModelDescriptor`.
  `ModelPortraitTests` walks `ModelCatalog.all` and fails when a model has neither, so
  a ninth model cannot ship with a blank card.
- The samples are one prompt at one seed for every model, so a row of cards compares
  models and not prompts: the website's own copper-robot still life, seed 42, rendered
  at each family's preset nearest 16:9 and centre-cropped to 800 x 450 JPEG in
  `Assets.xcassets`. `scripts/make-samples.sh MODELS_DIR` regenerates the set
  (`scripts/crop-sample.py` is the crop); a model with no sample draws a plain panel
  in its own `ModelDot` colour rather than a hole. A model whose weights are not under
  `MODELS_DIR` is **skipped, not fetched** — `ZephraBench` downloads what it cannot
  find, which is right for a benchmark and wrong here, where it would quietly pull
  tens of gigabytes; `ALLOW_DOWNLOAD=1` asks for that on purpose.
- Choosing goes through `GenerationStore.chooseFirstModel(_:)`, which is now
  `switchModel` where the pick differs from the chosen model, and then `loadModel()`
  always. Two rules meet there. `switchModel` refuses a pick of the model already
  chosen, which on a first launch is whatever `default(fitting:)` answered, so
  pressing the recommended card would otherwise do nothing at all. And under
  `ModelLoadingMode.onDemand` — the default — `switchModel` loads nothing even when
  it does take the pick, since a pick is only a pick there. A first-launch card is an
  explicit "load it now" in either mode, so the load is said out loud rather than
  left to the mode; under `.automatic` the switch has already loaded and `loadModel()`
  is a no-op.
- `ZEPHRA_GENERATE_ON_LAUNCH` is inert while the chooser is up: `WelcomeHost` returns
  before it rather than leaving it to poll, since with the chooser up nothing is loading
  and nothing will be until somebody presses a card. The hook is for an unattended launch
  on a Mac that is already set up, where it waits for the survey to land and then for a
  model that is ready or loadable.
- `ZEPHRA_PREVIEW_STATE=welcome` photographs it. Screenshot it at 1200 x 840 and again
  at the window's 880 x 560 floor: the grid's columns are adaptive and reflow to two
  there, and the footer must stay put under the scroll.
