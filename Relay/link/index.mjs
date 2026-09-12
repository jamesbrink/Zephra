// Zephra link relay.
//
// A WebSocket bridge between one host (a Mac running Zephra) and one guest (an
// iPhone companion) in a room. The relay never sees plaintext: `d` is an opaque
// base64 payload the peers encrypt for each other.
//
// A host names the keys it will accept (`allow`), so holding a room id is not
// enough to join it, and a room carries at most one guest at a time. A host
// pairing for the first time has no key to name yet, so it may open the room
// (`open`) for as long as that takes.
//
// Dependencies: none beyond the AWS SDK v3 that the Lambda runtime already
// provides, so the deployment package is this file alone. The runtime is
// nodejs20.x only because the pinned AWS provider predates nodejs22.x; nothing
// here needs a Node 22 feature.

import {
  createHash,
  createPublicKey,
  randomBytes,
  verify as verifySignature,
} from "node:crypto";
import {
  DynamoDBClient,
  DeleteItemCommand,
  GetItemCommand,
  PutItemCommand,
  QueryCommand,
  UpdateItemCommand,
} from "@aws-sdk/client-dynamodb";
import {
  ApiGatewayManagementApiClient,
  DeleteConnectionCommand,
  PostToConnectionCommand,
} from "@aws-sdk/client-apigatewaymanagementapi";

const TABLE_NAME = process.env.TABLE_NAME;
const MANAGEMENT_ENDPOINT = process.env.MANAGEMENT_ENDPOINT;

// A membership row outlives the two-hour API Gateway connection cap, so the TTL
// only ever sweeps rows whose $disconnect never ran.
const ROW_TTL_SECONDS = 3 * 60 * 60;

// A challenge is short-lived on purpose: it is one round trip from being used.
const CHALLENGE_TTL_SECONDS = 60;

// A connection gets three challenges and no more. Each one is a write, so an
// unauthenticated socket that only ever says hello costs a bounded amount.
const MAX_HELLOS = 3;

// The byConnection index is eventually consistent. One short wait covers the
// replication gap, and only for a connection whose own row says it has joined.
const INDEX_RETRY_MS = 150;

// A bound on the host's allow list, which is one DynamoDB attribute.
const MAX_ALLOWED_KEYS = 16;

// A pending row hides in the same table under a synthetic room name. The key is
// derivable from the connection id alone, so the challenge is read back with a
// strongly consistent GetItem rather than through the eventually consistent
// index. After a join the same row stays behind as the marker that says this
// connection is entitled to the index retry, its nonce overwritten and spent.
const PENDING_PREFIX = "pending#";

// SubjectPublicKeyInfo DER prefix for an Ed25519 key: the whole header is fixed,
// so a raw 32-byte key becomes a KeyObject by concatenation.
const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");

const ROOM_PATTERN = /^[0-9a-f]{32}$/;

const dynamo = new DynamoDBClient({});
const gateway = new ApiGatewayManagementApiClient({ endpoint: MANAGEMENT_ENDPOINT });

export const handler = async (event) => {
  const routeKey = event.requestContext?.routeKey;
  const connectionId = event.requestContext?.connectionId;

  try {
    if (routeKey === "$connect") {
      // Nothing is authenticated yet. The connection proves itself over the
      // next two frames, hello then join.
      logLine({ at: "$connect", from: connectionId, result: "open" });
      return { statusCode: 200 };
    }
    if (routeKey === "$disconnect") {
      await onDisconnect(connectionId, closing(event.requestContext));
      return { statusCode: 200 };
    }
    await onMessage(connectionId, event.body);
    return { statusCode: 200 };
  } catch (error) {
    console.error("relay failure", routeKey, connectionId, error);
    // The backstop line: whatever threw, the frame that died leaves one JSON
    // line behind like every other, so a filter over `result` sees it too.
    logLine({
      at: short(routeKey, 32) ?? "unknown",
      from: connectionId,
      result: "error",
      error: describe(error),
    });
    // Returning 200 keeps API Gateway from retrying a frame we cannot handle.
    return { statusCode: 200 };
  }
};

