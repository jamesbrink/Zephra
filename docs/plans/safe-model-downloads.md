# Safe model switching and concurrent downloads

Status: proposed implementation; independently peer-reviewed and approved. No runtime changes yet.

## Evidence and diagnosis

- `GenerationStore+Switching.reload` already cancels and awaits the previous switch and bootstrap task before unloading. Simply adding cancellation, or relying on a serial actor, is insufficient: async actor methods can interleave at suspension points.
- `GenerationStore+Loading` couples download, build, load and warm-up into one bootstrap task. `applyLoadEvent` accepts events without an operation identity; terminal state and loaded-model publication also need ownership checks. This is a hardening target, not an established crash cause.
- `InferenceActor.prepare` has no explicit cancellation checks between ensureAvailable, build and load. A backend that returns after cancellation can continue into expensive work. A canceled warm-up that returns successfully can currently publish ready without a final cancellation check.
- `ModelDownloader.fetch` removes unfinished writable repositories on cancellation. FLUX 4-bit and 8-bit share a source directory. Multiple independent fetches would race writes, revision pins and cleanup; they must not be enabled as-is.
- The existing “switching during the initial download” test delays load, not HTTP body delivery; separate cancellation tests do exercise download delay, but not rapid cross-model download handoff with the real downloader.
- Local report `Zephra-2026-09-04-152913.ips` shows SIGABRT on Metal's completion queue in MLX scheduler mutex handling. The main thread is in `NSApplication.terminate`, while inference is in FLUX warm-up. This supports investigating shutdown during preparation; it does not establish that model switching caused that crash. Correlate executable/build identity and logs before assigning a root cause.

## User-facing behavior

1. Selecting B while A downloads immediately selects B. A remains visible and continues downloading; B starts if a transfer slot is free. At most two repository transfers run at once, one file at a time per transfer. Additional requests wait visibly.
2. Only the foreground preparation target is built, loaded and warmed up. An obsolete download completing only updates disk availability. It must never change the selected model or take over the canvas.
3. Shared source releases and adapters transfer once. Choosing another FLUX precision joins the same source download; only the desired variant is then built.
4. Settings > Models shows download jobs with model names, bytes/progress, queued/downloading/paused/failed state and Pause, Resume, Cancel download or Retry. The model picker shows matching status, and the canvas describes only its foreground target, with a link to the other downloads.
5. Switching is not cancellation. Pause retains revision pins, partial files and ETags; Resume revalidates and resumes. Explicit Cancel download removes unfinished data only after the last consumer releases it and all writes stop. Completed releases and read-only fallbacks stay. If another model still needs the source, cancel only this model's interest and explain that the shared download continues.
6. A background failure is shown on its job, without failing the active model. A foreground failure shows its existing recoverable error UI. A failed queue-required preparation retains today's queue-failure behavior unless changed separately.
7. Existing generation order is unchanged: the running request finishes, queued requests retain their models, and the queue head is the preparation target while draining. Selection does not automatically enqueue a generation. Background downloading may overlap inference; build/load/warm-up/generation/upscale never overlap one another.

## Implementation sequence

### 1. Diagnose and protect the existing single-preparation path

- Add bounded, deterministic barriers to engine mocks and HTTP fixtures for headers, body chunks, retry backoff, build/load and warm-up. Reproduce A-to-B and A-to-B-to-A switches with small disposable repositories and capture stage, operation ID, model ID, destination and cancellation reason in logs.
- Give foreground preparations an identity and explicit cancelling/settling state. Invalidate it synchronously when switching or stopping; only its owner may apply progress, publish loaded paths/descriptors, settle state or clear task handles/flags. Keep physical cleanup bookkeeping separate so stale UI suppression cannot lose track of resident weights.
- Keep cancel-and-await ordering and add cancellation checks before/after every preparation stage and after warm-up. The next backend may not unload or start until previous backend work actually settles; an actor executor alone is not an operation lock. Clear `loadedPath` on unload.
- Treat load failure/cancellation as potentially leaving resident allocations even if no directory was returned. The inference lane owns rollback: unload and settle partial residency before releasing storage protection or accepting another preparation. If warm-up cancellation deliberately retains a fully loaded model, return explicit residency bookkeeping to the store even when its UI operation is obsolete; never infer safe deletion from a missing `loadedDescriptor`.
- Audit `ChunkedDownload.start` for cancellation before pending registration, during headers, while the body is suspended for backpressure, and while the stream finishes. Guarantee one continuation completion and bounded cancellation settlement; change only defects demonstrated by tests.
- Correlate the shutdown crash and reproduce quit during warm-up in an isolated app instance. Add an asynchronous AppKit termination handoff if confirmed: reject new work, stop and await preparation/inference, synchronize outstanding GPU work through the runtime seam, then allow termination. Never block the main actor or pretend task cancellation has drained Metal. Keep AppKit in the app target and MLX inside its existing boundary.

### 2. Separate acquisition from inference without losing family validation

