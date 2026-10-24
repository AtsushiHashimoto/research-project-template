# Issue #201: spec: 進捗一覧のカード型・メタ情報・判定の見直し

## メタ情報

- 作成日: 2026-10-24
- ステータス: completed
- 親: task #200 / epic #192
- 前の仕様: `.spec/issues/176-progress-server.md`（§3-1「作業中」、§6「GET 以外は 405」を本仕様で置き換える）、
  `.spec/issues/194-progress-collapse.md`（開閉・初期表示・closed の隠し方は**そのまま保つ**。§3-2 の「除くノード」に完了扱いを足す）

## 1. 目的

進捗一覧（`scripts/progress/`）は「作業中」を「open でブランチか worktree が 1 本でもある」で決めている
（`working()`、`progress_tree.py:160`）。下流 delta-clip-dev では 22 件が作業中に出るが、多くは PR がマージ済みか
8〜9 月から動いていない。各行は 1 行のテキストの並びで、メタ情報が無い。一括の 4 ボタンは押しても手応えが無い。
判定の規則を見直し、一覧をテキスト圧の弱いカードにし、メタ情報を足す。

## 2. 前提（epic #192 の原文。`bash scripts/read-premises.sh 201`）

- 「一覧の見た目は「もう少しテキスト圧が弱いカード型のデザイン」」（2026-10-24）
- 「最終更新がいつかなどのメタ情報が欲しい」。出すもの: 最終更新日・作成日・PR の状態・ブランチの最終コミット日・「survey->experimentのどこまで進んでいるか」（2026-10-24）
- 「作業中」は「open PR か直近14日のコミット」があるものだけ（2026-10-24）
- 子が全部 closed なのに open の epic・task は「完了扱いで隠す」（2026-10-24）
- 30 日更新の無い open の issue は「『30日動きなし』と印だけ」（2026-10-24）
- 一括の 4 ボタンは「フィードバックがないのでデザインミスがありそう。動作はします。」（2026-10-24）
- 子が 0 件の epic・task は「異常なEPICとして印を付けて、htmlからcloseできるようにする。」（2026-10-24）
- 閲覧のみ（epic #170 から継続。2026-10-24 変更: 子が 0 件の epic・task だけは html から close できる）
- PR と issue の結び付け方は「仕様の段で決める」（2026-10-24）
- 「文字の量を減らす」ではなく「テキスト圧を弱める」で判定する（2026-10-24）
- 「closeしたものは出さないでね。」「全部closeされたepicやtaskは特別な処理をしない限り気配もないようにしておけ。」（2026-10-23）
- epic #170 から継続: 常時読み込みのファイルに記述を足さない。テストは 1 秒未満で、ネットワークも git も使わない（176 §2）

## 3. 未確定の解消（task #200 の `## 未確定` の 6 行）

### 3-1. PR と issue の結び付け方 → **PR の head ブランチ名を、ブランチと同じ規則で読む**

| 案 | 下流の実測（PR 348 件、2026-10-24） | 採否 |
|---|---|---|
| **A. `headRefName` を `progress_tree.branch_issue`（`progress_tree.py:33`）で読む** | **343 件が issue に結び付く**。外れる 5 件は番号を持たないブランチ名（`chore/template-skills-migration` 等） | **採用** |
| B. 本文の `Refs #N` | 本文を全件取ると応答が大きくなる（本文は 1 件で数 KB）。1 本の PR が複数の issue を参照する | 不採用 |
| C. いまの `closedByPullRequestsReferences`（closing keyword） | flow は `Refs #N` を使うので、ほとんど空 | **A に足す**（既存の経路を消さない） |

- task 単位のブランチ `<type>/<TASK>-i<N>` の PR は **issue N** に結び付ける（`branch_issue` の戻り値の 1 つ目）。task #TASK には結び付けない。
  task のカードは「配下で作業中」（§4-3）で子の作業を表す。
- 1 つの issue に PR が複数あれば全部持つ（番号で重複を除く）。カードには番号の最も大きい 1 本の状態と「+k」を出す（§5-2）。

### 3-2. 「作業中」に要るコミット日・PR の状態を、取得時間を大きく増やさずに取れるか → **取れる（実測）**

