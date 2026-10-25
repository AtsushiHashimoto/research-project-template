# Issue #212: spec: 進捗一覧のサーバーの起動コマンドとポートの固定

## メタ情報

- 作成日: 2026-10-24
- ステータス: completed
- 親: task #211 / epic #210
- 前の仕様: `.spec/issues/176-progress-server.md`（サーバー本体。§6「GET 以外は 405」・Host 検査は**そのまま保つ**）、
  `.spec/issues/201-progress-cards.md`（close の経路。変えない）

## 1. 目的

進捗一覧のサーバーは手で `python3 scripts/progress/server.py --port <番号>` と起動する（既定 8765、`server.py:252`）。
立っているかを確かめる口が無く、devcontainer に `portsAttributes` が無いので、手元の 8765 が使われていると
VS Code が黙って 8766 にずらす（2026-10-23 に画面が真っ黒になった）。
起動スクリプト 1 本で「確かめる → 無ければ立てる → URL を出す」を行い、番号を repo ごとに固定し、ずれを禁じる。

## 2. 前提（epic #210 の原文。`bash scripts/read-premises.sh 212`）

- 「このweb serverの状態を確認し、まだ立っていなければ(portがgit containerのhostやremote接続元のlocal重複しないように調整しながら)serverを立てるskill(コマンド?)を作ってtemplate-contributeしません？」（2026-10-24）
- ポートは「repo ごとの固定番号＋ずれ禁止」（2026-10-24、選択肢から。説明: repo 名から 18000 番台の番号を決め、上書きもできる。devcontainer の portsAttributes で requireLocalPort を指定し、VS Code が黙って 8766 などへずらす代わりにエラーを出す）
- 形は「スクリプト＋薄い skill」（2026-10-24、選択肢から。実体は scripts/progress/ の起動スクリプト、/progress はそれを呼ぶだけ）
- 背景: 2026-10-23、8765 で起動したところ手元の 8765 が使われていて VS Code が 8766 に黙ってずらし、ユーザーが「8765->8766 とても怪しい。」と気づくまで画面が真っ黒だった。コンテナの中からはホストのポートも接続元のポートも見えない（2026-10-24 実測: ゲートウェイ 172.18.0.1 の 8765 は connect 拒否）
- 進め方は既定どおり task で（epic #192 の「規定どおり task で」を継続）
- ユーザーは token の量とテスト時間が増える変更を嫌う（skill は薄く）

前提との関係: 「重複しないように調整しながら」は、2 つ目の前提（固定番号＋ずれ禁止）で「自動でずらさず、衝突したら理由と上書きの方法を出す」と具体化されている。
本仕様は**自動で別の番号を選ばない**（選ぶと URL が repo ごとに定まらず、2026-10-23 の失敗と同じ形になる）。
コンテナの中から手元のポートは見えない（前提 4）ので、手元の衝突は VS Code の `requireLocalPort` に任せる（§4-3）。

## 3. 未確定の解消（task #211 の `## 未確定` の 4 行）

### 3-1. 番号の式・範囲・上書きの置き場所

- **範囲は 18000〜18999（1000 個）。** 式は `18000 + zlib.crc32(<repo 名>.lower().encode()) % 1000`。
  - `crc32` を使うのは Python の `hash()` が起動ごとに変わる（`PYTHONHASHSEED`）ため。標準ライブラリだけで決まる。
  - 実測（2026-10-24）: `research-project-template` → **18415**、`delta-clip-dev` → **18218**、`weavenet2` → 18356。
- **repo 名**は `git remote get-url origin` の最後の要素（`/` と `:` の両方で区切る。`git@github.com:o/r.git`・`https://github.com/o/r/` のどちらでも `r`。末尾の `/` は外す）から `.git` を外したもの。
  - ★ ディレクトリ名（作業ディレクトリ・主 worktree のどちらも）を使わない。devcontainer ではどの repo も `/workspace` なので全部 `workspace`（18809）になり、番号が同じになる。
  - **origin が無い・名前が空になる・git 自体が失敗する**ときは式を使わず、終了コード 2 で「`git config progress.port <18000〜18999>` で番号を決める」と出す（下の上書きがあればそちらを使うので止まらない）。
- **上書きは 2 段**（上が優先）:
  1. `--port <番号>`（その 1 回だけ）
  2. `git config progress.port <番号>`（その clone に残る。追跡されるファイルを汚さない。worktree 間で共有される）
