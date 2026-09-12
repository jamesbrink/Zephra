# The companion link

`Packages/ZephraLink` is three targets. `ZephraLinkProtocol` is the wire the Mac
app and the iOS companion both speak: no transport and no interface are in it, so
both ends are tested in milliseconds without a socket. `ZephraLinkTransport` is
the roads under it — TCP and Bonjour on the local network, the relay's WebSocket
from anywhere — and `ZephraLinkClient` is the phone's side over one of those, the
one object its views observe. Each takes only the one before it.

It may import Foundation, CryptoKit, Network, os, Observation, ImageIO,
CoreGraphics, Synchronization, `ZephraCore` and `ZephraEngine`, and nothing else;
`make lint-layers` fails on anything further. `ZephraEngine` is there for
`GenerationRecord` and `LibraryAnnotation` alone. Those two are the on-disk truth
inside every PNG and they are already `Codable`, so they cross the wire as
themselves: a second shape of the same provenance is a second thing to keep in
step, and the phone's inspector shows the same fields the Mac's does.

## Frames

Everything that crosses is one of two things, and the leading byte says which.

| Byte | Frame | Body |
| --- | --- | --- |
| `0x01` | envelope | JSON, sorted keys, ISO 8601 dates (`LinkJSON`) |
| `0x02` | chunk | 16 bytes of blob id, `UInt32` index, `UInt32` count, big-endian, then the payload |

The kind is outside the body because the secure channel authenticates it as
additional data: a chunk cannot be replayed as an envelope.

An envelope is `{ id, kind, inReplyTo?, body }`, and the body stays `Data` rather
than becoming an associated value per kind. A message from a newer build is then
a well-formed envelope this build can log and refuse, not a parse failure that
kills the connection.

## Messages

| Kind | Body | Direction |
| --- | --- | --- |
| `hello` | `Hello` | phone to Mac, plaintext |
| `accept` | `Accept` | Mac to phone, plaintext |
| `confirm` | `Confirm` | phone to Mac, plaintext |
| `snapshot` | `StateSnapshot` | Mac to phone, once per session |
| `delta` | `StateDelta` | Mac to phone |
| `preview` | `PreviewFrameDTO` | Mac to phone |
| `request` | `Command` | phone to Mac |
| `reply` | `Reply` | Mac to phone, `inReplyTo` names the request |
| `blobStart` | `BlobStart` | Mac to phone |
| `error` | `LinkError` | either way |
| `ping` / `pong` | `{}` | either way |

Every command gets exactly one reply, a refusal included, so the phone can hold a
request open and know it will close — and **every command is safe to send
twice**, because a reply can go missing. `LinkClient.request` asks once more
under a fresh envelope id before it throws, so nothing a command does may count
how many times it was asked: the queue commands, the library edits and the
fetches all say what the Mac should end up like. The exception is `enqueue`,
which adds work, and it is answered from what the session already did rather
than queued again (below).

`resync` is the phone saying it no longer trusts what it is holding: it stepped
over a hole in the stream. The Mac answers `.ok` and then a fresh `snapshot`
envelope, in that order on the one stream, so the request closes before the
state it asked for arrives. The phone's library pull restarts on a snapshot
landing, so the window it has been sent is asked for again as well.

```json
{"kind":"setFavourite","names":["lighthouse.png"],"on":true}
{"kind":"libraryPage","limit":20,"offset":40}
{"kind":"acceptsWork","value":true}
{"kind":"historyRemoved","value":"3A7B9C10-2D4E-4F6A-8B5C-1E9D0A2B3C4D"}
{"error":{"code":"busy","reason":"The Mac is busy."},"kind":"error"}
```

A command and a delta are tagged objects with a `kind` and their fields beside
it, written by hand rather than left to Swift's own enum encoding, whose shape
changes with the number of associated values a case happens to have. The golden
strings in `CommandCodingTests` and `StateCodingTests` pin them.

`EngineStateDTO` is a struct of scalars, not the engine's enum. `EngineState`
carries progress events that carry a decoded preview frame, and a quarter of a
megabyte of pixels must never ride inside a state update; previews have a message
kind of their own. The facts the Mac derives from a case (`isBusy`,
`isFinishing`, `acceptsGeneration`, `canQueue`) are stored fields, so the phone
never has to know a rule the Mac already knows.

`canQueue` is the odd one out, and the reason it exists is worth writing down.
The other three are functions of `EngineState` alone, so
`EngineStateDTO(_ state:)` in the shared package derives them and a new case of
the engine's fails to compile there rather than reaching a phone as `idle`.
Whether a generation may be *queued* is not: a Mac four steps into a picture is
`.generating`, which says a run is in flight and nothing about whether another
may wait behind it. That is `GenerationStore.acceptsQueuedGeneration`
(`state.acceptsGeneration || isDraining`), the store's own fact and the one
`remoteAdmission` gates on — so if the phone worked it out from `kind` it would
be a second copy of a rule that can disagree with the Mac that then refuses the
press. `EngineStateProjection` (`ZephraLinkHost/Projection/`) is where the store
stamps it, and the two sites that build the DTO for a phone —
`StateSnapshotProjection` and `CompanionHost.publishEngine` — both go through
it. An upscale is deliberately not a queue: nothing is draining, no model need
even be loaded, and a request arriving then is refused with "Zephra is upscaling
a picture."

`EngineStateDTO` reads itself by hand (`EngineStateDTO+Codable`) for one field.
`canQueue` shipped after the first Macs did, and a state without it is not a Mac
that takes no queued work — it is a Mac that never had an opinion. Read as
absent it would grey out Generate for good against an older Mac, so it is
`decodeIfPresent ?? acceptsGeneration`, which is exactly what the field's
absence used to mean: one picture at a time. Encoding stays synthesised, since
what this Mac sends is everything it has. That is the rule for every field added
to a DTO after a release — default it to what its absence meant — and
`QueuedEntry` is the other hand-written reader, for its own reason.

`GenerationRequest` carries `ZephraCore`'s own `GenerationSettings`, so the Mac
clamps what arrives through the same `clamp` a local press of Generate goes
through. The one thing stripped is the pixels, on the way in and on the way out
(`GenerationSettings.withoutPixels`, the protocol's one rule for a settings
value on the wire): `referenceImage` goes, since a picture crosses as a blob and
is named by `referenceBlobID`, and a `continuation` keeps its origin and its
count but not its frames, which the Mac's `clamp` then drops as a continuation
with nothing to hold.

`QueuedEntry`, the row `snapshot.queue` and `snapshot.running` are made of,
carries the run's whole `settings` through the same strip beside `id`,
`batchID`, `batchIndex` and `modelID`; `prompt`, `width`, `height`, `seed` and
`frames` are reads over it. Whole rather than flattened because the phone's
capsule follows the Mac's run (`PromptDraft.follow`), and what it wants is what
the Mac's own capsule gets back from `watchRun()`: the settings that are
running, not a summary of them.