| 取得 | 回数 | 下流の実測 | 壁時計への影響 |
|---|---|---|---|
| issue（既存）に `createdAt` を足す | 0 回増（同じ query） | 660 件 7 ページで 8.5 秒（既存） | 0 |
| **PR（新規）** `gh api graphql --paginate --slurp`、1 ページ 100 件、`number state url headRefName headRefOid updatedAt` | **ページ数（348 件で 4 回）** | **3.2 秒、69 KB** | **issue の取得と並行に走らせる**（`ThreadPoolExecutor(2)`）ので、壁時計は max(8.5, 3.2) = 0 秒増 |
| git の ref（既存の `for-each-ref` の書式に `%(objectname)`・`%(committerdate:unix)` を足す） | 0 回増 | 305 本で 0.02 秒 | 0 |
| **git の「main に無い tip」**（新規）`git for-each-ref --no-merged=<基準>` | **1 回** | 150 本で 0.02 秒 | +0.02 秒 |
| **基準の有無**（新規）`git rev-parse --verify -q refs/remotes/origin/main`、無ければ `refs/heads/main` | **1〜2 回** | < 0.01 秒 | +0.01 秒 |

閲覧のみ（GET の範囲）のまま、GitHub への呼び出しは PR のページ数ぶん増えるが並行なので待ち時間は増えない。fetch はしない（176 §3 のまま）。
**基準は手元の `origin/main`**（fetch しない）。手元が古いと、マージ済みの内容を「main に無い」と数えうる。画面の「表示の規則」に 1 行で書く。

### 3-3. epic のカードの「どこまで進んでいるか」 → **task と同じ 5 段の帯を、task を単位に集計して出す**

| カード | 段 i（survey・spec・feature・validation・experiment）の値 | 実体 |
|---|---|---|
| task | 段 i のラベルを持つ**子**の数 `total` と、そのうち CLOSED（理由を問わない）の数 `closed` | `progress_work.steps(node, nodes)`（新規） |
| epic | 子孫の task のうち §4-2 の「除くノード」でないものについて、段 i を持つ task の数 `total` と、段 i が閉じた（`closed == total`）task の数 `closed` | `progress_view` の `item.steps` |
| issue | 帯を出さない（`steps = null`） | |

完了した task は「除くノード」なので epic の帯に入らない（194 §3-2 と同じく、隠した task の気配を出さない）。
epic の帯は「open の task がどの段まで閉じたか」を表し、済んだ量は既存の進捗バッジ（`完了 / 分母`）が表す。

### 3-4. 一括ボタンの手応え → **押されている段を `aria-pressed` と塗りで示し、いまの状態を 1 行の status で出す**（§5-3）

### 3-5. テキスト圧を弱めるカードの見た目の規則 → §5-1 の K1〜K7（合否は規則を守っているか。文字数は合否にしない）

### 3-6. html から close する操作の安全策 → §6（Host・Origin・独自ヘッダ・GitHub での再確認・2 段の確認）

## 4. 判定の規則

用語: **基準** = §3-2 の `origin/main`（無ければ `main`）。**fetch 時刻** `now` = 取得を始めた時刻（`server.default_fetch` が `time.time()` を渡す。テストは固定値）。

### 4-1. 作業中

```
working(n) = n.state == OPEN
             and ( n の PR に state == OPEN が 1 本ある
                   or n のブランチの tip のうち「新しい tip」が 1 本ある )
新しい tip  = 基準に含まれない（--no-merged に出る）
              and MERGED の PR の headRefOid のどれとも一致しない（squash merge 済みの head は main に入ったとみなす）
              and now − committerdate < 14 × 86400
```

- 「main に無いコミットの最終日」は tip の committerdate で代える（rebase で committer date は付け直されるので tip が最新になる）。
- ローカルとリモートの同名ブランチは tip を 2 つとも見る（どちらかが新しい tip なら真）。
- git が失敗したら `working = None`（既存と同じ「不明」）。**基準が無い**（`origin/main` も `main` も無い）ときも `working = None` にし、帯に「基準のブランチが無い — 作業中は不明」を出す（全部を「main に無い」と数えない）。**PR の取得だけが失敗**したら PR の条件を使えないので `working = None` にし、帯に「PR を取れない — 作業中は不明」を出す（木は出す）。
- 残骸の注記（closed でブランチが残る、`progress_tree.py:77`）は変えない。
- 下流の実測（2026-10-24 18 時 JST、この規則の試算）: 作業中 22 件 → **4 件**（#751・#859・#885・#1006。いずれも 14 日以内の新しい tip。open の PR #118 はブランチ名に番号が無く結び付かない）。
  task #200 の「現在の状態」が挙げた #119・#386・#486・#496（PR マージ済み）、#250・#352・#361・#373・#515・#537（新しい tip なし）は全部外れる。
  #1008 は main の先端と同じ tip のブランチだけを持つので作業中にならない（goal「ブランチ・worktree が残っていてもこれに当たらなければ「作業中」にしない」どおり）。

