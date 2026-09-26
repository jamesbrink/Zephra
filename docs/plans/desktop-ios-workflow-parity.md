# Desktop and iOS workflow parity

One PR, on `feat/desktop-ios-workflow-parity`. The phone manages files on the
explicitly named Mac; it never downloads inference weights onto the phone.

## Scope and interaction contracts

1. Queue order is execution order, per Mac. Move whole waiting batches with
   drag/drop and accessible Move Earlier / Move Later actions. Preserve seed
   order and video continuations. A running batch and a model swap already
   preparing the next batch remain pinned. Validate stale IDs on the host;
   never recreate removed work, reorder another host, or interrupt inference.
   Add oldest/newest sorting for waiting batches, with explicit labels.
2. Models: a host-specific management screen reachable from Settings and the
   model picker. Download without choosing/loading, progress and errors,
   Pause, Resume/Retry, Cancel with confirmation, Load/Unload, and storage
   inventory with measured bytes, shared-source labels, and confirmed deletion.
   Deletion uses an opaque inventory token resolved by the Mac, never a path
   provided by a phone; recheck current inventory and in-use guards on action.
   Reuse the engine's download ownership and storage safety rules. Busy/offline
   states disable unavailable actions and explain refusals. Auto stays
   installed-only and never starts downloads.
3. Prompt history: record admitted requests once per press, including requests
   that subsequently fail, with timestamp and stable identity; bounded persistent
   history on the Mac, seeded from the library for existing installations.
   No reference pixels or generation settings in history. Desktop Up/Down at
   text boundaries recalls newest/older prompts and restores the unsent draft;
   ordinary multiline caret navigation and text selection remain intact.
   Visible History affordance and keyboard hint make it discoverable.
   iOS History sheet and previous/next controls use the chosen destination's
   history; Auto merges enabled connected Macs chronologically with host labels,
   stable timestamp/host/id tie breaks, without conflating identical filenames.
   Recalling replaces only prompt text and preserves model/settings/references.
4. iOS viewer: constrain the title beside Close, wrap long prompts in a
   selectable scrolling sheet, show host attribution, provide Copy and reuse
   actions. Validate long words, multiline prompts and accessibility text.
5. iOS Generate: full-width bounded scrolling multiline editor; separate
   reference area from prompt, accessible History controls, explicit keyboard
   Done action; keyboard dismissal must allow scrolling back to the top.
   Keep desktop capability-driven size/steps/guidance/length/seed/reference
   controls and preserve draft when watching or changing destination.

## Parity audit

Already present: reference strips, negative prompts, custom size/seed, seed lock,
chained clip duration, settings reuse, Copy/View Prompt, favorite/tags/delete,
Save/Share, multi-host owner-specific upscaling, model load/unload, live previews.
Additional gaps addressed here: download lifecycle controls/storage accounting,
queue ordering/clear controls per host, prompt navigation/discoverability,
model-management entry from generation, robust multiline composer layout.
The audit also confirmed mobile gaps in animation/clip continuation, queue
variations, Recently Deleted recovery, albums and multi-selection. These remain
explicit follow-up scope: they require media ownership/recovery contracts beyond
this PR's requested queue/model/history/composer/gallery controls.
Finder, local folder selection, Metal performance and Mac app lifecycle settings
are intentionally host-local. Other media operations are audited and any
remaining actionable gaps will be documented rather than silently claimed done.

## Compatibility and implementation

Optional `workflow` snapshot flag gates a new workflow command/reply envelope.
Expanded history and inventory are request/reply only, never new deltas or
unsolicited snapshots. Legacy clients never ask for or receive these payloads.
Resume calls downloadModel, never the load-producing resumeDownload. Queue
changes send an absolute order and expected entry IDs; any membership change
refuses stale intent. Cache operation results by request UUID so retries cannot
reapply order to newer work. Deletion tokens are session-local, bound to inventory
root and file identity, and single-use; repeated request IDs return their outcome.
History retains 100 requests and at most 256 KiB of prompt text, records all
admission paths by batch ID, excludes internal passes/reruns, and seeds old
library batches once. Arrow recall requires an unmodified arrow, no selection,
no IME marked text, and first/last visual line. Editing resets recall; returning
forward restores the draft. Auto filters live enabled nodes, with stable host/id
ties; legacy nodes fall back to their library. Destination changes reset recall.
Gallery pinch changes persisted thumbnail density from one to six columns,
with a Zoom menu alternative, scroll anchor preservation and no effect on viewer
zoom. Accessibility text defaults to one column.
Use small Core value types, Engine operations, Link DTOs/client commands,
LinkHost adapters and native platform views; keep the existing module graph.
No concrete backend changes.

## Milestones and verification

- Commit/push reviewed plan.
- Commit/push engine and compatible protocol contracts with meaningful tests:
  stale reorder, batch/chain integrity, pinned running/preparing work,
  golden legacy payloads, unsupported hosts, busy storage, failed transfers,
  request history and chronological multi-host selection.
- Commit/push desktop/iOS interactions with hosted tests and documentation.
- Build both applications and run ZephraKit, Link, Mac and iOS suites; layer lint
  before every commit. Rendered UAT on desktop and iPhone simulator covers
  queue changes during a run, every model state, confirmations, offline/legacy
  behavior, Auto versus manual history, draft restore, multiline scrolling,
  viewer overflow and Dynamic Type. Use isolated fixtures; do not delete the
  user's model files. Record evidence and distinguish simulated versus real
  encrypted host behavior. Shut down the simulator after UAT.
- Independent final implementation review; fix valid findings, rerun affected
  checks, then open one PR and verify CI on its exact head. Merge after the
  user's final review as requested, preserving the single-PR boundary.