It also carries the phone's own `requestID`, made once per press of Generate and
kept across a retry while the envelope's id changes. `CompanionSession` remembers
the run each id queued (`runMemory`, 32, oldest forgotten first) and answers a
repeat with that same `queued(batchID:)` rather than queueing a second time — a
hole in the stream must not cost somebody two generations. A request from a
build that sends no id is simply one the Mac cannot recognise again.

## Blobs

Thumbnails, files and clips do not go in JSON. A `blobStart` announces the id,
the byte count and the mime; the bytes follow as chunk frames.

- `BlobChunker.chunkSize` is 64 KiB. One chunk, its 24-byte header and the
  channel's tag fit inside the relay's 128 KB frame with room to spare.
- Empty data is one empty chunk, not none: a blob of nothing still has to be
  announced, sent and completed.
- `BlobReassembly` takes chunks **in order only**. It is read through
  `OrderedInbox`, which has already put an overtaken frame back where it belongs,
  so a gap here means loss or tampering; holding out-of-order pieces at this
  level as well would mean holding arbitrary memory for a sender that never sends
  the missing one. A duplicate index is the same answer. A transfer refused this
  way is **that transfer** and never the session: the phone asks for the bytes
  again, and a picture on its way to the Mac is answered `notFound` when the
  `enqueue` names it.
- One blob may not exceed 64 MiB while it is being assembled, and it may not
  exceed **what it announced**: `BlobReassembly` takes the `byteCount` at
  construction, trims a claim past the cap down to it, refuses the chunk that
  would pass the claim, and refuses a transfer that completes short of it.
  Without that the announcement was a courtesy rather than a limit — a thumbnail
  announced as forty kilobytes could arrive as sixty-four megabytes, and the
  receiver had already decided to accept it.

## The handshake

A Noise-style pattern on CryptoKit. The phone is the initiator, the Mac the
responder. Three plaintext messages, and everything after them is sealed.

```
phone -> Mac   hello    version, ephemeral, static keys, nonce(16), pairing, deviceName
Mac   -> phone accept   ephemeral, nonce(16), tagR
phone -> Mac   confirm  tagI
```

Each device holds a `DeviceIdentity`: a Curve25519 key agreement private key and
a Curve25519 signing private key, 64 bytes together, kept in the keychain so a
relaunch is the same device and not a new one.

The responder decides who may talk to it before it derives any key. A `hello`
with `pairing` set needs a live pairing secret; one without needs a static key
the Mac already knows; a version that is not `LinkProtocolVersion.current` is
`protocolMismatch`.

**Every way it is turned away is the same answer**, `LinkError.notPaired` and
the one sentence "This Mac has not paired this phone." Two answers were two
oracles to anybody who could reach the port: a `pairing: false` hello was told
`notPaired` for a key the Mac does not know and answered for one it does, which
turns a knock into "is this key paired with this Mac"; and a `pairing: true`
hello was told `refused` only while no code was up, which turns a knock into "is
somebody at that Mac pairing right now". The refusal goes out in the clear,
before anything is authenticated, so every word in it is a word anyone can read:
it names no Mac, no model and no person. The phone's pairing screen adds the half
a person can act on — "Check that the code is still showing on your Mac" — in
`LinkClient+Pairing`, where a code is known to have been read.

**Key schedule.** Four Diffie-Hellman results are concatenated as
`ee || es || se || ss`, naming them from the initiator's side. Mixing all four
means the channel is only as good as every one of them: an attacker with the
ephemeral keys still lacks the static ones, and one with a stolen identity still
cannot read yesterday's traffic.

```
transcript = SHA256(canonical hello JSON || responder ephemeral || responder nonce)
okm        = HKDF-SHA256(ikm: ee||es||se||ss,
                         salt: pairingSecret ?? 32 zero bytes,
                         info: "zephra-link-v1" || transcript,
                         length: 96)
kI2R, kR2I, kConfirm = okm[0..32], okm[32..64], okm[64..96]
tagR = HMAC-SHA256(kConfirm, "r" || transcript)
tagI = HMAC-SHA256(kConfirm, "i" || transcript)
```

The hello is hashed as the responder re-encodes it, which is safe exactly because
`LinkJSON` sorts its keys: two encodings of one value are the same bytes. Both
tags are compared with `HMAC.isValidAuthenticationCode`, in constant time.

The initiator checks `tagR` when the accept lands, one message earlier than the
responder checks `tagI`. So a wrong pairing secret is a refusal the person can be
shown rather than a frame that will not decrypt.

A recorded hello replayed at a Mac that has restarted its handshake gets a new
ephemeral and a new nonce, so the transcript differs, the keys differ, and the
recorded confirm proves nothing: `HandshakeReplayTests` pins it.

## The channel

AES-GCM under two keys, one per direction. The nonce is four zero bytes and a
`UInt64` counter, big-endian, and the counter **is sent**, in the clear, between
the kind byte and the ciphertext. A sealed frame on the wire is

```
kind (1) || counter (8, big-endian) || ciphertext || tag (16)
```

The additional authenticated data is the frame's one kind byte and nothing else.
The counter does not need to be in it: the counter *is* the nonce, so a counter
somebody edited is a different nonce, the tag does not verify, and the frame is
`undecipherable`. Authenticating it comes free.

The counter was implicit until a live run through the relay showed why it cannot
be. Every `send` is a separate Lambda invocation at API Gateway and those
invocations post to the far end concurrently, so under a sustained delta stream —
one message every 50 ms while a run goes — frames arrive overtaken. With the
counter implicit, the first overtaken frame decrypted under the wrong nonce, the
channel closed, and the phone lost the Mac mid-run.

What the channel refuses now is anything outside a window over the stream:
`replayed` for a counter at or below the last one released downstream, and
`outOfWindow` for one a whole `SecureChannel.receiveWindow` (1024 frames) beyond
it. Neither closes the channel — a duplicate is cheap to drop and a reordering is
ordinary. **Only a frame that does not authenticate closes it**, for good, both
ways: that means the stream is not the one that started, and carrying on would
let an attacker probe until something got through. At 2^32 frames one way the
nonce space is finished and `rekeyRequired` says the connection has to be made
again.

`open` hands back an `OpenedFrame` — the frame and its counter — because the
receiver is not finished with the number.

### The inbox

`OrderedInbox` is the receiving half, and both `CompanionSession` and
`LinkSession` read through it. Frames are opened as they arrive and **released in
counter order**, so everything above it still sees one ordered stream:
`BlobReassembly` keeps its in-order rule, and `StateDelta`s apply in the order
they were sent.

- A frame that overtook its neighbours waits, at most `frameLimit` (256) frames
  and no longer than `hold` (500 ms). Releasing moves the channel's release point
  on with `released(through:)`, which is what the replay check is measured from.
