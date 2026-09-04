# Model directory selection and migration

## Problem and evidence

Settings persists `/Volumes/ExternalStorage/ZephraHome/`, but the reported download is writing to the default folder. The current folder picker publishes its preference and inventory before asynchronously handing the location to the engine. InferenceActor deliberately pins a running prepare operation to its starting folder. This proves a live-change mismatch; the reported restart behavior still needs reproduction rather than an assumed cause.

## Implementation plan

1. Trace startup, retry, model switching, and download destinations with current source and focused tests. Reapply persisted model locations at the interface bootstrap boundary before starting work. Verify a fresh process uses the saved external root and fails visibly if it cannot write there, without fallback writes.
2. Give folder changes a single engine-owned transaction. Prevent new generation/load/swap/upscale work during the change. Cancel and await a model preparation already in progress before committing the new destination; refuse the change during generation or upscaling, with a clear message. Release loaded weights before migrating files. Synchronize engine, persisted preference, and inventory only after success. Do not automatically restart a large download without making the behavior clear.
3. After choosing a different folder (including Use Default), offer Move Existing Models, Keep Existing Models Where They Are, and Cancel. Migration covers catalog-owned downloads, adapters, and built variants in the current models root, including resumable partial downloads. Keep previous roots readable for the keep option. The image library and read-only Hugging Face cache are outside this setting's scope. Allow migration from remembered roots to the selected current root too, so a user who already changed folders can recover existing data.
4. Implement Foundation-only migration in ZephraSnapshot, orchestrated in ZephraEngine. Preflight canonical paths, nested roots, symlinks, destination conflicts, writability, and available space. Never overwrite an existing destination model or follow a symlink outside the source. Copy across volumes into staging, verify copied files before publishing with rename, and remove source data only after the destination is verified. On failure keep original data and a recoverable state; report exactly what was moved or left. Keep the UI responsive and show progress. Block concurrent settings deletions and duplicate migrations.
5. Add meaningful tests using scratch folders and stub backends: fresh custom root, change during blocked download, retry into new root, previous-root fallback remains read-only, complete and partial migrations, collision/nesting/symlink refusal, failed copy preservation, and engine busy gating. Update settings wording and project documentation for the new behavior.
6. Run relevant tests, full Foundation suite, layer lint, and Debug app build. UAT the actual Settings flow with small disposable model fixtures, including cancellation, keep, migration, and restart persistence. Do not move or delete the user's real models during UAT.
7. Have a second sub-agent review the final diff and validation evidence. Address valid findings and rerun affected checks. Report completion and review findings before the merge-and-push step.

## Structure and boundaries

Keep model-family code unchanged unless tracing establishes a family-specific defect. Files stay focused and near the 150-line target, views at three stored properties, with no new global singleton. Use conventional commits on `fix/model-directory-migration`.

## Plan review amendments

Independent review confirmed that startup already injects saved locations: restart misrouting is not established. Bootstrap reapplication is defensive. Migration sources will be explicit, one remembered root at a time. Existing destination models cause a preflight refusal identifying the path and suggesting a fresh folder; compatible partial reconciliation is outside scope. Acquire the engine gate before suspension, await both load and switch tasks, and reject queued work. Preserve all partial-download metadata. Copy and verify every model before publishing any; keep originals if publication fails, reporting any published duplicates. Once all destinations publish, source-removal failures commit the chosen location with a warning. Add tests for pending model-switch cancellation and separate publication/cleanup failures.

## Implementation and validation

Implemented an engine gate around folder changes, cancellation and settlement of outstanding preparation, optional verified migration, explicit remembered-source selection, and destination validation for downloads and all three backend build paths. Settings persists only successful changes. Inventory location is observable, and bootstrap reapplies saved locations defensively.

- Independent implementation review found and resolved a mounted-volume URL directory-hint comparison bug. A regression test now covers it; the reviewer reported no remaining blocking findings.
- `make test`: 391 tests passed in 69 suites.
- `make lint-layers`, `git diff --check`, and `make CONFIG=Debug build`: passed.
- Native Settings UAT used an isolated app preferences domain and disposable fixtures. Cancel preserved the existing folder; Keep in Place changed the destination while retaining original files; Move Models Here migrated a resumable partial download from the internal disk to a real external volume. Exact bytes, revision pin, and ETag sidecar survived, source cleanup followed verification, and an unrelated source file remained.
- Relaunch preserved the external destination and the migrated inventory row. A destination conflict displayed the expected refusal and preserved both copies. Use Default offered the same move/keep/cancel choice and was cancelled before touching normal model storage.
- The user's real model folder preference and model files were not changed during UAT. Disposable model fixtures were removed afterwards.

The screenshot's restart-specific root cause remains unproven: startup already injected the saved preference before this change. Fresh-download regression coverage verifies that a selected root receives writes even with partial files in the old root, and restarting the UAT app retains the selected external folder. The confirmed live-change mismatch is fixed by stopping old preparation before committing a folder change.
