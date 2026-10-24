// test_progress_page.py から node で呼ぶ。index.html の <script> を最小限の DOM の stub の上で動かし、結果を JSON で返す。
// 入力（stdin の JSON）: {script, payloads: {"<closed 0|1>|<label>|<q>": 応答の body}, buttons: [[段, 文言]]}
"use strict";
const vm = require("vm");

class El {
  constructor(tag, attrs = {}) {
    Object.assign(this, { tagName: tag.toUpperCase(), children: [], _text: "", dataset: {}, listeners: {},
      attrs, className: "", hidden: false, open: false, value: "", checked: false });
  }
  get textContent() { return this._text + this.children.map((c) => c.textContent).join(""); }
  set textContent(t) { this._text = String(t); this.children = []; }
  get firstChild() { return this.children[0]; }
  append(...xs) { this.children.push(...xs); }
  replaceChildren(...xs) { this._text = ""; this.children = [...xs]; }
  addEventListener(type, f) { (this.listeners[type] ||= []).push(f); }
  dispatch(type) { for (const f of this.listeners[type] || []) f({ target: this }); }
  *all() { for (const c of this.children) { yield c; yield* c.all(); } }
  querySelector(sel) { const name = /^\[name=(\w+)\]$/.exec(sel)[1]; return [...this.all()].find((c) => c.attrs.name === name) || null; }
  querySelectorAll(tag) { return [...this.all()].filter((c) => c.tagName === tag.toUpperCase()); }
}

function page(input, search) {
  const ids = {};
  for (const id of ["title", "when", "banner", "summary", "tree", "refresh"]) ids[id] = new El(id === "refresh" ? "button" : "div");
  ids.filters = new El("div");
  ids.filters.append(new El("input", { name: "closed" }), new El("input", { name: "marks" }),
                     new El("select", { name: "label" }), new El("input", { name: "q" }));
  ids.bulk = new El("div");
  for (const [lv, text] of input.buttons) { const b = new El("button"); b.dataset.level = String(lv); b.textContent = text; ids.bulk.append(b); }
  const timers = [], urls = [], held = [];
  const location = { search, pathname: "/" };
  const ctx = {
    document: { getElementById: (id) => ids[id], createElement: (t) => new El(t) },
    location, window: { innerWidth: 1000 }, URLSearchParams, console,
    history: { replaceState: (_s, _t, url) => { location.search = url.startsWith("?") ? url : ""; } },
    setTimeout: (f) => timers.push(f), clearTimeout: () => { timers.length = 0; },
    fetch: (url) => {
      urls.push(url);
      const p = new URLSearchParams(url.split("?")[1] || "");
      const body = input.payloads[`${p.get("closed") === "1" ? 1 : 0}|${p.get("label") || ""}|${p.get("q") || ""}`];
      const res = { ok: Boolean(body), status: body ? 200 : 404, text: async () => (body ? JSON.stringify(body) : "no payload") };
      return ctx.hold ? new Promise((r) => held.push(() => r(res))) : Promise.resolve(res);
    },
  };
  vm.createContext(ctx);
  vm.runInContext(input.script, ctx);
  const flush = () => new Promise((r) => setImmediate(r)).then(() => new Promise((r) => setImmediate(r)));
  const runTimers = () => timers.splice(0).forEach((f) => f());
  const opened = () => [...ids.tree.all()].filter((e) => e.tagName === "DETAILS" && e.open).map((e) => String(e.dataset.key)).sort();
  const shown = () => [...ids.tree.all()].filter((e) => e.tagName === "A").map((e) => Number(/^#(\d+)/.exec(e.textContent)[1]));
  const details = (key) => [...ids.summary.all(), ...ids.tree.all()].find((e) => e.tagName === "DETAILS" && String(e.dataset.key) === key);
  const click = (lv) => ids.bulk.children.find((b) => b.dataset.level === String(lv)).dispatch("click");
  return { ids, ctx, urls, held, flush, runTimers, opened, shown, details, click };
}

async function main() {
  const input = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const out = {};
  const p = page(input, "");
  await p.flush();
  out.firstUrl = p.urls[0];
  out.levels = {};
  for (const lv of [0, 1, 2, 3]) { p.click(lv); out.levels[lv] = p.opened(); }
  p.click(0);
  const row = p.details("1"), sum = p.details("sum:要対応");
  row.open = true; row.dispatch("toggle");          // 利用者が開けた行
  sum.open = false; sum.dispatch("toggle");         // 利用者が閉じた要約
  out.toggledBefore = { row: p.details("1").open, sum: p.details("sum:要対応").open };
  p.click(0);
  out.toggledAfter = { row: p.details("1").open, sum: p.details("sum:要対応").open };
  // 古い応答: #770 の応答が #2 の応答の後に届いても描かない
  p.ctx.hold = true;
  const q = p.ids.filters.querySelector("[name=q]");
  q.value = "#770"; p.ids.filters.dispatch("input"); p.runTimers();
  q.value = "#2"; p.ids.filters.dispatch("input"); p.runTimers();
  out.staleUrls = p.urls.slice(-2);
  p.held[1](); await p.flush();
  p.held[0](); await p.flush();
  out.staleShown = p.shown();
  out.staleOpened = p.opened();
  // 絞り込みを URL に持って開いたとき、load() の URL に載る
  const f = page(input, "?closed=1&label=blocked&q=x");
  await f.flush();
  out.filteredUrl = f.urls[0];
  out.filteredText = f.ids.tree.textContent;
  process.stdout.write(JSON.stringify(out));
}
main().catch((e) => { console.error(e.stack); process.exit(1); });