- **The hold is one clock per gap, re-armed whenever the release point moves.**
  It was armed when `held` first became non-empty and cancelled only when `held`
  emptied, so under sustained reordering — which is what a relay is — it ran
  across a chain of gaps that each filled in milliseconds, and stepped over
  whichever gap happened to be open when the half-second ran out. The frame it
  called lost then arrived a beat later as `replayed`: the receiver was
  manufacturing holes with no loss underneath it at all, which over a picture's
  hundreds of chunks is a failed transfer every few seconds. `State.armedFor`
  records the counter a clock was started against, and a clock that outlives its
  gap does nothing.
- A frame that arrives after the stream moved past it is the channel's
  `replayed`, and the session drops it with a line in the log.
- A gap nothing fills inside `hold` is **loss, not reordering**: each hop is TCP
  under a WebSocket, so overtaking is expected between hops and a hole is not.
  It is **skipped**, not fatal. The release point jumps to the lowest counter
  waiting, everything contiguous behind the hole is released in order, and
  `released(through:)` moves the channel's floor with it — so the swallowed
  counter is `replayed` if it ever does turn up. A live relay run dropped one
  small frame (the receiver held 3, 4 and 5; frame 2 never came) with no Lambda
  error and nothing logged at either end, and closing the session over it meant
  the phone reconnecting every few seconds for the length of a run until it gave
  up. What a hole actually costs is one message.
- More than `frameLimit` (256) frames held on one gap is still the end of the
  session: that is a stream nothing is going to put back together, and not
  memory worth keeping. `accept` throws `SecureChannelError.lost` and the
  channel closes.
- The owner is handed a `FrameGap` — the counter that never came, the lowest one
  waiting behind it, how many were waiting — and the frames the skip released,
  to dispatch as if they had just arrived. **Both ends log it at error**:
  `CompanionSession.stepOver` and `LinkClient.lost`. A skip is rare, costs the
  phone a whole resync, and is the first thing to look for when a session
  behaves oddly.
- **The phone answers a gap by resyncing.** Every blob part way through is
  dropped and every open request failed as `LinkClientError.lost` — both of
  which are asked again once — and `Command.resync` goes out, so the state the
  lost deltas were editing is replaced rather than patched around. The road
  stays up: the session is the same session and the channel the same channel.
- **The Mac answers a gap by carrying on.** The transfer that was arriving is
  dropped, since its chunks are an ordered run with one missing, and the
  `enqueue` naming that picture is answered `notFound`. A lost request never
  arrives at all and the phone's own retry covers it. A chunk that does not fit
  its transfer refuses **that transfer**, with a sealed error to the phone, and
  never the session.
- The hold is `CompanionHost.frameHold` and `LinkClient.frameHold` rather than
  the constant, so a suite asks the question in milliseconds.

## Pairing

The Mac shows a QR code holding a `PairingPayload`, and its secret is live for
120 seconds.

```
zephra://pair?v=1&d=<base64url JSON, unpadded>
```

`PairingURL.decode` takes the whole link or the bare payload, trimmed, because a
scanner may hand back either. The JSON uses one-letter keys and seconds since
1970: the payload is measured in the modules of a code somebody photographs
across a desk. Measured at 522 characters for the whole link with a 32-character
Mac name, four addresses, both public keys, the room, the secret and the expiry;
the budget is 600, which a version 11 code holds at the error correction a screen
wants.

The payload also names a `RoomID`: the first 16 bytes of `SHA256(signing public
key)`, as lowercase hex. Derived rather than assigned, so the relay hands out no
names and stores no mapping. A phone that has paired already knows the Mac's
public key and can work out where to knock.

## The relay

When neither end can reach the other directly, both join a room on a WebSocket
relay, which copies bytes and never sees inside them: a `send` payload is one
sealed frame and the relay has no key. The relay is a Lambda behind API Gateway;
this package and that Lambda are two implementations of one contract, so the
field names below are the relay's own and not ours.

**The Lambda is in this repository**, at `Relay/link/` — `index.mjs`, a README
stating the contract as the relay states it, and `test/`, which drives the
handler the way API Gateway drives it against fakes for DynamoDB and the API
Gateway management API (`make relay-test`, seconds, no AWS account). It lives
here so that a change to the contract is one commit rather than two in two
repositories drifting apart; nothing links it, and nothing in Swift may. `make
relay-deploy` zips the one file, replaces the function's code, waits for it to
settle and then opens a real socket to `wss://zephra-link.urandom.io` to check
that `hello` comes back a `challenge`; CI runs that on every push to `main`
(`docs/build-and-release.md`). Terraform in the urandom.io repository still owns
the function, its role, the DynamoDB table, the API, the stage and the domain,
and deliberately not the code: its `aws_lambda_function.link` ignores `filename`
and `source_code_hash`, so an apply there cannot roll a deployed relay back to
the bootstrap copy it keeps.

A room is the lowercase hex of the first 16 bytes of `SHA-256` over the raw
32-byte Ed25519 public key — `RoomID(signingPublicKey:)`, the one place that rule
lives. The relay checks that the key hashes to the room **for a host only**.

**A guest is admitted only off the host's allow-list.** The host's `join` carries
`allow`, the raw signing key of every device it has paired, and the relay lets a
guest in only when the key it signed with is one of them — and only when no other
guest holds the room. Before that check existed, any device that could sign for
any key was let into any room it knew the name of, and the room's name is in a
Bonjour TXT record; the host's refusal of an unknown static came one handshake
too late to stop it taking the room. The list is `RelayJoin.allowLimit` keys at
most, which `CompanionHost.relayAllowList` orders by what was last seen, and the
relay refuses a longer one as `bad allow`. An absent or empty list admits nobody.

The set moves while the socket is up — a pairing completes, a device is revoked —
so `{"a":"allow","pubs":[...]}` replaces it, and the relay answers
`{"a":"allowed","count":N}`, which `RelayConnection` swallows with a debug line.
It governs **future joins only**: it does not evict a guest already in the room,
so a revoke still closes that guest's own session with `revoked`, which is what
`CompanionHost.revoke` has always done.

**A host that joins again supersedes the one before it.** A Mac that goes without
a `$disconnect` — `kill -9`, a crash, a battery — leaves its host row and the
guest bound to it in the table until the three-hour TTL sweeps them. It comes back
on a new connection and finds its own room already occupied: a host row naming a
socket nobody reads, and a guest row holding the room's one slot, so the phone is
answered `room busy` or binds to the dead host and waits. The newest host is the
real one, so its join deletes every other host row in the room and closes those
sockets, tells every guest `{"a":"peer","event":"left"}` and deletes its row, and
logs `"result":"superseded"` naming what it swept. The phone rejoins within a
backoff step. `claimGuestSlot` prefers the host row with the latest `expiresAt`
besides, so a delete that did not land still leaves the room to the Mac that is
there rather than to a row that outlived it.

