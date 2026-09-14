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
  (`+ImageDirectory`, `+ModelDirectory`), weight residency (`+Residency`), the
  live memory check (`+MemoryGuard`), and
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
  A length past one pass is a **chain**: `generate(count:)` asks `ChainPlan`
  (`ZephraCore/Generation/`, where both apps can read it) for
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
  passes make them (`ClipLength`, in `ZephraCore` because the phone's capsule
  draws the same menu), and `StepProgress` reads the chain's passes as one bar.
  Stop drops the passes made so far, as it drops a single run. A request
  composed anywhere but the store carries the whole length through
  `ChainPlan.frames`, which bounds and snaps it the way the chain will make it,
  because `clamp` alone would cut a ten-second clip to its first pass;
  `GenerationStore.enqueue` then plans the segments from what it was handed.
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

### A GPU fault fails the run, not the app

The story: on 2026-09-14, bender was screen-shared to over macOS's own Screen
Sharing while Zephra generated. `avconferenced`'s encoder took an MMU fault,
the GPU driver reset the device to recover, and every command buffer in
flight anywhere on the Mac came back discarded as an innocent victim —
Zephra's included, though nothing in Zephra had done anything wrong. Up to
mlx-swift 0.31.x that discarded buffer surfaced as an uncaught C++ exception
inside Metal's completion-handler callback, a thread no Swift `catch`
reaches, and the process ended with `SIGABRT` on
`com.Metal.CompletionQueueDispatch`. The crash report said only `abort()
called`; the actual reason — Zephra's own "Discarded (victim of GPU
error/recovery)" line — was in `/usr/bin/log show --info`, alongside the
kernel's `gpuEvent-*.ips` report naming every process the reset touched.

mlx now carries commit `a025496c8`, "Catch error in CommandBuffer and poison
the events" (mlx#3523, pulled in 2026-09-14 by pinning mlx-swift to main at
revision `ea8a179690170ca891a97bc0473198ab1ecda5f4`, mlx v0.32.2): a failed
command buffer is rethrown on the thread that asked for the work instead of
inside the completion handler. That moves the failure from "unreachable" to
"ordinary Swift error on the calling thread" — but MLX still ends the process
by default when nothing has installed a handler, so the crash simply moved
rather than disappeared until Zephra added one.

`InferenceRuntime.catchingDeviceErrors(_:)` (`ZephraCore/Runtime`) is that
handler's boundary, and `InferenceActor` opens it around everything that
touches the device: build, load, warm-up, generate, upscale
(`InferenceActor+DeviceErrors.swift`, `+Preparation.swift`). Every one of
those calls already runs on the actor's own serial `DispatchQueue`, which is
the thread MLX raises the fault on, so the boundary is reached and can act on
the same task the fault interrupted.

`MLXInferenceRuntime+DeviceErrors.swift` implements the boundary over MLX's
one process-wide handler (`MLX.setErrorHandler`, installed once and
idempotently by `MLXRuntime+ErrorLogging.swift`, from `ZephraApp` and from
`ZephraBench/main.swift` before either does anything else with MLX) and a
locked slot, `DeviceFaultSink`: opening the boundary arms a fresh
`DeviceErrorBox` in that slot for the length of the body, and the installed
handler hands whatever MLX raises to whichever box is armed. The *first*
fault recorded is the one kept — a fault poisons every array the run still
holds, so what follows is an echo of the one that matters — and recording it
also cancels the run's own task, so the kit unwinds at its next
`Task.checkCancellation()` (between denoising steps, between streamed
blocks, between VAE tiles) rather than walking the rest of a ladder over
poisoned arrays. What the boundary throws is `BackendError.deviceFailed`,
carrying the runtime's raw text, and it deliberately wins over the
`CancellationError` the cancel caused: a run the GPU lost has to read as a
failure, never as a Stop nobody pressed. `GenerationStore+Generation.run`'s
catch carries the invariant this depends on — nothing after it may add a
`Task.sleep` or a further cancellation check, or a `.deviceFailed` racing a
later cancel could be swallowed. The canvas shows one sentence, "The GPU
stopped responding and this run was lost. Try again."; `InferenceActor.upscale`
maps the same case to `UpscaleError.failed("The GPU stopped responding. Try
again.")` rather than the failure screen, whose remedy is to reload a model
an upscale never needed. Outside any boundary — the wired-limit reservation
on its own task, the allocator's cache being released as a model unloads, the
device asked what generation it is before anything is loaded — the same
handler writes "MLX error outside any run" to the log instead of ending the
process; none of that work is worth the app, and none of it is trusted
afterwards, since each is asked again the next time it is wanted.

Nothing is unloaded on a generate-time fault: the device recovers on its own,
and a forced reload is a two-minute wait for weights that never moved. A
load-time fault still unloads, through the catch `+Preparation.load` already
had — a half-read model is not something to leave resident. `DeviceFaultTests`
(`ZephraEngineTests`) pins all three shapes: the run fails and keeps no
picture, the weights stay up so retry generates without reloading, and a
fault mid-load unloads and reports the same sentence.

**Design alternatives rejected.** mlx-swift's *scoped* handlers — the ones
upstream actually recommends over the process-wide one this uses — take a
`withErrorHandler(_:)` closure, and handing the run's own body to one moves
that work off `InferenceActor`'s serial queue; the compiler refuses it, since
the queue is the actor's isolation and the closure crosses an isolation
boundary. Their task-local handler *stack*, which would otherwise let a
nested boundary compose more cleanly than one shared slot, is typed
file-private upstream and unreachable outside that closure form. A `TaskGroup`
around the device work, racing a timeout or a cancellation signal, was
considered and dropped: the fault is not a hang to race against, it is a
thrown error already on the right thread, and a group would only add a second
task whose cancellation has to be kept in lock-step with the first. Unloading
the model on every fault, not only a load-time one, was dropped because a
generate-time fault is the device recovering from someone else's problem —
the weights themselves are fine — and unloading would turn a several-second
retry into the multi-minute reload every streamed family pays for a cold
start.

