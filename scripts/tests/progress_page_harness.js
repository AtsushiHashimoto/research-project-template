// test_progress_page.py から node で呼ぶ。scripts/progress/page.js を最小限の DOM の stub の上で動かし、結果を JSON で返す。
// 入力（stdin の JSON）: {script, payloads: {"<closed 0|1>|<label>|<q>": 応答の body}, buttons: [[段, 文言]], close: {status, body}}
"use strict";
const vm = require("vm");

// 実ブラウザに合わせるもの: <details> の open を変えると toggle が非同期に届く（代入でも）、
// <select> に選択肢に無い値を入れると "" になる
class El {
  constructor(tag, attrs = {}) {
    Object.assign(this, { tagName: tag.toUpperCase(), children: [], _text: "", dataset: {}, listeners: {},
      attrs, className: "", hidden: false, _open: false, _value: "", checked: false, disabled: false });
  }
  setAttribute(k, v) { this.attrs[k] = String(v); }
  getAttribute(k) { return k in this.attrs ? this.attrs[k] : null; }
  focus() { El.focused = this; }
  get open() { return this._open; }
  set open(v) {
    const changed = this._open !== Boolean(v);
    this._open = Boolean(v);
    if (changed && this.tagName === "DETAILS") setImmediate(() => this.dispatch("toggle"));
  }
  get value() { return this._value; }
  set value(v) {
    v = String(v);
    this._value = this.tagName !== "SELECT" || this.children.some((o) => o.value === v) ? v : "";
  }
  get textContent() { return this._text + this.children.map((c) => c.textContent).join(""); }
  set textContent(t) { this._text = String(t); this.children = []; }
  get firstChild() { return this.children[0]; }
  append(...xs) { this.children.push(...xs); }
  replaceChildren(...xs) { this._text = ""; this.children = [...xs]; }
  addEventListener(type, f) { (this.listeners[type] ||= []).push(f); }
  dispatch(type, extra = {}) {
    const ev = { target: this, defaultPrevented: false, preventDefault() { this.defaultPrevented = true; }, ...extra };
    for (const f of this.listeners[type] || []) f(ev);
    return ev;
  }
  *all() { for (const c of this.children) { yield c; yield* c.all(); } }
  querySelector(sel) { const name = /^\[name=(\w+)\]$/.exec(sel)[1]; return [...this.all()].find((c) => c.attrs.name === name) || null; }
  querySelectorAll(tag) { return [...this.all()].filter((c) => c.tagName === tag.toUpperCase()); }
}

