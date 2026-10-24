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

### 3-1. PR と issue の結び付け方 → **PR の head ブランチ名を、ブランチと同じ規則で読む。open の PR は本文の `Refs #N` も読む**（B は #208 で採用）

| 案 | 下流の実測（PR 348 件、2026-10-24） | 採否 |
|---|---|---|
| **A. `headRefName` を `branch_issue`（いまは `progress_tree.py:33`）で読む** | **343 件が issue に結び付く**。外れる 5 件は番号を持たないブランチ名（`chore/template-skills-migration` 等） | **採用** |
| B. 本文の `Refs #N` | 当初は「本文を全件取ると応答が大きくなる（本文は 1 件で数 KB）」として不採用。しかし A だけでは番号を持たないブランチの open の PR（下流 #118。本文は `Refs #70`）を見落とし、#70 を作業中にしなかった（validation #203、bug #208）。**本文を取るのは open の PR だけ**にすれば応答は open の件数ぶん（下流 2 件）で済む | **A に足す**（#208。open の PR だけ） |
| C. いまの `closedByPullRequestsReferences`（closing keyword） | flow は `Refs #N` を使うので、ほとんど空 | **A に足す**（既存の経路を消さない） |

- task 単位のブランチ `<type>/<TASK>-i<N>` の PR は **issue N** に結び付ける（`branch_issue` の戻り値の 1 つ目）。task #TASK には結び付けない。
  task のカードは「配下で作業中」（§4-3）で子の作業を表す。
- **B の規則（#208）**: open の PR だけ、本文の**行頭の** `Refs #N`（`Closes`・`Fixes`・`Resolves` も同じ形で読む。大文字小文字を問わない。`:` 可、`Refs #1, #2` の並びも読む）を同じ repo の issue 番号として読み、その issue に結び付ける（`progress_work.BODY_REFS`・`body_issues`）。
  - 行頭に限るのは、文中に引用した `Refs #N`（例: 別 repo の PR の説明に書いた「本文 `Refs #70`」）を読まないため。flow が書く形（`commit.sh`・`quick.sh` の `Refs #$N`）は行頭にある。
  - `owner/repo#N`（別の repo）・語の途中（`xrefs #N`）・語の続く番号（`#12abc`）・10 桁以上の番号は読まない（本文は他人が書ける入力なので、巨大な数字で `int` を落とさない）。merged・closed の PR の本文は取らないので読まない。
  - **kind が epic・task の番号には結び付けない**（task のカードは §4-3 の「配下で作業中」で表す。A はブランチ名の形で task 番号を外すが、B は kind で外す）。epic・task だけを参照する open の PR は下の `unlinkedOpenPrs` に出る。
  - fork の PR も本文は読む（fork を外す理由はブランチ名の衝突で、本文には当たらない）。
  - 参照先の issue が closed でも結び付ける（A と同じ。closed の issue は作業中にならないので、その PR は作業中を生まないが `unlinkedOpenPrs` にも出ない）。
  - `scripts/flow/issue-finish.sh` の PR 本文の検査も同じ語を読むが、目的（1 本の PR が #N を持つか）が違い、並び・行頭の扱いも違う。規則の原本はここと `BODY_REFS` で、issue-finish.sh とは共有しない。
- `isCrossRepository` が真の PR（fork から）はブランチ名では結び付けない（他人の fork のブランチ名が手元の番号に当たるため。下流は 0 件）。
- 1 つの issue に PR が複数あれば全部持つ。A・B・C を番号で重複を除いて合わせ、残す値は `{number, state, url}`（C は `headRefOid` を持たないので、§4-1 の照合には A の全 PR の一覧を使う）。カードには番号の最も大きい 1 本の状態と「+k」を出す（§5-2）。
- **結び付かなかった open の PR**（下流では #208 の前は #118 の 1 本。#208 の後は 0 本）は、`rules.unlinkedOpenPrs` として返し、帯に「issue に結び付かない open の PR: #n」と出す（作業中から黙って外さない）。

### 3-2. 「作業中」に要るコミット日・PR の状態を、取得時間を大きく増やさずに取れるか → **取れる（実測）**

| 取得 | 回数 | 下流の実測 | 壁時計への影響 |
|---|---|---|---|
| issue（既存）に `createdAt` を足す | 0 回増（同じ query） | 660 件 7 ページで 8.5 秒（既存） | 0 |
| **PR（新規）** `gh api graphql --paginate --slurp`、1 ページ 100 件、`number state url headRefName headRefOid isCrossRepository` | **ページ数（348 件で 4 回）** | **3.2 秒、69 KB** | **issue の取得と並行**（`ThreadPoolExecutor(2)` を `with` で使い、両方の完了を待ってから例外を出す）。壁時計は max(8.5, 3.2) で 0 秒増 |
| **open の PR の本文**（#208）同じ形の 2 本目の query、`pullRequests(states: [OPEN])` の `number body` だけ | **ページ数（open 2 件で 1 回）** | `fetch_pulls` の中で全 PR の query の後に続けて呼ぶ。PR の取得 2.59 → 2.86 秒（6 回の平均、+0.27 秒） | issue の取得と並行のまま。壁時計（`default_fetch` 全体）は 8.33 → 8.09 秒（6 回の平均。差は揺れの範囲で増えていない） |
| git の ref（既存の `for-each-ref` の書式に `%(objectname)`・`%(committerdate:unix)` を足す） | 0 回増 | 305 本で 0.02 秒 | 0 |
| **git の「main に無い tip」**（新規）`git for-each-ref --no-merged=<基準> --format=%(refname) refs/heads refs/remotes` | **1 回** | 150 本で 0.02 秒 | +0.02 秒 |
| **基準の有無**（新規）`git rev-parse --verify -q refs/remotes/origin/main`、無ければ `refs/heads/main` | **1〜2 回** | < 0.01 秒 | +0.01 秒 |