- Introduce Sendable acquisition request/result/progress and an acquisition protocol in ZephraCore; Foundation-only transfer ownership in ZephraSnapshot; injected scheduling and observable job state in ZephraEngine. No singleton, model imports in Engine, or new third-party dependency.
- Retain family-specific packed-variant/release/local-directory validation currently in each backend's `ensureAvailable`. Introduce an injected acquisition argument there instead of constructing `ModelDownloader()` independently in each backend. Audit/update all conformers, mocks and tools together.
- Resolve acquisition with dedicated actor-confined backend instances made by the registry, never the live inference backend. These instances only inspect disk and request transfers; they never build, load, warm up or allocate MLX weights. Move any violating code into the later inference stage. A job survives cancellation of one foreground waiter.
- After acquisition, pass the validated result and pinned locations to the single inference preparation lane. Revalidate ownership and disk inputs before build/load. Maintain read leases on source/adapter directories through build and on loaded weights until unload; migration/deletion cannot invalidate them.
- Acquisition completion atomically hands ownership to read leases before exposing a successful result. Protect already-local/packed/cache inputs before validation too. Release all dependency leases on every cancellation/failure path; physical download completion does not release a build's input protection.

### 3. Add shared ownership before increasing concurrency

- Key physical ownership by canonical writable destination, with repository, resolved commit and requested file set as compatibility metadata. Reserve the destination before revision resolution/listing mutates pins. Descriptor ID alone, or repo ID without root/revision, is not a safe key.
- Coalesce compatible shared requests and fan out progress. Expand compatible file needs through the same writer; serialize incompatible commits/pattern requirements and revalidate after acquiring ownership. Never let different commits mutate one folder concurrently, including while an earlier build reads it.
- Acquire writer ownership per physical repository transfer; never retain an exclusive repository lock or HTTP slot while waiting for a different dependency. Collect compatible read leases for final verification/build. Operations requiring several exclusive paths, such as migration, acquire them atomically or in one stable canonical order with rollback. Add crossed release/adapter dependency tests and transfer-to-build handoff tests.
- Resume a retained job at its original pinned commit. The current revision resolver accepts an existing pin unconditionally; compare incoming requested revision/resolved commit metadata before joining it. A different explicit revision waits for old readers/writers to settle and is then revalidated, while a resumed moving branch keeps its existing pin. Test both cases.
- Own retries and cancellation at the physical job level. Distinguish foreground waiters, generation-queue consumers and retained user download requests. Detaching a superseded waiter is not canceling the physical task. Release an acquisition slot only after its body, handles and cleanup settle.
- Pause/Cancel controls act on a named model request, not an anonymous shared repository. Pause makes that request dormant; Resume reactivates it; Retry explicitly clears its failure and joins or restarts the compatible job. Foreground pause stops its preparation and presents Resume without an automatic reload loop. Other consumers continue; label this as a shared transfer that is still running. A queue-required request cannot be paused or canceled through its model row while queued consumers remain: disable these controls with an explanation to remove queued work first. The explicit foreground engine Stop action keeps today's behavior of clearing the queue; canceling a separate background request never clears it. A stopped request must not be silently reactivated by an availability refresh.
- Preserve release-plus-adapter correctness: preflight all required repositories, track readiness per requested file set, and report a model acquired only when its entire dependency set is verified. A generic completion marker does not prove every consumer's files exist.
- Make destructive cleanup ownership-aware, retaining complete repositories and preventing cancellation from removing another job's pin, partial file or input. Keep the existing containment, symlink, pinned-commit, Range/If-Range and read-only-cache safeguards.
- Start the scheduler with concurrency one; once ownership tests pass, allow two physical transfers. Promote the foreground/queue-head target among waiting jobs without repeatedly canceling active transfers. Deduplicate repeated selections and resume retained jobs instead of creating new ones.
- Budget disk space per volume from unique remaining transfer bytes and pending build requirements, with a safety reserve and reservations released on settlement. Recheck when listings supply exact sizes and before building; insufficient space pauses/fails only the affected job. External disk loss is recoverable, with no fallback write into another root. Keep bounded body buffering per transfer and measure aggregate memory with two transfers.

### 4. Integrate controls, storage and lifecycle

- Split download observation from the foreground EngineState. Use small job values and focused store extensions/views; preserve one public type per file, roughly 150-line files, three stored properties per view and existing layer lint.
- Add engine-enforced storage leases for download writes, source reads, builds, resident weights, queued consumers and deletion. Settings derives protected paths from these leases and rechecks atomically at deletion admission; disabling a button is insufficient.
- Folder change/migration closes job admission, pauses and awaits every affected transfer, settles preparation and acquires exclusive storage access before moving anything. Preserve partial metadata. Commit new locations only after success; retain the previous location on failure and report recoverable paused jobs. Resume only when requested, matching current folder-change behavior.
- Normal quit pauses downloads without deleting partials and awaits their file closure alongside the inference shutdown handoff. Relaunch recognizes resumable partials; initially require explicit Resume/selection rather than persisting automatic background intent. Unexpected exit uses the existing incomplete-file/pin recovery path.
- Update AGENTS.md and user documentation for the distinction between switching, pausing and explicit cancellation. Put automatic restart of background jobs, more than two transfers and concurrent quantization in ROADMAP.md as deferred work.

