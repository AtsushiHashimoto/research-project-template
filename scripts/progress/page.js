"use strict";
// 表示の規則（出す行・開閉の既定・件数・進捗・作業中などの判定）は server が返す JSON が決める
// （.spec/issues/194-progress-collapse.md §4-3、.spec/issues/201-progress-cards.md §5）。
// ここは view をカードの DOM にし、一括の段と利用者が開け閉めした行を覚え、古い応答を捨て、close の確認をするだけ
const $ = (id) => document.getElementById(id);
const field = (name) => $("filters").querySelector(`[name=${name}]`);
const el = (tag, text, cls) => {
  const e = document.createElement(tag);
  if (text !== undefined) e.textContent = text;
  if (cls) e.className = cls;
  return e;
};
const badge = (text, cls, title) => { const b = el("span", text, "badge " + (cls || "")); if (title) b.title = title; return b; };
let data = null, labelsFilled = false, level = 0, missing = [], seq = 0, loadError = "", closeError = "";
let confirming = null, focusAfter = null;
const toggled = new Map();      // 利用者が開け閉めした行（key は番号と "lone"）。一括・絞り込みで消す
const sumToggled = new Map();   // 要約の 3 群（key は "sum:…"）。一括・絞り込みでは消さない
const LEVEL_TEXT = ["すべて閉じた後", "epic まで", "task まで", "すべて"];   // 段 0 は手で開けた行があるときだけ使う
const REAPPLIED = " · 再適用";

function options() {
  const p = new URLSearchParams(location.search);
  return { closed: p.get("closed") === "1", marks: p.get("marks") === "1", label: p.get("label") || "", q: p.get("q") || "" };
}
function syncForm() {
  const o = options();
  field("closed").checked = o.closed; field("marks").checked = o.marks; field("q").value = o.q; field("label").dataset.want = o.label;
}
// 絞り込みの値（ラベルの選択肢を作る前は URL の値）
function query() {
  const sel = field("label");
  return { closed: field("closed").checked, label: labelsFilled ? sel.value : (sel.dataset.want || ""), q: field("q").value };
}
const sameQuery = (a, b) => a.closed === b.closed && a.label === b.label && a.q === b.q;
const filtering = () => Boolean(data && data.view.filtering);
let timer = null, lastQuery = null;
function writeParams() {
  const p = new URLSearchParams(), cur = query();
  if (cur.closed) p.set("closed", "1");
  if (field("marks").checked) p.set("marks", "1");
  if (cur.label) p.set("label", cur.label);
  if (cur.q) p.set("q", cur.q);
  const qs = p.toString();
  history.replaceState(null, "", qs ? "?" + qs : location.pathname);
  if (lastQuery && sameQuery(cur, lastQuery)) return render();   // 印の表示だけを変えた
  lastQuery = cur; level = 0; toggled.clear();                   // 一致した行に至る経路だけを開く
  clearTimeout(timer); timer = setTimeout(() => load(false), 150);
}
// B3: 同じ段をもう一度押しても行の記録を消して描き直す。文言が変わらなければ「再適用」を足す
function setLevel(n) {
  const before = $("bulk-state").textContent.replace(REAPPLIED, "");
  level = n; toggled.clear(); render();
  const s = $("bulk-state");
  if (s.textContent === before) s.textContent = before + REAPPLIED;
}

// ── 日付（K6: JST で MM-DD、年が now と違えば YYYY-MM-DD）───────────
const JST = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Tokyo", year: "numeric", month: "2-digit", day: "2-digit",
                                                hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
const parts = (ms) => Object.fromEntries(JST.formatToParts(new Date(ms)).map((p) => [p.type, p.value]));
const toMs = (v) => (typeof v === "number" ? v * 1000 : Date.parse(v));
function day(v) {
  const p = parts(toMs(v)); return p.year === parts(data.now * 1000).year ? `${p.month}-${p.day}` : `${p.year}-${p.month}-${p.day}`;
}
function full(v) { const p = parts(toMs(v)); return `${p.year}-${p.month}-${p.day} ${p.hour}:${p.minute} JST`; }

