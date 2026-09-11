export const sent = new Map();
export const closed = new Set();
export const gone = new Set();
// A connection the management API fails on for a reason that is not a dead
// peer: a throttle, a timeout, a permission. `gone` is answered 410 and swept;
// this one is what the relay must tell the sender about rather than swallow.
export const broken = new Set();

export function reset() {
  sent.clear();
  closed.clear();
  gone.clear();
  broken.clear();
}

export function frames(id) {
  return (sent.get(id) ?? []).map((s) => JSON.parse(s));
}

class Cmd {
  constructor(input) {
    this.input = input;
  }
}
export class PostToConnectionCommand extends Cmd {}
export class DeleteConnectionCommand extends Cmd {}

class GoneException extends Error {
  constructor() {
    super("gone");
    this.name = "GoneException";
  }
}

class ThrottledException extends Error {
  constructor() {
    super("too many requests");
    this.name = "LimitExceededException";
  }
}

export class ApiGatewayManagementApiClient {
  async send(cmd) {
    const id = cmd.input.ConnectionId;
    if (gone.has(id)) throw new GoneException();
    if (broken.has(id)) throw new ThrottledException();
    if (cmd instanceof PostToConnectionCommand) {
      if (!sent.has(id)) sent.set(id, []);
      sent.get(id).push(cmd.input.Data);
      return {};
    }
    closed.add(id);
    return {};
  }
}