**A room is open while a code is on screen.** A phone pairing for the first time
holds a key that is on no list — the pairing is what puts it there — so an
allow-list alone refused the one guest the code was put up for, and a first
pairing over the relay could not be made at all. Both `join` and `allow` carry an
optional `"open"`, and while it is true the relay admits any guest, still one at a
time; while it is false or absent, only listed keys. It is written **only when
true**: a shut room says nothing, so every message a previous build sent is
unchanged on the wire. `RelayMessage.isOpen` is the one place absent and false are
read as the same answer, and only a host's join carries either flag.

An open room is not a weaker Mac. It buys a stranger a handshake and nothing
else: `HandshakeResponder` still refuses any static key it has not paired unless
that device can answer the code, `CompanionHost.unauthenticatedLimit` and
`handshakeDeadline` still bound the plaintext stage, and three wrong answers still
burn the secret. What it removes is a refusal one layer too early to be useful.

`CompanionHost.relayOpen` is the flag, observable beside `relayAllowList`:
`beginPairing` raises it, and it falls when the code comes down, when a pairing
succeeds, when three wrong answers burn the secret, when the host stops, or when
the code simply runs out — `CompanionHost+RelayRoom` holds the clock for that last
one, since nothing else would ask. `RelayRoad` reads both inside one
`withObservationTracking` and republishes on either, so a code going up reaches
the relay the same way a pairing completing does.

### The sequence

```
client -> relay  {"a":"hello"}
relay  -> client {"a":"challenge","n":"<base64, 32 random bytes>"}
client -> relay  {"a":"join","room":"<32 hex>","pub":"<base64 key>","role":"host","sig":"<base64>",
                  "allow":["<base64 raw pub>", ...],"open":true}
                                        allow and open: a host's; allow at most 16 keys,
                                        open written only while a code is on screen
relay  -> client {"a":"joined","role":"host"}          or  {"a":"error","reason":"..."}
host   -> relay  {"a":"allow","pubs":["<base64 raw pub>", ...],"open":true}
                                        when the paired set moves or a code goes up or down
relay  -> host   {"a":"allowed","count":2}
client -> relay  {"a":"send","d":"<base64 sealed frame>"}
relay  -> client {"a":"peer","event":"joined"}          when the other end arrives
client -> relay  {"a":"ping"}   relay -> client {"a":"pong"}
```

The first frame must be `hello` and the second `join`; anything else from a
connection with no membership is `{"a":"error","reason":"not joined"}` and an
immediate close. Wait for `joined` before the first `send`: the relay's
connection index is eventually consistent.

A `send` is forwarded verbatim, the `a` field included, so the receiver sees the
same JSON the sender wrote and extra fields survive the trip. A host's frame goes
to the room's one guest; a guest's goes to the host alone. `d` is opaque to
the relay, which is not a trust boundary: the payload is a sealed frame.

#### A payload too big for one frame

API Gateway's 128 KB is the limit on a **message**; one **frame** may carry 32 KB,
and `URLSessionWebSocketTask` sends a message as a single frame. A 64 KiB blob
chunk sealed and base64'd is about 87 KB, so the first one closed the Mac's socket
with `NSPOSIXErrorDomain 57` and nothing said about why. The client fragments, not
the relay:

```
client -> relay  {"a":"send","d":"<base64 slice>","m":"<16 hex>","i":0,"n":3}
```

`m` is a message id every slice of one payload shares, `i` is this slice's index
and `n` how many there are — ordinary extra fields, which the relay neither reads
nor rewrites. A slice is `RelayFragment.byteLimit` (18,000) bytes, exactly 24,000
characters of base64 and a multiple of three, so concatenating the slices' bytes
and concatenating their base64 are the same answer. A payload that fits goes as
`{"a":"send","d":"..."}` with none of the three, which is every frame a previous
build sent.

`RelayFragments` is the receiving half, and it assumes nothing about order:
invocations run concurrently, so slices are held by `m`, indexed by `i`, and
released only when all `n` are there. Slices of *different* messages interleave
for the same reason, which is what the bounds have to survive: a picture
transfer is many 64 KiB chunks of six slices each, all in flight together, and
against a cap of eight sets that cost sixteen frames in a burst while the relay
logged every one of them forwarded. So a set nothing finishes is dropped after
`lifetime` (30 s) — expiry first, since that costs nobody anything — at most
`setLimit` (256) sets are held, and `byteLimit` (64 MiB) across all of them is
the real memory guard, since 256 is a count and not a size. Past either the
oldest set goes, **and every eviction is logged at info** under `link.relay`
with the set's `m`, how many of its `n` had arrived and how long it had waited:
a set dropped part way through is a hole in the stream above, and it was silent
once.

A `peer` event fires on a disconnect in both directions — a host leaving notifies
its guest, a guest leaving notifies the host — and both say `left`.

An `error` during the handshake, or on a frame from a connection that has not
joined, is followed by the relay closing the connection. An error on a joined
connection leaves it open. The handshake's reasons are `malformed`, `bad room`,
`bad role`, `bad key`, `no challenge`, `challenge expired`, `bad signature`,
`room does not match key`, `bad allow`, `malformed`, `not joined` and `too many
hellos`, and the three a guest may meet: `no host` (the Mac is not in its room),
`room busy` (its one guest slot is taken) and `not allowed` (this device is not
on the list). A joined connection may also be told `not host` (a guest sent an
`allow`), `bad allow`, `bad payload`, `already joined`, `malformed` or `unknown
action`, and stays open.

**A refusal on a joined connection is a frame the far end never sees**, and the
far end has no way to know it happened: the hole simply appears in its counters.
So `RelayConnection` logs it at error *and* yields it on `relayErrors()`, a
stream beside `peerEvents()` that is empty for a road which refuses nothing, and
the session over the road logs it again with the phone or the Mac it belongs to.

### What a missing frame writes in the log

Every place a frame can vanish says so at error, under `io.zephra`
(`make logs`). A live run had one dropped with nothing written anywhere, which
is what this list is for.

| Where | Category | What it says |
| --- | --- | --- |
| `RelayConnection.write` | `link.relay` | the relay action, the byte count and the error, for any send that fails — a `try?` over one still logs here |
| `RelayConnection.send` | `link.relay` | the frame's size and the error, before the road is taken down |
| `RelayConnection.streamEnded` | `link.relay` | the socket's close code and the error, for a socket that went on its own |
| `RelayConnection.dispatch` | `link.relay` | the relay's own reason for refusing a frame after the join |
| `LinkSession`'s writer | `link.client` | a frame that never left the phone, with its size |
| `CompanionSession`'s writer | `companion` | the same, from the Mac |
| `LinkClient.lost` | `link.client` | the `FrameGap`, and that the world is being asked for again |
| `CompanionSession.stepOver` | `companion` | the `FrameGap`, and that the session carries on |
| `RelayFragments.accept` | `link.relay` | at info: a slice set evicted before it was whole, its `m`, how many of `n` had come and its age |