### 4-2. 完了扱い

```
completedLike(n) = n.state == OPEN and n.kind in (epic, task)
                   and len(n.children) >= 1 and 全ての子の state == CLOSED
```

- 子は木の上の子（`build` の `children`。同じ repo の sub-issue）。**再帰にしない**（goal の「全部 closed」の文言どおり）。下流では再帰にしても同じ 7 件（#476・#587・#608・#609・#893・#908・#924）。
- `progress_view` は完了扱いを **CLOSED と同じに扱う**: `shown(n)` は `closed or (state == OPEN and not completedLike)`。194 §3-2 の「除くノード」の判定でも CLOSED と同じに扱う（`excluded` = (CLOSED または completedLike) かつ open の子孫なし。`open_below` も完了扱いのノードを open に数えない。数えると、完了扱いの task だけを持つ closed の epic が除かれず、親のバッジに気配が出る）。子は全部 closed でも、closed の子の下に open の孫がありうる。そのときは closed のノードと同じく 194 §3-1 の持ち上げに従う（孫を完了扱いのノードの位置に出し、`liftedFrom` を付ける）。
- `closed=1` のときは出し、カードに chip「完了扱い」を付ける。
- 要約の 3 群（要対応・作業中・次の候補）からも外す（隠した行の気配を要約に出さない）。

### 4-3. 配下で作業中

task・epic の `workingBelow` = 子孫に `working` が真のものがある。既存の `taskBranches`（ブランチの有無で決める）を置き換える。git か PR が失敗したら `None`。

### 4-4. 30日動きなし

```
stale(n) = n.state == OPEN
           and now − n.updatedAt > 30 × 86400        # n 自身の updatedAt だけを見る
```

goal「30 日更新の無い open」と task #200 の「現在の状態」の 112 件（自分の `updatedAt` で数えた値）に合わせ、子孫の更新は見ない。
完了扱いも除かない（完了扱いは §4-2 で隠れるが、`closed=1` で出したときは「30日動きなし」も付く）。
（初版は子孫の `updatedAt` も見て 109 件にしていたが、goal の範囲を狭めるので auto-reviewer が戻した。子が動いている epic に印を付けないことが要るなら、goal の判断としてユーザーに確かめる）

### 4-5. 異常（子が 0 件）

`anomaly(n)` = `n.state == OPEN and n.kind in (epic, task) and len(n.children) == 0`。既存の注記「子なし」（`progress_tree.py:83-84`）は、注記の切り替えに関係なく出る chip「異常: 子なし」に置き換える。下流: 6 件（#469・#566・#567・#590・#777・#809）。

## 5. 画面（`index.html`）

### 5-1. カードの規則（テキスト圧）