本文の query だけが失敗しても `fetch_pulls` 全体を失敗にする（PR の取得の失敗と同じく作業中は「不明」。B を黙って落とした一部の結果で作業中を決めない。176 §3 の「一部だけの木を出さない」と同じ）。2 本の query の間に状態が変わった PR は、本文が付かないだけで誤って結び付けない。

閲覧のみ（GET の範囲）のまま、GitHub への呼び出しは PR のページ数ぶん増えるが並行なので待ち時間は増えない。fetch はしない（176 §3 のまま）。
**基準は手元の `origin/main`**（fetch しない）。手元が古いと、マージ済みの内容を「main に無い」と数えうる。実際に使った基準の ref 名を `rules.base` で返し、「表示の規則」に出す（`main` に落ちたことも見える）。
`rev-parse --verify -q` は「無い」ときも終了コード 1 を返すので、`read_base` は終了コード 1 だけを「無い」と読み、それ以外の失敗は git の失敗にする。

### 3-3. epic のカードの「どこまで進んでいるか」 → **task と同じ 5 段の帯を、task を単位に集計して出す**

`steps` の形: `[{"step": "survey", "total": t, "closed": c}, …]`（`STEP_ORDER` の順に 5 要素）。段の名前と順は `progress_work.STEP_ORDER` だけが持ち、view と画面は `steps` を順に描くだけ。

| カード | 段 i の値 | 実体 |
|---|---|---|
| task | 段 i のラベルを持つ**子**の数 `total` と、そのうち CLOSED（理由を問わない）の数 `closed` | `node.steps`（`progress_work.steps`） |
| epic | 子孫の task のうち、**この view に出す task**（`closed=False` なら §4-2 の `shown`、`closed=True` なら全部）について、段 i を持つ（`total > 0`）task の数 `total` と、段 i が閉じた（`closed == total`）task の数 `closed` | `progress_view` の `item.steps`（`node.steps` を足し合わせる） |
| issue | 帯を出さない（`steps = null`） | |

完了した task・closed の task は `closed=False` では出ないので、epic の帯に入らない（隠した task の気配を出さない）。
epic の帯は「open の task がどの段まで閉じたか」を表し、済んだ量は既存の進捗バッジ（`完了 / 分母`）が表す。

### 3-4. 一括ボタンの手応え → **押されている段を `aria-pressed` と塗りで示し、いまの状態を 1 行の status で出す**（§5-3）

### 3-5. テキスト圧を弱めるカードの見た目の規則 → §5-1 の K1〜K8（合否は規則を守っているか。文字数は合否にしない）

### 3-6. html から close する操作の安全策 → §6（Host・Origin・独自ヘッダ・GitHub での再確認・2 段の確認）

## 4. 判定の規則

用語:
- **基準** = §3-2 の ref（`origin/main`、無ければ `main`）。
- **`now`** = 取得を始めた時刻（unix 秒）。`server.default_fetch` が `time.time()` を渡す。**`build` は `now` を省略できない**（省略したら `TypeError`。`time.time()` に落ちない。テストは `progress_fixture.NOW`）。JSON に `now` として返し、画面の日付の表示にも使う。
- **`updatedAt`・`createdAt`** は `Z` 付きの ISO 8601 を `datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()` で unix 秒にして比べる。
- **`work_ok`** = git の読み取り・基準・PR の取得の 3 つがそろっている。そろわないときは `working`・`workingBelow`・`summary.working`・`summary.next` を全部 `None`（不明）にし、帯に欠けた理由を 1 つずつ出す（「手元の git を読めない」「基準のブランチが無い」「PR を取れない」— 続けて「作業中・次の候補は不明」）。カードごとの「作業中: 不明」の chip は出さない（全 open に付くと一覧が埋まる。帯 1 行に任せる）。

### 4-1. 作業中

```
working(n) = n.state == OPEN
             and ( n の PR に state == OPEN が 1 本ある
                   or n のブランチの tip のうち「新しい tip」が 1 本ある )
新しい tip  = その ref（完全な refname）が --no-merged=<基準> に出る
              and その oid が、repo の MERGED の PR（A の全 PR）の headRefOid のどれとも一致しない（squash merge 済みの head は main に入ったとみなす）
              and now − committerdate <= 14 × 86400      # ちょうど 14 日は含む。未来の日付（時計のずれ）も含む
```

- 「main に無いコミットの最終日」は tip の committerdate で代える（rebase で committer date は付け直されるので tip が最新になる）。
- ローカルとリモートの同名ブランチは **ref ごと**に判定する（どちらかが新しい tip なら真）。`refs/remotes/*/HEAD` は既存の `read_branches`（`progress_git.py:17`）と同じく除く。
- 残骸の注記（closed でブランチが残る、`progress_tree.py:77`）は変えない。
- 下流の試算（now = 2026-10-24 18 時 JST）: 作業中 22 件 → **4 件**（#751・#859・#885・#1006。いずれも 14 日以内の新しい tip）。
  task #200 の「現在の状態」が挙げた #119・#386・#486・#496（PR マージ済み）、#250・#352・#361・#373・#515・#537（新しい tip なし）は全部外れる。
  #1008 は main の先端と同じ tip のブランチだけを持つので作業中にならない（goal「ブランチ・worktree が残っていてもこれに当たらなければ「作業中」にしない」どおり）。
  **件数は now で変わる**（#751 の tip は 13.4 日前で、2026-10-25 朝に外れる）。validation の照合は同じ now で独立に数えた値との一致で判定し、この 4 件は参考値として扱う。

