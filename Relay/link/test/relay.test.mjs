// The relay, against a DynamoDB table and an API Gateway management API that are
// both in this process: `node --test Relay/link/test`, or `make relay-test`.
//
// Nothing here reaches AWS. `fake-aws/hooks.mjs` resolves the two SDK packages
// the relay imports to the fakes beside it, so the relay file under test is the
// file that is deployed, byte for byte, with no seam cut into it for testing.
//
// Every case is driven the way API Gateway drives it: one `handler` call per
// frame, with the route key and the connection id the socket would carry.
import { register } from "node:module";
import { test } from "node:test";
import assert from "node:assert/strict";

register("./fake-aws/hooks.mjs", import.meta.url);

process.env.TABLE_NAME = "t";
process.env.MANAGEMENT_ENDPOINT = "http://local";

// Every line the relay writes, parsed. `console.log` is the relay's only way
// out to CloudWatch, so the test reads exactly what a person reading the log
// would: one JSON object per line and nothing else. The stub stays up for the
// whole file -- the scenarios run as this module is evaluated, and `check`
// reports their answers afterwards without printing anything itself.
const logged = [];
const realLog = console.log;
console.log = (...args) => {
  const text = args.join(" ");
  try {
    logged.push(JSON.parse(text));
  } catch {
    logged.push({ unparsed: text });
  }
};
process.on("exit", () => {
  console.log = realLog;
});

// The raw text of what was logged, for asserting what is *not* in a line.
const loggedText = [];
const noteText = (line) => JSON.stringify(line);

const { generateKeyPairSync, createHash, sign } = await import("node:crypto");
const db = await import("@aws-sdk/client-dynamodb");
const gw = await import("@aws-sdk/client-apigatewaymanagementapi");
const { handler } = await import("../index.mjs");

// Each check is registered as a `node:test` case. The answer is worked out here,
// as the scenario runs, and the case only reports it: the scenarios share one
// fake table and must stay in the order they are written in.
function check(name, ok, extra) {
  test(name, () => {
    assert.ok(ok, extra === undefined ? name : `${name} -> ${JSON.stringify(extra)}`);
  });
}

function key() {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  const raw = publicKey.export({ format: "der", type: "spki" }).subarray(12);
  return {
    raw,
    pub: raw.toString("base64"),
    room: createHash("sha256").update(raw).digest().subarray(0, 16).toString("hex"),
    priv: privateKey,
  };
}

const msg = (id, body) =>
  handler({ requestContext: { routeKey: "$default", connectionId: id }, body: JSON.stringify(body) });
const raw = (id, body) =>
  handler({ requestContext: { routeKey: "$default", connectionId: id }, body });
const bye = (id) => handler({ requestContext: { routeKey: "$disconnect", connectionId: id } });

function last(id) {
  const f = gw.frames(id);
  return f[f.length - 1];
}

async function joinAs(id, k, room, role, extra = {}) {
  await msg(id, { a: "hello" });
  const challenge = last(id);
  const nonce = Buffer.from(challenge.n, "base64");
  const signed = Buffer.concat([nonce, Buffer.from(room, "utf8"), Buffer.from(role, "utf8")]);
  await msg(id, {
    a: "join",
    room,
    role,
    pub: k.pub,
    sig: sign(null, signed, k.priv).toString("base64"),
    ...extra,
  });
  return last(id);
}

function fresh() {
  db.reset();
  gw.reset();
  logged.length = 0;
  loggedText.length = 0;
}

// The lines written since the last `sinceLogs()`, which is how a scenario reads
// only its own.
function sinceLogs() {
  const lines = logged.splice(0, logged.length);
  loggedText.push(...lines.map(noteText));
  return lines;
}

const lineFor = (lines, at, result) =>
  lines.find((line) => line.at === at && (result === undefined || line.result === result));

// 1. A host joins, names one guest key, and that guest joins.
{
  fresh();
  const host = key();
  const guest = key();
  check("host joins", (await joinAs("H", host, host.room, "host", { allow: [guest.pub] })).a === "joined");
  const r = await joinAs("G", guest, host.room, "guest");
  check("allowed guest joins", r.a === "joined" && r.role === "guest", r);
  check("host told a peer joined", gw.frames("H").some((f) => f.a === "peer" && f.event === "joined"));

  await msg("G", { a: "send", d: "aGk=" });
  check("guest frame reaches the host", last("H").a === "send" && last("H").d === "aGk=");
  await msg("H", { a: "send", d: "eW8=" });
  check("host frame reaches the guest", last("G").a === "send" && last("G").d === "eW8=");
}