async function onMessage(connectionId, body) {
  // One lookup answers both questions every branch below asks: is this
  // connection joined, and has it ever completed a join.
  const state = await connectionState(connectionId);
  const message = parseMessage(body);

  if (!message) {
    logLine({
      at: "malformed",
      from: connectionId,
      result: state.member ? "errored" : "closed",
    });
    await fail(state, connectionId, "malformed");
    return;
  }

  if (message.a === "hello") {
    await onHello(connectionId, state);
    return;
  }
  if (message.a === "join") {
    await onJoin(connectionId, message, state);
    return;
  }

  // Every other action needs a joined connection. An unauthenticated connection
  // that speaks anything but hello or join is closed on the spot.
  if (!state.member) {
    // Two holes, and the log tells them apart: a connection that never joined,
    // or one whose own pending row says it did and whose index entry was still
    // not there after the retry.
    logLine({
      at: short(message.a, 32) ?? "unknown",
      from: connectionId,
      result: state.retried ? "index-lag" : "not-joined",
      error: "not joined",
    });
    await reject(connectionId, "not joined");
    return;
  }

  switch (message.a) {
    case "send":
      await onSend(state.member, message, body);
      return;
    case "allow":
      await onAllow(state.member, message);
      return;
    case "ping":
      await touch(state.member);
      await post(connectionId, { a: "pong" });
      return;
    default:
      // A joined connection keeps its socket: the client is authenticated and a
      // stray frame is a bug to report, not grounds to tear the session down.
      logLine({
        at: short(message.a, 32) ?? "unknown",
        from: connectionId,
        role: state.member.role,
        room: state.member.room,
        result: "unknown-action",
      });
      await post(connectionId, { a: "error", reason: "unknown action" });
  }
}

// The client cannot know its own API Gateway connection id, so the relay issues
// the challenge instead: 32 random bytes the client signs to prove it holds the
// key it is about to claim.
async function onHello(connectionId, state) {
  if (state.member || state.pending?.joined) {
    logLine({ at: "hello", from: connectionId, result: "already-joined" });
    await post(connectionId, { a: "error", reason: "already joined" });
    return;
  }

  const hellos = (state.pending?.hellos ?? 0) + 1;
  if (hellos > MAX_HELLOS) {
    logLine({ at: "hello", from: connectionId, result: "too-many" });
    await reject(connectionId, "too many hellos");
    return;
  }

  const nonce = randomBytes(32).toString("base64");

  // Same key as any earlier pending row, so a second hello replaces the first
  // and only the newest challenge is live.
  await dynamo.send(
    new PutItemCommand({
      TableName: TABLE_NAME,
      Item: {
        room: { S: pendingRoom(connectionId) },
        connectionId: { S: connectionId },
        nonce: { S: nonce },
        hellos: { N: String(hellos) },
        expiresAt: { N: String(expiry(CHALLENGE_TTL_SECONDS)) },
      },
    }),
  );

  await post(connectionId, { a: "challenge", n: nonce });
  logLine({ at: "hello", from: connectionId, result: "challenged" });
}

