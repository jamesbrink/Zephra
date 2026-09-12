// Zephra link relay.
//
// A WebSocket bridge between one host (a Mac running Zephra) and the iPhone
// companions in its room. The relay never sees plaintext: `d` is an opaque
// base64 payload the peers encrypt for each other.
//
// A host names the keys it will accept (`allow`), so holding a room id is not
// enough to join it, and a room carries at most `MAX_GUESTS` of them at a time.
// A host pairing for the first time has no key to name yet, so it may open the
// room (`open`) for as long as that takes.
//
// A room with several guests in it is why a frame to a host carries `from`, the
// guest's connection id, and why a host's frame carries `to`: the host has one
// socket, so the guest a frame belongs to has to be written on it.
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

// How many guests one room holds at once. The slots are a string set on the
// host's own row, claimed by a conditional update, so guests racing for the last
// one cannot both win. Eight is a household's phones and a bound on the fan-out
// a host leaving has to write.
const MAX_GUESTS = 8;

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
  if (role === "host") {
    await supersedeHosts(connectionId, room, line);
  }
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
    // `from` is what tells the host which of its guests arrived, since one socket
    // carries them all.
    const told = await post(hostConnectionId, { a: "peer", event: "joined", from: connectionId }, {
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

// A host that joins again takes the room from whatever the last one left behind.
//
// A Mac that goes without a `$disconnect` -- a kill -9, a crash, a battery --
// leaves its host row and the guest bound to it in the table for the three-hour
// TTL. It comes back on a new connection, and the room it rejoins still holds a
// host row naming a socket nobody is reading and a guest row holding the room's
// one slot: the phone is answered `room busy`, or it binds to the dead connection
// and waits for a Mac that cannot hear it. The newest host is the real one, so the
// rows behind it go: any other host row is deleted and its socket closed, and any
// guest is told its peer left and cleared, since the connection it was talking to
// is not this one and cannot become it.
async function supersedeHosts(connectionId, room, line) {
  const stale = (await roomRows(room)).filter((peer) => peer.connectionId !== connectionId);
  const hosts = stale.filter((peer) => peer.role === "host");
  const guests = stale.filter((peer) => peer.role === "guest");
  if (hosts.length === 0 && guests.length === 0) {
    return;
  }

  for (const host of hosts) {
    await drop(host);
    await closeSocket(host.connectionId);
  }
  for (const guest of guests) {
    await post(guest.connectionId, { a: "peer", event: "left" });
    await drop(guest);
  }

  logLine({
    ...line,
    result: "superseded",
    to: [...hosts, ...guests].map((peer) => peer.connectionId),
  });
}

// `{ host }` with the host's connection id, or `{ refusal }` with the reason
// this guest cannot have the room. The caller answers and logs, so every refusal
// leaves the same line behind. The slot is taken on the host's own row, so
// guests racing for the last one cannot both win: DynamoDB decides it, not a
// read followed by a write.
async function claimGuestSlot(connectionId, room, publicKey) {
  const rows = await roomRows(room);
  // The newest host row, by the expiry a join and every `touch` since have moved
  // forward. A host join supersedes the rows before it, so there is normally one;
  // where a delete did not land, the room is the newest host's and not a row that
  // outlived the Mac that wrote it.
  const host = rows
    .filter((peer) => peer.role === "host")
    .sort((a, b) => b.expiresAt - a.expiresAt)[0];
  if (!host) {
    return { refusal: "no host" };
  }
  // An open room admits any key; a closed one only the keys the host named.
  if (!host.open && !host.allow.includes(publicKey)) {
    return { refusal: "not allowed" };
  }

  await adoptLegacySlot(room, host);

  if (await addGuestSlot(room, host.connectionId, connectionId)) {
    return { host: host.connectionId };
  }
  // The cap refused. A slot may be a phantom: a guest whose `$disconnect` never
  // ran (API Gateway does not promise it) and that nothing has addressed since,
  // so nothing has met the 410 that would have freed it. Reconcile the set against
  // the guest rows that actually exist and try once more; a room that is full of
  // live phones is refused the same way after the check.
  const live = new Set(rows.filter((peer) => peer.role === "guest").map((peer) => peer.connectionId));
  const phantoms = guestSlots(host).filter((slot) => !live.has(slot));
  for (const phantom of phantoms) {
    await releaseGuestSlot(room, host.connectionId, phantom);
  }
  if (phantoms.length > 0 && (await addGuestSlot(room, host.connectionId, connectionId))) {
    return { host: host.connectionId };
  }
  return { refusal: "room full" };
}

// Puts one guest on the host's row under the cap, answering whether it went in.
async function addGuestSlot(room, hostConnectionId, connectionId) {
  try {
    await dynamo.send(
      new UpdateItemCommand({
        TableName: TABLE_NAME,
        Key: { room: { S: room }, connectionId: { S: hostConnectionId } },
        UpdateExpression: "ADD #guests :c",
        // The cap is checked where the write happens, so the last slot goes to one
        // guest and not to two. An absent set is a room with nobody in it.
        ConditionExpression:
          "attribute_exists(connectionId) AND "
          + "(attribute_not_exists(#guests) OR size(#guests) < :cap)",
        ExpressionAttributeNames: { "#guests": "guests" },
        ExpressionAttributeValues: {
          ":c": { SS: [connectionId] },
          ":cap": { N: String(MAX_GUESTS) },
        },
      }),
    );
    return true;
  } catch (error) {
    if (error.name === "ConditionalCheckFailedException") {
      // Either the room is full or the host left mid-join.
      return false;
    }
    throw error;
  }
}

// The slot a host row written by the build before this one holds: one `guest`
// attribute rather than the `guests` set. It is read as a one-element set
// everywhere, and moved into the set here the first time a guest joins that room,
// so the cap counts it and a `$disconnect` clears it like any other. Rows like
// this exist only until the three-hour TTL sweeps the last of them.
async function adoptLegacySlot(room, host) {
  if (!host.guest || host.guests.length > 0) {
    return;
  }
  try {
    await dynamo.send(
      new UpdateItemCommand({
        TableName: TABLE_NAME,
        Key: { room: { S: room }, connectionId: { S: host.connectionId } },
        UpdateExpression: "SET #guests = :s REMOVE #guest",
        ConditionExpression: "#guest = :legacy AND attribute_not_exists(#guests)",
        ExpressionAttributeNames: { "#guest": "guest", "#guests": "guests" },
        ExpressionAttributeValues: {
          ":s": { SS: [host.guest] },
          ":legacy": { S: host.guest },
        },
      }),
    );
  } catch (error) {
    // Another guest's join moved it first, which is the whole of what this does.
    if (error.name !== "ConditionalCheckFailedException") {
      throw error;
    }
  }
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

  if (member.role === "guest") {
    await sendToHost(member, message, line);
    return;
  }
  await sendToGuest(member, message, body, line);
}

// A guest's frame goes to the one host it is bound to, stamped with the guest it
// came from: the host has one socket for every phone in the room, so the id is
// the only thing that says which session the frame belongs to. It is written by
// the relay over whatever the sender put there, and the rest of the frame --
// `d`, `m`, `i`, `n` and any field the two peers invented -- is carried across
// as it arrived.
async function sendToHost(member, message, line) {
  if (!member.host) {
    // A guest whose row points at no host has nothing to wait for: rejoining is
    // the only way back, so it is told rather than left writing into nothing.
    await post(member.connectionId, { a: "error", reason: "no host" });
    await post(member.connectionId, { a: "peer", event: "left" });
    logLine({ ...line, result: "no-host" });
    return;
  }

  line.to = [member.host];
  // `to` is the host's field and means nothing here, so it is dropped rather than
  // carried; `undefined` is what JSON.stringify leaves out.
  const stamped = JSON.stringify({ ...message, to: undefined, from: member.connectionId });

  let delivered;
  try {
    delivered = await post(member.host, stamped, {
      room: member.room,
      connectionId: member.host,
    });
  } catch (error) {
    await forwardFailed(member, line, error);
    return;
  }

  if (delivered) {
    logLine({ ...line, result: "forwarded" });
    return;
  }
  // The host is gone and `post` took its row with it.
  await post(member.connectionId, { a: "peer", event: "left" });
  logLine({ ...line, result: "gone" });
}

// A host's frame goes to the guest it names in `to`, or to its one guest where it
// names none. Several guests and no `to` is the one thing the relay cannot guess:
// a sealed frame delivered to the wrong phone is a channel that closes rather
// than a frame that is merely late, so it is refused instead.
async function sendToGuest(member, message, body, line) {
  const asked = typeof message.to === "string" ? message.to : null;
  const known = guestSlots(member);

  if (asked) {
    // The host's own row reaches this frame through an eventually consistent
    // index, so a guest it does not list yet is looked up in the room itself
    // before it is called gone.
    const present = known.includes(asked) || (await roomGuests(member.room)).includes(asked);
    if (!present) {
      // The host is talking to a phone that has left. Nothing is forwarded, and
      // the host is told which session to drop.
      await post(member.connectionId, { a: "peer", event: "left", from: asked });
      logLine({ ...line, result: "unknown-peer" });
      return;
    }
  }

  const guests = asked ? [asked] : known.length > 0 ? known : await roomGuests(member.room);

  if (guests.length === 0) {
    // The documented silent drop: a host may write before its guest has
    // arrived, and an error frame for each of those would tell it nothing it
    // does not already know. The line is the record that it happened.
    logLine({ ...line, result: "no-peer" });
    return;
  }
  if (guests.length > 1) {
    await post(member.connectionId, { a: "error", reason: "ambiguous" });
    logLine({ ...line, result: "ambiguous", to: guests });
    return;
  }

  const target = guests[0];
  line.to = [target];

  let delivered;
  try {
    // Forwarded verbatim: the relay does not read or rewrite `d`.
    delivered = await post(target, body, { room: member.room, connectionId: target });
  } catch (error) {
    await forwardFailed(member, line, error);
    return;
  }

  if (delivered) {
    logLine({ ...line, result: "forwarded" });
    return;
  }

  // The guest is gone and `post` took its row with it. The host's slot goes too,
  // or the room stays full against connections that no longer exist, and the host
  // is told which session left rather than left to guess.
  await releaseGuestSlot(member.room, member.connectionId, target);
  await post(member.connectionId, { a: "peer", event: "left", from: target });
  logLine({ ...line, result: "gone" });
}

// Anything that is not a dead peer: a throttle, a timeout, a permission.
// Swallowing it is what made the last drop invisible, so the sender is told and
// keeps its socket.
async function forwardFailed(member, line, error) {
  await post(member.connectionId, { a: "error", reason: "forward failed" });
  logLine({ ...line, result: "error", error: describe(error) });
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

  // The host leaving ends the session for every guest; a guest leaving is news
  // the host needs to drop that one session, and frees the slot it held.
  if (member.role === "host") {
    const guests = await resolveGuests(member);
    if (guests.length === 0) {
      logLine({ ...line, to: [], result: "no-peer" });
      return;
    }
    let told = false;
    for (const guest of guests) {
      const reached = await post(guest, { a: "peer", event: "left" }, {
        room: member.room,
        connectionId: guest,
      });
      told = told || reached;
    }
    logLine({ ...line, to: guests, result: told ? "left" : "gone" });
    return;
  }

  if (!member.host) {
    logLine({ ...line, to: [], result: "no-peer" });
    return;
  }

  await releaseGuestSlot(member.room, member.host, connectionId);
  const told = await post(member.host, { a: "peer", event: "left", from: connectionId }, {
    room: member.room,
    connectionId: member.host,
  });
  logLine({ ...line, to: [member.host], result: told ? "left" : "gone" });
}

// The guests a host row names, the legacy single slot read as one of them.
function guestSlots(member) {
  const slots = member.guests ?? [];
  return member.guest && !slots.includes(member.guest) ? [...slots, member.guest] : slots;
}

// A guest's connection id reaches the host's row by a later UpdateItem, so the
// eventually consistent index can hand back a host row that predates its guests.
// Falling back to a strongly consistent read of the room costs a query only
// while the host believes it has none.
async function resolveGuests(member) {
  const slots = guestSlots(member);
  return slots.length > 0 ? slots : await roomGuests(member.room);
}

// Every guest actually in the room, read strongly consistently.
async function roomGuests(room) {
  return (await roomRows(room))
    .filter((peer) => peer.role === "guest")
    .map((peer) => peer.connectionId);
}

// The slot one guest held, given back. Two writes because a host row written by
// the build before this one holds its guest in `guest` rather than in the set,
// and a row that has both would keep the stale one otherwise.
async function releaseGuestSlot(room, hostConnectionId, guestConnectionId) {
  await forgiving(
    new UpdateItemCommand({
      TableName: TABLE_NAME,
      Key: { room: { S: room }, connectionId: { S: hostConnectionId } },
      UpdateExpression: "DELETE #guests :c",
      ConditionExpression: "attribute_exists(connectionId)",
      ExpressionAttributeNames: { "#guests": "guests" },
      ExpressionAttributeValues: { ":c": { SS: [guestConnectionId] } },
    }),
  );
  await forgiving(
    new UpdateItemCommand({
      TableName: TABLE_NAME,
      Key: { room: { S: room }, connectionId: { S: hostConnectionId } },
      UpdateExpression: "REMOVE #guest",
      ConditionExpression: "#guest = :c",
      ExpressionAttributeNames: { "#guest": "guest" },
      ExpressionAttributeValues: { ":c": { S: guestConnectionId } },
    }),
  );
}

// A write whose condition failing is an answer rather than a fault: the host is
// gone, or the slot it named is not this guest's any more. Either way there is
// nothing of this guest's left to clear.
async function forgiving(command) {
  try {
    await dynamo.send(command);
  } catch (error) {
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
    // The set of guests in the room, and the single slot a row written by the
    // build before this one holds instead, read as one of them.
    guests: item.guests?.SS ?? [],
    guest: item.guest?.S ?? null,
    host: item.host?.S ?? null,
    // Written at the join and moved forward by every `touch`, so of two host rows
    // it is the later one that belongs to the Mac that is still here.
    expiresAt: Number(item.expiresAt?.N ?? "0"),
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
  await closeSocket(connectionId);
}

// Closes a socket. A connection that is already gone is the thing being asked
// for, not a failure.
async function closeSocket(connectionId) {
  try {
    await gateway.send(new DeleteConnectionCommand({ ConnectionId: connectionId }));
  } catch (error) {
    if (error.name !== "GoneException" && error.$metadata?.httpStatusCode !== 410) {
      throw error;
    }
  }
}
