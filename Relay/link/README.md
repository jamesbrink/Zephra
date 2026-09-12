# Zephra link relay

**Where this came from, and who owns what.** The relay lived in the Terraform
repository that stands the infrastructure up (`urandom.io`, at
`modules/zephra/lambda/link/`) until the Zephra repository grew a CI that could
deploy it. The code is now here, beside the two ends that talk to it, and
`.github/workflows/release.yml` deploys it with `make relay-deploy` on every push
to `main`. Terraform still owns the function, the table, the API and the domain;
it no longer owns what the function runs, and its `aws_lambda_function.link`
ignores `filename` and `source_code_hash` so that a `terraform apply` does not
put the bootstrap copy back over a deployed one. Git history did not come across:
the file is the one that was deployed, unchanged.

`Packages/ZephraLink` is the other half of this contract. Nothing imports
anything here: the relay and `RelayConnection` are two implementations of the
same wire, and `docs/companion.md` is where the two are described together.

A WebSocket relay that pairs the Zephra Mac app (the **host**) with one iPhone
companion (a **guest**) inside a room. The relay is a dumb pipe: it
authenticates who may join a room, then forwards opaque payloads between the
host and its guest. It never reads, stores, or rewrites a payload.

- Endpoint: `wss://zephra-link.urandom.io` (module output `link_wss_url`)
- Room membership: DynamoDB table `zephra-link-rooms` (output `link_table_name`)
- Runtime: one Lambda (Node.js 20, arm64) behind `$connect`, `$disconnect` and
  `$default`

## Rooms and identity

A room is named by its host. The name is the lowercase hex of the **first 16
bytes of SHA-256 over the host's raw 32-byte Ed25519 public key**, so a room id
is always 32 hex characters and only the holder of that private key can host it.

**The room id is not a credential.** A guest learns it out of band (a QR code,
say), but knowing it admits nobody by itself: the host decides what the room
admits. A room carries **at most one guest at a time**.

**Admission.** A host's room is either open or closed, and closed is the
default. A closed room admits only the keys the host has named in its allow
list. An open room admits any key, which is how a phone that the host has never
seen pairs for the first time; the host should name that key and close the room
as soon as the pairing is done.

## Wire contract

Every frame is UTF-8 JSON text with an `a` field naming the action. The API's
route selection expression is `$request.body.a`, but all three routes land on
the same Lambda, so an unknown `a` is handled in code rather than by the router.

### `hello` — required first frame

```json
{ "a": "hello" }
```

The relay generates 32 random bytes, holds them against this connection for 60
seconds, and replies:

```json
{ "a": "challenge", "n": "<base64 of 32 random bytes>" }
```

A second `hello` replaces the first challenge; only the newest one is live. A
connection gets **three challenges at most**: the fourth `hello` is answered
`{"a":"error","reason":"too many hellos"}` and the connection is closed. A
`hello` from a connection that has already joined is answered
`{"a":"error","reason":"already joined"}` and the connection stays open.

### `join` — second frame

```json
{
  "a": "join",
  "room": "<32 lowercase hex characters>",
  "pub": "<base64 of the raw 32-byte Ed25519 public key>",
  "role": "host" | "guest",
  "sig": "<base64 of the 64-byte Ed25519 signature>",
  "allow": ["<base64 raw Ed25519 public key>", "..."],
  "open": false
}
```

`allow` is **the host's list of guest keys** and is read only from a host's
join. It is optional and defaults to empty. At most 16 keys; each must be base64
for exactly 32 bytes, or the join is refused with `bad allow`.

`open` is the host's **first-pairing switch**, also read only from a host's
join. It is optional, must be a boolean, and defaults to `false`; anything else
is refused with `bad open`. `true` admits any key until the host closes the room
again. A guest's `allow` and `open` are ignored.

**The signed bytes**, concatenated with no separator, no length prefix and no
terminator:

```
nonce (the 32 raw bytes, base64-decoded from "n")
  || room (32 bytes, the room id as ASCII)
  || role (4 or 5 bytes, "host" or "guest" as ASCII)
```