- **上書きした番号も 18000〜18999 に限る。** 範囲外、または整数として読めない値なら立てずに終了コード 2 で理由を出す（式の番号に黙って戻さない。R-D01）（範囲外は §4-3 の `requireLocalPort` が掛からず、黙ったずれが戻るため）。
  - 読み方は `git config --get progress.port` の文字列を正規表現 `^[0-9]+$` で照合してから `int()`（`git config --int` は `18k` を 18432 と読むので使わない。Python の `int()` だけだと `+18000`・`18_000` を通す）。
- 環境変数は採らない（シェルを開き直すと消え、衝突の回避が続かない。置き場所を 1 つにする）。

### 3-2. 止め方・ログの置き場所

- **止め方**: `python3 scripts/progress/ensure.py --stop`。その番号のサーバーが**この repo のもの**（§4-1 の判定 B）のときだけ、
  `/api/identity` が返す `pid` に `SIGTERM` を送り（送る直前に、`/proc/<pid>/cmdline` に `server.py` と `--port` `<番号>` が含まれることを確かめる。違えば送らずに終了コード 2。identity を読んでから送るまでの pid の再利用と、identity を偽る別のプロセスを止めないため）、応答が無くなるまで最大 5 秒待つ。この repo のものでなければ（§4-1 の C）何も止めずに終了コード 2。立っていなければ（A）「立っていない」と出して終了コード 0。5 秒で応答が無くならなければ終了コード 1。
  - pid ファイルは持たない（古い pid ファイルが別のプロセスを指す事故を避ける。生きているサーバー自身に聞く）。
  - `pkill -f` 等の名前での停止はしない。
  - 作り直し（コードを更新した後）は `--stop` の後にもう一度呼ぶ。`--restart` は作らない（KISS）。
- **ログ**: `<git common dir>/progress-server.log`（`git rev-parse --path-format=absolute --git-common-dir`。
  主 repo なら `.git/progress-server.log`）。**追記**し、起動のたびに `--- <JST 時刻> pid <子の pid> port <番号>` の区切りの行を書く。
  失敗時に出す末尾は、その呼び出しの区切りの行より後だけ（同時に 2 回呼ばれても、他方の出力を原因として見せない）。
  上書きにしないのは、同時起動で切り詰めが起き、直前の失敗の記録も消えるため。ファイルが 1 MB を超えていたら起動の前に空にする。
  - ここに置くのは、worktree で共有され・追跡されず・`git status` に出ず・worktree を消しても残るため。`data/local/` は worktree ごとで、主 repo に無いことがある。

### 3-3. `requireLocalPort` が効かない環境

`requireLocalPort` は VS Code（Dev Containers・Remote）の転送にだけ掛かる。それ以外ではスクリプトの側で手元の衝突を検出できない（前提 4）。

| 接続 | 扱い |
|---|---|
| VS Code の自動転送 | §4-3 の `portsAttributes` が効く（効くかは #214 で実測） |
| `ssh -L` | 既定では手元で bind できなくても**接続を続ける**（`ExitOnForwardFailure` の既定は no。出典 §8）。起動スクリプトの出力に 1 行、`ssh -o ExitOnForwardFailure=yes -L <番号>:127.0.0.1:<番号>` を添える |
| Codespaces・ブラウザの VS Code 等 | 転送先の URL が `127.0.0.1` にならない。**範囲外**（§7）。出力の URL はコンテナの中での URL だと明記する |

- 出力の URL はつねに `http://127.0.0.1:<番号>/`（コンテナの中の番号）。転送で手元の番号がずれた場合は URL が誤りになる。これを防ぐのが §4-3 で、防げない接続は上の表のとおり利用者が同じ番号で転送する。

### 3-4. 下流の `.devcontainer/` 取り込み（下流 #970）とぶつからないか → **ぶつからない**

- 下流 #970 が「残す下流の差分」としているのは `post-create.sh` の 3 箇所と `install-claude-native.sh` の 1 行だけ
  （下流 #970 本文「残す下流の差分」、下流 `.claude/CLAUDE.md` の表）。本仕様が触るのは `cpu/devcontainer.json`・`gpu/devcontainer.json` だけで、
  下流の `devcontainer.json` の差分（`name`・コメント・`initializeCommand`。2026-10-24 に `gh api` で比較）は #970 で上流版に置き換わるもの。
  したがって `portsAttributes` は #970 の取り込みにそのまま乗る。
- 起動スクリプト・`server.py`・skill は `/template-sync` で下流に届く（`.devcontainer/` とは別の経路）。
- **#214 で下流を測る時点で #970 が済んでいなければ**、下流の作業ツリーの `devcontainer.json` 2 本に同じブロックを足して rebuild して測り、
  コミットはしない（下流への反映は #970 が担う）。どちらで測ったかを #214 の判定に書く。

