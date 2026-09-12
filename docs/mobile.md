# The phone

The long form of the matching section of `AGENTS.md`: the rules there, the
reasoning and the history here. When the two disagree, `AGENTS.md` is wrong or
this is stale; fix both.

`Sources/ZephraMobile` is the companion app: an iPhone app that shows what a
paired Mac is making and asks it for more. It renders nothing itself. There is
no MLX on a phone, no model folder, no library folder and no engine — every
number on its screen came over the link, and every button it has is a message
sent. That is the whole design, and it is what the layering rule below is
protecting.

## The target

`ZephraMobile` in `project.yml`: an iOS 18 application, arm64, portrait, iPhone
only (`TARGETED_DEVICE_FAMILY: "1"`), `io.zephra.ZephraMobile`, product name
`Zephra`. It links exactly five of our own modules:

```
Sources/ZephraMobile -> ZephraCore, ZephraLinkProtocol, ZephraLinkTransport,
                        ZephraLinkClient, ZephraStyle
```

- `ZephraCore` for the value layer both apps read: `ModelCapabilities` and the
  `clamp` that goes with it, `ImageSize`, `SeedEntry`, `SeedFormat`,
  `SizeEntry`, `ReferenceRole`, `DurationLabel`, `ChainPlan` and `ClipLength`.
  The phone runs the Mac's own rules rather than a second copy of them that
  could drift.
- `ZephraLinkProtocol` for the wire: the pairing payload, the state snapshot and
  its deltas, the commands, the library page. See `docs/companion.md`.
- `ZephraLinkTransport` for the roads and for `LinkBackoff`. The app names them
  because the app is what knows the relay's URL and what hands
  `NetworkLinkRoads` this device's identity; nothing under the root opens a road.
- `ZephraLinkClient` for `LinkClient`, which is the one type a view reads the Mac
  through.
- `ZephraStyle` for the chrome: every radius, hairline, wash and colour set the
  Mac is drawn from. The two apps look like one program because they are drawn
  from one set of numbers.

Four system frameworks are linked by name: `AVKit` for a clip fetched from the
Mac, `VisionKit` for the pairing scanner, `Photos` for saving a picture to the
camera roll, and `PhotosUI` for `PhotosPicker`, the camera-roll door into the
reference well — its own framework and not part of `Photos`, because the picker
runs out of process, so the app never asks for a photo permission of its own and
only the picture somebody chose crosses.

`ZephraLinkProtocol` depends on `ZephraEngine`, which depends on
`ZephraSnapshot`, so both compile for iOS as well. Three places in them reached
for `FileManager.homeDirectoryForCurrentUser`, which is a Mac API — `HubCache`,
`ImageLibrary.pictures()` and `SnapshotUnderTest` — and all three are now
spelled `#if os(macOS)` with the container's home on the other side. None of
them is ever called from a phone: there is no hub cache there, no images folder
and no model snapshot. They only have to compile.

Two settings are spelled out on the target because a name is doing two jobs:

- `PRODUCT_MODULE_NAME: ZephraMobile`. The app is *called* Zephra, but the Mac's
  app target already owns that module name, and two modules called Zephra in one
  project is a trap every `@testable import` falls into.
- `TEST_HOST` on `ZephraMobileTests`. XcodeGen's default is
  `$(TARGET_NAME).app/$(TARGET_NAME)`, which is `ZephraMobile`; the bundle on
  disk is `Zephra.app/Zephra`. The Mac pair never noticed, its target and its
  product being the one word.

`make lint-layers` enforces the rest: nothing under `Sources/ZephraMobile` may
import a model package, MLX, a backend, an upscaler, `ZephraMedia`,
`ZephraSnapshot`, `ZephraEngine` or `AppKit`. The repeating-animation ban and
the US-spelling check cover it the same way they cover the Mac, and
`ZephraKit`'s UI ban now names `UIKit` beside `SwiftUI` and `AppKit`.

## The shape

Four directories, by what a file is, the way the Mac's target is laid out.

- `App/` — `ZephraMobileApp` is the composition root: it builds the one object
  every view observes and injects it, and it is the only file that knows how a
  Mac is actually reached. `RootView` is the four surfaces behind a `TabView`
  bound to `MobileSelection.tab`, with `PairingView` over them as a
  `.fullScreenCover` until a Mac is paired. A cover rather than a branch, so the
  tabs are built once and keep their state.
- `Support/` — the cross-cutting answers. `MobileKeychain`, `LinkReconnect`,
  `MobileTab` and `MobileSelection`, `PairingEntry`, `MobilePreview`,
  `DecodedPicture`.
- `Style/` — `MobileChrome`, and only what has no counterpart on the Mac: the
  room the tab bar takes, the side margin, the gap between blocks. Anything
  a radius, a hairline or a wash could be belongs in `Packages/ZephraStyle`.
- `Views/` — one subfolder per surface, and every surface is real:
  `Canvas/` and `Capsule/` are the two halves of the first, what the Mac is
  making and what asks it for more; `LibraryScreen` and `TodayScreen` are the
  Mac's library and its canvas sidebar; `SettingsScreen` is `PairedMacRow`,
  `ConnectionRow`, `AppearanceRow`, `RandomizeSeedRow`, `SeedFormatRow`,
  `CacheRow` and `AboutRow`, a row to a file, so a later change replaces one of
  them rather than editing a screen around it. `Shared/` is the one exception
  to "a subfolder per surface", and it holds exactly what two surfaces draw the
  same way: `ClipPlayerView`, `EntryThumbnail` and `StopRunButton`, which the
  Today tab's running card and the capsule both draw.

`MobileSelection` (`Support/`) is where the phone is looking: which tab is up,
whether the capsule is showing its settings, and whether the prompt wants the
keyboard. The Mac's `WorkspaceSelection` in a phone's shape, and it exists for
the same reason — which surface is up is a fact several places **write**. The
library's "Use as Reference" moves it, and a binding threaded down through four
surfaces to let one menu item change a tab is worse than one object in the
environment. Nothing in it is persisted: a launch opens on the canvas, or
wherever a frozen preview state asked for, and always with the keyboard down.