| # | 規則 | 判定の仕方（W7 の DOM・CSS の検査） |
|---|---|---|
| K1 | 各 item は 1 枚のカード（`class="card"`）。子を持つものは `<details class="card">`、子の無いものは `<div class="card">`。カードの中は **見出し行（`.head`）とメタ行（`.meta`）の 2 行だけ**で、子のカードはその下に入れ子にする | カードの直下の要素が `.head`・`.meta`（と子のカード）だけ |
| K2 | **本文を出さない**（issue の本文は取得もしない） | GraphQL に `body` が無い |
| K3 | 見出し行: 種別（epic・task・issue の小さな文字）・`#N`（薄い字）・タイトル（リンク）・chip・右端に進捗バッジと段の帯と「子 N」 | |
| K4 | chip の文言は固定の集合だけ: 作業中・配下で作業中・作業中: 不明・要対応・blocked・異常: 子なし・30日動きなし・完了扱い・完了・見送り。ブランチ名・理由などの自由な文字は `title` 属性に入れ、chip の中に書かない | chip の `textContent` が集合に入る |
| K5 | メタ行は 12px・`var(--muted)` の 1 行: `更新 MM-DD · 作成 MM-DD · PR #n merged(+k) · コミット MM-DD`。年が fetch 時刻と違えば `YYYY-MM-DD`。無い項目は書かない（「なし」と書かない）。完全な日時は `title` に JST で | `.meta` の CSS が `font-size:12px` と `color:var(--muted)` |
| K6 | タイトルは 14px・通常の太さ。`font-weight` ≥ 600 は `h1` と要約の見出しだけ。色は `:root` の変数だけ | CSS の検査 |
| K7 | カードは `background:var(--card)`、角丸 8px、内側の余白 6px 10px、カードの間 4px。入れ子は左に 12px 下げ、左に 1px の `var(--line)` の線。逸脱の印と注記は既存どおり切り替えのときだけ（見出し行の chip の後ろ） | CSS の検査 |

既存の説明の段落（`index.html:64`）は `<details class="rules">表示の規則</details>` の中に移し、既定で閉じる。中身は §4 の規則を 1 行ずつ（作業中・完了扱い・30日動きなし・異常・基準が手元の `origin/main`）。

### 5-2. メタ情報の出どころ

| 表示 | 値 | 実体 |
|---|---|---|
| 更新 | `node.updatedAt`（自分のもの） | 既存 |
| 作成 | `node.createdAt` | GraphQL に `createdAt` を足す（`progress_gh.py:18`） |
| PR | `node.prs`（§3-1 の A と C の和、番号の降順）の先頭の `#n` と状態（open・merged・closed）、2 本目以降は `+k` | `progress_work.attach_prs` |
| コミット | `node.lastCommit` = n のブランチの tip の committerdate の最大（基準に含まれるかを問わない）。ブランチが無ければ出さない | `progress_work` |
| 段の帯 | §3-3。5 つの小さな四角（文字は出さない）。`closed == total > 0` は塗り、`0 < total` で未完は枠、`total == 0` は点線。`title`・`aria-label` に「spec 1/2」等 | `item.steps` |

### 5-3. 一括の 4 ボタンの手応え

| # | 規則 |
|---|---|
| B1 | いまの段 `level` と同じ `data-level` のボタンだけ `aria-pressed="true"`、他は `"false"`。CSS で `[aria-pressed="true"]` は `background:var(--work)`・文字は `var(--bg)`。初期（`level = 0`）は「すべて閉じる」が押された状態 |
| B2 | ボタンの並びの右に `<span id="bulk-state" role="status" aria-live="polite">` を置き、描くたびに書き直す: 「いま: epic まで開いている · 開いている行 N」（N = `#tree` の中の開いた `<details>` の数）。利用者が行を開け閉めしたら「· 手で変えた行 k」（k = `toggled.size`）を足す。絞り込み中で `level = 0` なら「いま: 一致への経路だけ開いている」 |
| B3 | 同じボタンをもう一度押しても行の記録を消して描き直し、status を書き直す（押したことが分かる） |

### 5-4. 子 0 件の close（画面側）

- `anomaly` のカードの見出し行の右端に `<button type="button" class="close">close…</button>`。
- 押すと、そのカードの見出し行の下に確認行を出す: 「#N「タイトル」を not planned で close する」と `<button>close する</button>` `<button>やめる</button>`。**2 回目の押下でだけ**送る。
- 送信中は 2 つのボタンを disabled。成功したら `load(true)` で取り直す。失敗したら確認行を消し、帯に理由を出す。

## 6. close の経路（server）

`POST /api/close`、本文 `{"number": N}`。これが**唯一の書き込みの経路**。