### 4-2. 完了扱い

```
completedLike(n) = n.state == OPEN and n.kind in (epic, task)
                   and len(n.children) >= 1 and 全ての子の state == CLOSED
gone(n)          = n.state == CLOSED or completedLike(n)
```

- 子は木の上の子（`build` の `children`。同じ repo の sub-issue）。**再帰にしない**（goal の「全部 closed」の文言どおり）。下流では再帰にしても同じ 7 件（#476・#587・#608・#609・#893・#908・#924）。
- **`gone` は `progress_work` が node のキーとして 1 回だけ決める。** `progress_view`（`shown`・`excluded`・`open_below`）、`summarize`、epic の帯の集計は `gone` だけを読み、`state == "CLOSED"` を直接見ない（いまの `progress_view.py:46,51` を置き換える）。
  - `shown(n)` = `closed or not gone(n)`。
  - 194 §3-2 の除くノード: `excluded` = `gone` かつ「`gone` でない子孫が無い」。`open_below` も `gone` でない子孫だけを数える（完了扱いの task だけを持つ closed の epic が除かれず、親のバッジに気配が出るのを防ぐ）。
  - 子が全部 closed でも、closed の子の下に open の孫がありうる。そのときは closed のノードと同じく 194 §3-1 の持ち上げに従う（孫を完了扱いのノードの位置に出し、`liftedFrom` を付ける）。
- `closed=1` のときは出し、カードに chip「完了扱い」を付ける（`title` に「open のまま、子が全部 closed」）。
- 要約の 3 群（要対応・作業中・次の候補）からも外す（隠した行の気配を要約に出さない）。
- **子が全部完了扱いの open の親**（例: open の epic の子が完了扱いの task だけ）は、規則が再帰しないので完了扱いにも異常にもならない。`closed=False` では子 0 行のカードになるので、chip「子は全部完了扱い」を付ける（異常と見分ける。close ボタンは出さない）。下流はいま 0 件。

### 4-3. 配下で作業中

task・epic の `workingBelow` = 子孫に `working` が真のものがある。既存の `taskBranches`（ブランチの有無で決める）を置き換える。`work_ok` が偽なら `None`。

### 4-4. 30日動きなし

```
stale(n) = n.state == OPEN
           and now − n.updatedAt > 30 × 86400        # n 自身の updatedAt だけを見る。ちょうど 30 日は付かない
```

goal「30 日更新の無い open」と task #200 の「現在の状態」の 112 件（自分の `updatedAt` で数えた値）に合わせ、子孫の更新は見ない。
完了扱いも除かない（完了扱いは §4-2 で隠れるが、`closed=1` で出したときは「30日動きなし」も付く）。
（初版は子孫の `updatedAt` も見て 109 件にしていたが、goal の範囲を狭めるので auto-reviewer が戻した。子が動いている epic に印を付けないことが要るなら、goal の判断としてユーザーに確かめる）

### 4-5. 異常（子が 0 件）

`anomaly(n)` = `n.state == OPEN and n.kind in (epic, task) and len(n.children) == 0`。既存の注記「子なし」（`progress_tree.py:83-84`）は、注記の切り替えに関係なく出る chip「異常: 子なし」に置き換える。下流: 6 件（#469・#566・#567・#590・#777・#809。GitHub 上の `subIssues.totalCount` も 6 件とも 0）。
木の子は同じ repo の sub-issue だけなので、**別 repo にだけ sub-issue を持つ**ノードも異常になる。close の検査（§6 順 6）は `subIssues.totalCount`（別 repo を含む）で見るので、その場合は 409「別 repo の子がある」で close しない（安全側。下流は 0 件）。

## 5. 画面（`index.html` と `page.js`）

### 5-1. カードの規則（テキスト圧）