// ── カード ──────────────────────────────────────────────
// K4: chip の文言と順は固定。自由な文字は title に入れる
function chips(n) {
  const out = [];
  const chip = (text, cls, title) => out.push(badge(text, "chip " + (cls || ""), title));
  if (n.anomaly) chip("異常: 子なし", "c-anom", "open の epic・task で子が 0 件");
  for (const text of n.needs) chip(text, "b-need");
  if (n.working) chip("作業中", "b-work", [...n.branches, ...n.worktrees, ...n.prs.filter((p) => p.state === "OPEN").map((p) => "PR #" + p.number)].join(", "));
  if (n.workingBelow) chip("配下で作業中", "b-work");
  if (n.stale) chip(`${data.rules.staleDays}日動きなし`, "c-stale", "更新 " + full(n.updatedAt));
  if (n.childrenCompletedLike) chip("子は全部完了扱い", "", "子が全部「完了扱い」なので、closed を出さないと子が出ない");
  if (n.completedLike) chip("完了扱い", "b-done", "open のまま、子が全部 closed");
  if (n.state === "CLOSED") chip(n.dropped ? "見送り" : "完了", "b-done");
  return out;
}
function marks(n, item) {
  const out = [];
  if (item && item.liftedFrom !== null) out.push(badge(`親 #${item.liftedFrom} は closed`));
  for (const note of n.notes) out.push(badge(note.split("（")[0].split(":")[0], "", note));
  for (const m of n.marks) out.push(badge("⚠ " + m, "b-mark"));
  return out;
}
function stepsEl(steps) {
  const box = el("span", undefined, "steps");
  const said = steps.map((s) => `${s.step} ${s.closed}/${s.total}`);
  box.setAttribute("role", "img"); box.setAttribute("aria-label", said.join(", ")); box.title = said.join(", ");
  for (const s of steps) {
    const sq = el("span", undefined, "st " + (s.total === 0 ? "st-none" : s.closed === s.total ? "st-done" : "st-part"));
    sq.title = `${s.step} ${s.closed}/${s.total}`; box.append(sq);
  }
  const next = steps.find((s) => s.total > 0 && s.closed < s.total);
  return next ? [box, el("span", next.step, "next-step")] : [box];
}
function head(n, opt, item) {
  const h = el("div", undefined, "head"), a = el("a", n.title, "title");
  a.href = n.url; a.target = "_blank"; a.rel = "noopener";
  h.append(el("span", n.kind, "kind"), el("span", "#" + n.number, "num"), a, ...chips(n));
  if (opt.marks) h.append(...marks(n, item));
  if (!item) return h;
  const right = el("span", undefined, "right"), pg = item.progress;
  if (pg) right.append(badge(`${pg.completed}/${pg.total}` + (pg.notPlanned ? ` 見送り ${pg.notPlanned}` : ""), "", "完了 / （全数 − 見送り）"));
  if (item.steps) right.append(...stepsEl(item.steps));
  if (item.children.length) right.append(badge(`子 ${item.count}`, "", "開くと出る直下の行の数"));
  if (n.anomaly) right.append(closeButton(n));
  h.append(right);
  return h;
}
function meta(n) {
  const out = [`更新 ${day(n.updatedAt)}`], titles = [`更新 ${full(n.updatedAt)}`];
  if (n.createdAt) { out.push(`作成 ${day(n.createdAt)}`); titles.push(`作成 ${full(n.createdAt)}`); }
  if (data.pullsError) out.push("PR ?");
  else if (n.prs.length) out.push(`PR #${n.prs[0].number} ${n.prs[0].state.toLowerCase()}` + (n.prs.length > 1 ? ` +${n.prs.length - 1}` : ""));
  if (data.gitError) out.push("コミット ?");
  else if (n.lastCommit) { out.push(`コミット ${day(n.lastCommit)}`); titles.push(`コミット ${full(n.lastCommit)}`); }
  const m = el("div", out.join(" · "), "meta"); m.title = titles.join(" / "); return m;
}
function folder(key, summary, defaultOpen) {
  const store = String(key).startsWith("sum:") ? sumToggled : toggled;
  const d = el("details"); d.dataset.key = key; d.open = store.has(key) ? store.get(key) : defaultOpen;
  // 既定と違うときだけ記録する（既定・一括で開いた行を利用者の操作として覚えない）
  d.addEventListener("toggle", () => {
    const had = store.has(key) ? store.get(key) : null;
    if (d.open === defaultOpen) store.delete(key); else store.set(key, d.open);
    if (store === toggled && had !== (store.has(key) ? store.get(key) : null)) bulkState();
  });
  d.append(summary); return d;
}
function cardEl(item, opt) {
  const n = data.nodes[item.number];
  if (!n) { missing.push(item.number); return null; }
  const body = [head(n, opt, item), meta(n)];
  if (confirming === n.number) body.push(confirmRow(n));
  if (!item.children.length) { const d = el("div", undefined, "card"); d.dataset.key = item.number; d.append(...body); return d; }
  const s = el("summary"); s.append(...body);
  const d = folder(item.number, s, item.defaultOpen || item.openAt <= level);
  d.className = "card";
  for (const c of item.children) { const e = cardEl(c, opt); if (e) d.append(e); }
  return d;
}