## Verification and acceptance

- Deterministic engine tests: A-to-B-to-C/A across families; stale progress/success/error; cancellation before task start and after each stage; retry while settling; rapid repeated selection; queue-head versus selected model; generation/upscale coexistence; only one heavyweight operation; only the current target publishes ready.
- Snapshot tests through URLProtocol and scratch roots: two independent downloads; shared FLUX source fetched once; shared and distinct adapter files; cancellation of one/all consumers; paused body cancellation; retry backoff; incompatible revisions; per-consumer file readiness; cleanup with active readers; full disk and disconnected volume. Assert final bytes, pins/ETags, preserved completed data and zero simultaneous writers for a destination.
- Scheduler/storage tests: limit two, waiting priority, slot release after settlement, no duplicate reservations for shared bytes, deletion/migration admission races, partial preservation across folder changes and restart, background failure isolation.
- Run `make test`, `make lint-layers`, `git diff --check`, Debug app build and relevant backend/MLX suites after protocol/runtime changes. Use Swift Testing and bounded waits, not timing-only sleeps. No real weights in unit tests.
- Native UAT in an isolated preferences domain and disposable model root: rapid switching during real streamed HTTP, two progress rows, shared-source switching, Pause/Resume/Cancel, retry, folder move, relaunch and quit during download/build/warm-up. For actual Metal paths use already-available models; record the exact build and crash/log evidence. Do not delete or move the user's real model files.
- Acceptance: no process crash or stuck task across the matrix; no stale takeover, duplicate writer, lost shared bytes, overlapping heavy operations or migration/deletion race. A narrow switch fix is independently deliverable; multi-download support ships only with ownership and lifecycle tests passing.
- Before implementation release, request independent final-diff review and address findings. Use conventional commits on `fix/model-download-switching` for the safety change and `feat/concurrent-model-downloads` for the follow-on; this document is on `docs/safe-model-downloads-plan`.

## Independent plan review

The `review_download_plan` sub-agent reviewed current source and the draft, then reread the amended plan. Final verdict: approved, with no remaining blocking design findings.

Review amendments incorporated: atomic transfer-to-read lease handoff; avoidance of dependency lock/slot deadlocks; explicit shared Pause/Resume/Retry and queue-consumer semantics; original pinned-commit resume versus incompatible revision requests; and partial-residency cleanup/protection after cancellation. The reviewer endorsed delivering switching safeguards first and enabling two transfers only after ownership tests pass.

## Implementation and review

Implemented on `feat/concurrent-model-downloads`. Acquisition now retains independent model requests, coalesces identical repository transfers, limits active repositories to two, and serializes conflicting destinations. Foreground preparation has identity-based event ownership and explicit settlement. Settings exposes Pause/Resume/Cancel/Retry; folder changes, deletion, and Quit wait for storage and inference work. Quit drains MLX before allowing process termination.

The implementation reviewer approved after fixes for complete storage-transaction settlement at shutdown and revision provenance across downloaded releases, adapters, legacy folders, and packed variants. Explicit revision changes cannot accept same-sized old files. Packed provenance is written before atomic publication. Legacy main snapshots remain compatible.

The historical crash report showed termination during FLUX warm-up with an MLX scheduler abort. It supports the shutdown fix, but does not prove that model switching alone caused the reported crash.

Validation completed:

- 413 Foundation tests across 71 suites pass with both `make test` (parallel) and `swift test --package-path Packages/ZephraKit --no-parallel`. The concurrent-transfer tests use held URLProtocol responses and identify the actual admitted writer; cancellation assertions await settlement.
- `make CONFIG=Debug build`, `make lint-layers`, and `git diff --check` pass.
- Native UAT used a separately signed `io.zephra.DownloadUAT` bundle and disposable roots with `scripts/download-fixture.py`. FLUX 4-bit → 8-bit shared exactly one body request; switching to Z-Image started a second independent body. Pause/Resume, shared cancellation, Retry, foreground Cancel, Quit, relaunch, and moving the models folder during a transfer all passed. Recorded resume offsets included 2,293,760 and 5,636,096 bytes. Explicit Cancel removed the unfinished writable repository and preserved the completed shared release.
- 111 native tests pass: 36 MLX/quantization, 44 Z-Image backend, 21 Qwen backend, and 10 FLUX backend. The MLX test submits asynchronous GPU work and drains it through the runtime seam.
- UAT deliberately used fake model bytes with the real networking, engine, and UI paths. It did not run a full-weight quantization or warm-up. Tiny MLX tests cover device synchronization separately; the historical crash attribution remains a hypothesis.
