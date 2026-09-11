export const sent = new Map();
export const closed = new Set();
export const gone = new Set();

export function reset() {
  sent.clear();
  closed.clear();
  gone.clear();
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

export class ApiGatewayManagementApiClient {
  async send(cmd) {
    const id = cmd.input.ConnectionId;
    if (gone.has(id)) throw new GoneException();
    if (cmd instanceof PostToConnectionCommand) {
      if (!sent.has(id)) sent.set(id, []);
      sent.get(id).push(cmd.input.Data);
      return {};
    }
    closed.add(id);
    return {};
  }
}