async function onJoin(connectionId, message, state) {
  // What every line about this join says, whatever it ends as. Both fields are
  // the client's own words until they are checked, so both are logged bounded.
  const line = {
    at: "join",
    from: connectionId,
    role: short(message.role, 16),
    room: short(message.room, 64),
  };

  if (state.member || state.pending?.joined) {
    logLine({ ...line, result: "already-joined" });
    await post(connectionId, { a: "error", reason: "already joined" });
    return;
  }

  const room = message.room;
  const role = message.role;

  if (!ROOM_PATTERN.test(room ?? "")) {
    await refuseJoin(connectionId, line, "bad room");
    return;
  }
  if (role !== "host" && role !== "guest") {
    await refuseJoin(connectionId, line, "bad role");
    return;
  }

  const pub = decodeBase64(message.pub, 32);
  const sig = decodeBase64(message.sig, 64);
  if (!pub || !sig) {
    await refuseJoin(connectionId, line, "bad key");
    return;
  }

  // A guest is compared against the host's list byte for byte, so both sides are
  // stored re-encoded rather than as the client spelled them.
  const publicKey = pub.toString("base64");

  const allow = role === "host" ? parseAllowList(message.allow) : [];
  if (!allow) {
    await refuseJoin(connectionId, line, "bad allow");
    return;
  }

  const open = role === "host" ? parseOpen(message.open) : false;
  if (open === null) {
    await refuseJoin(connectionId, line, "bad open");
    return;
  }

  const pending = state.pending;
  if (!pending?.nonce) {
    await refuseJoin(connectionId, line, "no challenge");
    return;
  }
  if (pending.expiresAt <= now()) {
    // DynamoDB's TTL sweep runs on its own schedule, so an expired challenge is
    // still readable. Refuse it here rather than trust the sweep.
    await dropPending(connectionId);
    await refuseJoin(connectionId, line, "challenge expired");
    return;
  }

  const nonce = decodeBase64(pending.nonce, 32);
  if (!nonce) {
    await dropPending(connectionId);
    await refuseJoin(connectionId, line, "challenge expired");
    return;
  }

  // The signed bytes are the raw nonce followed by the room and the role as
  // UTF-8, concatenated with no separator and no length prefix.
  //
  // Domain separation rests on both variable parts being fixed width: a 32-byte
  // nonce and a 32-character room id. The concatenation therefore parses exactly
  // one way, the trailing role is what the signature is bound to, and a host's
  // signature cannot be replayed as a guest's in the same room. The nonce binds
  // it to this connection, and the room binds it to this room.
  const signed = Buffer.concat([nonce, Buffer.from(room, "utf8"), Buffer.from(role, "utf8")]);
  if (!verifyEd25519(signed, pub, sig)) {
    await refuseJoin(connectionId, line, "bad signature");
    return;
  }

  // A host owns the room name: it is the fingerprint of its own public key, so
  // nobody else can claim to host it. Same domain separation as the signature —
  // the fingerprint covers the raw key and nothing else, so a key that hashes to
  // another room cannot host this one.
  if (role === "host") {
    const fingerprint = createHash("sha256").update(pub).digest().subarray(0, 16).toString("hex");
    if (fingerprint !== room) {
      await refuseJoin(connectionId, line, "room does not match key");
      return;
    }
  }

  let hostConnectionId = null;
  if (role === "guest") {
    const claim = await claimGuestSlot(connectionId, room, publicKey);
    if (claim.refusal) {
      await refuseJoin(connectionId, line, claim.refusal);
      return;
    }
    hostConnectionId = claim.host;
  }

  // The nonce is single use: spending it is what makes a captured join frame
  // worthless on a later connection. The row stays as the joined marker.
  await markJoined(connectionId);

  const item = {
    room: { S: room },
    connectionId: { S: connectionId },
    role: { S: role },
    pub: { S: publicKey },
    expiresAt: { N: String(expiry(ROW_TTL_SECONDS)) },
  };
  if (role === "host" && allow.length > 0) {
    item.allow = { SS: allow };
  }
  if (open) {
    item.open = { BOOL: true };
  }
  if (hostConnectionId) {
    item.host = { S: hostConnectionId };
  }

  await dynamo.send(new PutItemCommand({ TableName: TABLE_NAME, Item: item }));

  await post(connectionId, { a: "joined", role });
  logLine({ ...line, at: "joined", result: "joined" });

  if (hostConnectionId) {
    const told = await post(hostConnectionId, { a: "peer", event: "joined" }, {
      room,
      connectionId: hostConnectionId,
    });
    logLine({
      at: "peer",
      event: "joined",
      from: connectionId,
      role,
      room,
      to: [hostConnectionId],
      result: told ? "forwarded" : "gone",
    });
  }
}

// A join that goes no further: one line saying why, then the error frame and
// the close the contract promises.
async function refuseJoin(connectionId, line, reason) {
  logLine({ ...line, result: "refused", error: reason });
  await reject(connectionId, reason);
}