The relay writes the middle of that journey: one JSON line per frame in
`/aws/lambda/zephra-link` saying whether it forwarded, dropped or failed each
one, which is the first place to look when a counter goes missing over the relay
rather than the LAN — the line shape and the filters are under "Logs" in
`Relay/link/README.md`. Those filters are **substring** patterns
(`--filter-pattern '"result":"no-peer"'`, `'"room":"<32 hex>"'`): the Node
runtime prefixes each line with `<timestamp>\t<requestId>\tINFO\t`, so the line
is not pure JSON and a JSON filter pattern matches nothing.

`RelayError` tells the guest's three apart, and
`NetworkLinkRoads.connectRelay(room:pairing:)` is where that turns into
behaviour: `no host` and `room busy` are about the moment and read as
unreachable, so the phone waits on `LinkBackoff` and tries again; `not allowed`
is about this device, and what it is worth depends on what the phone was doing.

Reading a code, it becomes `LinkError.notPaired`, whose one sentence the person
is shown with "Check that the code is still showing on your Mac" added, and the
walk of the roads stops there. **Reconnecting, it is `LinkClientError.notAdmitted`
and the phone waits.** It used to be the same refusal either way, and
`LinkClient.refused(_:by:)` reads a `notPaired` from the Mac this phone is paired
with as a pairing withdrawn — so a phone would forget a Mac over a list the relay
read a beat too early. That list is the Mac's, not the relay's: it rides in the
host's `join` and is replaced by `allow`, so a Mac that has just restarted, or one
whose road joined before it had read its own pairings (which is the bug
`RelayRoad.rejoin()` fixes above), is briefly a Mac whose room admits nobody. The
cost of treating that as a revocation is a person hunting for a pairing code to
get back a pairing nobody withdrew; the cost of treating a real revocation as a
wait is a phone that retries on `LinkBackoff` until the Mac's own handshake tells
it — which it does, over the local road at once and over the relay as soon as the
Mac lets it in. Only the Mac's own `notPaired` or `revoked` unpairs.

A guest's `send` before the host is in the room is not forwarded.

### The signature

`sig` is Ed25519 — `Curve25519.Signing`, no pre-hash — over exactly:

```
nonce (32 raw bytes) || room (32 ASCII hex characters) || role ("host" | "guest", ASCII)
```

No separators and no length prefixes, because none of the three can run into the
next: the nonce and the room are both fixed at 32, so the role is whatever is
left. A host's signed message is **68 bytes** and a guest's 69;
`RelayMessageTests` pins the layout. `RelayJoin.sign(identity:nonce:room:role:)`
writes it and `verify(publicKey:nonce:room:role:signature:)` checks it.

The relay rebuilds the key from SPKI DER, whose fixed prefix is followed by
exactly the 32 bytes in `pub`, which is what
`Curve25519.Signing.PublicKey.rawRepresentation` already is.

The challenge is single-use — a successful join spends it, so a captured join
frame is worthless on a later connection — and it expires after 60 seconds. A
second `hello` replaces it, and only the newest is live.

### API Gateway's limits, which the protocol is shaped around

| Limit | Value | What it means here |
| --- | --- | --- |
| Message payload | 128 KB | a sealed 64 KiB chunk is about 87 KB of base64, inside it |
| Frame payload | 32 KB | one frame per message here, so payloads are cut at 24,000 base64 |
| Frame type | text only | JSON with base64 payloads, not binary frames |
| Connection lifetime | 2 hours | both ends reconnect and re-handshake |
| Idle timeout | 10 minutes | clients ping every 5 minutes |

A reconnection is a whole new handshake with new ephemerals, and it needs no
pairing secret: the static keys the two ends already share are what stand in for
one.

## The road under the channel

`LinkConnection` (`ZephraLinkProtocol/Transport/`) is all the secure channel asks of a
transport: `frames()`, one `AsyncThrowingStream` of whole frames; `send(_:)`, one frame
whole; `close()`. A TCP road prefixes each frame with a 4-byte big-endian length itself;
the relay road maps one WebSocket text message to one frame. `LinkListener` is the Mac's
side, yielding a `LinkConnection` per peer. `MemoryLinkConnection.pair()` is both ends of a
road that never leaves the process, for tests and the phone's frozen preview.

## Roads

`ZephraLinkTransport` is the roads themselves: Foundation, Network and os over
the protocol, no state, and every type in it is a `LinkConnection` or something
that makes one.

**TCP.** `TCPConnection` puts a four-byte big-endian length in front of every
frame and reads one back the same way: read the length, read exactly that many
bytes, hand the frame up, begin again. `NWConnection.receive` does the gathering,
with `minimumIncompleteLength` and `maximumLength` both set to the count, so a
frame split across packets arrives whole and a short read means the peer went
away part way through one. A frame is capped at 1 MiB in both directions — a
chunk is 64 KiB and a snapshot a few hundred kilobytes, so the cap is room to
spare and not a limit anything legitimate meets. A length past it is not a frame
this build would ever send, so the road closes rather than allocating what it
asks for. An empty frame is a frame, not the end of the road.

`TCPListener` is the Mac's side. The advertiser is not a type of its own:
`NWListener` publishes the service itself, and a separate advertiser would have
to be handed the port the listener chose and kept in step with its lifetime — two
objects that can only ever be right together. So advertising is an argument,
`TCPListener(advertising: room)`, and the TXT record is `BonjourRecord`: `room`,
the hash of the Mac's signing key, and `v`, the protocol version, on
`_zephra._tcp`. The room is in the record so a phone that has paired already
knows which of several Macs is its own before it opens a connection to any of
them.

**The room in the record is public, and that is acceptable.** Anyone on the local
network can read it, and the room is where the relay would route a guest — so
before the allow-list, knowing it was most of what taking a Mac's relay slot
needed. It is not any more: the relay admits a guest only when its signing key is
one the Mac has paired, so the room's name buys a refusal. The record is a
per-device name and never the Mac's model or the person's name; it is published
only while the local road is open, which is a switch that is off until asked for.
What is left is that the same Mac is recognisable on a network across time, which
is true of every Bonjour service on it, and the alternative — a rotating name —
costs a paired phone the ability to find the Mac again, which is the whole point
of the record.

`BonjourBrowser` hands back the whole list every time rather than a stream of
arrivals and departures, and `DiscoveredHost` keeps the endpoint as the service
rather than as an address: Network resolves a `.service` endpoint when the
connection is made, over whichever interface and address family actually works,
which is a better answer than any one address a browse could pick.

**The relay.** `RelayConnection` is a `URLSessionWebSocketTask` — the one WebSocket
that works the same on both platforms with no server-side headers to set — and it
speaks the sequence above: hello, challenge, join, joined, then `send` frames
carrying base64 of one sealed frame each — cut into `RelayFragment` slices when
the base64 passes 24,000 bytes, since one frame holds 32 KB and a sealed 64 KiB
chunk is about 87 KB, and put back together by `RelayFragments` on the way in. The rules about which message may
follow which live in `RelayHandshake`, a value with no socket under it, so they
can be tested by handing it the messages a relay would send. It pings every five
minutes against the ten-minute idle timeout, and it does **not** reconnect: a
reconnection is a whole new handshake, and pretending otherwise would hand the
channel above a stream with a hole in it.