Focus is there rather than in the capsule for a reason of the same kind. The
view that asks for the keyboard is the collapsed prompt line, and it no longer
exists by the time the editor is on screen; a `@FocusState` can only be written
by a view that is still there. So the wish outlives the tap —
`expandCapsule(focusingPrompt:)` records it, `collapseCapsule()` clears it, and
`PromptEditor` mirrors it into its own `@FocusState` both ways.

### Settings

`MobileSettings` (`Support/`) is the phone's whole preference layer — the Mac's
`AppSettings` in a phone's shape, and deliberately the first thing built rather
than grown one item at a time, so the surfaces landing after it (seed spelling,
the seed rule, the rest) bind an `@AppStorage` key that already exists instead
of inventing their own store.

`store` is `.standard` for an ordinary launch. Under a frozen preview state —
which is every screenshot *and* every hosted test, since the `ZephraMobile`
scheme's test action always sets `ZEPHRA_PREVIEW_STATE` — it is a suite of its
own, `io.zephra.ZephraMobile.preview`, with its persistent domain removed
before anything reads it. Without that a screenshot taken with Appearance set
to Dark would leave the next hosted test run reading Dark too, since
`UserDefaults` suites persist to disk like any other; emptying the domain at
each frozen launch is what makes a screenshot and a test start at the same
defaults every time, the same problem `FreshStart` solves for the Mac's own
preferences.

Applying the choice is simpler here than on the Mac. `AppearanceApplier` sets
`NSApplication.appearance`, because a `preferredColorScheme` on one scene would
leave Settings, menus and alerts on the system's own appearance — the Mac has
several windows. The phone has one `WindowGroup`, so `AppearancePreference`
puts `preferredColorScheme` at the root and every sheet and alert under it
inherits it for free. `AppearanceMode` itself is `ZephraStyle`'s rather than
either app's own: it is one preference two apps apply their own way, and a
type an iOS target and a macOS target can both compile is what a shared
package is for.

### `LinkClient`, and how it stays connected

`LinkClient` (`ZephraLinkClient`, see `docs/companion.md`) is the one type a view
reads the Mac through: `pairedHost`, `snapshot`, `preview`, `library` and
`connection`, with `pair(with:)`, `connect()`, `disconnect()`, `forgetHost()` and
the commands. Every view takes it from `@Environment(LinkClient.self)`. **Keep it
that way**: a second object holding a fact that came over the link is a fact that
can disagree with the Mac.

The composition root builds exactly one, and it is the only file that knows:

- **Where the secrets are.** `MobileKeychain` (`Support/`) is a `LinkKeyStore`
  over two generic-password items under the service `io.zephra.link`, the
  identity's sixty-four raw bytes and the `PairedHost` as `LinkJSON`, both
  `AfterFirstUnlockThisDeviceOnly` — the phone reconnects while it is locked in a
  pocket, and a backup restored onto another phone must not arrive already paired
  with somebody's Mac. The identity is resolved by the root rather than left to
  `LinkClient`, because `NetworkLinkRoads` needs the same one to sign a relay
  join with.
- **Which roads.** `NetworkLinkRoads(relayURL:identity:)` over
  `wss://zephra-link.urandom.io`, with `UIDevice.current.name` as the name the
  Mac is shown while somebody decides whether to let this phone in.
- **When to reach.** `LinkReconnect` (`Support/`) owns one task: `begin()` on
  `scenePhase == .active`, `end()` on `.background`, and after a failure
  or a session that dropped, `LinkBackoff`'s one, two, four, eight seconds capped
  at thirty until one works — the count reset by a live session and by the app
  coming to the front. Both call the client's own `connect()` and `disconnect()`,
  and `connect()` is idempotent, so nothing here keeps a flag of its own. The wait
  on a live session is `LinkClient.sessionEndings()`, which every way a session
  ends yields on — a `peer left`, a send that failed, a road that closed — so a
  dead session is reconnected to at once and not on the next foreground. The
  iterator lives in `SessionEndings`, a nonisolated box, because an `AsyncStream`
  iterator that is dropped ends the stream behind it; `heartbeat` is the fallback
  for a stream that has finished, since waking on the observable state itself is
  iOS 26 and the phone runs on 18.

  It is `@Observable`, because the wait is on screen. Before each sleep it writes
  the moment the next attempt is due to `nextAttemptAt` and to the client, through
  `markWaiting(until:)`, which is `LinkConnectionState.waiting(reason:until:)` —
  the failure's own sentence, kept, and a date. `retryNow()` cancels the sleeping
  loop and starts another, which is the Settings row's Retry Now and what a change
  of network path does. Three ways in take the loop down — `end()`, `retryNow()`,
  and nothing else — and each leaves what it cancelled on `settling`, which `run()`
  awaits before it does anything: an attempt already in flight is not something a
  cancellation stops part way through, and a second loop over one would be two
  roads to one Mac.

- **Which network.** `LinkPathWatch` (`Support/`) is an `NWPathMonitor` started with the
  reconnection and stopped with it. Every report becomes a `LinkPathMark` — satisfied,
  expensive, constrained, and the interface names **in the system's own order of
  preference** — and `reaction(from:to:isLive:)` is the whole decision: the first report and
  an unchanged path are nothing, a path that carries nothing is nothing (no road would open
  over it, and the wait already running is the right thing to be doing), a new path with
  nothing connected is `retryNow()`, and a new path under a live session is `client.probe()`.
  The two failures are one moment from either side: a phone that walks out of the house sits
  out a thirty-second wait it was given for a Mac that was asleep, and a phone that leaves
  Wi-Fi mid-session keeps a socket whose interface is gone, which delivers nothing and tells
  neither end. `probe()` sends a `ping` and gives the Mac `probeTimeout` (5 s) to answer the
  `pong` that names it, ending the session as `timedOut` where it does not; the Mac has
  answered pings with `inReplyTo` since the first build, so nothing at that end changed. The
  decision is pure and `LinkPathWatchTests` pins it; the monitor itself is exercised by hand,
  by turning Wi-Fi off.

  What that looks like: Settings shows "Reconnecting" with a countdown under it,
  `Text(timerInterval:)` so the clock is the system's own view and not a timer
  ticking state — the repeating-animation ban is `make lint-layers`' and it covers
  this target — beside a Retry Now button, since thirty seconds is right for a Mac
  that is asleep and wrong for one somebody has just woken up. The capsule says
  "Reconnecting to your Mac." for every state that is on its way to a session and
  "Offline. This is the last thing your Mac said." for the two that are not
  (`ConnectionNote`, the one place either sentence is written).