// ── 子 0 件の close（§5-4。2 回目の押下でだけ送る）──────────────────
function closeButton(n) {
  const b = el("button", "close…", "close"); b.type = "button"; b.setAttribute("aria-label", `#${n.number} を close`);
  b.addEventListener("click", (e) => { e.preventDefault(); confirming = n.number; focusAfter = true; render(); });
  return b;
}
function confirmRow(n) {
  const row = el("div", undefined, "confirm");
  const yes = el("button", "close する", "danger"), no = el("button", "やめる"), cancel = () => { confirming = null; render(); };
  yes.type = no.type = "button";
  yes.addEventListener("click", (e) => { e.preventDefault(); send(n, yes, no); });
  no.addEventListener("click", (e) => { e.preventDefault(); cancel(); });
  row.addEventListener("keydown", (e) => { if (e.key === "Escape") { e.preventDefault(); cancel(); } });
  row.append(el("span", `#${n.number}「${n.title}」を not planned で close する（戻すときは GitHub で reopen）`), yes, no);
  if (focusAfter === true) focusAfter = no;   // 確認行を開いた直後の 1 回だけ「やめる」へ（他の描き直しで focus を奪わない）
  return row;
}
async function send(n, yes, no) {
  yes.disabled = no.disabled = true; yes.textContent = "close 中…";
  let status = 0, why = "";
  try {
    const res = await fetch("/api/close", { method: "POST", headers: { "Content-Type": "application/json", "X-Progress-Close": "1" },
                                            body: JSON.stringify({ number: n.number }) });
    status = res.status; const text = await res.text();
    try { why = JSON.parse(text).error || ""; } catch { why = text.trim(); }
  } catch (e) { why = `サーバーに繋がらない: ${e.message}`; }
  confirming = null;
  if (status === 200) { closeError = ""; return load(true); }
  closeError = `#${n.number} を close できなかった（${status || "通信"}: ${why}）`;
  if (status === 502) return load(true);   // close が実際には通っていることがある
  render();
}

// ── 一括の手応え（B1・B2）────────────────────────────────────
function visibleOpen(e, shown) {
  let n = 0;
  for (const c of e.children || []) {
    if (c.tagName === "DETAILS") { const s = shown && c.open; n += s ? 1 : 0; n += visibleOpen(c, s); }
    else n += visibleOpen(c, shown);
  }
  return n;
}
function bulkState() {
  const f = filtering(), k = toggled.size;
  for (const b of $("bulk").querySelectorAll("button")) {
    b.setAttribute("aria-pressed", String(!f && k === 0 && Number(b.dataset.level) === level));
  }
  const n = visibleOpen($("tree"), true);
  let text = f && level === 0 ? `一致への経路だけ開いている · 開いている ${n} 行`
    : level === 0 && k === 0 ? "すべて閉じている" : `${LEVEL_TEXT[level]} · 開いている ${n} 行`;
  if (k) text += ` · 手で変えた ${k} 行`;
  $("bulk-state").textContent = text;
}