// `{ host }` with the host's connection id, or `{ refusal }` with the reason
// this guest cannot have the room. The caller answers and logs, so every refusal
// leaves the same line behind. The slot is taken on the host's own row, so two
// guests racing for the same room cannot both win: DynamoDB decides it, not a
// read followed by a write.
async function claimGuestSlot(connectionId, room, publicKey) {
  const rows = await roomRows(room);
  const host = rows.find((peer) => peer.role === "host");
  if (!host) {
    return { refusal: "no host" };
  }
  // An open room admits any key; a closed one only the keys the host named.
  if (!host.open && !host.allow.includes(publicKey)) {
    return { refusal: "not allowed" };
  }
  if (rows.some((peer) => peer.role === "guest")) {
    return { refusal: "room busy" };
  }

  // A slot naming a guest whose row is gone is stale — the row was swept by the
  // TTL or dropped on a failed forward — so it may be taken over.
  const stale = host.guest ?? null;

  try {
    await dynamo.send(
      new UpdateItemCommand({
        TableName: TABLE_NAME,
        Key: { room: { S: room }, connectionId: { S: host.connectionId } },
        UpdateExpression: "SET #guest = :c",
        ConditionExpression: stale
          ? "attribute_exists(connectionId) AND #guest = :stale"
          : "attribute_exists(connectionId) AND attribute_not_exists(#guest)",
        ExpressionAttributeNames: { "#guest": "guest" },
        ExpressionAttributeValues: stale
          ? { ":c": { S: connectionId }, ":stale": { S: stale } }
          : { ":c": { S: connectionId } },
      }),
    );
  } catch (error) {
    if (error.name === "ConditionalCheckFailedException") {
      // Either another guest won the race or the host left mid-join.
      return { refusal: "room busy" };
    }
    throw error;
  }

  return { host: host.connectionId };
}

// The host's admission policy, replaced wholesale: the frame says what the room
// admits from now on, so an omitted `open` closes it. It governs who may join
// next; a guest already in the room is not evicted by it.
async function onAllow(member, message) {
  const line = {
    at: "allow",
    from: member.connectionId,
    role: member.role,
    room: member.room,
  };

  if (member.role !== "host") {
    logLine({ ...line, result: "not-host" });
    await post(member.connectionId, { a: "error", reason: "not host" });
    return;
  }

  const allow = parseAllowList(message.pubs);
  if (!allow) {
    logLine({ ...line, result: "bad-allow" });
    await post(member.connectionId, { a: "error", reason: "bad allow" });
    return;
  }

  const open = parseOpen(message.open);
  if (open === null) {
    logLine({ ...line, result: "bad-open" });
    await post(member.connectionId, { a: "error", reason: "bad open" });
    return;
  }

  // Each of the two attributes is either set or removed, so both names are
  // always used and neither value is left dangling. REMOVE is only spelled when
  // something is being removed: an empty clause is a syntax error.
  const sets = ["expiresAt = :e"];
  const removes = [];
  const values = { ":e": { N: String(expiry(ROW_TTL_SECONDS)) } };

  if (allow.length > 0) {
    sets.push("#allow = :a");
    values[":a"] = { SS: allow };
  } else {
    removes.push("#allow");
  }
  if (open) {
    sets.push("#open = :o");
    values[":o"] = { BOOL: true };
  } else {
    removes.push("#open");
  }

  await dynamo.send(
    new UpdateItemCommand({
      TableName: TABLE_NAME,
      Key: { room: { S: member.room }, connectionId: { S: member.connectionId } },
      UpdateExpression:
        `SET ${sets.join(", ")}` + (removes.length > 0 ? ` REMOVE ${removes.join(", ")}` : ""),
      ConditionExpression: "attribute_exists(connectionId)",
      ExpressionAttributeNames: { "#allow": "allow", "#open": "open" },
      ExpressionAttributeValues: values,
    }),
  );

  await post(member.connectionId, { a: "allowed", count: allow.length });
  // The keys themselves are not logged: how many, and whether the room is open.
  logLine({ ...line, result: "allowed", count: allow.length, open });
}