Under a frozen preview state the root builds `LinkClient.frozen` instead and no
`LinkReconnect` at all: a client with no road under it has nothing to reconnect.

### Pairing

Three doors, one parser.

- `PairingScanner` (`Views/Pairing/`) is VisionKit's `DataScannerViewController`
  over `.barcode(symbologies: [.qr])`, the one piece of UIKit in the app. Shown
  only when `DataScannerViewController.isSupported && .isAvailable`, which is
  never in the simulator. It reads each code **once**: `ScanGate` in the
  coordinator drops a text equal to the last one handed on, and the view pauses
  the scanner while `client.connection.isBusy`. Both exist because the first
  real phone never paired by camera: every SwiftUI update restarted the scanner,
  a restart reports the code in frame again, each report was a `pair(with:)`,
  and each `pair` begins by closing the session before it. The relay saw the
  phone join and leave 260 ms later without a frame, as long as the code was in
  view. A new code is read; the same code again is the paste field's job.
- `PairingPasteField` is always shown, for that reason and two others: a code
  can arrive by message as easily as on a screen, and nobody using VoiceOver
  should have to aim a camera.
- `.onOpenURL` for a `zephra://pair` link. It is handled on `PairingView` while
  the pairing screen is up, so a code that arrives as a link fills the field and
  a bad one says why where the person is looking; `RootView` handles it only
  once a Mac is paired, which is re-pairing to another Mac, and reports a failure
  as an alert. Exactly one of the two fires for any given link.

All three go through `PairingEntry.parse`, which is `PairingURL.decode` plus the
two rules that decode does not know, both of them about the person holding the
phone. A code has a life, and an expired one is refused here, with a sentence,
rather than at the far end as a timeout. And everything thrown is a `LinkError`:
the payload is JSON under a base64 alphabet, so a code cut in half comes back as
a `DecodingError` complaining about an unexpected end of file, which is not a
sentence to put in front of anybody. `PairingEntry.message(for:)` is the one
that goes on screen, for a refusal from the far end as much as for a bad code.

## Canvas and capsule

The canvas is the surface the app opens on, and it is two things: what the Mac
is making, and the capsule that asks it for more.

### `PromptDraft`, the phone's capsule

`Support/PromptDraft.swift` is `@MainActor @Observable`, built once by the
composition root beside the client and injected with it. It holds
`GenerationSettings` — the Mac's own type — the model the next press names, the
reference picture as PNG bytes and the shape they came out at, and how many
seeds one press is worth.

It is the one object on the phone that holds something the Mac did not say, and
that is exactly the line: a draft is a request being composed, never a fact
about the Mac. The facts stay on `LinkClient`.

- `adopt(_ snapshot:)` seeds the model and its defaults, **the first snapshot
  only**. Every snapshot after it would land on a prompt somebody is in the
  middle of typing. Having seeded, it follows `snapshot.running`, so a phone
  that connects mid-run shows the prompt at once.
- `follow(_ running:)` (`PromptDraft+FollowingRun`) is the Mac's own
  follow-the-run rule (`GenerationStore+FollowingRun`, `watchRun()`) in a
  phone's shape: when a run starts, the draft takes its `settings` and
  `modelID` — the well emptied, since the phone has no pixels for the Mac's
  picture, `referenceOrigin` kept as the row carries it, the continuation
  dropped with the well — **only while the draft is untouched**: its prompt is
  empty or is the last prompt it followed or sent. `followedPrompt` is that
  one fact, set by `follow` and by `noteSubmitted`, which `GenerateButton`
  calls once the Mac has answered `queued`. So a run the phone submitted is
  followed harmlessly, a later run of the Mac's replaces it, and a prompt
  somebody typed is never written over. `DraftFollowsMac` (`Views/Canvas/`) is
  the modifier that calls both, on the first snapshot and on every change of
  `running?.id`; a run ending changes nothing, the way the Mac's capsule keeps
  a finished run's settings.
- `request(clampedBy:)` rebuilds the real `ModelCapabilities` from
  `CapabilitiesSummary` and runs the Mac's own `clamp`. The phone therefore asks
  for what the Mac would have allowed, rather than for something the Mac quietly
  rewrites while the controls go on showing what was asked for. The picture is
  put back into the settings just long enough to be clamped, since `clamp` is
  what drops it for a model that reads none; `GenerationRequest` strips the
  bytes on the way out, because a picture crosses as a blob. The clip's length
  is the one thing put back after the clamp: `clamp` bounds it at one pass on
  purpose, since no backend runs more, and a longer clip is a chain the Mac
  plans from the length it is handed (`GenerationStore.enqueue` calls
  `ChainPlan.segments` and clamps only the first pass). So the request carries
  the whole length through `ChainPlan.frames`, bounded by `ChainPlan.maxFrames`
  and snapped to the model's ladder; a clamped length here would be a
  ten-second clip quietly cut to five.
- `submission(clampedBy:randomizingSeed:)` (`PromptDraft+Submission`) is the
  press itself, and the one moment a seed changes without anybody asking. The
  phone used to send the same seed every time: the draft seeds itself once a
  launch, `randomizeSeed()` was the shuffle button's alone, and `follow` copies
  the running run's seed back — so two presses of Generate made the same
  picture twice. The Mac picks its fresh seed in `generateFromInterface`, under
  `randomizeSeedEachRun`, *before* the request is built; `GenerationStore.enqueue`
  — the door a phone's request comes through — deliberately randomises nothing,
  since a request that crossed the link is one somebody already composed. So the
  phone does its own, in the same place the Mac's own interface does. The seed is
  written back into the draft rather than only into the request, because a chip
  showing the last run's seed is a chip lying about the picture being made, and
  it is picked before the clamp, since the clamp is what will actually run.
  `GenerateButton` reads the flag in its action rather than holding a fourth
  stored property — again the Mac's pattern. `SeedLockToggle` (`Views/Capsule/`)
  writes the same key from beside the seed, closed for a seed held and open for
  a fresh one each press, because the moment somebody wants a seed kept is the
  moment they are looking at it. The lock guards the press and nothing else:
  `follow` still takes a run's whole settings, seed included, exactly as the
  Mac's `watchRun()` does.
