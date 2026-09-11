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
  `clamp` that goes with it, `ImageSize`, `SeedEntry`, `SizeEntry`,
  `ReferenceRole`, `DurationLabel`. The phone runs the Mac's own rules rather
  than a second copy of them that could drift.
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

Three system frameworks are linked by name: `AVKit` for a clip fetched from the
Mac, `VisionKit` for the pairing scanner, `Photos` for saving a picture to the
camera roll.

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
  Mac is actually reached. `RootView` is the four surfaces behind a `TabView`,
  with `PairingView` over them as a `.fullScreenCover` until a Mac is paired. A
  cover rather than a branch, so the tabs are built once and keep their state.
- `Support/` — the cross-cutting answers. `MobileKeychain`, `LinkReconnect`,
  `MobileTab`, `PairingEntry`, `MobilePreview`.
- `Style/` — `MobileChrome`, and only what has no counterpart on the Mac: the
  prompt sheet's heights, the room the tab bar takes, the side margin. Anything
  a radius, a hairline or a wash could be belongs in `Packages/ZephraStyle`.
- `Views/` — one subfolder per surface. `CanvasScreen`, `TodayScreen` and
  `LibraryScreen` are placeholders that already show the one fact the snapshot
  knows about them, so the tabs, the paired state and the frozen previews are
  exercised from the first commit; each is replaced from the inside as its
  surface is built. `SurfacePlaceholder` is what they all draw. `SettingsScreen`
  is real: `PairedMacRow`, `ConnectionRow`, `CacheRow` and `AboutRow`, a row to
  a file, so a later agent replaces one of them rather than editing a screen
  around it.

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
- **When to reach.** `LinkReconnect` (`Support/`) owns one task: `connect()` on
  `scenePhase == .active`, `disconnect()` on `.background`, and after a failure
  or a session that dropped, `LinkBackoff`'s one, two, four, eight seconds capped
  at thirty until one works — the count reset by a live session and by the app
  coming to the front. `connect()` is idempotent, so nothing here keeps a flag of
  its own; the loop watches a live session at `heartbeat` rather than waking on
  an observation, because the sequence that would do that is iOS 26 and the phone
  runs on 18.

Under a frozen preview state the root builds `LinkClient.frozen` instead and no
`LinkReconnect` at all: a client with no road under it has nothing to reconnect.

### Pairing

Three doors, one parser.

- `PairingScanner` (`Views/Pairing/`) is VisionKit's `DataScannerViewController`
  over `.barcode(symbologies: [.qr])`, the one piece of UIKit in the app. Shown
  only when `DataScannerViewController.isSupported && .isAvailable`, which is
  never in the simulator.
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

## Frozen preview states

The same mechanism as the Mac's `InterfacePreview`, in the same shape, so a
screenshot of either app is taken the same way. `ZEPHRA_PREVIEW_STATE` is read
once, in `MobilePreview`, `#if DEBUG` only.

| State | What it shows |
| --- | --- |
| `pairing` | no Mac paired: the pairing screen over nothing |
| `ready` | paired and idle, on the canvas |
| `generating` | paired, four steps into a nine-step ladder |
| `library` | paired, opened on the library |
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
`MobilePreview.midRun` swaps the engine state and the running entry in.

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
that it is incremental. There is no Release lane and no benchmark: the phone
renders nothing, so there is nothing to measure.

## TestFlight, when it comes

Nothing here is wired up yet. What it will need:

- An App Store Connect record for `io.zephra.ZephraMobile`, under team
  `28X9H69QGE`. The bundle identifier is already what the target builds.
- An App Store Connect API key (`.p8`) under `~/Documents/Zephra Signing/`,
  beside the Developer ID material `make release` already sources from
  `signing.env`, with its key id and issuer id in that same file. Uploads go
  through `xcrun altool`/`notarytool`'s successor, never a keychain password.
- A distribution certificate and a provisioning profile for the identifier.
  `CODE_SIGN_IDENTITY[sdk=iphoneos*]` is `Apple Development` today, which is a
  device build; a distribution build overrides it on the command line the way
  `make release` overrides the Mac's.
- `ITSAppUsesNonExemptEncryption` is already `true` in the Info.plist. The link
  uses CryptoKit — Curve25519 and AES-GCM — so the answer is yes, and declaring
  it in the bundle stops every upload asking. An export-compliance exemption
  claim, if one is ever made, goes in App Store Connect and not here.
- Marketing version and build number come from `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` in `project.yml`, overridable on the xcodebuild line
  exactly as the Mac's are.

Deferred work lives in `ROADMAP.md`.
