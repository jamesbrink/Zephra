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

// One term of a condition: the three shapes the relay writes, plus `size(path)`
// against a number, which is what the guest cap is checked with.
function checkTerm(part, item, names, values) {
  let m = /^attribute_exists\((.+)\)$/.exec(part);
  if (m) return Boolean(item) && item[resolveName(m[1], names)] !== undefined;
  m = /^attribute_not_exists\((.+)\)$/.exec(part);
  if (m) return !item || item[resolveName(m[1], names)] === undefined;
  m = /^size\((#?\w+)\) < (:\w+)$/.exec(part);
  if (m) {
    const a = item && item[resolveName(m[1], names)];
    return (a?.SS?.length ?? 0) < Number(values[m[2]].N);
  }
  m = /^(#?\w+) = (:\w+)$/.exec(part);
  if (m) {
    const a = item && item[resolveName(m[1], names)];
    return a !== undefined && a !== null && a.S === values[m[2]].S;
  }
  throw new Error("unhandled condition: " + part);
}

// Splits on a keyword outside any brackets, so `attribute_exists(x)` stays whole
// and a parenthesised group is one part.
function splitOutsideBrackets(expr, keyword) {
  const parts = [];
  let depth = 0;
  let start = 0;
  for (let at = 0; at < expr.length; at += 1) {
    if (expr[at] === "(") depth += 1;
    else if (expr[at] === ")") depth -= 1;
    else if (depth === 0 && expr.startsWith(keyword, at)) {
      parts.push(expr.slice(start, at));
      at += keyword.length - 1;
      start = at + 1;
    }
  }
  parts.push(expr.slice(start));
  return parts.map((part) => part.trim()).filter((part) => part.length > 0);
}

// A group's own brackets, off: `(A OR B)` is the one shape the relay writes.
function unwrap(part) {
  return part.startsWith("(") && part.endsWith(")") ? part.slice(1, -1).trim() : part;
}

// `A AND B` and `A AND (B OR C)`, which is as far as the relay's conditions go.
function checkCondition(expr, item, names, values) {
  if (!expr) return true;
  return splitOutsideBrackets(expr, " AND ").every((part) =>
    splitOutsideBrackets(unwrap(part), " OR ").some((term) =>
      checkTerm(term, item, names, values),
    ),
  );
}

// An update expression as its clauses: `[["SET", "a = :b"], ["REMOVE", "#c"]]`.
function clauses(expr) {
  const found = [];
  const pattern = /\b(SET|REMOVE|ADD|DELETE)\b/g;
  const starts = [...expr.matchAll(pattern)];
  starts.forEach((match, at) => {
    const from = match.index + match[0].length;
    const to = at + 1 < starts.length ? starts[at + 1].index : expr.length;
    found.push([match[0], expr.slice(from, to).trim()]);
  });
  return found;
}

// One clause against the item, as DynamoDB applies it. `ADD` and `DELETE` are
// the string-set pair the guest slots are held by; a set emptied by a `DELETE`
// takes its attribute with it, which is what `attribute_not_exists` then reads.
function apply(keyword, clause, item, names, values) {
  if (keyword === "SET") {
    const [lhs, rhs] = clause.split(" = ").map((s) => s.trim());
    item[resolveName(lhs, names)] = structuredClone(values[rhs]);
    return;
  }
  if (keyword === "REMOVE") {
    delete item[resolveName(clause, names)];
    return;
  }
  const [path, token] = clause.split(" ").map((s) => s.trim());
  const name = resolveName(path, names);
  const held = new Set(item[name]?.SS ?? []);
  for (const member of values[token].SS ?? []) {
    if (keyword === "ADD") held.add(member);
    else held.delete(member);
  }
  if (held.size === 0) delete item[name];
  else item[name] = { SS: [...held] };
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
      for (const [keyword, clause] of clauses(i.UpdateExpression)) {
        for (const one of clause.split(", ").map((s) => s.trim())) {
          apply(keyword, one, next, names, values);
        }
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