| # | 規則 | 判定の仕方（W7。CSS と文言の静的な検査は node なしで Python が行う） |
|---|---|---|
| K1 | 各 item は 1 枚のカード。子を持つものは `<details class="card">` で、**最初の子が `<summary>`**、その中に見出し行（`.head`）とメタ行（`.meta`、`display:block`）と、close の確認中だけ確認行（`.confirm`）。子のカードは `<summary>` の外に置く。子の無いものは `<div class="card">` で、中身は同じ `.head`・`.meta`（・`.confirm`） | 子を持つカードの最初の子が `SUMMARY` で、その子の class が `head`・`meta`（・`confirm`）だけ。葉のカードも同じ |
| K2 | **本文を出さない**（issue の本文は取得もしない） | issue の query（`QUERY`）と全 PR の query（`PULL_QUERY`）に `body` が無い（open の PR だけの `OPEN_BODY_QUERY` は §3-1 の B のために本文を取る。本文はノードに写さない） |
| K3 | 見出し行（`flex-wrap:wrap`）: 種別（小さな文字）・`#N`（薄い字の別要素）・タイトル（リンク）・chip・右端のまとまり（進捗バッジ・段の帯・「子 N」・close ボタン）。右端のまとまりは幅が足りなければ次の行に回る | CSS の検査 |
| K4 | chip の文言は固定の集合だけで、この順に並べる: 異常: 子なし・要対応・blocked・作業中・配下で作業中・30日動きなし・子は全部完了扱い・完了扱い・完了・見送り。ブランチ名・理由などの自由な文字は `title` 属性に入れ、chip の中に書かない | chip の `textContent` が集合に入り、並びがこの順 |
| K5 | chip の形: 「異常: 子なし」だけ `var(--warn)` の輪郭。「30日動きなし」は枠なしの `var(--muted)` の字（状態の chip と重さを分ける）。他は既存の `.badge` の色。文字は 12px | CSS の検査 |
| K6 | メタ行は 12px・`var(--muted)` の 1 行: `更新 MM-DD · 作成 MM-DD · PR #n merged(+k) · コミット MM-DD`。日付は `Intl.DateTimeFormat` に `timeZone: "Asia/Tokyo"` を渡して JST で出し、年が `now` の年（JST）と違えば `YYYY-MM-DD`。無い項目は書かない（「なし」と書かない）。**取れなかった項目は `PR ?`・`コミット ?`**（PR の取得・git が失敗したとき。無いことと区別する）。完全な日時は `title` に JST で。`var(--muted)` より薄い色を使わない | `.meta` の CSS が `font-size:12px` と `color:var(--muted)`。node を `TZ=UTC` で起動して日付の文字列を照合 |
| K7 | タイトルは 14px・通常の太さ。`font-weight` ≥ 600 は `h1` と要約の見出しだけ。色は `:root` の変数だけ | CSS の検査 |
| K8 | カードは `background:var(--card)`、角丸 8px、内側の余白 6px 10px、カードの間 4px。入れ子は左に 12px 下げ、左に 1px の `var(--line)` の線。逸脱の印と注記は既存どおり切り替えのときだけ（chip の後ろ） | CSS の検査 |

既存の説明の段落（`index.html:64`）は `<details class="rules">表示の規則</details>` の中に移し、既定で閉じる。中身は server が返す `rules`（`{"workingDays": 14, "staleDays": 30, "base": "<実際に使った ref>", "unlinkedOpenPrs": [番号]}`）から作る（閾値と基準の文言を画面に二重に書かない）。行: 作業中・完了扱い・30日動きなし・異常・基準。`rules` の閾値の実体は `progress_work.WORKING_DAYS`・`STALE_DAYS`。
既存の画面テストが `#N` をリンクの文字列の先頭から読んでいる箇所（`test_progress_page.py` の `shown()`）は `dataset.key` で読むように直す。

### 5-2. メタ情報の出どころ

| 表示 | 値 | 実体 |
|---|---|---|
| 更新 | `node.updatedAt`（自分のもの） | 既存 |
| 作成 | `node.createdAt` | GraphQL に `createdAt` を足す（`progress_gh.py:18`） |
| PR | `node.prs`（§3-1 の A・B・C の和、番号の降順）の先頭の `#n` と状態（open・merged・closed）、2 本目以降は `+k` | `progress_work.attach_prs` |
| コミット | `node.lastCommit` = n のブランチの tip の committerdate の最大（基準に含まれるかを問わない）。ブランチが無ければ出さない | `progress_work` |
| 段の帯 | §3-3。5 つの小さな四角（文字は出さない）。`closed == total > 0` は塗り、`0 < total` で未完は枠、`total == 0` は点線。`title`・`aria-label` に「spec 1/2」等。帯の直後に、最初の未完の段の名前を muted で 1 語（例「spec」。全部閉じていれば出さない） | `item.steps` |

### 5-3. 一括の 4 ボタンの手応え

| # | 規則 |
|---|---|
| B1 | いまの段 `level` と同じ `data-level` のボタンだけ `aria-pressed="true"`、他は `"false"`。CSS で `[aria-pressed="true"]` は `background:var(--work)`・文字は `var(--bg)`。初期（`level = 0`）は「すべて閉じる」が押された状態。**絞り込み中、または手で変えた行がある（`toggled.size > 0`）ときは全部 `"false"`**（押された段と実際の開閉が食い違うため） |
| B2 | ボタンの並びの右に `<span id="bulk-state" role="status">` を置き、描き直しのたびと、行の `toggle` のたびに書き直す: 「epic まで · 開いている N 行」。N = `#tree` の中の、開いていて祖先の `<details>` も全部開いている（見えている）`<details>` の数。`toggled.size > 0` なら「 · 手で変えた k 行」を足す。絞り込み中で `level = 0` なら「一致への経路だけ開いている · 開いている N 行」。段 0 は「すべて閉じている」 |
| B3 | 同じボタンをもう一度押しても行の記録を消して描き直す。文言が前と同じなら末尾に「 · 再適用」を付ける（`role="status"` は文言が変わったときだけ読み上げるため） |

### 5-4. 子 0 件の close（画面側）

- `anomaly` のカードの右端のまとまりに `<button type="button" class="close" aria-label="#N を close">close…</button>`。枠なし・`var(--muted)` の小さい字で、hover と focus で `var(--warn)`。
- 押すと、そのカードの `<summary>`（葉は `div`）の中に確認行 `.confirm` を出す: 「#N「タイトル」を not planned で close する（戻すときは GitHub で reopen）」と `<button>close する</button>`（`var(--warn)` の輪郭）`<button>やめる</button>`。初期 focus は「やめる」。Esc で確認行を消す。**2 回目の押下でだけ**送る。
- ボタンの click は `preventDefault()` する（`<summary>` の中なので、押すとカードが開閉してしまう）。
- 送信は `fetch("/api/close", {method: "POST", headers: {"Content-Type": "application/json", "X-Progress-Close": "1"}, body: JSON.stringify({number})})`。`index.html` に `referrerpolicy="no-referrer"` 等の Origin を消す設定を置かない。
- 送信中は 2 つのボタンを disabled。成功したら `load(true)` で取り直す。失敗したら確認行を消し、理由を `closeError` に持って帯に出す（`loadError` と同じく描き直しで消さない。次の close の成功か、ページの再読み込みで消える）。502 のときも `load(true)` する（close が実際には通っていることがある）。