// Every way out of this function writes one line. A frame that vanishes with
// nothing written is the bug this logging exists for: a live run lost one small
// `send` between two counters and CloudWatch held nothing at all.
async function onSend(member, message, body) {
  const line = {
    at: "send",
    from: member.connectionId,
    role: member.role,
    room: member.room,
    bytes: typeof message.d === "string" ? message.d.length : 0,
    // The fragment fields are the client's, so they are logged only in a shape
    // a filter can rely on. `d` itself never is.
    m: short(message.m),
    i: counter(message.i),
    n: counter(message.n),
    to: [],
  };

  if (typeof message.d !== "string") {
    await post(member.connectionId, { a: "error", reason: "bad payload" });
    logLine({ ...line, result: "bad-payload" });
    return;
  }

  // One peer each way: a host talks to its one guest, a guest to its host.
  const target = member.role === "host" ? await resolveGuest(member) : member.host;
  if (!target) {
    if (member.role === "host") {
      // The documented silent drop: a host may write before its guest has
      // arrived, and an error frame for each of those would tell it nothing it
      // does not already know. The line is the record that it happened.
      logLine({ ...line, result: "no-peer" });
      return;
    }
    // A guest whose row points at no host has nothing to wait for: rejoining is
    // the only way back, so it is told rather than left writing into nothing.
    await post(member.connectionId, { a: "error", reason: "no host" });
    await post(member.connectionId, { a: "peer", event: "left" });
    logLine({ ...line, result: "no-host" });
    return;
  }

  line.to = [target];

  let delivered;
  try {
    // Forwarded verbatim: the relay does not read or rewrite `d`.
    delivered = await post(target, body, { room: member.room, connectionId: target });
  } catch (error) {
    // Anything that is not a dead peer: a throttle, a timeout, a permission.
    // Swallowing it is what made the last drop invisible, so the sender is told
    // and keeps its socket.
    await post(member.connectionId, { a: "error", reason: "forward failed" });
    logLine({ ...line, result: "error", error: describe(error) });
    return;
  }

  if (delivered) {
    logLine({ ...line, result: "forwarded" });
    return;
  }

  // The peer is gone and `post` took its row with it. A host frees the room's
  // slot too, or the room stays busy against a connection that no longer
  // exists, and either sender is told its peer left rather than left to guess.
  if (member.role === "host") {
    await releaseGuestSlot(member.room, member.connectionId, target);
  }
  await post(member.connectionId, { a: "peer", event: "left" });
  logLine({ ...line, result: "gone" });
}

async function onDisconnect(connectionId, close = {}) {
  const member = await findMember(connectionId);

  // A connection that never got past the challenge leaves a pending row behind,
  // and a joined one leaves its marker.
  await dropPending(connectionId);

  if (!member) {
    logLine({ at: "$disconnect", from: connectionId, ...close, to: [], result: "unknown" });
    return;
  }

  await drop(member);

  const line = {
    at: "$disconnect",
    from: connectionId,
    role: member.role,
    room: member.room,
    ...close,
  };

  // The host leaving ends the session for the guest; a guest leaving is news the
  // host needs to drop its own peer state, and frees the room's one slot.
  if (member.role === "host") {
    const guest = await resolveGuest(member);
    if (!guest) {
      logLine({ ...line, to: [], result: "no-peer" });
      return;
    }
    const told = await post(guest, { a: "peer", event: "left" }, {
      room: member.room,
      connectionId: guest,
    });
    logLine({ ...line, to: [guest], result: told ? "left" : "gone" });
    return;
  }

  if (!member.host) {
    logLine({ ...line, to: [], result: "no-peer" });
    return;
  }

  await releaseGuestSlot(member.room, member.host, connectionId);
  const told = await post(member.host, { a: "peer", event: "left" }, {
    room: member.room,
    connectionId: member.host,
  });
  logLine({ ...line, to: [member.host], result: told ? "left" : "gone" });
}

// A guest's connection id reaches the host's row by a later UpdateItem, so the
// eventually consistent index can hand back a host row that predates its guest.
// Falling back to a strongly consistent read of the room costs a query only
// while the host believes it has no guest.
async function resolveGuest(member) {
  if (member.guest) {
    return member.guest;
  }
  const guest = (await roomRows(member.room)).find((peer) => peer.role === "guest");
  return guest?.connectionId ?? null;
}

async function releaseGuestSlot(room, hostConnectionId, guestConnectionId) {
  try {
    await dynamo.send(
      new UpdateItemCommand({
        TableName: TABLE_NAME,
        Key: { room: { S: room }, connectionId: { S: hostConnectionId } },
        UpdateExpression: "REMOVE #guest",
        ConditionExpression: "#guest = :c",
        ExpressionAttributeNames: { "#guest": "guest" },
        ExpressionAttributeValues: { ":c": { S: guestConnectionId } },
      }),
    );
  } catch (error) {
    // The host is gone, or a newer guest already holds the slot. Either way
    // there is nothing of this guest's left to clear.
    if (error.name !== "ConditionalCheckFailedException") {
      throw error;
    }
  }
}