function page(input, search) {
  const ids = {};
  for (const id of ["title", "when", "banner", "summary", "tree", "refresh", "rules", "bulk-state"]) ids[id] = new El(id === "refresh" ? "button" : "div");
  ids.filters = new El("div");
  ids.filters.append(new El("input", { name: "closed" }), new El("input", { name: "marks" }),
                     new El("select", { name: "label" }), new El("input", { name: "q" }));
  ids.bulk = new El("div");
  for (const [lv, text] of input.buttons) { const b = new El("button"); b.dataset.level = String(lv); b.textContent = text; ids.bulk.append(b); }
  const timers = [], urls = [], held = [], posts = [];
  const location = { search, pathname: "/" };
  const ctx = {
    document: { getElementById: (id) => ids[id], createElement: (t) => new El(t) },
    location, window: { innerWidth: 1000 }, URLSearchParams, console,
    history: { replaceState: (_s, _t, url) => { location.search = url.startsWith("?") ? url : ""; } },
    setTimeout: (f) => timers.push(f), clearTimeout: () => { timers.length = 0; },
    fetch: (url, init = {}) => {
      if (url === "/api/close") {
        posts.push({ url, method: init.method, headers: init.headers, body: init.body });
        const c = input.close;
        return Promise.resolve({ ok: c.status === 200, status: c.status, text: async () => JSON.stringify(c.body) });
      }
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
  const shown = () => [...ids.tree.all()].filter((e) => /\bcard\b/.test(e.className)).map((e) => Number(e.dataset.key));
  const details = (key) => [...ids.summary.all(), ...ids.tree.all()].find((e) => e.tagName === "DETAILS" && String(e.dataset.key) === key);
  const click = (lv) => ids.bulk.children.find((b) => b.dataset.level === String(lv)).dispatch("click");
  const pressed = () => ids.bulk.children.map((b) => b.getAttribute("aria-pressed"));
  const card = (num) => [...ids.tree.all()].find((e) => /\bcard\b/.test(e.className) && String(e.dataset.key) === String(num));
  // 見えている開いた <details> の数を、page.js とは別に数える（祖先が全部開いているもの）
  const visible = () => { let n = 0; const rec = (e, s) => { for (const c of e.children) { const o = s && c.tagName === "DETAILS" && c.open; if (o) n++; rec(c, c.tagName === "DETAILS" ? o : s); } }; rec(ids.tree, true); return n; };
  return { ids, ctx, urls, held, posts, flush, runTimers, opened, shown, details, click, pressed, card, visible };
}

async function main() {
  const input = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const out = {};
  const p = page(input, "");
  await p.flush();
  out.firstUrl = p.urls[0];
  out.levels = {};
  for (const lv of [0, 1, 2, 3]) { p.click(lv); await p.flush(); out.levels[lv] = p.opened(); }
  // 一括で開いた行の toggle が描き直しの後に届いても、利用者の操作として覚えない
  p.click(3); p.click(0); await p.flush();
  p.ids.filters.querySelector("[name=marks]").checked = true; p.ids.filters.dispatch("input"); await p.flush();
  out.afterLateToggles = p.opened();
  p.details("1").open = true;                     // 利用者が開けた行
  p.details("sum:要対応").open = false;           // 利用者が閉じた要約
  await p.flush();
  out.toggledBefore = { row: p.details("1").open, sum: p.details("sum:要対応").open };
  p.click(0); await p.flush();
  out.toggledAfter = { row: p.details("1").open, sum: p.details("sum:要対応").open };
  // 絞り込みを変えると段と行の記録を消す（一致した行に至る経路だけが開く）
  const q = p.ids.filters.querySelector("[name=q]");
  const search = async (text) => { q.value = text; p.ids.filters.dispatch("input"); p.runTimers(); await p.flush(); };
  p.click(1); await p.flush();
  p.details("1").open = false; await p.flush();   // 段 1 で開いた epic を利用者が閉じた
  await search("#770");
  out.filterOpened = p.opened();
  await search("");
  out.clearedOpened = p.opened();
  await search("#40");
  out.loneOpened = p.opened();
  // 古い応答: #770 の応答が #2 の応答の後に届いても描かない
  p.ctx.hold = true;
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
  // 201 K4 と #218: closed のカードの chip（見送り・完了は node の dropped）と、規則の説明の日数（rules.staleDays）
  const c = page(input, "?closed=1&label=feature");
  await c.flush();
  out.closedChips = Object.fromEntries([...c.ids.tree.all()].filter((e) => /\bcard\b/.test(e.className)).map((e) => {
    const top = e.tagName === "DETAILS" ? e.children[0] : e, head = top.children.find((x) => x.className === "head");
    return [e.dataset.key, head.children.filter((x) => /\bchip\b/.test(x.className)).map((x) => x.textContent)];
  }));
  out.rulesText = p.ids.rules.textContent;
  // URL のラベルが一覧に無ければ外して取り直す。取得の失敗は次の描き直しでも帯に残る
  const g = page(input, "?label=nosuch");
  await g.flush(); g.runTimers(); await g.flush();
  out.unknownLabelUrls = g.urls;
  const gq = g.ids.filters.querySelector("[name=q]");
  gq.value = "no-payload"; g.ids.filters.dispatch("input"); g.runTimers(); await g.flush();
  g.ids.filters.querySelector("[name=marks]").checked = true; g.ids.filters.dispatch("input"); g.runTimers(); await g.flush();
  out.failBanner = g.ids.banner.textContent;
  // 201 W7: 一括の手応え（B1〜B3）
  const h = page(input, "");
  await h.flush();
  const state = () => h.ids["bulk-state"].textContent;
  out.bulk = {};
  for (const lv of [0, 1, 2, 3]) { h.click(lv); await h.flush(); out.bulk[lv] = { pressed: h.pressed(), text: state(), visible: h.visible() }; }
  h.click(3); await h.flush();
  out.bulk.reapplied = state();
  h.click(1); await h.flush();
  h.details("2").open = true; await h.flush();              // 段 1 で閉じている task を手で開けた
  out.bulk.toggled = { pressed: h.pressed(), text: state(), visible: h.visible() };
  h.click(1); await h.flush();
  out.bulk.afterReapply = { pressed: h.pressed(), text: state() };
  const hq = h.ids.filters.querySelector("[name=q]");
  hq.value = "#770"; h.ids.filters.dispatch("input"); h.runTimers(); await h.flush();
  out.bulk.filtered = { pressed: h.pressed(), text: state(), visible: h.visible() };
  // 201 K1・K4・K6: カードの構造・chip・メタ行
  hq.value = ""; h.ids.filters.dispatch("input"); h.runTimers(); await h.flush();
  h.click(3); await h.flush();
  out.cards = [...h.ids.tree.all()].filter((e) => /\bcard\b/.test(e.className)).map((e) => {
    const top = e.tagName === "DETAILS" ? e.children[0] : e;
    const head = top.children.find((c) => c.className === "head");
    return { key: Number(e.dataset.key), tag: e.tagName, first: e.children[0].tagName,
             inner: top.children.map((c) => c.className),
             outside: e.tagName === "DETAILS" ? e.children.slice(1).map((c) => c.className) : [],
             chips: head ? head.children.filter((c) => /\bchip\b/.test(c.className)).map((c) => c.textContent) : [],
             meta: (top.children.find((c) => c.className === "meta") || {}).textContent };
  });
  // 201 W5: close は 2 回目の押下でだけ送る
  const closeBtn = () => [...h.card(30).all()].find((c) => c.className === "close");
  const ev = closeBtn().dispatch("click"); await h.flush();
  const row = () => [...h.card(30).all()].find((c) => c.className === "confirm");
  out.close = { prevented: ev.defaultPrevented, postsAfterFirst: h.posts.length, confirm: Boolean(row()),
                focused: El.focused && El.focused.textContent };
  row().dispatch("keydown", { key: "Escape" }); await h.flush();
  out.close.afterEscape = Boolean(row());
  closeBtn().dispatch("click"); await h.flush();
  const before = h.urls.length;
  row().children.find((c) => c.textContent === "close する").dispatch("click"); await h.flush(); await h.flush();
  out.close.posts = h.posts;
  out.close.reload = h.urls.slice(before);
  out.close.afterSend = Boolean(row());
  process.stdout.write(JSON.stringify(out));
}
main().catch((e) => { console.error(e.stack); process.exit(1); });