// 2. A key the host did not name is refused and closed.
{
  fresh();
  const host = key();
  const guest = key();
  const stranger = key();
  await joinAs("H", host, host.room, "host", { allow: [guest.pub] });
  const r = await joinAs("X", stranger, host.room, "guest");
  check("stranger gets not allowed", r.a === "error" && r.reason === "not allowed", r);
  check("stranger is closed", gw.closed.has("X"));
  check("host heard nothing of it", !gw.frames("H").some((f) => f.a === "peer"));
}

// 3. No host row yet.
{
  fresh();
  const host = key();
  const guest = key();
  const r = await joinAs("G", guest, host.room, "guest");
  check("guest with no host gets no host", r.a === "error" && r.reason === "no host", r);
}

// 4. A second guest joins beside the first, and every notice says which one.
{
  fresh();
  const host = key();
  const a = key();
  const b = key();
  await joinAs("H", host, host.room, "host", { allow: [a.pub, b.pub] });
  await joinAs("A", a, host.room, "guest");
  const r = await joinAs("B", b, host.room, "guest");
  check("a second guest joins beside the first", r.a === "joined", r);
  check(
    "and the host is told which one arrived",
    last("H").a === "peer" && last("H").event === "joined" && last("H").from === "B",
    last("H"),
  );

  await bye("A");
  check(
    "host told which peer left",
    last("H").a === "peer" && last("H").event === "left" && last("H").from === "A",
    last("H"),
  );
  const again = await joinAs("A2", a, host.room, "guest");
  check("the phone that left comes back on a new connection", again.a === "joined", again);
}

// 5. The allow action replaces the set, and only a host may send it.
{
  fresh();
  const host = key();
  const a = key();
  const b = key();
  await joinAs("H", host, host.room, "host", { allow: [a.pub] });
  await msg("H", { a: "allow", pubs: [b.pub] });
  check("host allow is acknowledged", last("H").a === "allowed" && last("H").count === 1, last("H"));

  const refused = await joinAs("A", a, host.room, "guest");
  check("the replaced key no longer joins", refused.reason === "not allowed", refused);
  const accepted = await joinAs("B", b, host.room, "guest");
  check("the new key joins", accepted.a === "joined", accepted);

  await msg("B", { a: "allow", pubs: [a.pub] });
  check("a guest allow is refused", last("B").a === "error" && last("B").reason === "not host", last("B"));
  check("a guest allow does not close", !gw.closed.has("B"));

  await msg("H", { a: "allow", pubs: ["nope"] });
  check("a bad allow list is refused", last("H").reason === "bad allow", last("H"));
  check("a bad allow does not close the host", !gw.closed.has("H"));
}

// 6. A host with no allow list admits nobody.
{
  fresh();
  const host = key();
  const guest = key();
  await joinAs("H", host, host.room, "host");
  const r = await joinAs("G", guest, host.room, "guest");
  check("an empty allow list admits nobody", r.reason === "not allowed", r);
}

// 7. Signature and room binding.
{
  fresh();
  const host = key();
  const other = key();
  const r = await joinAs("H", host, other.room, "host");
  check("a host cannot claim another room", r.reason === "room does not match key", r);

  // A signature made for the guest role must not pass as a host join.
  fresh();
  const h = key();
  await msg("H", { a: "hello" });
  const nonce = Buffer.from(last("H").n, "base64");
  const guestSigned = Buffer.concat([nonce, Buffer.from(h.room, "utf8"), Buffer.from("guest", "utf8")]);
  await msg("H", {
    a: "join",
    room: h.room,
    role: "host",
    pub: h.pub,
    sig: sign(null, guestSigned, h.priv).toString("base64"),
  });
  check("a guest signature is not a host join", last("H").reason === "bad signature", last("H"));
}