**A road that cannot carry ends.** A `send` that fails, or a socket that closes,
marks the connection closed and finishes `frames()` — with the error where there
was one. A session over a dead socket is the failure that made this a rule: the
Mac kept a `CompanionSession` on a socket API Gateway had closed, `RelayRoad`
rejoined the room beside it, and the phone still said "Live through relay" while
every request timed out. `RelayListener` ends the guest session its road carried
as that road stops, and `RelayRoad` ends every guest of a join after the join
does and before the next one yields any.

On the phone, `LinkConnection.peerEvents()` is how a road says the other end
arrived or went — the relay can, a TCP road answers a stream that finishes at
once — and a `peer left` ends the session as a failed send does. Both announce
themselves on `LinkClient.sessionEndings()`, which is what `LinkReconnect` waits
on: a session that dies is reconnected to at once rather than on the next beat of
a poll or the next foreground.

**One guest at a time over the relay.** `RelayListener` is a `LinkListener` like
the TCP one, so the Mac's session code is the same over either road, but with a
limit the local network does not have. The relay gives a host one connection and
a frame on it carries no guest id, so two phones at once would be one interleaved
stream that no channel could open. Several phones at once is a LAN feature; over
the relay it is one, and per-guest multiplexing is in `ROADMAP.md`.

A frame that arrives with no session behind it opens one, because the relay's
connection index is eventually consistent and a guest's first frame can beat the
`peer joined` that announces it. Which is why a `peer joined` over a session that
is already up **leaves it alone**: the relay admits one allow-listed guest at a
time, so that announcement is the one already talking catching up with its own
first frame, and closing the session on it would tear the handshake that frame
began in half. A session stands until a `peer left`, or until the host's own road
goes. `updateAllowList(_:open:)` is on the listener too, and both the list and the
open flag ride in the join when it is called before `start()`.

**Reconnecting** is the caller's job, not the road's — the phone's client on one
side, and `RelayRoad` in the Mac app on the other, which rejoins its room when
the socket goes and ends that join's guests before the new join yields its own. `LinkBackoff` (`ZephraLinkTransport`) is the one
place the numbers live: a second, then two, four, eight, capped at thirty. The
count is the caller's, because the caller is what knows a connection succeeded —
it resets on a live session and on the app coming to the foreground, which is
also when it reconnects.

## The Mac host

`ZephraLinkHost` (`Packages/ZephraKit`) is the Mac's side: `CompanionHost`, the
sessions under it, and the projections that turn the store and the index into
what crosses. It lives in `ZephraKit` rather than in `ZephraLink` because it is
Mac-only and reaches deep into the engine, and `ZephraLink` is the one package
the phone links whole. SwiftPM takes the resulting bidirectional *package*
dependency because the target graph under it is acyclic: `ZephraLinkProtocol` ->
`ZephraEngine`, `ZephraLinkHost` -> `ZephraLinkProtocol`.

**What it watches.** One `withObservationTracking` loop, re-armed after every
change and coalesced by a 50 ms sleep, over `store.state`, `store.current?.id`,
the ids in `store.history`, `store.queue`, `store.running`,
`store.descriptor.id`, `store.availability`, `store.downloads.items`,
`store.acceptsWork`, `store.livePreview` and `index.items`. The sleep is what
makes it correct as well as cheap: the callback runs *before* the change lands,
so reading in it would read the value before. Each `StateDelta` case is compared
on its own against `CompanionPublication`, what the sessions were last told, so a
step counter ticking does not resend the model list. The library is compared by
`LibraryEntry.version`, and a change of more than a hundred entries is a
`.reset` rather than a diff — a folder scanned wholesale is not a diff worth
sending. The loop runs only while a session is open.

**The library is pulled, not pushed.** The first pass publishes nothing and the
snapshot carries `libraryCount` rather than the folder, so what the Mac sends
about the library is only what *changed* after a phone arrived. The entries
themselves the phone asks for: `libraryPage(offset:limit:)` answers a window onto
`LibraryEntryProjection.listing`, newest first, Recently Deleted left out, the
limit clamped to 200 and the offset clamped to the end — a page past the end is
empty and still carries the total, which is what says a pull is finished. The
command reads the index and nothing else, so a page is answered while the Mac is
mid-run.

Preview frames have their own path: `PreviewEncoder` turns the engine's RGBA8
into JPEG at 0.6 off the main actor, at most ten a second, newest wins, and the
frame is fingerprinted by its size and its first and last sixteen bytes rather
than hashed — a quarter of a megabyte, several times a second.

**What it never touches.** `CompanionSession+Commands` maps every `Command`
through the doors the Mac's own menus use: `GenerationStore.enqueue` for a
submit, `switchModel`, `cancel`, the queue calls, `LibraryIndex`'s own mutations,
`moveToRecentlyDeleted`, `upscale`, `animate`. It never writes `settings` or
`descriptor`, never sets `index.query`, and never calls `generate(count:)` — the
person at the Mac may be halfway through typing a prompt. An annotation edit is
made with `index.undoManager` lifted off and put back, because Undo is the Edit
menu of the window in front of somebody, and a favourite a phone toggled sitting
on it as "Undo Favorite" would be an edit they never made.

A refused submit carries the store's own words: `RemoteAdmission`'s `.busy`,
`.refused` and `.badRequest` become `LinkError`s of the same three codes.
`store.clips == nil` refuses Animate as `unsupported`; a file name the index does
not know is `notFound`.

**Sessions.** `CompanionSession` is one phone from its handshake to the road
closing. One loop over the connection's frames, with `channel == nil` standing
for "still in the plaintext stage", so there is one reader and no iterator
crossing an isolation domain.

The plaintext stage is where an unpaired device can cost the Mac something, so it
is bounded twice. `CompanionHost.accept` refuses a connection when
`CompanionHost.unauthenticatedLimit` sessions already have no channel — eight,
far more than the phones in one house — and closes that connection rather than
allocating a session for it; only the unauthenticated are counted, so a house of
paired phones talking is never refused. And each session starts a clock:
`handshakeDeadline`, ten seconds, cancelled the moment the `confirm` settles, and
otherwise the session closes. Both live here rather than in `TCPListener`, which
has no notion of a handshake and would have to be told about one; the relay road
gets the same bound for free. Everything the Mac says is sealed at the call and
yielded into one `AsyncStream<Data>` drained by a writer task of its own: the
channel's nonce is a frame's position in the stream, so the order frames are
sealed in must be the order they leave in, and a phone on a slow link never holds
the main actor. A blob leaves as a `blobStart` reply and the chunks behind it.

**The app's side** is `Sources/Zephra/Companion/`. `LinkKeychain` is the facade
over this Mac's identity and its pairings, and `LinkKeychainKind` decides where
those two secrets are kept — **three** answers, one question, asked once a launch
and logged: does this code carry a team identifier
(`SecCodeCopySelf` and `SecCodeCopySigningInformation`, `kSecCodeInfoTeamIdentifier`)?