## 4. 仕様

### 4-1. 起動スクリプト `scripts/progress/ensure.py`

```
python3 scripts/progress/ensure.py [--port N] [--stop]
```

1. 番号を §3-1 で決める。範囲外 → 終了コード 2。
2. `127.0.0.1:<番号>` に TCP で connect し、つながれば `GET /api/identity`（Host: `127.0.0.1:<番号>`、timeout 2 秒）を送る。結果を 3 つに分ける。

| 判定 | 条件 | 動き | 終了コード |
|---|---|---|---|
| **A. 立っていない** | connect が拒否される（`ConnectionRefusedError`） | 背景で立て（下記）、`/api/identity` が B になるまで 0.2 秒おきに最大 10 秒待ち、URL を出す | 0（子が先に終了したら、もう一度判定する。B なら 0（同時に呼ばれて別の呼び出しが立てた場合）、C なら C と同じく 2。10 秒で B にならないか、子が終了して A のままなら 1。10 秒で B にならず子が生きていれば、子に SIGTERM を送ってから 1 で終わる（失敗と報告したのに後から立つことを防ぐ）。1 のときはログのその回の区切りより後の末尾 20 行とログのパス、C と同じ上書きの方法を出す） |
| **B. この repo のサーバー** | 200 で JSON、`app == "progress"`、`commonDir` が自分の git common dir と一致（両方を `os.path.realpath` してから比べる） | URL を出すだけ（何も立てない） | 0 |
| **C. 別のものが使っている** | 上のどちらでもない（別の repo の進捗一覧・`commonDir` が null・別のアプリ・HTTP でない・拒否以外の `OSError`・timeout） | 立てない。何が使っているか（別の repo の進捗一覧ならその `commonDir`。404 の本文が `server.py` の `not found` なら「`/api/identity` の無い古い進捗一覧の可能性。そのプロセスを手で止める」。timeout なら「応答なし（別のもの、または高負荷）」。それ以外は「進捗一覧ではない」）と、上書きの方法（`git config progress.port <18000〜18999 の別の番号>` か `--port`）を出す | 2 |

- 同じ repo の別の worktree から呼んでも B になる（`commonDir` は worktree 間で同じ）。
- **git common dir と主 worktree の取り方は `progress_git.py` に 1 関数ずつ置き、`ensure.py` と `server.py` の両方がそれを使う**（B の一致判定が 2 つの書き方の一致に依存しないように。単一情報源）。
- **背景での起動**: `subprocess.Popen([sys.executable, <このファイルの隣の server.py>, "--port", N], cwd=<主 worktree。bare で作業ツリーが無ければ呼んだ worktree の toplevel。`progress_git.start_dir()`>,
  stdin=DEVNULL, stdout/stderr=ログ（追記）, start_new_session=True)`。親は開いたログを Popen の後に閉じる。主 worktree で立てるのは、呼んだ worktree が後で消されても止まらないため。
- `--stop` は §3-2。
- 出力（標準出力）: 成功時は 1 行目に URL だけ、2 行目に「（コンテナの中の番号。VS Code 以外で転送するなら `ssh -o ExitOnForwardFailure=yes -L <番号>:127.0.0.1:<番号>`）」の 1 行（§3-3 の明記はこの行が担う）。失敗の理由は標準エラーへ。

### 4-2. サーバーに足すもの（`scripts/progress/server.py`）

- `GET /api/identity` → `{"app": "progress", "commonDir": <起動時の git common dir の絶対パス>, "pid": <os.getpid()>}`。
  - `commonDir` は起動時に 1 回だけ `git rev-parse --path-format=absolute --git-common-dir` で求める。失敗したら `null`（起動スクリプトは C と判定する）。
  - Host 検査（`loopback()`）は他の GET と同じく掛ける。GitHub への取得は起こさない（`cache.get` を呼ばない）。
- `--port` の既定は §3-1 の番号に変えない（`server.py` を直接呼ぶ使い方は残し、既定 8765 のまま。repo の番号は `ensure.py` だけが決める。単一情報源）。
  **直接起動は §4-3 の保護の対象外**（8765 は範囲外なので黙ったずれが起こりうる）。README・skill は `ensure.py` だけを案内し、`server.py` の docstring に「通常は ensure.py から起動する」と 1 行書く。

### 4-3. devcontainer（`.devcontainer/cpu/devcontainer.json`・`gpu/devcontainer.json`）

```jsonc
"portsAttributes": {
  "18000-18999": { "label": "progress", "requireLocalPort": true }
}
```