// 8. Cost: hello is capped and an unjoined connection never waits.
{
  fresh();
  await msg("C", { a: "hello" });
  await msg("C", { a: "hello" });
  await msg("C", { a: "hello" });
  check("three hellos are challenges", gw.frames("C").filter((f) => f.a === "challenge").length === 3);
  await msg("C", { a: "hello" });
  check("the fourth hello is refused", last("C").reason === "too many hellos", last("C"));
  check("the fourth hello closes", gw.closed.has("C"));

  fresh();
  const started = Date.now();
  await msg("D", { a: "ping" });
  const elapsed = Date.now() - started;
  check("an unjoined ping answers not joined", last("D").reason === "not joined", last("D"));
  check("and does not wait 150 ms", elapsed < 100, elapsed);
  check("and closes", gw.closed.has("D"));
}

// 9. A joined connection survives a malformed or unknown frame.
{
  fresh();
  const host = key();
  await joinAs("H", host, host.room, "host", { allow: [] });
  await raw("H", "{not json");
  check("malformed from a joined connection errors", last("H").reason === "malformed", last("H"));
  check("malformed does not close it", !gw.closed.has("H"));
  await msg("H", { a: "nonsense" });
  check("unknown action errors", last("H").reason === "unknown action", last("H"));
  check("unknown action does not close it", !gw.closed.has("H"));
  await msg("H", { a: "send", d: 7 });
  check("bad payload errors", last("H").reason === "bad payload", last("H"));
  check("bad payload does not close it", !gw.closed.has("H"));
  await msg("H", { a: "ping" });
  check("ping still works", last("H").a === "pong");

  // Pre-join, a malformed frame still closes.
  await raw("Z", "{not json");
  check("malformed before join closes", gw.closed.has("Z") && last("Z").reason === "malformed");
}

// 10. The nonce is single use and a second join is refused without closing.
{
  fresh();
  const host = key();
  await msg("H", { a: "hello" });
  const nonce = Buffer.from(last("H").n, "base64");
  const signed = Buffer.concat([nonce, Buffer.from(host.room, "utf8"), Buffer.from("host", "utf8")]);
  const frame = {
    a: "join",
    room: host.room,
    role: "host",
    pub: host.pub,
    sig: sign(null, signed, host.priv).toString("base64"),
  };
  await msg("H", frame);
  check("the first join succeeds", last("H").a === "joined");
  await msg("H", frame);
  check("a replayed join is already joined", last("H").reason === "already joined", last("H"));
  check("and does not close", !gw.closed.has("H"));
  await msg("H", { a: "hello" });
  check("hello after joining is already joined", last("H").reason === "already joined");
}

// 11. A dead guest frees the room on the next forward.
{
  fresh();
  const host = key();
  const a = key();
  const b = key();
  await joinAs("H", host, host.room, "host", { allow: [a.pub, b.pub] });
  await joinAs("A", a, host.room, "guest");
  gw.gone.add("A");
  await msg("H", { a: "send", d: "aGk=" });
  const r = await joinAs("B", b, host.room, "guest");
  check("a dead guest does not wedge the room", r.a === "joined", r);
}

// 12. The host leaving tells the guest.
{
  fresh();
  const host = key();
  const guest = key();
  await joinAs("H", host, host.room, "host", { allow: [guest.pub] });
  await joinAs("G", guest, host.room, "guest");
  await bye("H");
  check("guest told the host left", last("G").a === "peer" && last("G").event === "left", last("G"));
  check("the table is empty after both leave", (await bye("G"), db.store.size === 0), [...db.store.keys()]);
}

// 13. An open room admits a key it never named, and closing it refuses the next.
{
  fresh();
  const host = key();
  const phone = key();
  const later = key();
  check(
    "host opens the room",
    (await joinAs("H", host, host.room, "host", { open: true })).a === "joined",
  );
  const paired = await joinAs("P", phone, host.room, "guest");
  check("an open room admits an unlisted guest", paired.a === "joined", paired);
  check("an open room admits a second one too", (await joinAs("Q", later, host.room, "guest")).a === "joined");

  // The host names the phone it just paired and closes the room.
  await msg("H", { a: "allow", pubs: [phone.pub] });
  check("closing acknowledges the list", last("H").a === "allowed" && last("H").count === 1, last("H"));

  await msg("P", { a: "send", d: "aGk=" });
  check("closing does not evict the joined guest", last("H").a === "send" && last("H").d === "aGk=");

  await bye("P");
  const refused = await joinAs("R", later, host.room, "guest");
  check("a closed room refuses the next unlisted guest", refused.reason === "not allowed", refused);
  const back = await joinAs("P2", phone, host.room, "guest");
  check("the named phone still joins", back.a === "joined", back);
}