## 6. close の経路（server）

`POST /api/close`、本文 `{"number": N}`。これが**唯一の書き込みの経路**。

| 順 | 検査 | 外れたら |
|---|---|---|
| 1 | Host がループバック（既存の `do_GET` の先頭と同じ関数にまとめる） | 403 |
| 2 | path が `/api/close`（他の path の POST は従来どおり 405 `Allow: GET`。`/api/close` への POST 以外の method は 405 `Allow: POST`） | 405 |
| 3 | `Origin` が `"http://" + Host ヘッダの値` と完全一致。**Origin が無い・`null` も 403**（拒む側に倒す。他のサイトのフォーム・fetch を拒む。TCP のポート転送では Host と Origin は同じ値で届く） | 403 |
| 4 | `Content-Type` の media type（`;` より前を小文字にしたもの）が `application/json`、かつ `X-Progress-Close: 1`（独自ヘッダは他の origin から preflight を要する。OPTIONS は従来どおり 405 で CORS ヘッダを返さない） | 403 |
| 5 | `Content-Length` が整数で 1〜1024。無い・`Transfer-Encoding` がある → 411、1024 を超える → 413（どちらも本文を読まずに返す）。本文が JSON で、`number` が `type(x) is int`（`bool` を除く）の正の整数 | 411・413・400 |
| 6 | **GitHub で取り直して確かめる**（キャッシュを使わない）: `progress_gh.fetch_issue_state(repo, number)` が `gh api graphql -F number=N` で `repository{ issue(number:$number){ state labels(first:100){totalCount nodes{name}} subIssues{totalCount} } }` を取る。OPEN・ラベルに `epic` か `task`・`subIssues.totalCount == 0` でなければ 409（理由を本文に。別 repo の子は §4-5）。**`gh` は存在しない番号・PR の番号で exit 1 と `errors[].type == "NOT_FOUND"`・`issue: null` を返す**（実測）ので、exit ≠ 0 でも stdout を JSON として読み、NOT_FOUND なら 409、それ以外の失敗（ネットワーク・認証・timeout）は 502 で close しない。**exit 0 で NOT_FOUND 以外の `errors` が来たときも 502**（exit の値によらず理由は先頭の `message`。`collect` と同じ `progress_gh.graphql_error`）。応答の形が違うとき（body・`data`・`repository` が想定の型でない）も 502 で、例外を漏らさない| 409・502 |
| 7 | `gh issue close N --repo <cwd の repo> --reason "not planned"`（コメントは付けない。前提の例外は close だけ） | 502（stderr の先頭）。**gh を実行できない・timeout（`run_raw` の `FetchError`）も `close()` の中で理由に変えて 502**（例外を漏らさない。どちらも「試みた」として順 8 の無効化を行う。timeout では GitHub 側で close が通っていることがあるので理由に「close されたかは不明」、起動できない `OSError` では「close していない」と書く） |
| 8 | キャッシュを無効にし、200 `{"closed": N}`。stderr に INFO で 1 行。順 7 が 502 のときも無効にする | |

- **キャッシュの無効化は世代番号で行う**: `Cache` に `generation` を持ち、無効化で 1 増やす。取得は始めたときの世代を覚え、終わったときに世代が変わっていたらその結果を「新しい」とみなさない（close の前に始まって後に終わった取得が、close 前の木を返すのを防ぐ）。次の GET（`load(true)`）で取り直す。
- **iframe に入れさせない**: server の全応答に `X-Frame-Options: DENY` と `Content-Security-Policy: frame-ancestors 'none'` を付ける（`server.FRAME_DENY`。`Handler.end_headers` で付けるので、標準の `send_error` が返す 400・414・501 にも付く）。他のサイトがこのページを iframe に入れると、中の fetch は Origin・Host とも 127.0.0.1 になり順 1〜5 を通るため、2 回のクリックを誘導されると close されうる（clickjacking）。
- close は lock で 1 本ずつ。1 回の close で GitHub への呼び出しは 2 回。
- 順 6 と 7 の間に別の人が sub-issue を足すと close されうる（数秒の窓）。これは受け入れ、確認行に reopen で戻せることを書く。
- 理由を not planned に固定するのは、子が 0 件＝何も行っていないため。画面の確認行に理由を書く。
- 実体: 順 3〜5 は純関数 `progress_close.check_request(headers, host) -> (code, msg) | None` と `parse_body(raw) -> number | (code, msg)`。順 6 の読み取りは `progress_gh.fetch_issue_state`。順 7 は `progress_close.close(number, repo, runner)`。**`gh issue close` を含むのは `progress_close.py` だけ**。`server.py` は順 1・2 と呼び出しだけを持つ。

## 7. 入力 → 処理 → 出力（ファイルの分け方）

依存の向き: `progress_work` は何も import しない（`progress_tree`・`progress_view` から import される）。`progress_view` は `progress_work` 以外を import しない。ブランチ名の規則（`TASK_BRANCH`・`ISSUE_BRANCH`・`branch_issue`）と `STEP_ORDER`・`DROPPED` は `progress_work` へ移し、`progress_tree` と `progress_view` はそこから使う（いまの `progress_view.py:11` の `DROPPED` の写しを消す）。

