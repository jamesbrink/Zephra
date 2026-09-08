# Audit remediation, September 2026

The findings of the full-app audit of 8 September 2026, and how each is fixed.
Branch `fix/audit-remediation-2026-09`, off `main` at `aeb14f8`.

The work is split into six parallel workstreams with **strictly disjoint file
ownership**, then a seventh that runs afterwards because it needs the finished
tree. No agent touches a file another agent owns; new files go under the owner's
own name so two agents cannot create the same path.

Three product-level forks were decided by the user before any work started:

- Settings > About is **removed**. The About and Acknowledgments windows stay.
- The Help menu gets a **website link**, replacing the synthesized dead item.
- All three menu-wording changes are applied: Zoom In/Zoom Out, an alternating
  Hide/Show Prompt button, and an Edit > Find submenu.

---

## Phase 1 — six parallel workstreams

### A. Menus, focus, and the Command Delete conflict

**Owns:** `Sources/Zephra/Views/ZephraCommands.swift`,
`Sources/Zephra/Views/ZephraCommands+Library.swift`,
`Sources/Zephra/Views/WorkspaceCommands.swift`,
`Sources/Zephra/Views/ThumbnailSizeCommands.swift`,
`Sources/Zephra/Support/CommandTarget.swift`,
`Sources/Zephra/Support/FocusedValues+Library.swift`,
new `Sources/Zephra/Views/HelpCommands.swift`,
`Tests/ZephraTests/CommandTargetFocusTests.swift` (new).

1. **Command Delete deletes the canvas picture while the caret is in the
   prompt.** `ZephraCommands.swift:56` binds Delete scene-wide and disables it
   only by `target.isEmpty`; `CommandTarget.resolve` consults focus on the
   library branch and not on the canvas branch. In AppKit Command Delete in an
   `NSTextView` is `deleteToBeginningOfLine:`, so the menu wins and the picture
   goes to Recently Deleted instead of the line being trimmed. Give the canvas
   branch the same gate the library branch has: a focused value published by the
   prompt while it is first responder, which makes `resolve` answer `.none`.
   `CommandTarget.resolve` stays pure so it keeps its unit tests.
2. **Help menu.** `CommandGroup(replacing: .help)` with "Zephra Help" opening
   `AppFacts.website`, and "Acknowledgments" opening
   `AboutScenes.acknowledgmentsID`.
3. **Wording.** "Bigger Thumbnails"/"Smaller Thumbnails" become "Zoom In"/"Zoom
   Out". The `Toggle("Hide Prompt")` becomes a Button whose title alternates
   between "Hide Prompt" and "Show Prompt". Command F moves into an
   Edit > Find > Find… submenu.
4. **Duplicate Command A risk.** "Select All Images" carries Command A after the
   built-in `.pasteboard` group's own Select All. Establish which one the system
   reaches and, if both are live, replace rather than append.

### B. Sheets, and the destructive default button

**Owns:** `Sources/Zephra/Support/PurgeConfirmation.swift`,
`ExportCollisionPrompt.swift`, `ImageExport.swift`, `ImageExport+Files.swift`,
`ImageDirectoryChoice.swift`, `ModelDirectoryChoice.swift`,
`ReferenceImagePicker.swift`, new `Sources/Zephra/Support/ModalHost.swift`,
`Tests/ZephraTests/ModalHostTests.swift` (new).

1. **Destructive alerts default to the destructive button.**
   `NSAlert.addButton(withTitle:)` gives the *first* button the Return key;
   `hasDestructiveAction` only tints it. So Return currently confirms:
   - `PurgeConfirmation.swift:27` — permanent deletion. Its own comment on
     line 29 claims the opposite.
   - `ImageDirectoryChoice.swift:27` — a full library migration.
   - `ModelDirectoryChoice.swift:28` and `:44` — a multi-gigabyte model move.

   `ExportCollisionPrompt.swift:23` already gets this right and its comment
   states the rule correctly. Make the safe answer the default at all four
   sites, keep the destructive tint, and keep Escape on Cancel.
