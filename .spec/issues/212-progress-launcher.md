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
- **repo 名**は `git remote get-url origin` の最後の要素（`/` と `:` の両方で区切る。`git@github.com:o/r.git`・`https://github.com/o/r/` のどちらでも `r`。末尾の `/` は外す）から `.git` を外したもの。origin が無ければ**主 worktree**
  （`git worktree list --porcelain` の 1 本目）のディレクトリ名。
  - ★ 作業ディレクトリ名を使わない。devcontainer ではどの repo も `/workspace` なので全部 `workspace` になり、番号が同じになる。
- **上書きは 2 段**（上が優先）:
  1. `--port <番号>`（その 1 回だけ）
  2. `git config progress.port <番号>`（その clone に残る。追跡されるファイルを汚さない。worktree 間で共有される）
- **上書きした番号も 18000〜18999 に限る。** 範囲外、または整数として読めない値（`git config progress.port abc` 等）なら立てずに終了コード 2 で理由を出す（式の番号に黙って戻さない。R-D01）（範囲外は §4-3 の `requireLocalPort` が掛からず、黙ったずれが戻るため）。
- 環境変数は採らない（シェルを開き直すと消え、衝突の回避が続かない。置き場所を 1 つにする）。

### 3-2. 止め方・ログの置き場所

- **止め方**: `python3 scripts/progress/ensure.py --stop`。その番号のサーバーが**この repo のもの**（§4-1 の判定 B）のときだけ、
  `/api/identity` が返す `pid` に `SIGTERM` を送り、応答が無くなるまで最大 5 秒待つ。この repo のものでなければ（§4-1 の C）何も止めずに終了コード 2。立っていなければ（A）「立っていない」と出して終了コード 0。5 秒で応答が無くならなければ終了コード 1。
  - pid ファイルは持たない（古い pid ファイルが別のプロセスを指す事故を避ける。生きているサーバー自身に聞く）。
  - `pkill -f` 等の名前での停止はしない。
  - 作り直し（コードを更新した後）は `--stop` の後にもう一度呼ぶ。`--restart` は作らない（KISS）。
- **ログ**: `<git common dir>/progress-server.log`（`git rev-parse --path-format=absolute --git-common-dir`。
  主 repo なら `.git/progress-server.log`）。起動のたびに上書きする。
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
| **A. 立っていない** | connect が拒否される | 背景で立て（下記）、`/api/identity` が B になるまで 0.2 秒おきに最大 10 秒待ち、URL を出す | 0（子が先に終了したら、もう一度判定する。B なら 0（同時に呼ばれて別の呼び出しが立てた場合）、C なら C と同じく 2。10 秒で B にならないか、子が終了して A のままなら 1。1 のときはログの末尾 20 行とログのパス、C と同じ上書きの方法を出す） |
| **B. この repo のサーバー** | 200 で JSON、`app == "progress"`、`commonDir` が自分の git common dir と一致（両方を `os.path.realpath` してから比べる） | URL を出すだけ（何も立てない） | 0 |
| **C. 別のものが使っている** | 上のどちらでもない（別の repo の進捗一覧・別のアプリ・HTTP でない・timeout） | 立てない。何が使っているか（別の repo の進捗一覧ならその `commonDir`、それ以外は「進捗一覧ではない」）と、上書きの方法（`git config progress.port <18000〜18999 の別の番号>` か `--port`）を出す | 2 |

- 同じ repo の別の worktree から呼んでも B になる（`commonDir` は worktree 間で同じ）。
- **背景での起動**: `subprocess.Popen([sys.executable, <このファイルの隣の server.py>, "--port", N], cwd=<主 worktree>,
  stdin=DEVNULL, stdout/stderr=ログ, start_new_session=True)`。主 worktree で立てるのは、呼んだ worktree が後で消されても止まらないため。
- `--stop` は §3-2。
- 出力（標準出力）: 成功時は 1 行目に URL だけ（skill が拾う）、2 行目に §3-3 の ssh の 1 行。失敗の理由は標準エラーへ。

### 4-2. サーバーに足すもの（`scripts/progress/server.py`）

- `GET /api/identity` → `{"app": "progress", "commonDir": <起動時の git common dir の絶対パス>, "pid": <os.getpid()>}`。
  - `commonDir` は起動時に 1 回だけ `git rev-parse --path-format=absolute --git-common-dir` で求める。失敗したら `null`（起動スクリプトは C と判定する）。
  - Host 検査（`loopback()`）は他の GET と同じく掛ける。GitHub への取得は起こさない（`cache.get` を呼ばない）。
