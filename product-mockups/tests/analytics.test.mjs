import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import assert from "node:assert/strict";
import { test } from "node:test";
const source = readFileSync(
  new URL("../public/analytics.js", import.meta.url),
  "utf8",
);
function page(url) {
  const scripts = [],
    listeners = {};
  class Element {
    constructor(href) {
      this.href = href;
    }
    closest() {
      return this;
    }
  }
  const context = {
    URL,
    Element,
    location: new URL(url),
    window: {},
    document: {
      title: "Zephra",
      referrer: "https://example.com/private?email=secret#token",
      createElement: () => ({}),
      head: { appendChild: (s) => scripts.push(s) },
      addEventListener: (name, listener) => {
        listeners[name] = listener;
      },
    },
  };
  const run = () => runInNewContext(source, context);
  run();
  return {
    context,
    scripts,
    run,
    click: (href) => listeners.click({ target: new Element(href) }),
    events: () =>
      (context.window.dataLayer || []).map((args) => Array.from(args)),
  };
}
test("production initializes once and strips private URL context", () => {
  const p = page("https://zephra.urandom.io/?email=secret#token");
  p.run();
  assert.equal(p.scripts.length, 1);
  assert.equal(p.events().filter((e) => e[1] === "page_view").length, 1);
  const settings = p.events().find((e) => e[0] === "set")[1];
  assert.equal(settings.page_location, "https://zephra.urandom.io/");
  assert.equal(settings.page_referrer, "https://example.com");
  assert.equal(
    p.events().find((e) => e[0] === "config")[2].send_page_view,
    false,
  );
  assert.equal(p.events()[0][2].ad_storage, "denied");
});
test("previews, sibling sites and non-page paths do not initialize", () => {
  for (const url of [
    "http://localhost:3000/",
    "https://zephra-product-concepts.jamesbrink.chatgpt.site/",
    "https://urandom.io/",
    "https://zephra.urandom.io/404.html",
  ]) {
    const p = page(url);
    assert.equal(p.scripts.length, 0);
    assert.equal(p.events().length, 0);
    assert.equal(p.context.window.zephraAnalytics, undefined);
  }
});
test("only release links emit sanitized download clicks", () => {
  const p = page("https://zephra.urandom.io/");
  p.click(
    "https://zephra-assets.urandom.io/releases/Zephra-0.1.0-20260906.dmg?private=yes#token",
  );
  p.click("https://example.com/private.dmg");
  p.click("https://zephra-assets.urandom.io/private.dmg");
  const events = p.events().filter((e) => e[1] === "file_download");
  assert.equal(events.length, 1);
  assert.equal(
    events[0][2].link_url,
    "https://zephra-assets.urandom.io/releases/Zephra-0.1.0-20260906.dmg",
  );
});