- **Data protection** where it does. `LinkKeychainStore` keeps both as generic
  passwords under `io.zephra.link`, accessible after first unlock and
  `ThisDeviceOnly` — a Mac restored from another Mac's backup should be a new
  device, not that one — and every query asks for the **data-protection**
  keychain (`kSecUseDataProtectionKeychain`), the only one on macOS where
  `kSecAttrAccessible` means anything: without it the items sit in the file-based
  login keychain under whatever its own unlock state happens to be, and
  `ThisDeviceOnly` is silently nothing. An item a build before that wrote is found
  by `legacyQuery`, moved across on the first read and deleted from where it was —
  **only where the write landed in the other keychain**, which is the rule below;
  `removeAll` clears both. The phone's `MobileKeychain` asks for the same flag,
  which is iOS's default, so both ends read the same.
- **Legacy** if that keychain refuses the entitlement after all. It is found out
  lazily, on the first call that answers `errSecMissingEntitlement`, which moves
  that store's `LinkKeychainLatch` and tries again the old way. No probe: a probe
  is one more keychain call, and calls are the thing being counted here. The latch
  is one object per store rather than a static, so the identity read and the
  devices read that follow it at a launch share one answer instead of racing a
  process-wide flag, and a test can hand a store the other answer.
- **Files** where there is no team identifier, which is every `make run`, `make
  build` and `CODE_SIGN_IDENTITY "-"` build. `LinkFileStore` keeps `identity` (the
  raw 64 bytes) and `devices.json` under `<Application Support>/Zephra/Companion`,
  the folder at 0700 and each file at 0600, written to a hidden sibling and renamed
  into place. The reason is the login keychain doing its job: it identifies an app
  by its signature, a local build has a new one every time it is built, and the
  rebuilt app touching what the last build wrote raises the password prompt at
  launch and on every pairing write — "Always Allow" lasting exactly until the next
  rebuild. Under `.file` no keychain is queried at all, so no prompt can appear.
  **Nothing is migrated out of the keychain**, deliberately: reading the item would
  raise the very prompt this avoids, so a local build pairs its phone once more and
  the log line says so. A Developer ID build, which has a stable designated
  requirement, is unaffected either way.

**The migration must never delete what it did not move.** It did once, and it cost
a Mac on the test bench its whole link. `read` copied the legacy item, called
`write`, and deleted the legacy item; the write hit `errSecMissingEntitlement`,
latched to legacy and wrote the bytes straight back into the item that was about
to be deleted. `remove` swallows its own errors, so nothing said anything. The
next launch found no identity, `LinkSecretStore.identity()` minted a new one, and
the Mac joined a brand-new relay room while the phone went on knocking at the old
one every thirty-four seconds and being told `no host`. Nothing in the log said
the identity had changed. So: the spelling is read once at the top of `read` and
again after the write, and the delete happens only when both say the bytes went
somewhere else; a write refused the data-protection keychain falls back once and
not twice, since a keychain that refuses both spellings would otherwise recurse;
`LinkKeychainKind.settle()` resolves the kind on one thread at the top of
`startCompanion`, before the detached read; and `identity()` logs at **error**
when it mints over devices that are still on file — there is no way back from a
lost identity, but the next time it happens `make logs` will say so rather than
leaving a phone that simply never connects again.

`LinkSecretCache` sits between the facade and whichever store, because a keychain
call on a signature the keychain does not recognise is a password prompt and
`SecItemCopyMatching` does not return until somebody answers one. It reads each
secret **once a launch** — `startCompanion` takes both in one detached pass and
nothing reads again, a write included — writes a pairing or a revocation straight
through, and rate-limits what is only cosmetic: a list that differs from the stored
one by `lastSeen` alone is written at most once a minute, the deferred value landing
on its timer or with the next real change. A `ZEPHRA_FRESH_START` launch keeps its
own secrets either way: accounts of its own in the keychain, a `Companion` folder
under its throwaway root on disk. `CompanionThumbnails` is `ThumbnailSupply` over the app's own
`ThumbnailFolder`, so a phone scrolling the library pays for each decode once and
shares what the Mac's grid already baked. `CompanionEndpoints` is the addresses a
code carries: the `.local` name first, then every IPv4 address on an interface
that is up, loopback and link-local left out. `CompanionRoads` opens the roads and
remembers the port the local one actually took, since 7723 may be held by
something else and a code has to name where the listener really is. `RelayRoad` is
one `LinkListener` that outlives the sockets under it, rejoining the room on
`LinkBackoff` so the host is served once rather than once per reconnection, and
carrying what the relay admits on: it reads `CompanionHost.relayAllowList` **and**
`CompanionHost.relayOpen` inside one `withObservationTracking` loop, hands both to
each listener before that listener joins, and sends an `allow` to the join already
up whenever either moves — a pairing completing, a device revoked, a code going up
or coming down. `rejoin()` reads both off the main actor **itself** before its
first join rather than trusting that loop to have run: `start()` puts the watch on
the main actor and the rejoining on the global executor, and whichever reached the
road's state first decided what the first join carried — which, when it was the
join, was `allow: []`, a room that admits nobody until the `allow` message lands
behind it. A phone dialling in that window is answered `not allowed`, which is the
refusal the phone must not read as a revocation (above). `RelayJoining` is the seam
the join is made through, so `RelayRoadTests` pins the order without a socket.
`ZephraApp+Companion` is where the two closures are tied to the
host, weakly, since the host holds every listener it is served.

**Three wrong answers burn the code.** A `confirm` whose tag does not prove the
secret, from a `Hello` that asked to pair, is counted; the third ends the pairing
outright — `secret` cleared, `pairing` nil, the QR gone from Settings and
`CompanionHost.pairingNote` in its place saying why. The secret behind a code is
a thing to be guessed at and the code sits on screen for two whole minutes, which
is the one window in the whole link that is cheap to attack. A wrong tag from a
device that was *reconnecting* is not counted: no code is being guessed at, and
that session is refused on its own account. `beginPairing()` clears both the
count and the note.

**A code on screen opens the relay room.** `beginPairing()` also sets
`CompanionHost.relayOpen`, which is what lets a phone that has never paired reach
the relay at all: its key is on no allow-list until the pairing puts it there.
The flag falls on every way the code goes — `endPairing()`, a pairing that
succeeds, the third wrong answer, `stop()` — and on the code simply expiring,
which `CompanionHost+RelayRoom` keeps a clock for because nothing else would
notice. The room being open changes nothing about who this Mac talks to: the
responder's refusal is unmoved, and a stranger gets a handshake it cannot pass.