- 範囲のキー（`"40000-55000"` の形）と `requireLocalPort`（"When true, a modal dialog will show if the chosen local port isn't used for forwarding."）は
  dev container の JSON schema の記述（出典 §8）。**手元の番号が使われているときに VS Code が転送そのものをやめるのか、ずらしたうえで dialog を出すのかは
  出典に書かれていない** → #214 で実測して判定する。
- `forwardPorts` は書かない（番号が repo ごとに違い、`devcontainer.json` は全 repo 共通のため）。自動転送に任せる。
- この範囲の他のプロセスにも掛かる（副作用として受け入れる。18000 番台を使う他のアプリは少ない）。

### 4-4. skill `/progress`（`.claude/skills/progress/SKILL.md`）

- frontmatter `metadata.harness: shared`。本文は agent-runtime の定型 2 行と、次の 2 行と、JSON の取り方の 2 行だけ:
  `python3 scripts/progress/ensure.py $ARGUMENTS` を実行し、標準出力（URL と注記の 2 行）か標準エラーの理由をそのまま伝える。止めるときは `--stop`。
  JSON の取り方（epic #210 の前提 2026-10-25「では、/progress の説明に JSON の取り方も書いて」）: agent が中身を読むときは出た URL に続けて `curl -s <URL>api/tree.json` で取ること（`view` が表示中の木）と、絞り込みの query（`?closed=1` で close 済みも含める・`?label=<ラベル>`・`?q=<文字列>` は 200 文字まで。`&` で組み合わせる）。文言は SKILL.md が正（ここは要約）。
- `.claude/rules/template/skills.md` に 1 行足す。README の `server.py` の 1 行（`README.md:124`）を `/progress`（`ensure.py`）に置き換える。
- 常時読み込みのルールファイルには何も足さない。

## 5. テスト（`scripts/tests/test_progress_ensure.py`。`python3 -m unittest` で走る既存の枠）

**軽く保つ**: 判定は関数に分け、接続結果・git の値・起動を差し込んで確かめる。**実際に listen するのは 2 件だけ**。ネットワーク（GitHub）は使わない。
git は repo 自身での `rev-parse`・`worktree list` だけ（176 §6 の「git を使わない」の例外。E5 で実物のサーバーが自分の common dir を求めるため。E1〜E3 は git の値を差し込み、git を呼ばない）。全体で 3 秒未満（176 §6 の「progress のテストは合計 1 秒未満」をこのファイルだけ超えるので、#213 で所要時間を実測して PR に書く。超えるなら E5 の待ちの間隔を詰める）。

| # | 確かめること | listen |
|---|---|---|
| E1 | 式: `research-project-template` → 18415、`delta-clip-dev` → 18218、大文字を混ぜても同じ、範囲内 | なし |
| E2 | 上書きの順（`--port` > `git config progress.port` > 式）と範囲外・整数でない値（`abc`・`18k`・`+18000`）の拒否（終了コード 2）。origin の URL の書式（scp 形式・https・末尾 `/`）から同じ repo 名が出る。origin が無い・名前が空なら（上書きが無ければ）終了コード 2 で、`workspace` 等のディレクトリ名を使わない | なし |
| E3 | 判定の分岐: 拒否 → A、一致 → B（symlink 越しのパスでも `realpath` で B）、別の `commonDir`・`commonDir` が null・`app` 違い・JSON でない・timeout → C。C の理由に `git config progress.port` が出る | なし |
| E3b | A の後半と `--stop`（起動・時計・接続結果を差し込む）: 子が先に終了 → 再判定で B なら 0・C なら 2、10 秒で B にならない → 子に SIGTERM を送って 1（理由にログのパス）。`--stop` は A なら 0、C なら 2、cmdline が合わなければ送らずに 2、5 秒で止まらなければ 1 | なし |
| E6 | `cpu/devcontainer.json`・`gpu/devcontainer.json` の `portsAttributes` のキーが式の範囲（`ensure.py` の定数）と一致し、`requireLocalPort` が true（範囲を 3 箇所に書くので、片方だけ変わる黙ったずれを検出する。jsonc なのでコメントを外してから読む） | なし |
| E4 | **番号が別のものに使われている**: 何にも 501 を返す HTTP サーバー（`BaseHTTPRequestHandler` に `do_GET` を持たせないもの）を立てた番号で呼ぶと、起動を呼ばず終了コード 2 | 1 |
| E7 | 作業ディレクトリ（`progress_git.start_dir`。`git` の出力を差し込む）: 主 worktree があればそれで toplevel を呼ばない、bare なら呼んだ worktree の toplevel。`main()` が `start_dir()` の値を `ensure()` に渡す | なし |
| E5 | **立っていない → 立てる → 立っている → 止める**: 空きの番号で呼ぶと `server.py` が立ち URL が出る。もう一度呼ぶと同じ `pid` で起動を呼ばない。`--stop` で connect が拒否されるようになる | 1 |

