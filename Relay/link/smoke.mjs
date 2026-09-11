// Is the deployed relay answering?
//
//   node Relay/link/smoke.mjs wss://zephra-link.urandom.io
//
// One socket, one `hello`, one `challenge` back. That is deliberately the whole
// of it: `hello` is the only message a client may send before it has a room and
// a key, so this proves the socket, the route, the Lambda and its table without
// holding an identity or leaving a row behind. Anything further is the wire
// contract, which `make relay-test` already covers in milliseconds.
//
// No dependencies: Node's own WebSocket, so this runs on a CI runner with
// nothing installed. Exits non-zero with a sentence on any failure, which is
// what makes it usable as the last step of `make relay-deploy`.
const endpoint = process.argv[2] ?? "wss://zephra-link.urandom.io";
const timeoutMs = Number(process.env.RELAY_SMOKE_TIMEOUT_MS ?? 20000);

function fail(reason) {
  console.error(`relay-smoke: ${reason}`);
  process.exit(1);
}

if (typeof WebSocket !== "function") {
  fail(`this Node (${process.version}) has no WebSocket; Node 22 or newer is needed`);
}

const socket = new WebSocket(endpoint);
const deadline = setTimeout(() => fail(`no challenge from ${endpoint} within ${timeoutMs} ms`), timeoutMs);

socket.addEventListener("open", () => {
  socket.send(JSON.stringify({ a: "hello" }));
});

socket.addEventListener("error", () => fail(`could not reach ${endpoint}`));

socket.addEventListener("close", (event) => {
  clearTimeout(deadline);
  if (event.code !== 1000) fail(`${endpoint} closed the socket (code ${event.code})`);
});

socket.addEventListener("message", (event) => {
  let message;
  try {
    message = JSON.parse(String(event.data));
  } catch {
    clearTimeout(deadline);
    fail(`${endpoint} answered with something that is not JSON`);
    return;
  }
  clearTimeout(deadline);
  // The nonce is 32 random bytes, so a challenge that is not 44 base64
  // characters is a relay answering with the wrong shape rather than a relay.
  if (message.a !== "challenge" || typeof message.n !== "string" || message.n.length !== 44) {
    fail(`expected a challenge from ${endpoint}, got ${JSON.stringify(message)}`);
    return;
  }
  console.log(`relay-smoke: ${endpoint} answered hello with a challenge`);
  socket.close(1000);
  process.exit(0);
});