| ファイル | 変更 |
|---|---|
| `progress_gh.py` | issue の query に `createdAt`。`collect(pages, field)` に一般化し（`issues`・`pullRequests`）、PR を取る `fetch_pulls(repo, runner)` と close の確認の `fetch_issue_state(repo, number, runner)` |
| `progress_git.py` | `read_branches` を `read_refs(runner)` → `[{refname, name, oid, time}]` に置き換える（`*/HEAD` を除く）。`read_unmerged(base, runner)` → 完全な refname の集合、`read_base(runner)` → 基準の ref か None。`read_worktrees` は変えない |
| `progress_work.py`（新規・純関数） | ブランチ名の規則、`STEP_ORDER`・`DROPPED`・`WORKING_DAYS`・`STALE_DAYS`、`attach_prs`・`working`・`workingBelow`・`lastCommit`・`completedLike`・`gone`・`stale`・`anomaly`・`steps`。#218 で `NEEDS_USER`・`dropped`・`needs` |
| `progress_tree.py` | `build(issues, repo, sections, refs, worktrees, pulls, base, now, unmerged, git_error=None, pulls_error=None)`（`now` と `unmerged`（`progress_git.read_unmerged` の完全な refname の集合。git が失敗したら None）は必須）。`working()`・`taskBranches` を `progress_work` に移す。`summarize` は `work_ok` と `gone` を見る。`rules` を返す |
| `progress_view.py` | §4-2 の `shown`・除くノードを `gone` で、`item.steps`（epic の集計） |
| `progress_close.py`（新規） | §6 |
| `server.py` | 取得の並行、`do_POST`（§6 の順 1・2 と呼び出し）、世代番号の無効化、`GET /page.js`（`text/javascript; charset=utf-8`）。配る path は `/`・`/page.js`・`/api/tree.json`、#213 で足した `/api/identity`（212）の 4 つだけ |
| `index.html` | §5 の CSS と骨組み。**`<script>` は `scripts/progress/page.js` に出す**（245 行に §5 を足すと 300 行を超える見込み。`<script src="/page.js">`） |
| `scripts/tests/progress_page_harness.js` | `page.js` を読む。`fetch` は method・headers・body を記録し、`/api/close` には別の応答を返す。`setAttribute`・`getAttribute`・`disabled`・`focus`・`keydown`・`preventDefault` と id `bulk-state` を stub に足す |
| `scripts/tests/test_progress_work.py`・`test_progress_close.py`（新規） | §9 |

node に足すキー: `createdAt`・`lastCommit`（unix 秒か null）・`workingBelow`・`completedLike`・`gone`・`stale`・`anomaly`・`steps`。`taskBranches` は消す。JSON の最上位に `now`・`rules`・`pullsError` を足す。

**判定の置き場所（refactor #218）**: 見送り（`DROPPED`・`dropped()`）と要対応のラベル（`NEEDS_USER`。ラベル → chip の文言）は `progress_work` だけが持ち、node の `dropped`（bool）・`needs`（chip の文言の list）に載せる。`progress_tree`（進捗・要約）と `progress_view`（数え直し）は node のキーを読む。絞り込み中かは `progress_view.view` が `filtering` として返し（q の空白を削るのは Python の `strip` だけ）、規則の説明の日数は `rules.staleDays` から組み立てる。`page.js` はこれらのキーを読むだけで、ラベル名・`stateReason` の値・日数を持たない（`test_progress_work.py` の `SingleSource` が grep で固定）。`collect` の形の違い（`KeyError`・`TypeError`）と `setup-labels.sh` の `OSError` は `FetchError`・`labelsError` にし、PR とラベル定義だけの失敗を取得全体の失敗にしない。

**分割方針**（1 ファイル 300 行の上限。#218 の時点で `page.js`・`server.py` とも 299 行。`test_progress_work.py` の `FileSize` が `scripts/progress/` の全ファイルを検査する）: 次に機能を足して 300 行を超えるなら、足す前に**どこにも依存しない塊から別ファイルに出す**。
- `page.js`: 第一候補は日付の整形（K6。`JST`・`parts`・`toMs`・`day`・`full`。`data.now` だけを引数で受ける形にする）を `page_date.js` に。子 0 件の close（§5-4。`closeButton`・`confirmRow`・`send`）は `confirming`・`focusAfter`・`closeError` と `render`・`load` に読み書きの両方で依存するので、出すなら状態は `page.js` に残して関数だけを移す（第二候補）。分けたファイルは上の表の `server.py` の行の配る path に足し（`text/javascript; charset=utf-8`）、`index.html` で `page.js` より先に読み、`progress_page_harness.js` は両方を順に評価する。
- `server.py`: 第一候補は `Cache`（世代番号を含む。§6）を `progress_cache.py` に。次が `default_fetch`・`read_git`・`read_label_sections`（取得の組み立て）。
- どちらも、判定を画面に戻して行数を減らすこと（server の JSON を読まずに JS で決め直すこと）はしない。

## 8. 制約

- 書き込みは §6 の 1 本だけ。他の書き込み（ラベル・コメント・編集）は持たない
- 1 ファイル 300 行以内（見込み: `server.py` 204 → 約 240、`progress_tree.py` 201 → 約 180（移す分を引く）、`progress_work.py` 約 150、`page.js` 約 260）。常時読み込みのファイルに記述を足さない
- テストは `scripts/tests/test_progress_*.py`。fixture と差し込みの runner だけで動き、ネットワーク・git を使わない。**追加分を含めて合計 1 秒未満**（いまは 37 件で 0.23 秒）