- `choose(_ model:)` puts steps, guidance, strength and length on the new
  model's ladder, which is `GenerationSettings.onSchedule(of:)`'s rule: a number
  inside both models' bounds survives clamping while meaning something else on
  the other side of it. The prompt, the size and the seed carry over.
- `adopt(_ picture:origin:fitting:)` is where **the size follows the picture**,
  the same rule as the Mac's `useAsReference`: on a model that makes clips the
  frame becomes the picture's own shape at the pixel budget in force
  (`ModelCapabilities.size(matchingAspectOf:budget:)`), because a clip is the
  picture moving; a model that makes pictures leaves the size alone.

### What the canvas shows

`CanvasPicture` follows the Mac's order of precedence. A run showing its frames
beats a finished picture, because what the model is doing now is what somebody
picked the phone up to see: `client.preview` through `LivePreviewView`, the
JPEG letterboxed into the run's own aspect at `.medium` interpolation, since a
frame is an estimate and should not pretend to be the print. Before the first
frame lands, `RunPlaceholderView` — the safelight card, the system's spinner and
the Mac's own word for the phase. Otherwise the newest history entry's picture,
through `ItemPicture`, or `ClipPicture` and `ClipPlayerView` for a clip, looped
and muted unless the asset itself says it has a track.

Both read `LibraryCatalog`, which is **the one cache on this phone**. The canvas
had one of its own once — a singleton actor of decoded pictures — and fetched
whole files straight past `FileStore`, so every picture crossed the link twice,
once for each surface; a clip went into the temporary directory, outside the
budget entirely. Now the file the library fetched is the file the canvas draws
and the other way round, one crossing of what may be a relay serves both, and
`CacheBudget` sees everything. Nothing is decoded on the main actor:
`DecodedPicture` is that one line, in one place, and there is no second copy of
the bytes in memory to go stale.

A fetch has three states and not two (`FetchPhase`): a picture that is not
coming says so, because a blank square reads as a bug rather than as a link that
is down.

Neither the placeholder nor anything else on this surface animates. The ban is
the Mac's, for the Mac's reason, and `make lint-layers` covers both targets.

### The capsule

`PromptCapsule` sits in the canvas's bottom safe area, **not** in a sheet: a
sheet covers the tab bar, and the four surfaces have to stay one tap apart
while a prompt is being typed. Collapsed it is one line of prompt and the
button, which is what a phone in a pocket is for. Expanded it is the Mac's
capsule, read top to bottom instead of left to right — the editor and the well,
the negative prompt, the settings, the count and the button. Whether it is up is
`MobileSelection`'s, not a `@Binding` threaded down from the canvas: the chevron,
the collapsed line and the keyboard's Done button all write it.

**One tap opens the prompt with the keyboard up.** It used to take two, and the
reason is worth writing down, because the obvious fix does not work. The
collapsed line was a `Button` over a `Text`; the tap flipped the capsule open,
`CapsuleExpanded` then mounted `PromptEditor`, and the `TextEditor` that should
take the keyboard did not exist when the tap began. A `@FocusState` cannot be
written by a view that is going away, so the wish for the keyboard is kept where
the rest of "where the phone is looking" is kept: `expandCapsule(focusingPrompt:)`
on `MobileSelection`. `PromptEditor` reads it once it is mounted, in a `.task`
after one `Task.yield()` — the Mac's `AlbumNameField` rule, since focus set in
the same pass as the view's first layout is dropped — and mirrors its own
`@FocusState` back with two `onChange`es, so the interactive dismissal of the
keyboard is seen too. The collapsed line is drawn as a field rather than as plain
text: it behaves like one, so it should look like one. `collapseCapsule()` takes
the keyboard down with the settings, because the editor is inside them and a wish
left standing would bring the keyboard back the next time the capsule opened. A
tap on the canvas picture drops focus as a `simultaneousGesture`, which leaves a
clip's own controls the taps they are waiting for. Nothing here changes the
frozen `capsule` state: it opens the settings and asks for no keyboard, since a
screenshot of the controls with a keyboard over them shows half of them.

Every control is drawn from the capabilities and hidden by the same rules the
Mac follows, and each re-checks the bounds itself: when the model changes, a
control's body can be re-evaluated with the new bounds before the row above
takes it away, and a `Slider` over a single value stops the app, which is how
the Mac once crashed on a model switch.

- `SizeMenu` over `SizeOptions.grouped(capabilities:reference:)`, the Mac's
  `SizeChoice.grouped` rule: presets by `SizeTier`, the well's picture's shape
  leading each tier at that tier's cost, "Custom Size…" into a sheet that reads
  `SizeEntry`.
- `StepsControl` as a stepper where the count is a choice, `GuidanceControl`
  where the model responds to guidance, `DurationControl` where `frameBounds` is
  a range — `ClipLength`'s menu, which is the Mac's: one pass by the second,
  then the longer clips the Mac makes as a chain of passes, each saying how many
  — `ReferenceStrengthControl` only while there is a picture and the
  bounds are a real range, with `ReferenceRole`'s own sentence under it.
- `SeedControl` spells the seed with `SeedFormat` — `ZephraCore`'s, not a copy
  of it — and reads one back through `SeedEntry`. Which spelling is the Settings
  tab's, reaching the chip as `\.seedFormat`: `SeedFormatPreference` is one
  `@AppStorage` at the root writing one environment value, the Mac's own shape,
  because the views that draw a seed are already at their three stored
  properties and the preference is one fact for the whole app. Hex is still the
  default, for the reason it is the Mac's — eight characters tell two seeds
  apart on a chip a phone has little room for — and the number is for the person
  who copies seeds between tools. Whichever is shown, the whole seed is in the
  accessibility label and the entry sheet opens on the whole seed exactly
  (`SeedFormat.exactText`), so Return with nothing typed keeps the seed it had;
  only what the sheet's footer names first changes with the setting
  (`SeedEntrySheet.footer(for:)`). `SeedEntryField` is split off it the way
  `SizeEntryField` is, so the sheet can hold the draft, the spelling and the way
  to close without a fourth property. Beside the shuffle is `SeedLockToggle`,
  the Mac's own lock over the Mac's own preference: open, every press picks a
  fresh seed; closed, the seed on screen is kept. `CountControl` is
  `GenerationRequest.countBounds`, read from the protocol rather than written
  down again.
