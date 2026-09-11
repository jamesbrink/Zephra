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
}

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

// 4. A second guest is refused while one is joined.
{
  fresh();
  const host = key();
  const a = key();
  const b = key();
  await joinAs("H", host, host.room, "host", { allow: [a.pub, b.pub] });
  await joinAs("A", a, host.room, "guest");
  const r = await joinAs("B", b, host.room, "guest");
  check("second guest gets room busy", r.a === "error" && r.reason === "room busy", r);
  check("second guest is closed", gw.closed.has("B"));

  // The first guest leaving frees the slot.
  await bye("A");
  check("host told the peer left", last("H").a === "peer" && last("H").event === "left");
  const again = await joinAs("B2", b, host.room, "guest");
  check("slot freed for the next guest", again.a === "joined", again);
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
  check("it is still one at a time", (await joinAs("Q", later, host.room, "guest")).reason === "room busy");

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
    "the fragment fields survive untouched",
    JSON.stringify(got) === JSON.stringify(slices),
    got,
  );

  // The text itself, not just an equal object: the relay forwards the original.
  const rawSent = (gw.sent.get("H") ?? []).filter((t) => t.includes('"send"'));
  check(
    "the original text is what arrives",
    rawSent[0] === JSON.stringify(slices[0]),
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

  // A 24,000-byte slice is still one frame the relay forwards whole.
  const big = "A".repeat(24000);
  await msg("G", { a: "send", d: big, m: "fedcba9876543210", i: 0, n: 1 });
  const last = gw.frames("H").filter((f) => f.a === "send").pop();
  check("a 24,000-byte slice arrives whole", last.d.length === 24000 && last.n === 1);
}