### Memory, checked twice

`MemoryFit` answers a catalog question — could this Mac ever hold that model — and
the pickers grey what it says no to. It is answered against a budget that does not
move, and that is the half it can answer. The other half is whether the memory is
there *this minute*, with a browser, a compiler and the model loaded five minutes
ago holding it, and until 2026-09-13 nothing asked. Two incidents in three days
said what that costs: halcyon (48 GB) kernel-panicked under a model switch with
Zephra at 37.5 GB resident, and bender (16 GB) aborted from Metal's completion
queue — where no Swift `catch` reached before mlx-swift 0.32.2 — when Z-Image
8-bit was picked from the menu. 2026-09-14's device-error boundary (above)
means a fault of that shape no longer takes the app with it, but that changes
nothing about which is better: a refusal ahead of time is two figures and a
remedy, and a run the boundary catches after the fact is a picture lost. The
best place to stop is still before the allocation.

So `GenerationStore+MemoryGuard` asks `MemoryGuard` (`ZephraCore/Runtime/`) twice.
`loadResidency(for:)` runs in `+Preparation.load` **after** the files are
acquired and the cancellation check, and before `reserveBuild` — after the download
rather than before, because a download is worth keeping whatever the machine is
doing and a load is not. It charges the peak for the way this load will actually
run (the streamed figure when streamed, the tiled one when tiled) against the
smaller of the budget and what the machine says it has, with Zephra's own active
and cached bytes counted back in, since the old model goes before the new one
arrives. `runShortfall(for:)` is the first line of `+Generation.run`, before
`beginActivity`, and charges only the transient — the peak less what is held —
scaled by pixels times frames against the size the peak was measured at. The job's
own model and settings are what it reads, not the capsule's, so a run queued behind
a switch is judged by what it will ask for.

**The load answers with a residency, not only with a refusal.** `MemoryGuard`
is the only reader of the live figure, so it is where the step down to streaming
belongs: `loadResidency(for:policy:tile:machine:runtime:)` asks the policy,
runs `loadShortfall` against that answer, and where a resident load under
Automatic is short re-asks for `.streamed` before refusing. `WeightResidencyPolicy`
deliberately stays static — the model menu's note, the Performance tab's caption
and the timing keys are about what this Mac could do with this model, and a
figure that moves with whatever a browser is holding would make those flicker.
On 2026-09-13 a Mac replaying a 12124 MiB working set met exactly the case the
two halves together fix: klein 4-bit fits that budget held whole, so the policy
said resident, 11.2 GB was free against its 12.1 GB peak, and the load was
refused although its 4.06 GB streamed peak would have fitted three times over.
Only Automatic steps down, and only to a family with a measured streamed peak;
`Never` is a choice to hold the weights and `Always` is streaming already. A
refusal after the step-down quotes the streamed figure, which is the load that
was going to be attempted. The store logs the step-down as one `info` line
naming both, since a Mac that quietly streamed and one that quietly did not are
otherwise the same three lines, and it stores what was actually loaded in
`loadedResidency`: `isResident(_:)` in `+Loading` therefore does *not* compare
that against the policy, or the next press of Generate would read the whole
model again to put it back where the static answer says it belongs and find the
same thing. A change of residency is felt through `setWeightResidencyPolicy`
and through a model switch, nowhere else.

Either answer is a `MemoryShortfall`: two figures and one of two remedies —
"Quit other apps and retry.", or "Set Stream weights from disk to Automatic in
Settings > Performance." The second is said under the `Never` **mode** alone,
where the memory exists and a preference is what is holding the model whole.
The remedy takes the mode rather than reading the residency, because under
Automatic a refusal means even streaming did not fit: the Mac on 2026-09-13 was
told to set Automatic while Automatic was what it was on. It reaches the canvas as
`EngineError.insufficientMemory`, whose message is that sentence. The load check is
*thrown*, so the `catch` that already unloads the actor and gives the disk lease
back runs on the way out; the run check calls `fail(with:)`, which empties the
queue. Retry goes back through `startLoading`, which asks again rather than
replaying a verdict, so a Mac where something else has quit in the meantime loads.
Both sites log the reading and the decision — admitted as well as refused, since
the admitted line is what makes the next refusal legible in `make logs`.

`canSelect(_:)` (`+Admission`) is the budget-only half, and it is a gate rather
than a note: `switchModel` drops a pick of a model this Mac cannot hold,
`startLoading` refuses one with `staticShortfall` before a byte is fetched,
`select(_ item:)` keeps the current model and clamps the settings for a picture
made by one, and `fallBackIfUnrunnable()` — the old `fallBackIfUnobtainable`,
widened from "cannot be had" to "cannot be had or cannot be held" — steps off one
at launch onto a candidate from `ModelCatalog.fitting(budget:)`. A Mac that can
hold none of them keeps what it had and hears the guard's sentence, since stepping
it onto a second model it also cannot hold helps nobody. A paired phone hears
exactly these words: `remoteAdmission` answers `.badRequest` with the static
shortfall (the machine, not the moment, so asking again is worth nothing) and
`.refused` with a live one when settings were handed in.

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