// ── 要約・帯・描画 ─────────────────────────────────────────
function summaryGroup(title, nums, why) {
  const s = el("summary", `${title} (${nums === null ? "不明" : nums.length})`);
  const g = folder("sum:" + title, s, window.innerWidth >= 600); g.className = "group";
  if (nums === null) { g.append(el("p", why, "muted")); return g; }
  const ul = el("ul");
  for (const num of nums) { const li = el("li"); li.append(head(data.nodes[num], { marks: false }, null)); ul.append(li); }
  g.append(ul); return g;
}
function showBanner(text) { const b = $("banner"); if (b.textContent !== text) b.textContent = text; b.hidden = !text; }
function fillLabels() {
  const sel = field("label"), want = labelsFilled ? sel.value : (sel.dataset.want || "");
  const names = [...new Set(Object.values(data.nodes).flatMap((n) => n.labels))].sort();
  sel.replaceChildren(el("option", "ラベル: すべて"));
  sel.firstChild.value = "";
  for (const name of names) { const o = el("option", name); o.value = name; sel.append(o); }
  sel.value = names.includes(want) ? want : "";
  labelsFilled = true;
}
function rulesEl() {
  const r = data.rules, ul = el("ul");
  for (const t of [`作業中 = open で、open の PR があるか、基準に無いブランチの tip が ${r.workingDays} 日以内（squash merge 済みの PR の head は除く）`,
                   "完了扱い = open の epic・task で、子が 1 件以上あり全部 closed（closed と同じく「closed も表示」で出す）",
                   `${r.staleDays}日動きなし = open で、自分の更新が ${r.staleDays} 日より前（一覧からは消さない）`,
                   "異常 = open の epic・task で子が 0 件（close… から not planned で close できる）",
                   `基準 = ${r.base || "なし"}（手元の ref。fetch はしない）`]) ul.append(el("li", t));
  const d = el("details", undefined, "rules"); d.append(el("summary", "表示の規則"), ul); return d;
}
function render() {
  if (!data) return;
  const opt = options(), v = data.view;
  $("title").textContent = "Progress — " + data.repo;
  $("when").textContent = `取得 ${data.fetchedAt}（ttl ${data.ttl} 秒）`;
  const s = data.summary, why = "作業中・次の候補は不明（帯を見る）";
  $("summary").replaceChildren(summaryGroup("要対応", s.needsUser),
    summaryGroup("作業中", s.working, why), summaryGroup("次の候補", s.next, why));
  const rules = $("rules"), keep = rules.firstChild && rules.firstChild.open;
  rules.replaceChildren(rulesEl()); rules.firstChild.open = Boolean(keep);
  const main = $("tree"); main.replaceChildren(); missing = [];
  for (const it of v.epics) { const e = cardEl(it, opt); if (e) main.append(e); }
  if (v.lone.count) {
    const d = folder("lone", el("summary", `親なし (${v.lone.count})`), v.lone.defaultOpen || v.lone.openAt <= level);
    d.className = "lone";
    for (const it of v.lone.items) { const e = cardEl(it, opt); if (e) d.append(e); }
    main.append(d);
  }
  if (!v.epics.length && !v.lone.count) {
    main.append(el("p", v.filtering ? "一致なし" : "open な issue はありません", "muted"));
  }
  const msgs = loadError ? [loadError] : [];
  if (closeError) msgs.push(closeError);
  if (data.error) msgs.push(`取得失敗 ${data.errorAt} — 表示は ${data.fetchedAt} 時点（${data.error}）`);
  const lack = [];
  if (data.gitError) lack.push(`手元の git を読めない（${data.gitError}）`);
  else if (!data.rules.base) lack.push("基準のブランチが無い");
  if (data.pullsError) lack.push(`PR を取れない（${data.pullsError}）`);
  if (lack.length) msgs.push(lack.join(" / ") + " — 作業中・次の候補は不明");
  const un = data.rules.unlinkedOpenPrs || [];
  if (un.length) msgs.push("issue に結び付かない open の PR: " + un.map((x) => "#" + x).join(", "));
  if (data.labelsError) msgs.push(`ラベルの検査をしていない（${data.labelsError}）`);
  if (missing.length) msgs.push(`一覧に無い issue 番号があるので、その行を出していない: ${missing.map((x) => "#" + x).join(", ")}`);
  showBanner(msgs.join(" / "));
  bulkState();
  if (focusAfter && focusAfter !== true) focusAfter.focus(); focusAfter = null;
}
// 失敗は帯に残す（次の描き直しで消さない）。下の木が前の条件のものであることも書く
function failed(why) {
  loadError = data ? `取得失敗 — 下は前の条件の表示（${data.fetchedAt} 時点）（${why}）` : `取得失敗 — 表示できるデータがありません（${why}）`;
  lastQuery = null;                      // 次の入力で必ず取り直す
  if (data) render(); else { showBanner(loadError); $("when").textContent = ""; }
}
async function load(refresh) {
  const btn = $("refresh"), want = query(), mine = ++seq;
  const p = new URLSearchParams({ closed: want.closed ? "1" : "0", label: want.label, q: want.q });
  if (refresh) p.set("refresh", "1");
  lastQuery = want;
  btn.disabled = true; btn.textContent = "取得中…";
  try {
    const res = await fetch("/api/tree.json?" + p, { headers: refresh ? { "X-Progress-Refresh": "1" } : {} });
    const text = await res.text();
    if (mine !== seq) return;            // 後から出した要求がある（その応答を待つ）
    let body = null;
    try { body = JSON.parse(text); } catch { /* 403・404 は text/plain */ }
    if (!res.ok || !body) return failed((body && body.error) || text.trim() || res.status);
    if (!sameQuery(body.view.query, query())) return;   // 古い応答（後から届いても描かない）
    loadError = ""; data = body; fillLabels();
    if (field("label").value !== want.label) return writeParams();   // URL のラベルが一覧に無い
    render();
  } catch (e) {
    if (mine === seq) failed(`サーバーに繋がらない: ${e.message}`);
  } finally {
    if (mine === seq) { btn.disabled = false; btn.textContent = "取り直す"; }
  }
}
syncForm();
$("filters").addEventListener("input", writeParams);
$("refresh").addEventListener("click", () => load(true));
for (const b of $("bulk").querySelectorAll("button")) b.addEventListener("click", () => setLevel(Number(b.dataset.level)));
load(false);