That is 68 bytes for a host and 69 for a guest. Sign the message directly with
Ed25519 (`crypto.sign(null, data, key)` in Node, `Curve25519.Signing.PrivateKey
.signature(for:)` in Swift Crypto) — Ed25519 hashes internally, so do **not**
pre-hash. `allow` and `open` are **not** signed; they are accepted on the
strength of the host's authenticated connection, exactly as a later `allow`
frame is.

**Domain separation.** Both variable parts of the signed message are fixed
width — a 32-byte nonce and a 32-character room id — so the concatenation parses
exactly one way and the trailing role is what the signature is bound to. A
signature made for `guest` is therefore not a valid `host` join in the same room,
the nonce binds it to one connection, and the room binds it to one room. The
host fingerprint check is the same separation applied to the key: the room id
covers the raw public key and nothing else, so a key that hashes to another room
cannot host this one.

The relay verifies against a key rebuilt from SPKI DER: the fixed prefix
`302a300506032b6570032100` followed by the raw 32 public-key bytes. In Swift,
`Curve25519.Signing.PublicKey.rawRepresentation` is exactly the 32 bytes that
go in `pub`.

For `"role": "host"` the relay additionally requires that `room` equals the
fingerprint of `pub` described above.

For `"role": "guest"` the relay requires, in this order:

| Refusal       | Meaning                                                      |
| ------------- | ------------------------------------------------------------ |
| `no host`     | no host has joined this room yet                             |
| `not allowed` | the room is closed and `pub` is not in the host's allow list |
| `room busy`   | another guest is already joined in this room                 |

A guest's `room` is not checked against its own key; the allow list is what
authorizes it.

The nonce is **single use**. A successful join spends it, so a captured join
frame is worthless on any later connection.

On success:

```json
{ "a": "joined", "role": "host" }
```

When a **guest** joins, the room's host receives:

```json
{ "a": "peer", "event": "joined" }
```

A join from a connection that has already joined is answered
`{"a":"error","reason":"already joined"}` and the connection stays open. Every
other failure replies with an error frame and then closes the connection.
Reasons: `bad room`, `bad role`, `bad key`, `bad allow`, `bad open`,
`no challenge`, `challenge expired`, `bad signature`, `room does not match key`,
`no host`, `not allowed`, `room busy`.

### `allow` — host only

```json
{
  "a": "allow",
  "pubs": ["<base64 raw Ed25519 public key>", "..."],
  "open": false
}
```

Replaces the host's **whole admission policy**, under the same limits as the
`allow` and `open` fields on join. The frame says what the room admits from now
on, so an omitted `open` closes the room and an omitted or empty `pubs` empties
the list. The relay answers with the size of the list, `open` or not:

```json
{ "a": "allowed", "count": 1 }
```

The new policy governs who may join **next**; a guest already in the room is not
evicted by it, so closing an open room is safe mid-session. Disconnect the guest
to end its session.

From a guest this is answered `{"a":"error","reason":"not host"}` and the
connection stays open. A malformed list is `{"a":"error","reason":"bad allow"}`
and a non-boolean `open` is `{"a":"error","reason":"bad open"}`, both also
without closing.

### `send`

```json
{ "a": "send", "d": "<base64 payload>" }
```

Forwarded **verbatim** — the same JSON text, `a` field included — to the other
side: a host's frame goes to the room's one guest, a guest's frame goes to the
host. Receivers therefore see `{"a":"send","d":"..."}` exactly as the sender
wrote it. The relay parses the frame only far enough to read `a` and check that
`d` is a string; it forwards the original text, so **extra fields survive the
trip untouched** and are the place to put anything the two peers need.

#### Fragmenting a large payload

API Gateway's advertised 128 KB is the **message** limit. A single WebSocket
**frame** may carry at most **32 KB**, and a client that cannot fragment a
message itself must stay under that: `URLSessionWebSocketTask` sends one frame
per message, so on Apple platforms 32 KB is the real ceiling.

A payload too big for one frame is therefore split by the **client**, not the
relay, at **24,000 bytes of base64** per slice — comfortably inside 32 KB once
the JSON envelope and the rest of the fields are counted:

```json
{ "a": "send", "d": "<slice>", "m": "<16 hex>", "i": 0, "n": 3 }
```

- `m` — a message id shared by every slice, 16 hex characters
- `i` — this slice's index, `0` to `n - 1`
- `n` — how many slices the message has

These are ordinary extra fields: the relay neither reads nor rewrites them, and
the receiver reassembles by concatenating the slices of one `m` in `i` order.
Because frames are not ordered end to end (see Rules and limits), a receiver
must buffer by `m` and index by `i` rather than assume slices arrive in
sequence.

A **host's** `send` with no guest in the room is **dropped silently**; wait for
`{"a":"peer","event":"joined"}` before a host sends anything. It is logged as
`"result":"no-peer"` (see Logs), which is the only trace of it.

A **guest's** `send` whose host is gone is answered
`{"a":"error","reason":"no host"}` and `{"a":"peer","event":"left"}`: a guest has
nothing to wait for, since the way back is a new host row and therefore a new
join.

A forward that fails for a reason that is **not** a dead peer — a throttle, a
timeout, a permission — is answered `{"a":"error","reason":"forward failed"}` and
the sender keeps its socket. A forward to a peer that is **gone** frees the
room's guest slot as before and tells the sender `{"a":"peer","event":"left"}`,
so a frame never disappears with nothing said to anybody.

`d` is opaque to the relay. Encrypt end to end; the relay is not a trust
boundary for payload contents.

### `ping`

```json
{ "a": "ping" }
```

Replies `{"a":"pong"}` and refreshes the row's TTL. Send one every few minutes
to stay under the idle timeout.

### `peer`

Pushed, never sent by a client:

```json
{ "a": "peer", "event": "joined" }
{ "a": "peer", "event": "left" }
```

A guest joining notifies the host. A **disconnect notifies the other side in
both directions**: a host leaving notifies its guest, and a guest leaving
notifies the host. Both use `event: "left"`.

### `error`

```json
{ "a": "error", "reason": "unknown action" }
```

An error on a connection that has **not** joined is followed by the relay
closing the connection: the handshake reasons above, plus `malformed`,
`not joined` and `too many hellos`.

An error on an **already-joined** connection leaves the connection open:
`malformed`, `unknown action`, `bad payload`, `bad allow`, `bad open`,
`not host`, `already joined`, `no host` (a guest whose host is gone) and
`forward failed` (the forward failed for a reason that is not a dead peer).

## Rules and limits

- **Text frames only.** Binary frames are not part of the contract; carry bytes
  as base64 in `d`.
- **128 KB per message and 32 KB per frame**, enforced by API Gateway. A client
  that sends one frame per message, as `URLSessionWebSocketTask` does, is
  bounded by the 32 KB figure; over it the connection is closed before the
  Lambda sees anything. Fragment a large payload as described under `send`.