| 順 | 検査 | 外れたら |
|---|---|---|
| 1 | Host がループバック（既存の `do_GET` の先頭と同じ関数にまとめる） | 403 |
| 2 | path が `/api/close`（他の path の POST は従来どおり 405） | 405 |
| 3 | `Origin` が `"http://" + Host ヘッダの値` と完全一致（他のサイトのフォーム・fetch を拒む。ポート転送でも Host と Origin は同じ値になる） | 403 |
| 4 | `Content-Type: application/json` と `X-Progress-Close: 1`（独自ヘッダは他の origin から preflight を要する。OPTIONS は従来どおり 405 で CORS ヘッダを返さない） | 403 |
| 5 | 本文が 1 KB 以下の JSON で、`number` が正の整数 | 400 |
| 6 | **GitHub で取り直して確かめる**（キャッシュを使わない）: `gh api graphql` で `issue(number:N){ state labels(first:20){nodes{name}} subIssues{totalCount} }`。OPEN・ラベルに `epic` か `task`・`subIssues.totalCount == 0`。`issue` が null（番号が PR か存在しない）も 409 | 409（理由を本文に） |
| 7 | `gh issue close N --repo <cwd の repo> --reason "not planned"`（コメントは付けない。前提の例外は close だけ） | 502（stderr の先頭） |
| 8 | キャッシュを無効にし（次の GET で取り直す）、200 `{"closed": N}`。stderr に INFO で 1 行 | |

- close は lock で 1 本ずつ。1 回の close で GitHub への呼び出しは 2 回。
- 理由を not planned に固定するのは、子が 0 件＝何も行っていないため。画面の確認行に理由を書く。
- 実体は新規 `scripts/progress/progress_close.py`（`verify(number, runner)`・`close(number, repo, runner)`）。`gh issue close` を含むのはこのファイルだけにする。

## 7. 入力 → 処理 → 出力（ファイルの分け方）

| ファイル | 変更 |
|---|---|
| `progress_gh.py` | issue の query に `createdAt`。PR を取る `fetch_pulls(repo, runner)`（`collect` と同じく全ページと `totalCount` の一致を検査） |
| `progress_git.py` | `read_refs(runner)` → `[{name, tips:[{oid, time}]}]`、`read_unmerged(base, runner)` → 名前の集合、`read_base(runner)` → 基準の ref か None。`read_worktrees` は変えない |
| `progress_work.py`（新規・純関数） | `attach_prs`・`working`・`workingBelow`・`lastCommit`・`completedLike`・`stale`・`anomaly`・`steps`。引数に `now` |
| `progress_tree.py` | `build(..., pulls=None, refs=None, now=None)`。`working()` と `taskBranches` を `progress_work` に移す。`summarize` は完了扱いを 3 群から除く（§4-2）。300 行以内を保つ |
| `progress_view.py` | §4-2 の `shown`・除くノード、`item.steps`（epic の集計） |
| `progress_close.py`（新規） | §6 |
| `server.py` | 取得の並行、`do_POST`（§6）、キャッシュの無効化 |
| `index.html` | §5。300 行を超えるなら `<script>` を `scripts/progress/page.js` に出し、`GET /page.js` で返す（`test_progress_page.py` の抜き出しもそれに合わせる） |

node に足すキー: `createdAt`・`lastCommit`（unix 秒か null）・`workingBelow`・`completedLike`・`stale`・`anomaly`・`steps`。`taskBranches` は消す。

## 8. 制約

- 書き込みは §6 の 1 本だけ。他の書き込み（ラベル・コメント・編集）は持たない
- 1 ファイル 300 行以内。常時読み込みのファイルに記述を足さない
- テストは `scripts/tests/test_progress_*.py`。fixture と差し込みの runner だけで動き、ネットワーク・git を使わない。**追加分を含めて合計 1 秒未満**

## 9. 判定（validation。実データは omron-sinicx/delta-clip-dev。閲覧のみ: close の実走は下流で行わない）

fixture に足すもの（`progress_fixture.py`）: `NOW` を固定し、
(e) open の task #150（epic #1 の下）と子 #151（closed）→ 完了扱い、(f) open の根の epic #160 と子 #161（closed）→ 完了扱い、
(g) refs: `fix/12-x` は基準に無く 3 日前 → #12 作業中、`survey/756-i770` は基準に含まれる・open の PR あり → #770 作業中、
`feature/13-y` は基準に無く 20 日前 → #13 作業中でない、`feature/14-z` は 2 日前だが MERGED の PR の head と同じ oid → #14 作業中でない、
(h) #97 の `updatedAt` を 40 日前 → 30日動きなし、#95 の `updatedAt` も 40 日前 → 子 #96 が新しくても 30日動きなし（自分の `updatedAt` だけを見る）、(i) PR `headRefName` に番号の無いもの 1 本、(j) open の epic #170 と子 task #171（closed）と孫 #172（open）→ #170 は完了扱いで隠れ、#172 が親なしの群に `liftedFrom: 171` で出る、(k) 基準が無い refs → 全ノード `working = None`。