// 14. Opening again, and what an omitted or bad open means.
{
  fresh();
  const host = key();
  const stranger = key();
  await joinAs("H", host, host.room, "host", { allow: [] });
  check("a closed room starts closed", (await joinAs("S", stranger, host.room, "guest")).reason === "not allowed");

  await msg("H", { a: "allow", pubs: [], open: true });
  check("the host can open it later", (await joinAs("S2", stranger, host.room, "guest")).a === "joined");
  await bye("S2");

  await msg("H", { a: "allow", pubs: [] });
  check("an omitted open closes the room", (await joinAs("S3", stranger, host.room, "guest")).reason === "not allowed");

  await msg("H", { a: "allow", pubs: [], open: "yes" });
  check("a non-boolean open is refused", last("H").reason === "bad open", last("H"));
  check("and does not close the host", !gw.closed.has("H"));

  fresh();
  const h2 = key();
  const r = await joinAs("H2", h2, h2.room, "host", { open: 1 });
  check("a non-boolean open on join is refused", r.reason === "bad open", r);
  check("and closes", gw.closed.has("H2"));
}

// 15. A fragmented send crosses with every extra field intact.
{
  fresh();
  const host = key();
  const guest = key();
  await joinAs("H", host, host.room, "host", { allow: [guest.pub] });
  await joinAs("G", guest, host.room, "guest");

  const slices = [
    { a: "send", d: "c2xpY2Ux", m: "0123456789abcdef", i: 0, n: 3 },
    { a: "send", d: "c2xpY2Uy", m: "0123456789abcdef", i: 1, n: 3 },
    { a: "send", d: "c2xpY2Uz", m: "0123456789abcdef", i: 2, n: 3 },
  ];
  for (const slice of slices) await msg("G", slice);

  const got = gw.frames("H").filter((f) => f.a === "send");
  check("every slice is forwarded", got.length === 3, got.length);
  check(
    "the fragment fields survive untouched, with the guest written on them",
    JSON.stringify(got) === JSON.stringify(slices.map((slice) => ({ ...slice, from: "G" }))),
    got,
  );

  // The text itself, not just an equal object: a frame to a host is the sender's
  // own with `from` added, and nothing else moved.
  const rawSent = (gw.sent.get("H") ?? []).filter((t) => t.includes('"send"'));
  check(
    "the original text is what arrives, plus the guest it came from",
    rawSent[0] === JSON.stringify({ ...slices[0], from: "G" }),
    rawSent[0],
  );

  // A field the relay has never heard of, and one that shadows its own names.
  await msg("G", { a: "send", d: "eA==", room: "nope", role: "host", extra: { deep: [1, 2] } });
  const odd = gw.frames("H").filter((f) => f.a === "send").pop();
  check(
    "unknown and shadowing fields pass through",
    odd.room === "nope" && odd.role === "host" && odd.extra.deep[1] === 2,
    odd,
  );

  // A guest cannot write its own `from`: the relay's is the last word.
  await msg("G", { a: "send", d: "eA==", from: "somebody-else" });
  const forged = gw.frames("H").filter((f) => f.a === "send").pop();
  check("a guest cannot forge the from field", forged.from === "G", forged);

  // A 24,000-byte slice is still one frame the relay forwards whole.
  const big = "A".repeat(24000);
  await msg("G", { a: "send", d: big, m: "fedcba9876543210", i: 0, n: 1 });
  const last = gw.frames("H").filter((f) => f.a === "send").pop();
  check("a 24,000-byte slice arrives whole", last.d.length === 24000 && last.n === 1);
}

