# Downloads and generation lifecycle

The long form of the matching section of `AGENTS.md`: the rules there, the reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or this is stale; fix both.

## Download lifecycle

`ModelAcquisition` in Core is injected into every backend's `ensureAvailable`.
`ModelResolution` creates a private unloaded backend for family-specific disk checks;
it never shares the inference actor's mutable backend or calls build/load/generate.
`ModelDownloads` in Engine owns request observation and foreground borrowing;
`ModelTransfers` in Snapshot owns network slots, preflight, compatible repository claims
and per-volume space reservations. A claim spans validation, build and resident use,
so acquisition completion never opens a deletion gap, and is borrowed once: Retry on
a resident model answers ready without touching the pool, and a load that reaches a
lease the store already holds reuses it (`unloadModel` asserts the request is gone
after its one release). Failed/canceled loads unload before releasing their claim. Foreground events carry an operation identity; superseded
progress and completion cannot change the selected model's state.

`GenerationStore.acceptsWork` (`+Admission`) is the one gate every entry point
reads — no folder changing, no storage being deleted, not quitting — and a caller
adds only the conditions that are its own; `drain()` reads it too, so
`deleteModelStorage` drains again on its way out. `canQueueVariation(of:)` is the
variation's own answer, and does not wait for a reference still on its way into
the well: a variation replaces the settings outright and cancels that read.
All UI storage deletion goes through `GenerationStore.deleteModelStorage`, which
checks active requests/residency/queued work and closes new admission while deleting.
Folder changes close download admission, pause every request and await file closure.
`AppLifecycle` defers normal Quit while `GenerationStore.shutdown` settles tasks,
then `LibraryIndex.shutdown` stops watching and drains its write chain and scans (store
first, because the store's last save inserts into the index), then the runtime seam
synchronizes Metal before allowing process teardown.


## How a generation runs

Three types in `ZephraEngine`, one concern each. The split is what lets the
engine be tested in seconds without Metal.

- `GenerationStore` (`@MainActor @Observable`) is the only object the UI
  observes, and it is split across `GenerationStore+*.swift` by concern —
  loading (the entry points in `+Loading`, the borrow-prepare-release body in
  `+Preparation`), the admission gate (`+Admission`), generation (`+Generation`,
  with the write that follows in `+Saving`, which moves an image deleted while
  its write was in flight straight on to Recently Deleted rather than announcing
  it saved), the queue,
  batches (several seeds of one prompt from
  one press of Generate), model switching, history, availability, preview,
  the public convenience init (`+Init`), the tiled decode (`+Tiling`),
  the reference picture, the library, following the run, upscaling and filing
  the upscaled result, the interface's own questions (`+Interaction`), the
  download requests it keeps alive (`+Downloads`), the two folder changes
  (`+ImageDirectory`, `+ModelDirectory`), weight residency (`+Residency`), and
  the seam a paired device submits through (`+Remote`).
  Add a new concern as another extension file, not as more lines in
  `GenerationStore.swift`.

  What a backend hands back is `GeneratedMedia`: `.image(png:)` from the three
  picture families, `.video(GeneratedVideo)` — the MP4, its first frame as the
  poster PNG, the frame count and rate, and `hasAudio` when the file carries a
  sound track — from Wan and LTX-2.5. One return type rather
  than two protocol methods, because the actor, the timer, the cancellation
  check and the queue are the same whatever comes back; only the last step
  reads the kind. `GenerationSettings.frames` is the clip's length (1 for a
  picture, pinned there by `clamp` for every model whose
  `ModelCapabilities.frameBounds` is the degenerate `1...1`), and a video
  model's `frameAlignment` snaps it to the `1 + 8k` ladder its autoencoder makes.
  A length past one pass is a **chain**: `generate(count:)` asks `ChainPlan` for
  the passes (a full one, then passes of the model's `defaultContinuationFrames`
  held plus new frames, at most `ChainPlan.maxPasses`), queues the first with a
  `ChainSegment`, and each pass that lands is kept in `chains` rather than
  published, its tail read through the injected `ClipEditing`, and the next
  pass put at the head of the queue on the next seed with that tail as its
  continuation (`GenerationStore+Chaining`). The last pass joins every part —
  the source clip first when Extend Clip started the chain — and publishes one
  clip whose settings say the whole length and the first seed. `clamp` keeps a
  single pass's bounds, so no backend is ever asked for more than it runs; the
  Duration menu offers the chained lengths every five seconds and says how many
  passes make them, and `StepProgress` reads the chain's passes as one bar.
  Stop drops the passes made so far, as it drops a single run.