2. **Every dialog is app-modal.** Fifteen `runModal()` call sites. On the Mac a
   question about a window's contents is a sheet on that window. Add one
   `ModalHost` in `Support/` that answers with the right window — the key
   window, or the Settings window for a Settings-raised panel — and routes both
   `NSAlert` and `NSOpenPanel`/`NSSavePanel` through `beginSheetModal(for:)`,
   falling back to `runModal()` when there is no window to hang from (a menu
   command with every window closed). The existing justification for `NSAlert`
   over SwiftUI's `.alert` is sound and stays; it does not extend to `runModal`
   over `beginSheetModal`.
3. Presenting a sheet is asynchronous where `runModal` was not. Callers that
   read a return value become `async`, or take a completion; do not block the
   main actor waiting on a sheet.

### C. Release safety and the launch hooks

**Owns:** `Sources/Zephra/Support/SingleInstance.swift`,
`Sources/Zephra/Support/LaunchGeneration.swift`,
`Sources/Zephra/Views/RootView.swift`,
`Sources/Zephra/Resources/Info.plist`,
`Tests/ZephraTests/SingleInstanceTests.swift` (existing),
`Tests/ZephraTests/LaunchHookTests.swift` (new).

1. **`ZEPHRA_PREVIEW_STATE` disables the single-instance guard in Release.**
   `SingleInstance.swift:27` tests `InterfacePreview.name != nil` — the raw
   environment variable — while `InterfacePreview.requestedState` is
   `#if DEBUG`. In Release the preview is inert but the guard still stands
   down, so a second real Zephra runs over the same library and models folder,
   which is the one thing the guard exists to prevent. Test
   `requestedState != nil` instead. `SingleInstanceTests` cannot catch this
   today because it exercises the pure `shouldYield`; add a case for the
   isolation predicate itself.
2. **`LaunchGeneration` is not Debug-gated.** `RootView.swift:53` calls it
   unconditionally and the type has no `#if DEBUG`, so a shipped Zephra honours
   `ZEPHRA_GENERATE_ON_LAUNCH` and `ZEPHRA_REFERENCE_ON_LAUNCH`. AGENTS.md
   lists it under "Debugging hooks" beside `ZEPHRA_PREVIEW_STATE`, which is
   documented as inert in Release. Gate it the same way.
3. **Missing TCC usage strings.** Settings > General can point the library at
   Documents, Desktop, Downloads, or a removable volume, and `Info.plist`
   carries none of `NSDocumentsFolderUsageDescription`,
   `NSDesktopFolderUsageDescription`, `NSDownloadsFolderUsageDescription`,
   `NSRemovableVolumesUsageDescription`, so those prompts arrive with no reason
   attached. Add all four, worded for what Zephra actually does with the folder.

### D. Wording, and the Settings About tab

**Owns:** `Sources/Zephra/Views/Library/LibraryEmptyState.swift`,
`Sources/Zephra/Views/Library/LibraryDayHeader.swift`,
`Sources/Zephra/Views/ModelDownloadRow.swift`,
`Sources/Zephra/Views/Sidebar/ScopeChips.swift`,
`Packages/ZephraKit/Sources/ZephraCore/Upscale/UpscaleError.swift`,
`Packages/ZephraKit/Sources/ZephraCore/Backend/BackendError.swift`,
`Sources/Zephra/Views/AboutSettings.swift` (deleted),
`Sources/Zephra/Views/SettingsView.swift`,
`Sources/Zephra/Views/SettingsTab.swift`.

1. **British spellings in shipped strings**, against AGENTS.md's stated US-spelling
   convention and ROADMAP.md's claim that every literal already follows it:
   `LibraryEmptyState.swift:25` "No favourites yet";
   `LibraryDayHeader.swift:48` "favourite"/"favourites", shown directly under a
   sidebar row that reads **Favorites**; `ModelDownloadRow.swift:53`
   "Cancelled"; `UpscaleError.swift:23` and `BackendError.swift:33`
   "cancelled". `ScopeChips.swift:51` is a preview title only, fix for
   consistency. `LibraryScope.rawValue`'s `"favourites"` is a **persistence
   key** and must not change — changing it would orphan every saved scope.