**Settings > Companion** is the fourth tab. Two switches, deliberately apart:
one opens the local road and puts the Mac on Bonjour, the other lets a phone
somewhere else meet it on the relay, and neither follows from the other. Both are
off until asked for. The pairing code is a version 11 QR at 240 points, drawn
without interpolation so every module stays a hard square, with `Text`'s own
timer style counting its two minutes down — no repeating animation, which the app
target forbids. Revoking a device is immediate: the list is written before the
sessions are closed, so a phone that reconnects the instant it is dropped is
refused rather than racing the save.

## The phone's client

`ZephraLinkClient` holds `LinkClient`, a `@MainActor @Observable` class that is
the phone's `GenerationStore`: the one object its views observe, split across
`LinkClient+*.swift` by concern — connecting, pairing, the handshake, the
dispatch, requests, blobs, commands. A new concern is another extension file,
never more lines in `LinkClient.swift`.

What it holds is what the Mac published: `snapshot`, brought up to date by
`StateSnapshot.applying(_:)` for every delta after it; `preview`, the newest
frame of the run in flight, cleared whenever the engine stops being busy;
`library`, the entries the Mac has sent **and the ones the phone pulled**, reset,
upserted by file name or removed; `libraryIsComplete`, whether that list is the
whole folder; and `pairedHost`, the Mac this phone knows. Nothing here decides anything about a
generation — the Mac clamps, the Mac queues, and the phone shows what came back.

Two things are injected, and both are what make the whole session testable in
milliseconds. `LinkKeyStore` is where the identity and the pairing are kept; the
keychain is the app's business, and `MemoryLinkKeyStore` is the test's.
`LinkRoads` is every way to reach a Mac — `NetworkLinkRoads` is Bonjour, TCP and
the relay; `MemoryLinkRoads` hands back one end of a `MemoryLinkConnection.pair()`
with a fake Mac on the other, so pairing, the handshake, the dispatch, a request
and a blob are all exercised with nothing between the two ends but an
`AsyncStream` and no permission dialog for the local network.

A pairing the Mac withdraws ends at the phone's end too. On a live session the
Mac's `revoke` sends a `revoked` error frame before it closes, and the phone
forgets the Mac and keeps the Mac's sentence as `LinkClient.farewell`. A phone
that was away learns on its next `connect()`: the Mac answers `notPaired`, the
relay answers `not allowed` (read as the same `LinkError`), and since the phone
was paired with that very Mac it treats either as revoked — it forgets the Mac
and sets a farewell of its own naming it, which the pairing screen shows in
place of "offline". The Mac's refusal stays one plain sentence for everyone,
so an unauthenticated caller cannot learn from it whether a key was once known.

`connect()` is idempotent, so the interface calls it on every foreground without
a flag of its own: the local network first, then the relay. The local network is
one race (`LocalRoadRace`): every stored address and every Mac a Bonjour browse
turns up in the room are dialled at once inside `LinkClient.lanWindow` (3 s),
the first road to open is taken, any that opens after it is closed, and a dial
still ringing when it is over is left to ring out on its own, since a Network
connect does not stop when its task is cancelled. Every address refusing is an
answer at once, so a phone away from home reaches the relay in well under a
second; the sequential walk it replaced dialled up to five addresses at ten
seconds each. A refusal ends it wherever it comes — it is the same Mac at the
end of every road, and trying the rest would waste the person's time and lose
the sentence the Mac wrote for them. `pair(with:)` is the same race and the same
relay carrying the code's secret, and it saves the `PairedHost` only once a
handshake has succeeded.

Everything sealed leaves through one `AsyncStream<Data>` on the `LinkSession`,
drained by a writer task of its own — the Mac's shape, for the Mac's reason. The
channel's nonce is a frame's position in the stream, so a frame's counter must be
taken in the order the frames go out; sealing on a task per request left two
requests, or a request and the pong an incoming ping asks for, free to take two
counters and reach the socket the other way round, which the far end cannot open
and never recovers from. `LinkSession.send(_:)` is synchronous for exactly that:
no await between taking the counter and queueing the bytes.

The session loop reads `frames()`, opens each through the `SecureChannel` and
dispatches by kind. The reader starts **before** the first plaintext message goes
out, not after the handshake: the Mac's answer can be on its way back before this
end asks for it, and a frame read by nobody is a handshake that hangs. A body
that will not decode is dropped with a log line rather than taken as a reason to
close, which is the case the envelope's opaque body exists for. An `error` with
`revoked` forgets the host, because the keys this phone holds are then worth
nothing.

`request(_:)` holds a command open for thirty seconds under its envelope's id,
and every command gets exactly one reply. A request that times out or is failed
as `lost` by a gap is **asked once more**, under a fresh envelope id — the first
may yet turn up, and two requests sharing an id would be two answers to one
continuation. `fetchBlob(_:)` is a request whose
reply announces a blob, and the chunks that follow are reassembled in order; it
retries once as well, since the reply arrived and it is the bytes behind it that
went missing. A transfer nothing is assembling any more is `lost` at once rather
than waited out, or a caller that reached its `await` a moment after a gap would
sit on a continuation nobody can resume. The
announcement is opened in `dispatch`, where the reply is read, rather than where
the request that asked for it resumes — the reply and the first chunk are two
frames on one stream, and a phone that had not got back to its own `await` would
drop the second. A chunk for a blob **nothing announced** is dropped with a log
line: the announcement is what says how much memory a transfer may take, so
without one there is nothing to assemble it into. At most `LinkClient.blobLimit`
(4) are part way through at once, oldest dropped, and each is given
`blobTimeout`, two minutes from the announcement rather than from the first
`await` for it. `enqueue(_:reference:)`
sends the picture as a blob first and names it in the request, for the reason
`GenerationRequest` strips the bytes at all.

`LinkClient+LibraryPull` is the phone's half of the library. A snapshot landing —
which is every connect — cancels any pull in flight, sets `libraryIsComplete`
false and starts one: `libraryPage` at offset 0 in pages of
`LinkClient.libraryPageSize` (100), one in flight at a time, each page absorbed
into `library` as it arrives so the grid fills progressively rather than after
the last one. The total is re-read from every page, since the folder may move
under a pull that takes a few seconds; a page whose entries run out at that total
sets `libraryIsComplete` in the same step as the entries land, because a cache
applies its removals on the strength of that flag and a turn of the main actor
between the two is a turn where the library looks present and incomplete. A
thrown request is not the end of it — the Mac may have been busy — so the same
offset is asked for again after `LinkBackoff`, for as long as the connection is
live; a session that ends cancels the pull, and the next session's snapshot
starts a fresh one. The loop is `nonisolated`, so the only thing it runs on the
main actor is the one mutation. Entries the phone has not got are **appended**
rather than inserted at the front the way `LibraryChange.upserted` does: the
pages arrive newest first, so the front is where the page before it already is.

`LinkClient.frozen(snapshot:library:)` is a client for a preview or a screenshot:
live over the LAN as far as the interface can tell, requests answering `.ok` and
blobs failing, and no road under it at all. A preview that could make a request
would be a preview that could queue a generation on somebody's Mac.