- `InferenceActor` is the only place backend code runs. It overrides
  `unownedExecutor` with a serial `DispatchQueue`: a generation is tens of
  seconds of synchronous Metal work, and on the cooperative pool that would
  starve every other task in the process. Backends are not `Sendable`, which is
  why a registry of `@Sendable` factories goes in and the backend is built here.
  A backend looks for a cancel between steps and not after its decode, so both
  `InferenceActor.generate` and the store's `run` check again once the bytes are
  back: a Stop that lands during the decode keeps no image, publishes nothing
  and writes nothing. A finished image carries its own job's batch and model
  (`QueuedGeneration`), not `running`'s, which a cancel empties, nor the store's
  `descriptor`, which a switch moves before the run is over. The VAE tile is chosen
  the same way, per run from the job's model, by `GenerationStore+Tiling` and set
  by the actor as the run starts; see `ZEPHRA_VAE_TILE` in `docs/debugging.md`.
- `EngineEventPump` carries progress from that queue back to the main actor. Its
  `AsyncStream` buffers the newest four events and drops the rest — progress is
  a snapshot, not a log — and `run` drains before returning, so the state a
  caller sets after an operation is never clobbered by an event still in flight.

### Work that did not come from the keyboard

`GenerationStore+Remote.swift` is the one seam a companion device submits
through: `enqueue(_:on:count:)` takes the settings and the model as arguments and
puts a batch in the queue, answering the batch id. Everything it *does not* do is
the point. The store's other two doors both move the capsule to say what is about
to run — `generate(count:)` reads `settings`, starts following the run and clears
`modelAwaitsGenerate`; `queueVariation(of:)` replaces `settings` and `descriptor`
outright and claims the reference ticket. A request that arrives over the network
must touch none of that: the person at the Mac may be halfway through a prompt,
may be watching a run of their own, and may have a picture on its way into the
well, and a remote submit that overwrote any of it would be a bug nobody could
explain from the interface. So `enqueue` writes to `queue` alone, and the result
enters history, the wall and the library the ordinary way while the canvas stays
where it was — `followsRun` was never turned on for it, which is the rule that
already governs a picture finished while the user looks elsewhere. What it
*does* share with `generate(count:)` is the run's shape: the chain planned before
the clamp, `model.capabilities.clamp` fitting the request to the model that will
run it (a size off the grid comes back on it rather than being refused), the
first seed kept and the rest fresh, one `batchID` across the batch, and the same
drain-or-log tail. `GenerationSettings` carries no model of its own, so there is
no second schedule to come off; `on model:` is the schedule.

`remoteAdmission(for:settings:count:)` is the same question asked before the
submit, and answers `RemoteAdmission` rather than a Bool because the device has
to say something: `.busy` when `acceptsWork` is closed (a folder change, a
storage deletion, a quit), `.refused` when the engine is not in a state that
takes a generation (worded from the same vocabulary as `EngineState+Display`, in
`EngineState+Remote`), and `.badRequest` when nothing about the request could
ever run — no prompt, a count outside 1...`batchLimit`, a model this build's
catalog does not know. A bad request is answered first, whatever the Mac is
doing: telling a phone to wait for a load that will never make its empty prompt
runnable helps nobody. The first two are worth retrying in a moment and the
third never is, which is the distinction a host adapter needs. Like
`canQueueVariation(of:)` and unlike `canQueue`, it does not wait on a reference
picture still being read: that well belongs to the Mac, and a remote request
carries its own picture in its settings.