// 16. What the log says. A frame that vanishes with nothing written is the bug
// this exists for: a live run lost one small `send` between two counters and
// CloudWatch held only the failures that threw.
{
  fresh();
  const host = key();
  const guest = key();
  await joinAs("H", host, host.room, "host", { allow: [guest.pub] });
  await joinAs("G", guest, host.room, "guest");

  const handshake = sinceLogs();
  check(
    "a join writes its own line",
    lineFor(handshake, "joined", "joined")?.room === host.room,
    handshake.map((l) => `${l.at}:${l.result}`),
  );
  check(
    "a peer notice says who it reached",
    lineFor(handshake, "peer", "forwarded")?.to?.[0] === "H",
    lineFor(handshake, "peer"),
  );

  // A forwarded fragment: the whole shape, and none of the payload.
  await msg("G", { a: "send", d: "c2xpY2Ux", m: "0123456789abcdef", i: 1, n: 3 });
  const [forwarded] = sinceLogs();
  check(
    "a forwarded frame is one send line",
    forwarded?.at === "send" && forwarded.result === "forwarded",
    forwarded,
  );
  check(
    "it says who, which room and how big",
    forwarded.from === "G" &&
      forwarded.role === "guest" &&
      forwarded.room === host.room &&
      forwarded.bytes === 8 &&
      JSON.stringify(forwarded.to) === JSON.stringify(["H"]),
    forwarded,
  );
  check(
    "it carries the fragment's m, i and n",
    forwarded.m === "0123456789abcdef" && forwarded.i === 1 && forwarded.n === 3,
    forwarded,
  );
  check(
    "an unfragmented send logs them as null",
    (await msg("G", { a: "send", d: "aGk=" }), sinceLogs()[0]).m === null,
  );
  check(
    "no line has ever carried a payload or a signature",
    !loggedText.some((text) => text.includes("c2xpY2Ux") || text.includes('"sig"')),
  );

  // A peer that is gone: the slot is freed, the sender is told, and the line
  // says `gone` rather than nothing at all.
  gw.gone.add("H");
  await msg("G", { a: "send", d: "aGk=" });
  const goneLine = sinceLogs()[0];
  check("a gone peer logs result gone", goneLine?.result === "gone", goneLine);
  check(
    "and the sender is told its peer left",
    last("G").a === "peer" && last("G").event === "left",
    last("G"),
  );
}

// 17. A host with no guest, and a forward that fails for another reason.
{
  fresh();
  const host = key();
  const guest = key();
  await joinAs("H", host, host.room, "host", { allow: [guest.pub] });
  sinceLogs();

  await msg("H", { a: "send", d: "aGk=" });
  const lonely = sinceLogs()[0];
  check(
    "a host with no guest logs no-peer",
    lonely?.at === "send" && lonely.result === "no-peer" && lonely.to.length === 0,
    lonely,
  );
  check("and is not sent an error for it", !gw.frames("H").some((f) => f.a === "error"));

  await joinAs("G", guest, host.room, "guest");
  sinceLogs();
  gw.broken.add("G");
  await msg("H", { a: "send", d: "aGk=" });
  const failed = sinceLogs()[0];
  check(
    "a forward that throws logs result error with the reason",
    failed?.result === "error" && failed.error === "too many requests",
    failed,
  );
  check(
    "and the sender is told the forward failed",
    last("H").a === "error" && last("H").reason === "forward failed",
    last("H"),
  );
  check("and keeps its socket", !gw.closed.has("H"));
  gw.broken.delete("G");
}

// 18. The refusals write lines too, and each says why.
{
  fresh();
  const host = key();
  const stranger = key();
  await joinAs("H", host, host.room, "host", { allow: [] });
  sinceLogs();

  await joinAs("S", stranger, host.room, "guest");
  const refused = sinceLogs();
  check(
    "a refused join says which refusal",
    lineFor(refused, "join", "refused")?.error === "not allowed",
    refused.map((l) => `${l.at}:${l.result}`),
  );

  await msg("N", { a: "ping" });
  const notJoined = sinceLogs();
  check(
    "a frame from a connection with no row logs not-joined",
    lineFor(notJoined, "ping", "not-joined")?.error === "not joined",
    notJoined,
  );

  await bye("H");
  const left = sinceLogs();
  check(
    "a disconnect logs what it told and whom",
    lineFor(left, "$disconnect")?.result === "no-peer",
    left,
  );

  await handler({
    requestContext: {
      routeKey: "$disconnect",
      connectionId: "N",
      disconnectStatusCode: 1001,
      disconnectReason: "Going away",
    },
  });
  const closed = sinceLogs();
  const closeLine = lineFor(closed, "$disconnect");
  check(
    "a disconnect logs the close code and reason the gateway saw",
    closeLine?.code === 1001 && closeLine?.reason === "Going away",
    closed,
  );
}