function parseMessage(body) {
  if (typeof body !== "string") {
    return null;
  }
  try {
    const parsed = JSON.parse(body);
    return parsed && typeof parsed === "object" && typeof parsed.a === "string" ? parsed : null;
  } catch {
    return null;
  }
}

// null for a list that is not one, too long, or holds anything but a base64 raw
// Ed25519 public key. An absent list is an empty one: a host that names nobody
// admits nobody.
function parseAllowList(value) {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value) || value.length > MAX_ALLOWED_KEYS) {
    return null;
  }
  const keys = [];
  for (const entry of value) {
    const raw = decodeBase64(entry, 32);
    if (!raw) {
      return null;
    }
    keys.push(raw.toString("base64"));
  }
  return [...new Set(keys)];
}

// null for anything that is not a boolean. Absent is false: a frame that does
// not ask for an open room does not get one.
function parseOpen(value) {
  if (value === undefined || value === null) {
    return false;
  }
  return typeof value === "boolean" ? value : null;
}

function decodeBase64(value, length) {
  if (typeof value !== "string") {
    return null;
  }
  const bytes = Buffer.from(value, "base64");
  return bytes.length === length ? bytes : null;
}

function verifyEd25519(data, rawPublicKey, signature) {
  try {
    const key = createPublicKey({
      key: Buffer.concat([ED25519_SPKI_PREFIX, rawPublicKey]),
      format: "der",
      type: "spki",
    });
    return verifySignature(null, data, key, signature);
  } catch (error) {
    console.warn("key rejected", error.message);
    return false;
  }
}

// One JSON object per line, so a field can be read out of it. The Node runtime
// prefixes the line with `<timestamp>\t<requestId>\tINFO\t`, so a JSON filter
// pattern (`{ $.at = "send" }`) matches nothing and a substring one is what
// works: `"result":"no-peer"`, and see "Logs" in the README. The contents of `d`
// and `sig` are never in a line -- the relay logs the shape of a frame, never
// what is in it.
function logLine(fields) {
  console.log(JSON.stringify(fields));
}

// A string a client chose, bounded, or null. Nothing unbounded reaches the log,
// so a peer cannot write a megabyte of its own into it.
// How the socket closed, as API Gateway reports it on `$disconnect`: the close
// code and the reason the closing side gave, or what the gateway saw when the
// connection simply went. A `1001` with a client reason is an end that closed on
// purpose; a `1006` is a phone that crashed, slept or lost the network. Without
// these, a session that ends the moment it joins reads the same as one that
// was torn down cleanly, and only the client's own log could tell them apart.
function closing(context) {
  const code = Number(context?.disconnectStatusCode);
  return {
    code: Number.isInteger(code) ? code : null,
    reason: short(context?.disconnectReason, 64),
  };
}

function short(value, limit = 64) {
  return typeof value === "string" && value.length <= limit ? value : null;
}