- `ReferenceWell` captions itself from `ReferenceRole`, so a clip's first frame
  is called a first frame here as it is there. Three doors, one rule:
  `PhotosPicker` for the camera roll, `ReferencePickerSheet` for the Mac's own
  library, and the library tab's own "Use as Reference". All three end at
  `ReferenceAdoption`, which encodes off the main actor with
  `ReferenceImageEncoder` — ImageIO, PNG, 1024 pixels an edge. The two that name
  a picture already on the Mac go through `ReferenceIntent` and take the same
  path; the picker draws `LibraryCatalog`'s entries rather than a library of its
  own, so it shows what the Library tab shows, works with no Mac in reach, and
  shares every thumbnail with the grid.

`GenerateButton` never changes its word and never goes away. `GenerateAvailability`
(`Support/`) is the whole of what it may do, read off four things the Mac said:
a live session, `acceptsWork`, `engine.canQueue`, and a prompt to make. Nothing
there is recomputed from the engine's case — `canQueue` is the Mac's own answer,
the one `remoteAdmission` gates on, so a press the button offers is a press the
Mac takes and a button that is grey is grey for the Mac's own reason.

That is what makes queueing from the phone work at all. The engine, the wire and
the host have always admitted work mid-run; what stopped it was this button
swapping itself for Stop while `kind == .generating`, which is the one state a
second press is most wanted in. So Stop moved out of the way: `StopRunButton`
(`Views/Shared/`, shared with the Today tab's running card) sits *beside*
Generate while a run is in flight rather than in its place. A thumb on its way
down to queue a second picture lands on Generate, not on the control that throws
away the first — and the Mac's own capsule has always behaved this way, where
Generate mid-run queues and File > Stop Generating is somewhere else entirely.

`GeneratePress` (`Support/`) is where one press has got to: `idle`, `sending`
while the Mac is being asked, or `refused` with the Mac's own sentence. The
button is disabled while a press is in the air, since a relay round trip is long
enough for a second press to arrive before the first is answered — and though
`enqueue` is idempotent by `requestID` at the far end, a button that looks live
while nothing has happened is a button somebody presses again. One line under it
carries the refusal, or, with nothing refused, how many runs are waiting
("3 waiting"). A sentence rather than an alert, since an alert over a phone's
canvas hides the picture it is about.

`CountChip` (`Views/Capsule/`) is the collapsed capsule's one reading of what a
press costs: "×3" when `draft.count` is more than one, tapping through to the
settings where the stepper is. Nothing at a count of one, which is every session
that never touched it.

Offline, the last picture stays and the capsule says so in one line, because
everything on the screen is still the last thing the Mac said.

What this surface deliberately leaves out — a picture saved to the camera roll —
is in `ROADMAP.md`.

## The cached library

The Library tab is the Mac's library, and it works with no Mac in reach. That
is the one place the phone keeps something, and it is worth being exact about
what it is: **the Mac's folder is the truth and this is a cache**. Nothing in it
is authoritative, nothing in it is backed up, and clearing it loses nothing.

`Support/Cache/` is three stores and two pure rules.

- `CachedEntry` wraps `LibraryEntry` rather than copying its fields, and codes
  transparently — a file in the cache is byte for byte the JSON that arrived.
  Two reasons. The record and the annotation inside an entry are `ZephraEngine`
  types and the phone may not import that module, so nothing here can spell one
  of those names; and an entry that *is* the wire's entry cannot drift from what
  a Mac would send. The facts the surfaces read (`prompt`, `modelID`,
  `isFavourite`, `videoSeconds`, `upscaleFactor`) are lifted out as scalars, and
  `searchKey` is folded once when the entry is taken in rather than on every
  keystroke.
- `EntryStore` is a JSON file per picture under
  `Application Support/Library/Entries/<file name>.json`. A file each rather
  than one document, because what happens to this folder is a handful of entries
  changing: rewriting a thousand-entry list to record one favorite is a write
  the size of the library for a change the size of a bool.
- `ThumbnailStore` keeps the JPEG bytes exactly as they arrived, under
  `Thumbnails/<2-char shard>/<digest>.jpg`, where the digest is the SHA-256 of
  the file's name, its modification time and the pixels asked for. That is the
  Mac's `ThumbnailKey` rule moved one device along, and for the Mac's reason: a
  picture that changed misses rather than showing yesterday's pixels under
  today's name. Two sizes only, 256 for a cell and 512 for the viewer — a phone
  has one grid at one width, where the Mac's slider needed four buckets.
- `FileStore` keeps whole pictures and clips in `Caches/Files/`, named as the
  Mac names them, a clip's MP4 beside its poster under the same stem
  (`VideoSidecar`'s rule). `CacheBudget` caps it at 512 MB and drops the least
  recently **read** first, not the least recently written: a clip watched four
  times today is worth more than a picture fetched once this morning. The access
  date is set explicitly on every read, because iOS mounts with `noatime` and
  every file would otherwise look equally old.
  A clip is **asked for under one name and kept under another**, and the reason
  is worth writing down because getting it wrong made every clip unfetchable for
  a while: the Mac's index is its *pictures*, so `item(named:)` resolves a
  poster's name and nothing else, and a request naming `<stem>.mp4` comes back
  `notFound`. `Command.fetchFile` answers a clip's video for its **poster**, so
  the request names the poster and the bytes are filed beside it as the sidecar,
  which is what `hasFile(for:)` reads back. `url(named:isVideo:)` is the one
  place that rule lives.
- `LibrarySync.plan(remote:local:)` is pure: an entry is taken in when the cache
  has never heard of it and again whenever its file has moved, which
  `CachedEntry.isStale(against:)` decides from the three facts
  `LibraryEntry.version` is made of. Favoriting a picture on the Mac rewrites
  its PNG, so its modification time moves and its version with it — which is the
  whole reason an annotation change reaches the phone at all.
- `CachedLibraryQuery` is the Mac's `LibraryQuery` cut to the two axes a phone
  has: a scope (All, Favorites, Clips) and free text over the prompt, the tags,
  the seed and the model. It answers `sections`, grouped by day, newest first.
  **Nothing in a view filters**, as on the Mac.

`LibraryCatalog` (`@MainActor @Observable`, split by concern like
`GenerationStore`) is what the surfaces observe. `start(client:)` reads the disk
*before* it looks at the client — the offline promise in one line — then follows
`client.library` and `client.connection` in one `withObservationTracking` loop,
both in the same arming because both decide what the surface draws. Fetching a
thumbnail or a file is store, then Mac, then store, and `LibraryCatalog+Media`
is the **only** place either crosses the link — the canvas's picture and the
well's reference come through it too, which is what makes it one cache rather
than a library cache with two private ones beside it. Favoriting, tagging and
deleting are optimistic and revert on a refusal, the way `LibraryIndex`'s
mutations are; nothing here invents a `version`, since the Mac decides what a
file's fingerprint is and a guessed one would make the next sync think the cache
was current.

**The library is pulled, not pushed**, and the Library tab was empty for a whole
afternoon on a real phone because it was not. The Mac publishes what *changed* in
its folder and counts the folder in the snapshot; it never sends the folder. A
phone that had just paired therefore saw a full Today tab and an empty grid until
somebody at the Mac made or edited a picture. `LinkClient+LibraryPull` is the
other half: every snapshot — which is every connect — starts one task that asks
for `libraryPage` at offset 0 in pages of a hundred, newest first, one in flight
at a time, absorbing each page into `client.library` as it arrives, so the grid
fills a page at a time rather than after the last one. A page that is refused is
asked for again from the same offset after `LinkBackoff`, for as long as the
connection is live; a session ending cancels the pull and the next session's
snapshot starts a fresh one. Nothing in it touches the Mac's store, so it keeps
going while the Mac is generating.

One rule is worth spelling out because it is not obvious. A `LibraryChange.reset`
carries at most `CompanionPublication.resetThreshold` entries — a hundred — so a
phone that treated every reset as the whole library would throw the rest of its
cache away the first time somebody with two thousand pictures rescanned a
folder. `LibrarySync.plan` still answers with the removals, because it is a pure
function over what it was given; `LibraryCatalog` applies them only when
`client.libraryIsComplete` says the pull has read the last page, and keeps what
it has otherwise. Counting was what it used to read — `client.library.count`
against `snapshot.libraryCount` — and counts cannot tell a short listing from a
complete one.

Offline, browsing, searching, the viewer over anything already fetched, Share
and Save to Photos all work. Favoriting, tagging, deleting and a fetch of
something never fetched are **greyed**, not failed on press: the annotation lives
in the picture's own PNG on the Mac, and a star that filled in offline would be a
lie about a file this phone cannot touch. Save and Share stay live for a file
already here, which is the one somebody is looking at.

`ReferenceIntent` (`Support/`) is how the library says "start from this one": an
`@Observable` with one file **name** on it. A name, never bytes — the Mac made
the picture and still has it, and sending a megabyte of PNG back to the machine
it came from to say one word would be absurd.

The canvas is the other half. `UseAsReferenceButton` puts the name on the intent
and sets `MobileSelection.tab` to the canvas, because that is one gesture:
somebody saying "start from this one" is asking to be taken where a run is
started. `ReferenceIntentReader` (`Views/Canvas/`) is the listener — a modifier
rather than a view, since there is nothing to draw. It takes the name, fetches
the picture through `LibraryCatalog` (so the file the library already has is the
file the well gets) and fills the well with `referenceOrigin` set to that name,
which is the provenance the Mac records beside the run. `ReferenceAdoption.take`
is the sequence as one function, which is how it is tested.

It is an object rather than a notification for three reasons, and the third is
the one that decides the shape: a request made while the library is up is still
there when the canvas is reached. Two smaller rules follow from that. The reader
watches with `onChange` and an unstructured task rather than `.task(id:)` —
taking the request clears the name, and a task keyed on the name would cancel
the very fetch it started. And the request is taken before anything is fetched,
so a slow link cannot let it be acted on twice and refill a well somebody
emptied.

### The viewer

`LibraryViewer` (`Views/Library/`) is a picture full size, and it is built the
way Photos is, because Photos is what every thumb on a phone already knows.

- **The pager is a lazy `ScrollView`**, horizontal, paging with
  `.viewAligned(limitBehavior: .always)` over a `LazyHStack` of `ViewerPicture`s
  a `containerRelativeFrame` wide and `MobileChrome.viewerPageGap` apart, its
  position bound to the current file name. Lazy is what lets `LibraryScreen`
  hand it **the whole grid** in the grid's order rather than one day: the grid
  is one continuous wall and its day headers are labels on it, and a swipe that
  stopped at midnight stopped somewhere nobody could see from the picture they
  were looking at. `TodayScreen` hands it the run's pictures in the strip's
  order, so a swipe there walks the seeds of one press of Generate.
- **Zoom is a `UIScrollView`.** `ZoomablePicture` wraps `ZoomingScrollView`, a
  scroll view holding one `UIImageView` sized to the aspect-fitted rectangle and
  kept centered with `contentInset`, minimum zoom 1, maximum 6, its own
  delegate. It is UIKit rather than a `MagnifyGesture` beside a `DragGesture`
  for one reason: a nested scroll view at zoom 1 has nothing to scroll, so UIKit
  hands the pan straight to the pager, and zoomed in the same pan scrolls the
  picture. Two SwiftUI gestures over the same pixels had to guess which, and
  guessed wrong often enough to feel broken. Double tap goes in to 2.5 around
  the finger or back to fit; a single tap waits for the double to fail. A page
  reads `\.viewerPageIsCurrent` and puts its zoom back to fit the moment it is
  not, so swiping away from a zoomed picture and back finds it fitted.
  Replacing the picture — the viewer sharpens a thumbnail into the file —
  keeps the zoom, since the shape is the same.
- **What the fingers did goes up as `ViewerGestures`** (`Support/`), three
  closures in the environment: `tapped` toggles the chrome, `zoomed` says
  whether the picture is in past fit, `pulled` carries each phase of a pull
  downwards. The viewer holds all of it in one `ViewerPose`: the current file
  name, whether the chrome is hidden, whether the picture is zoomed, and the
  pull.
- **Swipe down closes it, and the finger is read in UIKit too.** A SwiftUI
  `DragGesture` over the pager never saw a touch — the two scroll views
  underneath claim every one before SwiftUI's gesture does — so
  `ViewerPullRecognizer` is a `UIPanGestureRecognizer` on the page, its own
  delegate, and one type for both kinds of page: `ZoomingScrollView` attaches
  it to a picture and `ClipPlayerView` attaches it to the player's view when
  its `Place` is `.viewer`, so a clip drops and closes under the finger exactly
  as a picture does. It begins for any touch `mayBegin` allows — a picture at
  fit, a clip always — because UIKit asks a touch held still on a scroll view
  at zero translation and a refusal there is final; it reads the direction on
  the first change past `decision` (8 points), and for anything but a pull
  downwards it cancels itself, which is the failure the pager's pan has been
  told to wait for (`shouldBeRequiredToFailBy`). So a sideways drag is the
  pager's, a drag on a zoomed picture is the picture's, and a pull never drags
  the next picture sideways on its way down. It recognizes beside every other
  recognizer and cancels no touch in the view under it, which is what keeps
  AVKit's tap for the controls and its scrubber working under a clip.
  `ViewerPull` is what the phases do to the screen: the picture drops by the
  offset, shrinks by a quarter at most, and the black behind it thins so the
  grid shows through (`presentationBackground(.clear)` on the cover, which
  does show the grid). Letting go past `MobileChrome.viewerDismissDistance`,
  or flung so that a quarter of a second at lift-off speed would carry it past
  twice that (`Pull.predictedEnd`), dismisses; short of it the picture springs
  back, or snaps back under Reduce Motion. The decisions are static functions
  on `ViewerPose.Pull`, and `ViewerPoseTests` is what pins them.
- **It zooms out of the cell and back into one, the way Photos does.**
  `ViewerCover` is the one place both surfaces present the viewer: a
  `fullScreenCover` whose content wears `navigationTransition(.zoom)` against
  a `matchedTransitionSource` on the cell, in a `@Namespace` the cover owns and
  hands down as `\.viewerNamespace`. The catch is that the zoom's source id is
  fixed at presentation, and after paging the viewer should close into the
  cell it is *now* over. So the cover's item is a `ViewerOpening`: the entry
  opened on, which is its identity so paging changes the content and never the
  presentation, and `shown`, which the viewer reports through `\.viewerPaged`
  every time the pager settles. Every `LibraryCell` reads the opening from the
  environment and answers to `ViewerOpening.sourceID(forCell:)`: while the
  viewer is up the shown picture's cell is a source under the opened one's
  name and **no other cell is a source at all**. Not its own name, because the
  system follows a source that is added or taken away and not one whose id
  changes — with every cell keeping a source and the two names swapped between
  the shown cell and the opened one, the zoom back went to the opened cell
  whatever the pager had done. `ViewerOpeningTests` pins the rule.
  `LibraryGrid` and `RunThumbnailStrip`
  scroll the shown cell into view as the viewer pages, unanimated behind a
  cover that is opaque at rest, so the zoom back has a cell on screen to land
  on. A pull past the threshold calls `dismiss()` and the system's zoom-back
  runs from wherever the picture was let go; under Reduce Motion the system
  cross-dissolves instead, and nothing here decides that.
- A single tap hides the title strip and the bar and another brings them back,
  faded over 0.2 s or at once under Reduce Motion; hidden chrome takes no hits.
  A clip's page is `ClipPlayerView` with its controls, whose taps are AVKit's,
  and its pull is the same recognizer a picture's page has.
- **The close button is a fingertip, not the glyph.** `LibraryViewerTitle` drew
  `xmark.circle.fill` at `.title2` with no frame around it, so a thumb landing a
  few points off the small glyph missed the button and hit the tap-to-toggle
  area behind it instead — which hid the chrome and took the button away from
  under the same finger that just missed it. `MobileChrome.viewerCloseTarget`
  (44 pt, Apple's own minimum) is the button's `frame`, with
  `.contentShape(Rectangle())` so the whole frame is tappable rather than just
  the glyph inside it; the glyph itself grows to `.title` since the frame gives
  it room. It stays leading, Photos' own place for it, and answers
  `.accessibilityAction(.escape)` for VoiceOver's escape gesture.
  `LibraryViewerTitle.closeTarget` re-exports the number so
  `ViewerChromeTests` can pin it without reaching into `MobileChrome` from a
  test about one view.

## Today

The Today tab is the Mac's canvas sidebar: what is waiting, what is being
rendered, what has come out, in that order. **Nothing in it groups anything.**
`RunSummary` arrives already grouped, because the grouping is a rule about a
press of Generate and the Mac is what pressed it — `SessionTimeline` does that
work on the Mac and the phone would only be a second copy of it.

- `RunningRunCard` is the only amber thing on the phone, for the reason
  safelight amber is the only amber on the Mac. Its step count, its pace and its
  phase are read straight off `EngineStateDTO`, which already carries the
  derived facts (`isBusy`, `isFinishing`, `canQueue`): the phone never works out
  a rule the Mac knows. Stop is `StopRunButton`, shared with the capsule, over
  `client.cancel()`.
- `WaitingRunCard` takes the **whole run** out of the queue rather than one seed
  of it, finding its entries in `snapshot.queue` by their batch. A run is what
  was asked for, so a run is what can be taken back.
- `FinishedRunRow` draws its pictures out of the catalog by name, so a run made
  this morning still shows them on a train with no signal. A picture in the
  strip opens the same viewer and wears the same `LibraryItemMenu` the grid's
  cells do, through the same `\.openLibraryItem` — the surface keeps no copy of
  the library's actions.

This is the one surface that goes blank without a Mac, and it should: a run in
flight cannot be cached.

## Frozen preview states

The same mechanism as the Mac's `InterfacePreview`, in the same shape, so a
screenshot of either app is taken the same way. `ZEPHRA_PREVIEW_STATE` is read
once, in `MobilePreview`, `#if DEBUG` only.

`ZEPHRA_FORCE_RELAY=1` is the other switch and is not a frozen state at all: the
app is live, and what it loses is the local network. `RelayOnlyRoads` (`Support/`)
wraps `NetworkLinkRoads`, finishes the browse empty and fails every LAN endpoint,
so `connect()` and `pair(with:)` fall through their list to `connectRelay` — the
only way to exercise that road from a simulator beside the Mac, since a phone on
the same Wi-Fi answers on its first stored address and never asks the relay
anything. A decorator in the composition root rather than a flag inside the link
package, for the reason the root exists: which roads a phone has is the root's
business. Read once at launch, `#if DEBUG` only, and handed over by
`make run-ios FORCE_RELAY=1`.

| State | What it shows |
| --- | --- |
| `pairing` | no Mac paired: the pairing screen over nothing |
| `ready` | paired and idle, on the canvas |
| `generating` | paired, four steps into a nine-step ladder, with a frame of it in |
| `capsule` | paired and idle, with the capsule showing every control the model has |
| `library` | paired, opened on the library |
| `viewer` | the library with its first picture open full size |
| `today` | paired, one run four steps in and one waiting behind it |
| `offline` | paired, the connection `.offline`: everything is the last thing known |
| `settings` | paired, opened on the settings surface |

Every state but `pairing` is a `LinkClient.frozen`: paired with the Mac the
snapshot names, live over the LAN as far as the interface can tell, requests
answering `.ok` and blobs failing, and no road under it at all. `pairing` is a
real client over roads that go nowhere, so a code pasted into a screenshot build
says it could not reach a Mac rather than doing nothing at all — and reaches no
network either way.

The state on screen comes from two JSON files in the bundle,
`Resources/Fixtures/preview-snapshot.json` and `preview-library.json`, read with
`LinkJSON.decoder()` — the wire's own decoder. Written out rather than built in
code on purpose: a fixture that decodes is proof the DTOs still read what a Mac
would send, which a Swift literal could never be, and `PreviewFixtureTests` is
that proof run on every build. The one state the fixture cannot hold is the
mid-run one, since a frozen step count goes stale the moment the numbers move:
`MobilePreview.midRun` swaps the engine state and the running entry in, and
`MobilePreview.frame` draws the preview frame that rides beside it — a gradient
made with `UIGraphicsImageRenderer`, since a photograph of one particular run
saved in the bundle would prove nothing about a canvas that draws whatever
arrives. `capsule` is `ready` with `MobilePreview.capsuleIsExpanded` true, which
is the only way to photograph the settings: a screenshot build cannot tap.

`MobilePreview.todayRuns` (in `MobilePreview+Today.swift`, beside it for
the same reason) puts a waiting run behind that one and lists both at the head
of `today`, each under a batch identity of its own so no run is listed twice.
`MobilePreview.shaped(_:for:)` is the one place a state chooses between them.

Under any preview state the catalog is built with no roots at all: it seeds
itself from the frozen client's library and writes nothing, so photographing a
surface twice photographs the same surface. Blobs fail on a frozen client, so
the grid's cells are placeholders and the viewer says the picture is not on
this phone — which is, incidentally, exactly what the offline path looks like.
The one exception is `viewer`, which is about paging, pinching and pulling and
needs a picture under the finger: `MobilePreview.pictureFolder()`
(`MobilePreview+Pictures.swift`) draws one numbered, gridded picture per
fixture entry at the entry's own size into a folder under the temporary
directory, emptied at every launch, and the catalog's `FileStore` reads it
before asking the Mac. The fixture's clip gets its poster and, beside it under
the sidecar's name, two seconds of the same page with a bar sweeping across it,
written with `AVAssetWriter` on the way in (`MobilePreview+Clip.swift`), so the
clip's page plays and a pull over it can be tried with no Mac. Drawn rather
than bundled for the reason `frame()` is drawn: what matters is that each page
is unmistakably itself.

## Running it

```
make build-ios                      # generate, then build Debug for the simulator
make run-ios                        # build, boot the simulator, install, launch
make run-ios PREVIEW=pairing        # the same, frozen in one state
make test-ios                       # ZephraMobileTests, hosted in the app
make screenshot-ios                 # the booted simulator, into build/ios-<stamp>.png
```

`IOS_SIM` names the device (`iPhone 17 Pro` by default); `IOS_DEST` is built
from it. A name rather than a udid, so the same line works on any Mac.
`scripts/ios-sim.sh` prints the newest iPhone a machine actually has, which is
what CI passes — a device name pinned in a workflow breaks the day the runner
image moves. The workflow runs `make test-ios IOS_SIM="$(scripts/ios-sim.sh)"`
beside the Mac gates.

`screenshot-ios` takes the picture into a temporary directory and copies it into
`build/` afterwards. `simctl` is refused a write onto an external volume — where
this repository lives on the machine it is developed on — with "Operation not
permitted" and no hint as to why.

The first build compiles `ZephraCore`, `ZephraEngine`, `ZephraSnapshot`, the
protocol and the chrome for the simulator from scratch, which is minutes; after
that it is incremental. There is no benchmark: the phone renders nothing, so
there is nothing to measure. The one Release lane is `make archive-ios` and
`make testflight`, below.

## TestFlight

```
make archive-ios                    # Release archive into build/ZephraMobile.xcarchive
make testflight                     # that archive, uploaded to App Store Connect
```

Both live in **TestFlight** in `docs/build-and-release.md`, beside the Mac's
signing and notarization, because they are the same kind of thing and read from
the same `~/Documents/Zephra Signing/signing.env`: the export options
(`scripts/ExportOptions-testflight.plist`), the `ASC_KEY_PATH`, `ASC_KEY_ID`
and `ASC_ISSUER_ID` an upload needs, the stamping rule, and what James does by
hand once — the App Store Connect record for `io.zephra.ZephraMobile`, the API
key, the phone in internal testing, the export-compliance answer. It is a
TestFlight upload and never an App Store submission.

The two things that are the phone's own rather than the recipe's:

- `ITSAppUsesNonExemptEncryption` is `false` in the companion's `Info.plist`.
  The link uses CryptoKit — Curve25519 and AES-GCM — standard algorithms the
  platform ships and nothing of our own, which is the exempt case in Apple's
  questionnaire; `false` is that answer stated in the bundle, so an upload does
  not stop at "Missing Compliance". What the exemption still asks for is the
  annual self-classification report to the US Bureau of Industry and Security,
  James's to file.
- `CODE_SIGN_IDENTITY[sdk=iphoneos*]` is `Apple Development`, which is what a
  device build wants. The archive is signed with it and the export re-signs
  with the distribution certificate it fetches, which is what `signingStyle:
  automatic` in the export options and `-allowProvisioningUpdates` on the
  command line are for. Nothing is checked in: a provisioning profile in a
  repository is a thing that expires without telling anybody.

Deferred work lives in `ROADMAP.md`.