// 19. A Mac that was killed leaves its row behind, and the next host join takes
// the room from it: no `$disconnect` ever ran, so without this the phone meets a
// host row naming a dead socket and a guest row holding the room's one slot.
{
  fresh();
  const host = key();
  const guest = key();
  await joinAs("H", host, host.room, "host", { allow: [guest.pub] });
  await joinAs("G", guest, host.room, "guest");
  await msg("G", { a: "send", d: "aGk=" });
  sinceLogs();

  const again = await joinAs("H2", host, host.room, "host", { allow: [guest.pub] });
  check("a host that joins again is admitted", again.a === "joined", again);

  const lines = sinceLogs();
  const superseded = lineFor(lines, "join", "superseded");
  check(
    "the stale rows are superseded, and the line says so",
    superseded !== undefined,
    lines.map((l) => `${l.at}:${l.result}`),
  );
  check(
    "the line names what it swept",
    JSON.stringify(superseded?.to) === JSON.stringify(["H", "G"]),
    superseded,
  );
  check(
    "and carries nothing but the shape of what happened",
    JSON.stringify(Object.keys(superseded ?? {}).sort()) ===
      JSON.stringify(["at", "from", "result", "role", "room", "to"].sort()),
    superseded,
  );
  check("the old host socket is closed", gw.closed.has("H"));
  check(
    "the old guest is told the peer left",
    last("G").a === "peer" && last("G").event === "left",
    last("G"),
  );

  const back = await joinAs("G2", guest, host.room, "guest");
  check("a stale guest row does not make the room busy", back.a === "joined", back);
  await msg("G2", { a: "send", d: "eW8=" });
  check(
    "and the phone reaches the host that is really there",
    last("H2").a === "send" && last("H2").d === "eW8=",
    last("H2"),
  );
  check(
    "the room holds one host row",
    [...db.store.values()].filter((i) => i.room.S === host.room && i.role?.S === "host").length === 1,
    [...db.store.values()].map((i) => `${i.room.S}:${i.role?.S}`),
  );
}

// 20. Nothing to supersede: the ordinary first join says nothing about it.
{
  fresh();
  const host = key();
  await joinAs("H", host, host.room, "host", { allow: [] });
  const lines = sinceLogs();
  check(
    "a first join supersedes nothing and logs nothing about it",
    lineFor(lines, "join", "superseded") === undefined,
    lines.map((l) => `${l.at}:${l.result}`),
  );
}

// 21. Several phones on one Mac. The host has one socket, so a frame to it says
// which guest it came from and a frame from it says which guest it is for.
{
  fresh();
  const host = key();
  const one = key();
  const two = key();
  await joinAs("H", host, host.room, "host", { allow: [one.pub, two.pub] });
  await joinAs("G1", one, host.room, "guest");
  await joinAs("G2", two, host.room, "guest");

  await msg("G1", { a: "send", d: "b25l" });
  check(
    "a guest frame says which guest it came from",
    last("H").a === "send" && last("H").d === "b25l" && last("H").from === "G1",
    last("H"),
  );
  await msg("G2", { a: "send", d: "dHdv" });
  check(
    "and the other guest is told apart from it",
    last("H").d === "dHdv" && last("H").from === "G2",
    last("H"),
  );

  await msg("H", { a: "send", d: "YWE=", to: "G1" });
  check("the host's frame reaches the guest it named", last("G1").d === "YWE=", last("G1"));
  check(
    "and nobody else",
    !gw.frames("G2").some((f) => f.a === "send" && f.d === "YWE="),
    gw.frames("G2"),
  );

  await msg("H", { a: "send", d: "YmI=" });
  check(
    "a host frame naming nobody is refused as ambiguous",
    last("H").a === "error" && last("H").reason === "ambiguous",
    last("H"),
  );

  await msg("H", { a: "send", d: "Y2M=", to: "gone" });
  check(
    "a host frame to a guest that is not in the room is answered peer left",
    last("H").a === "peer" && last("H").event === "left" && last("H").from === "gone",
    last("H"),
  );

  await bye("G1");
  check(
    "one phone leaving is news about that one",
    last("H").a === "peer" && last("H").event === "left" && last("H").from === "G1",
    last("H"),
  );
  await msg("G2", { a: "send", d: "ZWU=" });
  check(
    "the other phone's session is untouched",
    last("H").a === "send" && last("H").d === "ZWU=" && last("H").from === "G2",
    last("H"),
  );
  await msg("H", { a: "send", d: "ZGQ=" });
  check(
    "and it is the sole guest again, so a frame naming nobody reaches it",
    last("G2").a === "send" && last("G2").d === "ZGQ=",
    last("G2"),
  );
}