2. **Settings > About is removed.** Delete `AboutSettings.swift`, drop `.about`
   from `SettingsTab`, and remove its case from `SettingsView.content(of:)`.
   Settings becomes three tabs. Check nothing else names `SettingsTab.about`.

### E. Correctness, deprecation, and appearance

**Owns:** `Sources/Zephra/Support/ClipFrames.swift`,
`Sources/Zephra/Support/BackgroundNotices.swift`,
`Sources/Zephra/Views/PromptTextView.swift`,
`Sources/Zephra/Views/MemoryReadout.swift`,
`Sources/Zephra/Views/WeightResidencyControl.swift`,
`Sources/Zephra/Style/ZephraChrome+Washes.swift`,
`Packages/ZephraKit/Sources/ZephraEngine/Library/LibraryIndex+Directory.swift`,
new `Sources/Zephra/Views/MemoryReadoutPoll.swift`,
`Tests/ZephraTests/MemoryReadoutTests.swift` (new).

1. **Deprecated AVFoundation on a macOS 15 floor.** `ClipFrames.swift:26` uses
   `asset.duration` (deprecated macOS 13) and `:33`
   `copyCGImage(at:actualTime:)` (deprecated macOS 15). Move to `load(.duration)`
   and `image(at:)`. Both entry points are `nonisolated static` and synchronous
   and are called from detached tasks; keep them off the main actor.
   `ClipFramesTests` reads a committed fixture and must keep passing.
2. **Swift 6 concurrency warnings**, `BackgroundNotices.swift:15-23`:
   `notice.title` and `notice.body` are main-actor properties read inside a
   `@Sendable` callback, and `center` is captured non-Sendable. Read the two
   strings before entering the closure. Also stop calling
   `requestAuthorization` on every post — ask once and remember the answer.
3. **Stale undo stack after a programmatic prompt replacement.**
   `PromptTextView.swift:72` assigns `textView.string` when the binding changes
   (picking a picture adopts its settings), but the coordinator's private
   `UndoManager` keeps the pre-replacement actions, so Command Z afterwards
   splices an old edit into the new text. Clear the stack on that branch.
4. **Discarded scan result.** `LibraryIndex+Directory.swift:26` drops a
   `LibraryIndex.Scanned`; the compiler warns. This is the only unused-expression
   warning in our own code — the Release build must end with zero warnings
   outside `Packages/ZImageKit`.
5. **`hoverWash` is appearance-blind.** `ZephraChrome+Washes.swift:21` is
   `Color.white.opacity(0.12)` while `wellFillHovered` two lines down correctly
   uses `Color.primary`. Over a bright thumbnail in Light appearance the wall
   square's one pressable affordance is close to invisible. Keep the wash
   instant — no fade — and keep it hit-test transparent;
   `WallSquareChromeTests` and the `make lint-layers` `hoverWash` rule both stay
   green.
6. **Three stored properties per view.** `MemoryReadout` (4) and
   `WeightResidencyControl` (4) are the only violations in the app target.
   Split the polling out of `MemoryReadout`.
7. **`MemoryReadout` claims a scope it may not have.** Its comment says it polls
   "only while this tab is on screen", but macOS `TabView` commonly builds every
   tab's content. Establish what actually happens and either fix the poll's
   lifetime or fix the comment.

### F. Window sizing

**Owns:** `Sources/Zephra/ZephraApp.swift`,
`Sources/Zephra/Views/WorkspaceSplitView.swift`,
`Sources/Zephra/Views/WorkspaceDetail.swift`.

1. **The main window has no minimum size.** `ZephraApp.swift:83` sets
   `.defaultSize` only. The sidebar floors at 240, the inspector is a fixed
   column, and nothing stops the window being dragged narrower than the three
   of them. Set a minimum from the parts' own floors rather than a guessed
   number, and check the toolbar still lays out at it.
