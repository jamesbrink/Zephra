# The companion link

`Packages/ZephraLink` holds `ZephraLinkProtocol`: the wire the Mac app and a
future iOS app both speak. No transport and no interface are in it, so both ends
are tested in milliseconds without a socket, and the phone links the whole target.

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
request open and know it will close.

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
`isFinishing`, `acceptsGeneration`) are stored fields, so the phone never has to
know a rule the Mac already knows.

`GenerationRequest` carries `ZephraCore`'s own `GenerationSettings`, so the Mac
clamps what arrives through the same `clamp` a local press of Generate goes
through. The one thing stripped is `referenceImage`, on the way in and on the way
out: a picture crosses as a blob and is named by `referenceBlobID`.

## Blobs

Thumbnails, files and clips do not go in JSON. A `blobStart` announces the id,
the byte count and the mime; the bytes follow as chunk frames.

- `BlobChunker.chunkSize` is 64 KiB. One chunk, its 24-byte header and the
  channel's tag fit inside the relay's 128 KB frame with room to spare.
- Empty data is one empty chunk, not none: a blob of nothing still has to be
  announced, sent and completed.
- `BlobReassembly` takes chunks **in order only**. The channel underneath is a
  single ordered stream, so a gap means loss or tampering rather than overtaking,
  and holding out-of-order pieces would mean holding arbitrary memory for a
  sender that never sends the missing one. A duplicate index is the same answer.
- One blob may not exceed 64 MiB while it is being assembled.

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
with `pairing` set needs a live pairing secret or it is `refused`; one without
needs a static key the Mac already knows or it is `notPaired`; a version that is
not `LinkProtocolVersion.current` is `protocolMismatch`.

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
`UInt64` counter, big-endian; the counter is implicit, never sent. The additional
authenticated data is the frame's one kind byte. A sealed frame on the wire is
`kind || ciphertext || tag`.

Requiring the exact next counter is what makes a replayed, lost or reordered
frame a failure instead of something the receiver quietly accepts: it decrypts
under the wrong nonce and the tag does not verify.

One failure closes the channel for good, both ways. There is nothing to recover
to: a frame that did not authenticate means the stream is not the one that
started, and carrying on would let an attacker probe until something got through.
At 2^32 frames one way the nonce space is finished and `rekeyRequired` says the
connection has to be made again.

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

A room is the lowercase hex of the first 16 bytes of `SHA-256` over the raw
32-byte Ed25519 public key — `RoomID(signingPublicKey:)`, the one place that rule
lives. The relay checks that the key hashes to the room **for a host only**. A
guest signs with its own key and is let in, because the host will refuse an
unknown static in the handshake the relay cannot read.

### The sequence

```
client -> relay  {"a":"hello"}
relay  -> client {"a":"challenge","n":"<base64, 32 random bytes>"}
client -> relay  {"a":"join","room":"<32 hex>","pub":"<base64 key>","role":"host","sig":"<base64>"}
relay  -> client {"a":"joined","role":"host"}          or  {"a":"error","reason":"..."}
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
to every guest in the room; a guest's goes to the host alone. `d` is opaque to
the relay, which is not a trust boundary: the payload is a sealed frame.

A `peer` event fires on a disconnect in both directions — a host leaving notifies
every guest, a guest leaving notifies the host — and both say `left`.

An `error` during the handshake, or on a frame from a connection that has not
joined, is followed by the relay closing the connection. An error on a joined
connection leaves it open. The handshake's reasons are `malformed`, `bad room`,
`bad role`, `bad key`, `no challenge`, `challenge expired`, `bad signature` and
`room does not match key`.

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
| Frame payload | 128 KB | 64 KiB chunks plus header and tag fit with room to spare |
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