- **2 hours** maximum connection lifetime (API Gateway's WebSocket cap). A
  client must expect to reconnect and repeat the handshake.
- **10 minutes** idle timeout. `ping` keeps a quiet connection alive.
- **The first frame must be `hello`, the second `join`.** There is no
  server-side grace timer: any other action from a connection with no
  membership row gets `{"a":"error","reason":"not joined"}` and an immediate
  close, and a connection that says nothing at all falls out on the 10-minute
  idle timeout.
- **Three `hello` frames per connection**, so an unauthenticated socket can
  force at most three challenge writes before it is closed.
- A challenge lives **60 seconds**. Past that, join returns `challenge expired`
  and the client must reconnect.
- Membership rows carry a **3-hour TTL** (`expiresAt`), longer than the
  connection cap, so the TTL only ever collects rows whose `$disconnect` never
  ran.
- A stale connection that returns `GoneException` (HTTP 410) on a forward is
  deleted from the table as a side effect of that forward, and a guest that goes
  that way frees the room's guest slot with it.
- **One guest per room**, open or closed. The slot is claimed by a conditional
  write on the host's own row, so two guests racing for the same room cannot
  both win.
- **An open room is a pairing window, not a mode to live in.** Any key on the
  internet that learns the room id can take the room's one guest slot while it
  is open.
- **Frames are not ordered end to end.** Rapid frames land in concurrent Lambda
  invocations, and nothing serialises the `PostToConnection` calls they make, so
  a receiver can see two frames in the order opposite to the one they were sent
  in. A client that cares must carry its own sequence number inside `d`.
- The relay does not stop a second host from joining a room if it holds the
  matching key. The newest host row carries no guest, so a host reconnect ends
  the guest's session and the guest must rejoin.
- The `byConnection` index is eventually consistent. The Lambda retries the
  membership lookup once after 150 ms, and **only for a connection whose own
  pending row says it has joined**; a connection that never joined is answered
  `not joined` on the first miss and never buys a second query. A client should
  still wait for `joined` before its first `send`. The challenge itself is read
  back with a strongly consistent `GetItem`, so hello and join never race.

### Table layout

One table holds both states, keyed `(room, connectionId)`:

| room                     | meaning                      | other attributes                                     |
| ------------------------ | ---------------------------- | ---------------------------------------------------- |
| `pending#<connectionId>` | an issued, unspent challenge | `nonce`, `hellos`, `expiresAt` (+60 s)               |
| `pending#<connectionId>` | the same row after a join    | `joined`, `expiresAt` (+3 h)                         |
| `<32 hex>`               | a joined host                | `role`, `pub`, `allow`, `open`, `guest`, `expiresAt` |
| `<32 hex>`               | a joined guest               | `role`, `pub`, `host`, `expiresAt`                   |

A join overwrites the pending row rather than deleting it: that spends the nonce
and leaves behind the marker that gates the 150 ms index retry. `hellos` counts
the challenges issued. The host row's `allow` is a string set of base64 public
keys, present only when the list is not empty; `open` is present only while the
room is open; `guest` names the connection holding the room's one guest slot; the
guest row's `host` points the other way, so a forward needs no lookup.

The `byConnection` global secondary index maps a connection id back to its rows,
which is how `$disconnect` finds what to clean up. A pending row's key is
derivable from the connection id alone, so join reads it directly.

## Smoke test

Run after an authorized apply. `wscat` comes from `nix shell nixpkgs#wscat`.

**1. The handshake, the certificate and `$connect`.** A raw upgrade request
proves DNS, the certificate, the custom domain mapping and `$connect` without a
WebSocket client:

```bash
curl -sS -i -N --max-time 5 \
  -H "Connection: Upgrade" -H "Upgrade: websocket" \
  -H "Sec-WebSocket-Version: 13" \
  -H "Sec-WebSocket-Key: $(openssl rand -base64 16)" \
  https://zephra-link.urandom.io | head -10
```

Expect `HTTP/1.1 101 Switching Protocols`.

**2. Routing, the Lambda and its DynamoDB permissions.** One round trip, no keys
needed:

```bash
wscat -c wss://zephra-link.urandom.io -x '{"a":"ping"}' -w 5
# < {"a":"error","reason":"not joined"}
# Disconnected (code: 1000, ...)
```

The error proves `$default` reached the Lambda, the Lambda queried the table and
posted back through `@connections`, and the close proves `DeleteConnection`
works.

**3. A full host join.** Make two keys and the host's room id once:

```bash
node -e '
const { generateKeyPairSync, createHash } = require("crypto");
const pair = () => {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const raw = publicKey.export({ format: "der", type: "spki" }).subarray(12);
  return { pub: raw.toString("base64"), raw, pem: privateKey.export({ format: "pem", type: "pkcs8" }) };
};
const host = pair();
const guest = pair();
console.log(JSON.stringify({
  host: { pub: host.pub, pem: host.pem },
  guest: { pub: guest.pub, pem: guest.pem },
  room: createHash("sha256").update(host.raw).digest().subarray(0, 16).toString("hex"),
}));
' > /tmp/zephra-link.json
```

Open a session and send `{"a":"hello"}`:

```bash
wscat -c wss://zephra-link.urandom.io
> {"a":"hello"}
< {"a":"challenge","n":"Yk9s...=="}
```

Build the join frame for that nonce, in a second shell, within 60 seconds. The
host names the guest's key in `allow`:

```bash
NONCE='Yk9s...==' ROLE=host node -e '
const { createPrivateKey, sign } = require("crypto");
const link = require("/tmp/zephra-link.json");
const role = process.env.ROLE;
const who = link[role];
const nonce = Buffer.from(process.env.NONCE, "base64");
const signed = Buffer.concat([nonce, Buffer.from(link.room, "utf8"), Buffer.from(role, "utf8")]);
const frame = {
  a: "join", room: link.room, role, pub: who.pub,
  sig: sign(null, signed, createPrivateKey(who.pem)).toString("base64"),
};
if (role === "host") frame.allow = [link.guest.pub];
console.log(JSON.stringify(frame));
'
```

Paste that line into the open `wscat` session. Expect:

```
< {"a":"joined","role":"host"}
```

**4. The forward.** Repeat step 3 for a second `wscat` session with `ROLE=guest`.
The host session should show `{"a":"peer","event":"joined"}`. Sending
`{"a":"send","d":"aGk="}` from the guest should arrive verbatim at the host, and
closing the guest should push `{"a":"peer","event":"left"}`.

**5. The refusals.** With the host still up, a third session joining as a guest
with a key the host never named should get
`{"a":"error","reason":"not allowed"}` and be closed; joining a second guest
while the first is up should get `{"a":"error","reason":"room busy"}`.

## Tests

`make relay-test`, which is `node --test Relay/link/test`. Seconds, no network,
no AWS account, no `npm install`.

`test/relay.test.mjs` drives `index.mjs` the way API Gateway drives it, one
`handler` call per frame, against fakes for the two AWS clients it imports:
`test/fake-aws/client-dynamodb.mjs` is the membership table in a `Map`, with the
conditional writes the guest slot is claimed by, and
`test/fake-aws/client-apigatewaymanagementapi.mjs` records what was posted to
each connection, can declare one `Gone` and can make one fail for a reason that
is not a dead peer (`broken`), which is what the `forward failed` answer is
pinned by. The suite also stubs `console.log` and asserts over the lines
themselves — the shape of a forwarded frame, a gone peer and a host with no
guest, and that no line has ever carried a payload or a signature.
`test/fake-aws/hooks.mjs` is a
resolve hook that puts the fakes where the bare `@aws-sdk/...` specifiers point,
so the file under test is the file that is deployed, with no seam cut into it.

## Deploying

`make relay-deploy` from the repository root: it zips `index.mjs`, sends it with
`aws lambda update-function-code`, waits for the function to settle, and then
opens a real socket to `wss://zephra-link.urandom.io` and checks that a `hello`
comes back a `challenge`. CI runs the same target over the OIDC role; a person
runs it over the `dev.urandom.io` profile. `RELAY_FUNCTION` names the function
(`zephra-link`) and `RELAY_WSS` the endpoint the smoke test uses.

## Logs

**Every frame writes one line, and every line is one JSON object.** A drop that
writes nothing is a drop nobody can explain: a live run lost one small `send`
between two counters and CloudWatch held only the failures that threw, which is
what this shape exists for.

```json
{"at":"send","from":"<connectionId>","role":"host","room":"<32 hex>","bytes":312,
 "m":"0123456789abcdef","i":1,"n":3,"to":["<connectionId>"],"result":"forwarded"}
```

- `at` — the action the line is about: `send`, `join`, `joined`, `hello`,
  `allow`, `peer`, `$connect`, `$disconnect`, `malformed`, or the `a` of a frame
  that got no further.
- `from` — the connection the frame came from. `to` — the connections it was
  posted to, `[]` when it reached nobody.
- `role`, `room` — the sender's, from its membership row; on a `join` they are
  what the client claimed, bounded, before anything checked them.
- `bytes` — the length of `d` as base64. **Never `d` itself, and never `sig`:
  the relay logs the shape of a frame and never what is in it.**
- `m`, `i`, `n` — the fragment fields off a `send`, `null` on a frame that is
  not a slice.
- `result` — how it ended, below. `error` — the reason, where there is one.

What a `result` means, by `at`:

| `at` | `result` | |
| --- | --- | --- |
| `send` | `forwarded` | posted to the peer |
| `send` | `gone` | the peer was 410; its row is swept, a host's slot freed, the sender told `peer left` |
| `send` | `no-peer` | a host with no guest in the room; dropped, as the contract says |
| `send` | `no-host` | a guest whose row points at no host; the sender is told |
| `send` | `error` | the forward threw; the sender is told `forward failed` |
| `send` | `bad-payload` | `d` was not a string |
| any action | `not-joined` | no membership row, and the connection never joined |
| any action | `index-lag` | its own pending row says it joined and the index still had nothing after the 150 ms retry |
| any action | `unknown-action` | a joined connection sent an `a` the relay has no branch for |
| `join` | `refused` \| `already-joined` \| — | `error` names the refusal |
| `joined` | `joined` | the membership row is written |
| `hello` | `challenged` \| `already-joined` \| `too-many` | |
| `allow` | `allowed` \| `not-host` \| `bad-allow` \| `bad-open` | `count` and `open` say what the policy became |
| `peer` | `forwarded` \| `gone` | a `peer` notice pushed; `event` is `joined` or `left` |
| `$disconnect` | `left` \| `gone` \| `no-peer` \| `unknown` | whether the other side was told; `unknown` is a connection with no row. `code` and `reason` are the close as API Gateway saw it: `1001` with a reason is an end that closed on purpose, `1006` one that crashed, slept or lost the network |

**Reading them.** A line is not pure JSON on the way out: the Node runtime
prefixes everything `console.log` writes with
`<timestamp>\t<requestId>\tINFO\t`, and the JSON object is what follows the last
tab. **So a JSON filter pattern — `{ $.at = "send" }` — matches nothing**, here
or as a metric filter, however well formed the object is. Filter on the text
instead: a quoted pattern is a substring match, and the fields have no spaces
around them, so `"result":"no-peer"` is exactly what is in the line.

Every frame that did not make it across is several such patterns rather than one
`!=`, so ask for the ones that matter. Dropped for want of a peer, over the last
hour:

```bash
aws logs filter-log-events --log-group-name /aws/lambda/zephra-link \
  --filter-pattern '"result":"no-peer"' \
  --start-time $(( ($(date +%s) - 3600) * 1000 )) \
  --profile dev.urandom.io --region us-west-2 --no-cli-pager \
  --query 'events[].message' --output text
```

Other useful ones, the same way: `'"room":"<32 hex>"'` for one room's whole
traffic, `'"from":"<connectionId>"'` for one peer's, `'"result":"index-lag"'`
for the eventually consistent index actually costing a frame, and
`'"m":"<message id>"'` for every slice of one fragmented message. Two substrings
in one pattern are an AND — `'"at":"send" "result":"gone"'`. To watch one room
as it runs, `aws logs tail` takes the same patterns:

```bash
aws logs tail /aws/lambda/zephra-link --since 5m --follow \
  --filter-pattern '"room":"<32 hex>"' \
  --profile dev.urandom.io --region us-west-2
```

CloudWatch Logs Insights is the other way and does not care about the prefix:
`parse @message '*\t{*' as _, body | filter body like '"result":"no-peer"'`.

A counter missing on the phone or the Mac (`docs/companion.md`) is one end of
this: the log line says whether the relay ever saw that frame, and if it did,
what it did with it.

## Operations

- Logs: `/aws/lambda/zephra-link`, 14-day retention, one JSON line per frame as
  above.
- Rows: `aws dynamodb scan --table-name zephra-link-rooms --profile dev.urandom.io --region us-west-2`
  shows live membership and unspent challenges. Rows should disappear on
  disconnect; any that linger are swept by the TTL.
- The stage throttles at 500 requests per second with a burst of 1000, which is
  the whole relay, not per room. One session in a run streams roughly 30
  messages a second before fragmenting, so the earlier 50 rps ceiling dropped
  frames.
- The deployment package is this directory's `index.mjs` alone, zipped by
  `make relay-deploy`. The AWS SDK v3 comes from the Lambda runtime, so there is
  no build step, no `node_modules` and no dependency to declare in
  `THIRD_PARTY_NOTICES.md`.