// 22. The cap: eight phones, and the ninth is told the room is full.
{
  fresh();
  const host = key();
  const phones = Array.from({ length: 9 }, () => key());
  await joinAs("H", host, host.room, "host", { allow: phones.map((phone) => phone.pub) });

  const admitted = [];
  for (let at = 0; at < 8; at += 1) {
    admitted.push((await joinAs(`P${at}`, phones[at], host.room, "guest")).a === "joined");
  }
  check("eight phones join one room", admitted.every(Boolean), admitted);

  const full = await joinAs("P8", phones[8], host.room, "guest");
  check("the ninth is refused as room full", full.a === "error" && full.reason === "room full", full);
  check("and is closed", gw.closed.has("P8"));

  await bye("P0");
  const back = await joinAs("P9", phones[8], host.room, "guest");
  check("a phone leaving frees a slot for it", back.a === "joined", back);
}

// 22b. A slot whose guest row is gone is a phantom: a phone whose $disconnect never
// ran, which API Gateway does not promise. The cap must not count it forever.
{
  fresh();
  const host = key();
  const phones = Array.from({ length: 9 }, () => key());
  await joinAs("H", host, host.room, "host", { allow: phones.map((phone) => phone.pub) });
  for (let at = 0; at < 8; at += 1) {
    await joinAs(`P${at}`, phones[at], host.room, "guest");
  }
  // P0 vanishes without a $disconnect: its row is swept by the TTL, its slot stays.
  db.store.delete(`${host.room} P0`);
  const before = db.store.get(`${host.room} H`);
  check("the phantom still holds a slot", before.guests.SS.includes("P0"), before.guests);

  const back = await joinAs("P8", phones[8], host.room, "guest");
  check("a phone joining at the cap reclaims the phantom's slot", back.a === "joined", back);
  const after = db.store.get(`${host.room} H`);
  check("the phantom is out of the set", !after.guests.SS.includes("P0"), after.guests);
  check("and the newcomer is in it", after.guests.SS.includes("P8"), after.guests);

  const ninth = key();
  await msg("H", { a: "allow", pubs: [...phones.map((phone) => phone.pub), ninth.pub] });
  const full = await joinAs("P9", ninth, host.room, "guest");
  check("a room full of live phones is still refused", full.a === "error" && full.reason === "room full", full);
}

// 23. A host row written by the build before this one holds its guest in `guest`
// rather than in the set. It is read as one guest until the row is rewritten, and
// the next join moves it into the set.
{
  fresh();
  const host = key();
  const first = key();
  const second = key();
  await joinAs("H", host, host.room, "host", { allow: [first.pub, second.pub] });
  await joinAs("A", first, host.room, "guest");

  const row = db.store.get(`${host.room} H`);
  row.guest = { S: "A" };
  delete row.guests;

  await msg("H", { a: "send", d: "aGk=" });
  check("the legacy slot is read as the room's one guest", last("A").d === "aGk=", last("A"));

  const r = await joinAs("B", second, host.room, "guest");
  check("and a second phone still joins beside it", r.a === "joined", r);
  const after = db.store.get(`${host.room} H`);
  check("the legacy attribute is gone", after.guest === undefined, after);
  check(
    "and both phones are in the set",
    JSON.stringify([...after.guests.SS].sort()) === JSON.stringify(["A", "B"]),
    after.guests,
  );

  await msg("H", { a: "send", d: "eW8=", to: "A" });
  check("the phone the legacy slot named still receives", last("A").d === "eW8=", last("A"));
}