| # | goal の項目 | テスト（fixture） | 実データ（delta-clip-dev） |
|---|---|---|---|
| W1 | カード型・テキスト圧（K1〜K7） | W7 の DOM・CSS の検査で K1・K4〜K7 を 1 つずつ。GraphQL に `body` が無い（K2） | ブラウザで 1 回開き、K1〜K7 を目で照合して項目ごとに記録。画面写しを残す |
| W2 | メタ情報 5 種 | `createdAt`・`prs`（A と C の和、重複除き）・`lastCommit`・`steps`（task: #2 の feature が closed 2 / total 5（#13・#14・#15・#16・#51。closed は #15・#16）等、手で数えた値）・epic の帯が除くノードを数えない | 全 open の `steps`・`lastCommit` を、`build` を使わない別のコードで ref と issue から数えた値と一致。PR の結び付きの件数（343/348 前後）を記録 |
| W3 | 作業中 | (g) の 4 本の期待どおり。PR 取得の失敗と (k) の基準なしで `working = None` と帯 | 規則で出た件数と番号を記録し、各件の根拠（PR か tip の日付）を独立に示す。§4-1 の外れるべき 10 件が外れる |
| W4 | 完了扱いで隠す | (e)(f)(j) の完了扱いが `closed=False` の `view` に現れず（(j) の #172 は持ち上がって出る）、`count`・`progress`・要約に寄与しない。`closed=True` では出て chip「完了扱い」。194 の W1〜W5 は回帰で通る | 完了扱いの集合が独立に数えた集合（いま 7 件）と一致し、`closed=False` の `view` に 0 件 |
| W5 | 異常と close | #30・#71・#72 が `anomaly`。§6 の順 1〜8 の各外れで期待のコード（403・405・400・409・502）、runner に渡る argv が `gh issue close N --repo o/r --reason "not planned" ...` だけ。`gh issue close` を含むファイルが `progress_close.py` だけ。画面は 1 回目の押下で送らず 2 回目で送る | 異常の件数と番号（いま 6 件）。**close は実走しない**。上流（このテンプレート）で使い捨ての issue を `/issue-create` で 1 件作り（`epic` ラベル・子 0 件）、ブラウザから close して状態が変わることを 1 回確かめる |
| W6 | 30日動きなし | (h) | 件数（自分の `updatedAt` で数える。task #200 の時点で 112 件）を独立に数えた値と一致。完了扱いでないものは `closed=False` の `view` に全件出る（印で消えない） |
| W7 | 一括の手応え（B1〜B3） | `node` で画面の JS を動かし、段 0〜3 で `aria-pressed` が 1 つだけ true、`#bulk-state` の文言と N が開いた `<details>` の数と一致、行を開けると「手で変えた行 1」、同じボタンの再押下で 0 に戻る | ブラウザで 4 ボタンを押して見た目が変わることを記録 |
| W8 | 取得時間（記録のみ。方向なし） | — | 取得 1 回の壁時計・PR のページ数・JSON の大きさを、変更前（issue 8.5 秒）と並べて記録 |

検出力の確認: `working` の 14 日を 15 日に、`completedLike` の `>= 1` を `>= 0` に、Origin の比較を外す変異で、W3・W4・W5 のテストがそれぞれ落ちることを validation で実測する。

## 10. 範囲外

- close 以外の書き込み。close の理由を選ばせること
- 子の無い issue 層の扱いの変更
- 開閉の状態を URL に持つこと（194 §7 のまま）

## 変更履歴

- 2026-10-24: 初版
- 2026-10-24: auto-reviewer（#201）。30日動きなしを自分の `updatedAt` だけに戻す（goal の範囲を狭めない）、完了扱いの下の open の孫の持ち上げを明記、基準が無いときと close の検査で issue が null のときの扱い、summarize の実体、`index.html` の行番号、fixture (j)(k)
- 2026-10-24: auto-reviewer の警告を反映し、close に添えるコメントをやめた（前提の例外は close だけ）