## 9. 判定（validation。実データは omron-sinicx/delta-clip-dev。閲覧のみ: close の実走は下流で行わない）

fixture（`progress_fixture.py`）: `NOW` を固定し、`built()` は既定で `now=NOW`・基準あり・PR 0 件を渡す。既存の `BRANCHES` は、`fix/12-x`・`survey/756-i770` を「基準に無く NOW − 3 日」の tip にして渡す（既存の V3 の「#12・#770 が作業中」を保つ）。
カード用の issue は既存の `ISSUES` に混ぜず **`CARD_ISSUES`**（`built_cards()`）に分ける（194 の W1〜W5 の手で数えた期待値を変えない）。`CARD_ISSUES` は `ISSUES` の複製に下の (e)〜(m) を足し、(h) の `updatedAt` を書き換えたもの。中身:
(e) open の epic #1 の下の open の task #150 と子 #151（closed）→ 完了扱い、(f) open の根の epic #160 と子 #161（closed）→ 完了扱い、
(g) refs: `fix/12-x` は基準に無く NOW − 3 日 → #12 作業中、`survey/756-i770` は基準に含まれる・open の PR あり → #770 作業中、
`feature/13-y` は基準に無く NOW − 20 日 → 作業中でない、`feature/14-z` は NOW − 2 日だが MERGED の PR の head と同じ oid → 作業中でない、
**境界**: `feature/51-a` はちょうど NOW − 14 日 → 作業中、`feature/97-b` は NOW − 14 日 − 1 秒 → 作業中でない、`feature/96-c` はローカルが基準に含まれリモートが基準に無く NOW − 1 日 → 作業中（ref ごとの判定）、
(h) #97 の `updatedAt` が NOW − 40 日 → 30日動きなし、#95 も NOW − 40 日 → 子 #96 が新しくても付く（自分の `updatedAt` だけ）、**境界**: #91 はちょうど NOW − 30 日 → 付かない、#92 は NOW − 30 日 − 1 秒 → 付く、
(i) PR: `headRefName` に番号の無い open の PR 1 本（`unlinkedOpenPrs` に出る）、fork の PR 1 本（`isCrossRepository`。結び付かない）、
(j) open の epic #170 と子 task #171（closed）と孫 #172（open）→ #170 は完了扱いで隠れ、#172 が親なしの群に `liftedFrom: 171` で出る、
(k) 基準が無い refs → `working`・`workingBelow`・`summary.working`・`summary.next` が全部 None で帯、
(l) open の epic #180 の子が完了扱いの task #181（子 #182 は closed）だけ → #180 に chip「子は全部完了扱い」、異常でない、
(m) `updatedAt` が `…T15:30:00Z`（JST では翌日）のもの 1 件と前年の日付のもの 1 件（K6 の日付の表示）。

既存テストで期待値を書き換えるもの（手で数えた新しい値）: `test_progress_tree.py:32` の `taskBranches` の検査 → `workingBelow`（#756 が真）。
`test_progress_view.py:128-135` の小さな木（open の epic #1 の子が closed の task #2 だけ、open の task #5 の子が closed の #6 だけ）→ #1・#5 は完了扱いで消え、期待 `[(1,0,None),(4,1,None)]` は `[(4,0,None)]`。
その他の 194 の W1〜W5 は `ISSUES` を変えないので回帰でそのまま通ること。

| # | goal の項目 | テスト（fixture） | 実データ（delta-clip-dev） |
|---|---|---|---|
| W1 | カード型・テキスト圧（K1〜K8） | W7 の DOM 検査で K1・K4・K6、Python の静的な検査で K2・K3・K5〜K8 | W7 の DOM 検査を下流の `view` で 1 回走らせ K1・K4 を機械的に照合。ブラウザで 1 回開き K3・K5〜K8 と 375px 幅で横スクロールが出ないことを目で照合して項目ごとに記録。画面写しを残す |
| W2 | メタ情報 5 種 | `createdAt`・`prs`（A・B・C の和、重複除き、fork はブランチ名だけ除く）・`lastCommit`・`steps`（task: #2 の feature が closed 2 / total 5（#13・#14・#15・#16・#51。closed は #15・#16）等、手で数えた値）・epic の帯が出さない task を数えない（`closed=False` で #80・#110・#171 が入らない）・(m) の日付の文字列（`TZ=UTC` の node） | 全 open の `steps`・`lastCommit` を、`build` を使わない別のコードで ref と issue から数えた値と一致。PR の結び付きの件数（343/348 前後）を記録 |
| W3 | 作業中 | (g) の全本と境界 2 本の期待どおり。PR 取得の失敗と (k) で `work_ok` が偽 | 同じ `now` で独立に数えた集合と一致し、各件の根拠（PR か tip の日付）を示す。§4-1 の外れるべき 10 件が外れる。**結び付かない open の PR の件数と番号を出し、それを「作業中」の規則の誤判定として判定に含める**（#208 の前は #118 の 1 件） |
| W4 | 完了扱いで隠す | (e)(f)(j)(l) が期待どおり。完了扱いが `closed=False` の `view` に現れず（(j) の #172 は持ち上がって出る）、`count`・`progress`・要約に寄与しない。`closed=True` では出て chip「完了扱い」 | 完了扱いの集合が独立に数えた集合（いま 7 件）と一致し、`closed=False` の `view` に 0 件 |
| W5 | 異常と close | #30・#71・#72 が `anomaly`。§6 の順 1〜8 の各外れ（Origin が無い・`null`・ポートだけ違う、Content-Type に charset 付きは通る、`Content-Length` 無し 411・1025 で 413、`number: true` で 400、NOT_FOUND で 409・その他の失敗で 502（exit 0 の `errors`・形の違う応答を含む）、close の gh が起動できない・timeout で 502 と無効化、全応答に frame の 2 ヘッダ、別 repo の子で 409、他の path の POST で 405）で期待のコード。runner に渡る argv が `gh issue close N --repo o/r --reason not planned` だけ。`gh issue close` を含むファイルが `progress_close.py` だけ。世代番号: 取得中に close すると、その取得の結果を新しいとみなさない。画面は 1 回目の押下で送らず、2 回目で method・headers・body のそろった POST を送る | **下流: 異常の件数と番号（いま 6 件）は実測。close は前提（閲覧のみ）により下流では行わず、「検証不能（上流で代替）」と項目を分けて記録する。** 上流（このテンプレート）で使い捨ての issue を `/issue-create` で 1 件作り（`epic` ラベル・子 0 件）、ブラウザから close して状態が変わることを 1 回確かめる。**上流への書き込みなので validation の前にユーザーに一言確かめる** |
| W6 | 30日動きなし | (h) の 4 件と境界 | 同じ `now` で独立に数えた件数と一致（task #200 の時点で 112 件）。完了扱いでないものは `closed=False` の `view` に全件出る（印で消えない） |
| W7 | 一括の手応え（B1〜B3） | node で `page.js` を動かし、段 0〜3 で `aria-pressed` が 1 つだけ true、絞り込み中と行を手で開けた後は全部 false、`#bulk-state` の文言と N が見えている開いた `<details>` の数と一致、行を開けると（描き直しなしで）「手で変えた 1 行」、同じボタンの再押下で「再適用」が付き k が 0 に戻る。**node が無い環境では SkipTest に理由を書いて skip**（静的な検査は Python 側なので外れない） | ブラウザで 4 ボタンを押して見た目が変わることを記録 |
| W8 | 取得時間（記録のみ。方向なし） | — | 取得 1 回の壁時計・PR のページ数・JSON の大きさを、変更前（issue 8.5 秒）と並べて記録 |