- E4・E5 は範囲の検査を通さない関数の口で空きの番号（`bind(("127.0.0.1", 0))`）を使う（固定番号だとテストを回すマシンで衝突する）。
- E5 は**ログのパスを関数の引数で一時ディレクトリに向ける**（本物の `.git/progress-server.log` に書かない）。途中で落ちても残らないよう、`tearDown`（`addCleanup`）で起動した pid に SIGTERM を送る。
- `/api/identity` の Host 検査（別名なら 403）と `cache.get` を呼ばないことは、既存の `test_progress_server.py` の Host の検査に 1 項目足して確かめる（listen を増やさない）。
- goal の成功条件の 3 つの場合との対応: 立っていない＝E3・E3b・E5、この repo のサーバー＝E3・E5、番号が別のもの＝E3・E4（手元でのずれ＝E6 と V3）。

## 6. 判定（validation #214）

| # | 何 | 満たす条件 |
|---|---|---|
| V1 | scripts/tests の E1〜E6（E3b を含む） | 全部 PASS |
| V2 | 下流 delta-clip-dev の devcontainer で `/progress`（または `ensure.py`）を呼ぶ | 18218 の URL が出て、手元のブラウザで一覧が開ける。2 回目は同じ URL で新しいプロセスを立てない |
| V3 | 手元の 18218 を先に使っておいて（手元で `python3 -m http.server 18218` 等）同じことをする | **満たす**: 手元で別の番号への転送が起きない、または起きても dialog が出る（黙らない）。**満たさない**: dialog なしで別の番号に転送される（2026-10-23 と同じ）。実際に起きたこと（dialog の文言・Ports view の Forwarded Address）を記録する |
| V4 | コンテナの中の番号を先に使っておく | 立てずに理由と上書きの方法が出る（終了コード 2） |

## 7. 範囲外

- 手元（接続元）のポートの検出（コンテナから見えない。前提 4）
- Codespaces・ブラウザの VS Code の転送 URL
- 衝突時に別の番号を自動で選ぶこと（§2）
- `server.py` を直接起動したときのずれの防止（§4-2。範囲外の 8765 のまま）
- サーバーの自動起動（postStartCommand 等）

## 8. 出典

- dev container の JSON schema `portsAttributes`（範囲のキー・`requireLocalPort`・`onAutoForward` の説明）:
  https://github.com/devcontainers/spec/blob/main/schemas/devContainer.base.schema.json （2026-10-24 取得）。
  https://containers.dev/implementors/json_reference/ は `portsAttributes` が「port number, "host:port" value, range, or regular expression」を取るとだけ書く
- `ExitOnForwardFailure`（"The argument must be yes or no (the default)."）: https://man.openbsd.org/ssh_config

## 変更履歴

- 2026-10-24: 作成
- 2026-10-24: auto-reviewer（`.spec/issues/212-auto-decisions.md`）。origin の URL の区切り、整数でない上書き値、`--stop` の A と待ち切れの終了コード、子が先に終了したときの再判定と上書きの方法の表示、`commonDir` の比較の正規化、テストの所要時間の記録を足した
- 2026-10-24: /review（PR #219）。origin が無いときにディレクトリ名へ戻さず終了コード 2、上書き値の読み方（`^[0-9]+$`）、`--stop` の cmdline 確認、ログを追記＋区切りの行、待ち切れで子を止める、古い `server.py` と timeout の文言、common dir と主 worktree を `progress_git.py` に 1 か所、bare の主 worktree、直接起動は保護の対象外、テスト E3b・E6 とログの差し込み・後片付け、V3 の境界を足した
- 2026-10-24: 仕様整合の照合（PR #219）。出力の 2 行目に「コンテナの中の番号」の注記と ssh の 1 行を置き、skill が 2 行とも伝えるようにした
- 2026-10-25: docs #227（Integrity Review 2026-10-25T1507、#226）。§4-4 の skill 本文に JSON の取り方の 2 行（epic #210 の前提 2026-10-25）を足し、§5 E4 のサーバーを実際のテストどおり 501 を返すものにした
- 2026-10-25: refactor #228（Integrity Review 2026-10-25T1507、#226）。作業ディレクトリの決め方を `progress_git.start_dir()` にし、テスト E7（bare の fallback と `main()` の配線）を足した
