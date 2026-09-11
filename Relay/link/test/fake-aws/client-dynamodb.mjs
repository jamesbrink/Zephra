export const store = new Map();
export function reset() {
  store.clear();
}

const k = (i) => `${i.room.S} ${i.connectionId.S}`;
const kk = (key) => `${key.room.S} ${key.connectionId.S}`;

class Cmd {
  constructor(input) {
    this.input = input;
  }
}
export class PutItemCommand extends Cmd {}
export class GetItemCommand extends Cmd {}
export class DeleteItemCommand extends Cmd {}
export class UpdateItemCommand extends Cmd {}
export class QueryCommand extends Cmd {}

class ConditionalCheckFailedException extends Error {
  constructor() {
    super("conditional check failed");
    this.name = "ConditionalCheckFailedException";
  }
}

function resolveName(tok, names) {
  return tok.startsWith("#") ? names[tok] : tok;
}

function checkCondition(expr, item, names, values) {
  if (!expr) return true;
  return expr.split(" AND ").every((raw) => {
    const part = raw.trim();
    let m = /^attribute_exists\((.+)\)$/.exec(part);
    if (m) return Boolean(item) && item[resolveName(m[1], names)] !== undefined;
    m = /^attribute_not_exists\((.+)\)$/.exec(part);
    if (m) return !item || item[resolveName(m[1], names)] === undefined;
    m = /^(#?\w+) = (:\w+)$/.exec(part);
    if (m) {
      const a = item && item[resolveName(m[1], names)];
      return a !== undefined && a !== null && a.S === values[m[2]].S;
    }
    throw new Error("unhandled condition: " + part);
  });
}

export class DynamoDBClient {
  async send(cmd) {
    const i = cmd.input;
    const names = i.ExpressionAttributeNames ?? {};
    const values = i.ExpressionAttributeValues ?? {};
    if (cmd instanceof PutItemCommand) {
      store.set(k(i.Item), structuredClone(i.Item));
      return {};
    }
    if (cmd instanceof GetItemCommand) {
      const it = store.get(kk(i.Key));
      return it ? { Item: structuredClone(it) } : {};
    }
    if (cmd instanceof DeleteItemCommand) {
      store.delete(kk(i.Key));
      return {};
    }
    if (cmd instanceof UpdateItemCommand) {
      const key = kk(i.Key);
      const item = store.get(key);
      if (!checkCondition(i.ConditionExpression, item, names, values)) {
        throw new ConditionalCheckFailedException();
      }
      const next = item
        ? structuredClone(item)
        : { room: i.Key.room, connectionId: i.Key.connectionId };
      const expr = i.UpdateExpression;
      const setPart = /SET (.+?)(?: REMOVE |$)/.exec(expr);
      if (setPart) {
        for (const a of setPart[1].split(", ")) {
          const [lhs, rhs] = a.split(" = ").map((s) => s.trim());
          next[resolveName(lhs, names)] = structuredClone(values[rhs]);
        }
      }
      const remPart = /REMOVE (.+)$/.exec(expr);
      if (remPart) {
        for (const a of remPart[1].split(", ")) delete next[resolveName(a.trim(), names)];
      }
      store.set(key, next);
      return {};
    }
    if (cmd instanceof QueryCommand) {
      const all = [...store.values()];
      if (i.IndexName === "byConnection") {
        const c = values[":c"].S;
        return { Items: all.filter((it) => it.connectionId.S === c).map((it) => structuredClone(it)) };
      }
      const r = values[":r"].S;
      return { Items: all.filter((it) => it.room.S === r).map((it) => structuredClone(it)) };
    }
    throw new Error("unknown command");
  }
}