検出力の確認（validation で実測。各変異で該当のテストが落ちること）: `WORKING_DAYS` を 15 に（境界の NOW − 14 日 − 1 秒が作業中になる）、`<=` を `<` に（ちょうど 14 日が外れる）、`STALE_DAYS` を 31 に、`completedLike` の `>= 1` を `>= 0` に、Origin の比較を外す、epic の帯の集計で `shown` を外す、B1 で `aria-pressed` を全部 true にする。

## 10. 範囲外

- close 以外の書き込み。close の理由を選ばせること
- 子の無い issue 層の扱いの変更
- 開閉の状態を URL に持つこと（194 §7 のまま）
- Host を書き換える reverse proxy・https の tunnel 越しの利用（既存の Host の検査で 403 になる）

## 変更履歴

- 2026-10-24: 初版
- 2026-10-24: auto-reviewer（#201）。30日動きなしを自分の `updatedAt` だけに戻す（goal の範囲を狭めない）、完了扱いの下の open の孫の持ち上げを明記、基準が無いときと close の検査で issue が null のときの扱い、summarize の実体、`index.html` の行番号、fixture (j)(k)
- 2026-10-24: auto-reviewer の警告を反映し、close に添えるコメントをやめた（前提の例外は close だけ）
- 2026-10-24: /review 8 観点を反映。`gone` を 1 か所で決める、依存の向き（`progress_work` へブランチ名・段の規則を移す）、`steps` の形、`rules` を server から返す、`page.js` に分ける（確定）、`work_ok`（git・基準・PR）で要約まで不明にする、結び付かない open の PR と fork の PR、ref ごとの判定、境界（14 日は含む・30 日ちょうどは付かない）と境界の fixture、`now` を必須に、JST の日付、K1 を `<summary>` の構造に、chip の順と形、close の検査（Origin 無し・`null`、Content-Length、bool、`-F`、NOT_FOUND、確認の失敗）、世代番号による無効化、確認行の focus・Esc・preventDefault、B1〜B3 の食い違いと再適用、epic の帯は出す task だけ、子が全部完了扱いの親、既存テストの書き換え箇所、`CARD_ISSUES` に分ける、W5 の下流は検証不能として分けて記録
- 2026-10-24: bug #208。§3-1 の案 B（open の PR だけ本文の行頭の `Refs #N`）を A に足す。§3-2 に本文の取得、K2・§5-2・W2・W3 の文言を A・B・C に合わせた
- 2026-10-25: bug #216（Integrity Review 2026-10-25T0642）。順 7 の gh を実行できない・timeout を 502 と順 8 の無効化に、順 6 の exit 0 の `errors` を 502（message）に、全応答に `X-Frame-Options: DENY`・`frame-ancestors 'none'` を足した。/review を反映し、timeout と起動できないときの文言を分け、`send_error` の応答にも付け、形の違う応答を 502 にした
- 2026-10-25: docs #217（Integrity Review 2026-10-25T0642）。§7 の `build` の引数に必須の `unmerged` を足した（`progress_tree.py:42`）
- 2026-10-25: refactor #218（Integrity Review 2026-10-25T0642）。§7 に判定の置き場所（`dropped`・`needs`・`view.filtering`・`rules.staleDays`、取得の失敗の包み方）と `page.js` の分割方針を足した。挙動は変えない（JS の `trim` と Python の `strip` で落とす空白が違った分だけ、画面の「絞り込み中」が server の判定に揃う）