- `--port` の既定は §3-1 の番号に変えない（`server.py` を直接呼ぶ使い方は残し、既定 8765 のまま。repo の番号は `ensure.py` だけが決める。単一情報源）。

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

- frontmatter `metadata.harness: shared`。本文は agent-runtime の定型 2 行と、次の 2 行だけ:
  `python3 scripts/progress/ensure.py $ARGUMENTS` を実行し、標準出力の 1 行目の URL か標準エラーの理由をそのまま伝える。止めるときは `--stop`。
- `.claude/rules/template/skills.md` に 1 行足す。README の `server.py` の 1 行（`README.md:124`）を `/progress`（`ensure.py`）に置き換える。
- 常時読み込みのルールファイルには何も足さない。

## 5. テスト（`scripts/tests/test_progress_ensure.py`。`python3 -m unittest` で走る既存の枠）

**軽く保つ**: 判定は関数に分け、接続結果・git の値・起動を差し込んで確かめる。**実際に listen するのは 2 件だけ**。ネットワーク（GitHub）は使わない。
git は repo 自身での `rev-parse` だけ。全体で 3 秒未満（176 §6 の「progress のテストは合計 1 秒未満」をこのファイルだけ超えるので、#213 で所要時間を実測して PR に書く。超えるなら E5 の待ちの間隔を詰める）。

| # | 確かめること | listen |
|---|---|---|
| E1 | 式: `research-project-template` → 18415、`delta-clip-dev` → 18218、大文字を混ぜても同じ、範囲内 | なし |
| E2 | 上書きの順（`--port` > `git config progress.port` > 式）と範囲外・整数でない値の拒否（終了コード 2）。origin の URL の 2 つの書式から同じ repo 名が出る | なし |
| E3 | 判定の分岐: 拒否 → A、一致 → B、別の `commonDir`・`app` 違い・JSON でない・timeout → C。C の理由に `git config progress.port` が出る | なし |
| E4 | **番号が別のものに使われている**: 404 を返すだけの HTTP サーバーを立てた番号で呼ぶと、起動を呼ばず終了コード 2 | 1 |
| E5 | **立っていない → 立てる → 立っている → 止める**: 空きの番号で呼ぶと `server.py` が立ち URL が出る。もう一度呼ぶと同じ `pid` で起動を呼ばない。`--stop` で connect が拒否されるようになる | 1 |

- E4・E5 は範囲の検査を通さない関数の口で空きの番号（`bind(("127.0.0.1", 0))`）を使う（固定番号だとテストを回すマシンで衝突する）。
- goal の成功条件の 3 つの場合との対応: 立っていない＝E3・E5、この repo のサーバー＝E3・E5、番号が別のもの＝E3・E4。

## 6. 判定（validation #214）

| # | 何 | 満たす条件 |
|---|---|---|
| V1 | scripts/tests の E1〜E5 | 全部 PASS |
| V2 | 下流 delta-clip-dev の devcontainer で `/progress`（または `ensure.py`）を呼ぶ | 18218 の URL が出て、手元のブラウザで一覧が開ける。2 回目は同じ URL で新しいプロセスを立てない |
| V3 | 手元の 18218 を先に使っておいて（手元で `python3 -m http.server 18218` 等）同じことをする | VS Code が黙って別の番号にずらさない（dialog が出る／転送しない）。実際に起きたことを記録する |
| V4 | コンテナの中の番号を先に使っておく | 立てずに理由と上書きの方法が出る（終了コード 2） |

## 7. 範囲外

- 手元（接続元）のポートの検出（コンテナから見えない。前提 4）
- Codespaces・ブラウザの VS Code の転送 URL
- 衝突時に別の番号を自動で選ぶこと（§2）
- サーバーの自動起動（postStartCommand 等）

## 8. 出典

- dev container の JSON schema `portsAttributes`（範囲のキー・`requireLocalPort`・`onAutoForward` の説明）:
  https://github.com/devcontainers/spec/blob/main/schemas/devContainer.base.schema.json （2026-10-24 取得）。
  https://containers.dev/implementors/json_reference/ は `portsAttributes` が「port number, "host:port" value, range, or regular expression」を取るとだけ書く
- `ExitOnForwardFailure`（"The argument must be yes or no (the default)."）: https://man.openbsd.org/ssh_config

## 変更履歴

- 2026-10-24: 作成
- 2026-10-24: auto-reviewer（`.spec/issues/212-auto-decisions.md`）。origin の URL の区切り、整数でない上書き値、`--stop` の A と待ち切れの終了コード、子が先に終了したときの再判定と上書きの方法の表示、`commonDir` の比較の正規化、テストの所要時間の記録を足した