// A number a client chose, or null: a fragment index is a number or it is not
// one, and a filter should never have to tell `"0"` from `0`.
function counter(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

// What an error says in a line: its message, bounded, never the object.
function describe(error) {
  const text = error?.message ?? String(error);
  return text.length > 200 ? `${text.slice(0, 200)}...` : text;
}

function now() {
  return Math.floor(Date.now() / 1000);
}

function expiry(seconds) {
  return now() + seconds;
}

function pendingRoom(connectionId) {
  return `${PENDING_PREFIX}${connectionId}`;
}

// What this connection is, in one place: its membership row if the index has
// caught up, and the pending row that says whether it ever joined.
async function connectionState(connectionId) {
  const member = await findMember(connectionId);
  if (member) {
    return { member, pending: null, retried: false };
  }

  const pending = await findPending(connectionId);
  if (!pending?.joined) {
    // Nothing here ever joined, so there is nothing for a retry to find. An
    // unauthenticated connection never buys a second query with its frames.
    return { member: null, pending, retried: false };
  }

  // The row says this connection joined, so the index is merely lagging.
  // `retried` is what tells a missing row from a lagging index in the log.
  await new Promise((resolve) => setTimeout(resolve, INDEX_RETRY_MS));
  return { member: await findMember(connectionId), pending, retried: true };
}

async function findPending(connectionId) {
  const result = await dynamo.send(
    new GetItemCommand({
      TableName: TABLE_NAME,
      Key: { room: { S: pendingRoom(connectionId) }, connectionId: { S: connectionId } },
      ConsistentRead: true,
    }),
  );

  const item = result.Item;
  if (!item) {
    return null;
  }
  return {
    nonce: item.nonce?.S ?? null,
    hellos: Number(item.hellos?.N ?? "0"),
    joined: item.joined?.BOOL === true,
    expiresAt: Number(item.expiresAt.N),
  };
}

// Overwrites the challenge, which is what spends the nonce, and leaves the row
// as the marker connectionState reads.
async function markJoined(connectionId) {
  await dynamo.send(
    new PutItemCommand({
      TableName: TABLE_NAME,
      Item: {
        room: { S: pendingRoom(connectionId) },
        connectionId: { S: connectionId },
        joined: { BOOL: true },
        expiresAt: { N: String(expiry(ROW_TTL_SECONDS)) },
      },
    }),
  );
}

async function dropPending(connectionId) {
  await dynamo.send(
    new DeleteItemCommand({
      TableName: TABLE_NAME,
      Key: { room: { S: pendingRoom(connectionId) }, connectionId: { S: connectionId } },
    }),
  );
}

async function findMember(connectionId) {
  const result = await dynamo.send(
    new QueryCommand({
      TableName: TABLE_NAME,
      IndexName: "byConnection",
      KeyConditionExpression: "connectionId = :c",
      ExpressionAttributeValues: { ":c": { S: connectionId } },
    }),
  );

  // The index also carries the connection's pending row, which is not a
  // membership.
  const item = (result.Items ?? []).find((row) => !row.room.S.startsWith(PENDING_PREFIX));
  return item ? readRow(item) : null;
}

async function roomRows(room) {
  const result = await dynamo.send(
    new QueryCommand({
      TableName: TABLE_NAME,
      KeyConditionExpression: "#room = :r",
      ExpressionAttributeNames: { "#room": "room" },
      ExpressionAttributeValues: { ":r": { S: room } },
      ConsistentRead: true,
    }),
  );
  return (result.Items ?? []).map(readRow);
}

function readRow(item) {
  return {
    room: item.room.S,
    connectionId: item.connectionId.S,
    role: item.role?.S ?? null,
    allow: item.allow?.SS ?? [],
    open: item.open?.BOOL === true,
    guest: item.guest?.S ?? null,
    host: item.host?.S ?? null,
  };
}

async function touch(member) {
  await dynamo.send(
    new UpdateItemCommand({
      TableName: TABLE_NAME,
      Key: { room: { S: member.room }, connectionId: { S: member.connectionId } },
      UpdateExpression: "SET expiresAt = :e",
      ExpressionAttributeValues: { ":e": { N: String(expiry(ROW_TTL_SECONDS)) } },
    }),
  );
}

async function drop(member) {
  await dynamo.send(
    new DeleteItemCommand({
      TableName: TABLE_NAME,
      Key: { room: { S: member.room }, connectionId: { S: member.connectionId } },
    }),
  );
}

// `row` is the target's own membership row when there is one, so a connection
// that died without a $disconnect is swept out of the table on the next
// forward.
async function post(connectionId, payload, row) {
  const data = typeof payload === "string" ? payload : JSON.stringify(payload);
  try {
    await gateway.send(new PostToConnectionCommand({ ConnectionId: connectionId, Data: data }));
    return true;
  } catch (error) {
    if (error.name === "GoneException" || error.$metadata?.httpStatusCode === 410) {
      if (row) {
        await drop(row);
      }
      return false;
    }
    throw error;
  }
}

// A joined connection keeps its socket through an error; an unauthenticated one
// does not.
async function fail(state, connectionId, reason) {
  if (state.member) {
    await post(connectionId, { a: "error", reason });
    return;
  }
  await reject(connectionId, reason);
}

async function reject(connectionId, reason) {
  await post(connectionId, { a: "error", reason });
  try {
    await gateway.send(new DeleteConnectionCommand({ ConnectionId: connectionId }));
  } catch (error) {
    if (error.name !== "GoneException") {
      throw error;
    }
  }
}