2. **The Settings Performance floor may not fit a 13-inch display.** Its
   opening height of 820 is also its minimum; 820 plus the tab strip and title
   bar is about 880 against roughly 931 usable points on a 13-inch MacBook Air,
   and less under Larger Text. `SettingsTab.swift` is owned by workstream D, so
   D takes the number change; F establishes what the number should be and hands
   it over in its report. Note that D also removes the `.about` case, so the two
   changes land in one file from one owner.

---

## Phase 2 — after phase 1 is merged and green

### G. Lint the conventions that drifted

**Owns:** `Makefile`, `Packages/ZImageKit/VENDORED.md`, `AGENTS.md`,
`ROADMAP.md`, plus whatever files the new rules turn out to fail on.

`make lint-layers` enforces imports, repeating animations, and the `hoverWash`
hit-test rule. It does not enforce the four conventions that actually drifted:

1. **US spelling in user-facing strings.** A grep over string literals for
   `favourite`, `colour`, `centre`, `cancelled`, `behaviour`, `licence`,
   `grey`, `organise`, `analyse`, `normalise`. Must skip `LibraryScope`'s
   persistence keys, code identifiers, doc comments and `#Preview` titles —
   AGENTS.md exempts identifiers on purpose (`isFavourite`,
   `FavouriteToggle`).
2. **The `Manager`/`Helper`/`Utils`/`Service` type-name ban**, with
   `PromptLayoutManager` as the one documented exception.
3. **Three stored properties per view.**
4. **The 150-line target.** This is a *target*, not a hard limit, and six files
   sit just over it: `ModelDownloader+File.swift` 168, `AppSettings.swift` 166,
   `ZephraApp.swift` 155, `GenerationStore.swift` 153, `QwenImageBackend.swift`
   152, `BenchReport.swift` 151 — and phase 1 will have moved some of those.
   Decide between splitting them and making the rule advisory; do not add a
   failing gate.

Also in this phase:

- **`VENDORED.md`: what is linked but unreachable.** `Packages/ZImageKit`
  carries `ZImageControlPipeline` and `ZImageControlTransformer2D` (ControlNet),
  the whole `LoRA/` directory (adapters are merged in the packer, never at
  runtime), `Model/TextEncoder/Vision/` (the ViT that is documented as never
  loaded), and `WeightsAudit` — roughly a third of 10,946 vendored lines that
  Zephra never runs. The vendoring policy justifies keeping them; record which
  parts are unreachable, because it is license and audit surface for a
  commercial ship.
- **`get-task-allow` in a signed Release.** `build/Release/Zephra.app` carries
  `com.apple.security.get-task-allow` from ad-hoc signing. Confirm `make
  release`'s re-sign drops it; a shipped hardened-runtime app with that
  entitlement is debuggable by any process. Fix the Makefile if it does not.
- **AGENTS.md and ROADMAP.md** brought back in line with what the code does
  after every change above.

---

## Rules for every workstream

- Swift 6, strict concurrency, no new warnings. Match the surrounding comment
  density and voice — this codebase explains *why*, and a change that removes a
  reason is a regression.
- Swift Testing only. Suites and tests named as sentences about behaviour.
- Anything testable without Metal belongs in `Packages/ZephraKit`
  (`make test`); pure interface logic belongs in `Tests/ZephraTests`
  (`make test-app`).
- No file outside the workstream's own list. If a fix needs one, stop and say
  so in the report rather than reaching for it.
- Run `make lint-layers` and `make test` before reporting done. Do not run
  `make build`, `make test-app` or `make test-mlx` — the orchestrator runs
  those once, over the merged tree, because several `xcodebuild` runs at once
  on one machine thrash.
- Do not commit, branch, stash, or touch git at all. The orchestrator commits.

## Gate

`make lint-layers`, `make test`, `make build` with zero new warnings,
`make test-app`, `make test-mlx`, then a Codex peer review of the whole diff,
then merge to `main` and push.