`current` is what the canvas is showing, and only that.
`GenerationStore+FollowingRun.swift` is the other half of that sentence: pressing
Generate — or asking for a variation — starts *following the run*, and opening or
selecting any other picture stops. A result is published to `current` only while
`followsRun`; one that lands while the user is looking elsewhere still enters
history, the wall and the library, and leaves the canvas where it is.
`watchRun()` follows again and, when a picture picked up from the sidebar has
replaced the capsule's settings and model since (`capsuleHoldsPicture`, which
any edit to `settings` clears), puts the run's own back — a capsule the user
has been working in, a model picked mid-run or a prompt typed since, it leaves
alone; `isShowingRun` is
"following, and something is running", and `hasPicture` in the app target is
`current != nil || isShowingRun`, so the inspector has something to describe
from the moment a run starts. Two ways onto the canvas from the library, told
apart by what they do to the capsule: `open(_ item:)` only looks, so the grid's
"Open in Canvas" never replaces the prompt being written, and `select(_ item:)`
adopts the picture's settings and chooses its model as `select(_ image:)` does
for a session's own (see "Selecting a picture chooses its model without
loading it" in `docs/adding-a-model.md`), which is what every square on the canvas
sidebar's wall does — a square is a run to pick up again, and the running card
is the way back to the one in flight. The
upscale result follows the same rule by the one test it can apply: it takes the
canvas only when the canvas was showing its parent, or was showing nothing.

`livePreview` is the newest frame of the run in flight — `GenerationPreview`,
RGBA8 pixels of at most 256 pixels an edge, decoded by the family's own VAE from
a pooled copy of the latent. It rides in on `GenerationProgressEvent.preview`,
which is why that type hand-writes `==` and `hash(into:)` to ignore it:
`EngineState` is `Hashable` and compared on every transition, and hashing a
quarter of a megabyte per step to answer a question nobody asks is not worth it.
The store keeps the frame outside the state and puts it down on every way a run
can end, and only then: looking away keeps it for the running card, and a press
of Generate that queues behind the run in flight leaves it on the canvas. `StepTimer.annotated` rebuilds the event field by field, so a new field
there has to be forwarded by name or it never reaches the canvas.

Where a frame comes from: each kit has a `<Family>LatentPreview` that takes a
latent in its loop's own packed space, unpacks it, pools it so its long edge is at
most 32 cells (8 for LTX-2.5, whose cell is 32 pixels), and decodes that through the family's own autoencoder with the
tiling skipped — `LatentPreview` in `ZephraMLX` holds the pooling and the byte
packing for Qwen-Image and klein, and the vendored `ZImageKit` keeps its own copy
for the same reason it keeps its own `VAETiledDecode`. Each loop calls an optional
`onPreview` **after** the step's `MLX.eval`, never on the last step, handing over
the step index and a *closure* that makes the frame rather than a frame: the
backend owns a `PreviewThrottle` (0.75 s, `ZephraCore`) and never pays for the
frames it drops. The existing before-step `onProgress` is untouched, so
a frame never splits a step: `BenchStepClock` and `StepTimer` ignore any update
carrying a frame, because a frame is reported after its step rather than before
the next one. A frame's decode does land inside the step it follows, and both
leave it there on purpose. On screen the pace is what the remaining steps will
really take, frames included; in the benchmark `--preview` is for finding out
what turning frames on costs, and it reports the frame's own mean beside the
step time so the two can be told apart. A family that never calls `onPreview`
simply shows no frames.

What each loop passes is the run's estimate of the **finished** latent,
`x - sigma * v`, and not the latent it is holding. This is the whole feature
working or not: all three schedules are bent towards their noisy end, and klein's
four-step ladder at 1024 pixels is still at sigma 0.77 on its third rung, which
decodes to flat brown mush. One more Euler step of the velocity already in hand,
all the way to zero noise, is what a person means by "how is it coming along".
It costs one elementwise operation, and it is computed inside the frame closure,
so a dropped frame does not pay for it.
