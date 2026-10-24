# Issue #214: validation: 進捗一覧のサーバーの起動コマンドとポートの固定

- 実施日: 2026-10-25 JST
- ステータス: completed
- 完了日: 2026-10-25
- 対象のコード: main = 4d43b52（feature #213、PR #221 マージ後）
- 仕様: `.spec/issues/212-progress-launcher.md` §6（V1〜V4）
- 下流: omron-sinicx/delta-clip-dev の devcontainer の中（チェックアウト `/workspace`、origin `https://github.com/omron-sinicx/delta-clip-dev.git`、
  `git config progress.port` は未設定）。上流の `scripts/progress/ensure.py` を cwd=`/workspace` で呼んだ。下流で走らせた git コマンドは読み取りだけ（`ensure.py` が下流の `.git/progress-server.log` に書いたログは測定後に消した。末尾の節）
- 一回きりの測定。恒常的なテストは増やしていない。測定の出力は #214 のコメントに全文

## 判定: 仕様 §6 の V1〜V4 のうち、満たす 2（V1・V4）、一部満たす 1（V2: コンテナの中は満たす／手元のブラウザは未確認）、未確認 1（V3: VS Code で効くか）、満たさない 0

V3a（指定が文書どおりか）は仕様 §6 に無い補助の確認で、V3 の判定には数えない。

| # | 何 | 結果 | 判定 |
|---|---|---|---|
| V1 | `scripts/tests/test_progress_ensure.py` の E1〜E6（E3b を含む） | **15 件 OK、0.243 秒**（`python3 -m unittest`。progress の全テスト 88 件は unittest の表示で 0.765 秒、`real` で 0.90 秒）。検出力: `ensure.py` に 10 個の変異を 1 つずつ入れ、**10 個とも落ちた**（下の表） | 満たす |
| V2 | 下流で起動する（未起動 → 起動済み） | 1 回目: 終了コード 0、標準出力 1 行目 `http://127.0.0.1:18218/`（式の値 18218 と一致）、2 行目に ssh の注記。`/api/identity` = `{"app": "progress", "commonDir": "/workspace/.git", "pid": 2150749}`。`GET /` 200、`GET /api/tree.json` 200 `application/json`（`repo` = `omron-sinicx/delta-clip-dev`、node 668、`gitError`・`pullsError` は null）。**2 回目: 同じ URL・終了コード 0。`server.py --port 18218` のプロセスは 1 本（pid 2150749）のまま、ログの区切りの行も 1 本のまま**（＝立て直していない）。下流の worktree `worktrees/issue1000` から呼んでも同じ URL で 0（B）。`--stop` で「止めた（pid 2150749）」0、その後 connect は拒否（111）、もう一度 `--stop` で「立っていない」0 | **コンテナの中で満たす。** 手元のブラウザで開けるかは**未確認**（このワーカーは手元のブラウザを持たない。開けるかは VS Code の自動転送で決まり、下流 #970 は待たない） |
| V3a | 上流の `portsAttributes` の指定が文書どおりか | `.devcontainer/cpu/devcontainer.json:30-32`・`gpu/devcontainer.json:28-30` の `{"18000-18999": {"label": "progress", "requireLocalPort": true}}` を、dev container の JSON schema（`devcontainers/spec` main の `devContainer.base.schema.json`、2026-10-25 取得）の `portsAttributes` の部分で `jsonschema.validate` して **2 本とも valid**（ただし schema の patternProperty は `(.+)` を含みどんなキーも通すので、valid 自体の検出力は小さい。検出力があるのは別に確かめたキーの書式と属性名）。キーは範囲の書式 `^\d+(-\d+)?$` に合い、`requireLocalPort` の説明は "When true, a modal dialog will show if the chosen local port isn't used for forwarding." | 満たす（文書の範囲。仕様外の補助の確認） |
| V3b | 手元の 18218 を使っておいたとき VS Code が黙ってずらさないか | **測っていない。** 下流の `.devcontainer/cpu|gpu/devcontainer.json` に `portsAttributes` がまだ無い（`grep` で 0 件。下流 #970 で `.devcontainer/` の取り込みを保留中）。仕様 §3-4 の「下流の作業ツリーに足して rebuild」は、下流の `.devcontainer/` を書き換えないという指示（2026-10-25）により行わない。手元の VS Code の操作も要る | **未確認**（ユーザーの手元の VS Code と、下流 #970 の取り込みが要る）。dialog の後に転送をやめるのか、ずらしたうえで dialog を出すのかは文書に書かれていない（仕様 §4-3）ので、取り込み後に測る |
| V4 | コンテナの中でその番号が別のものに使われている | 下表の 4 通りとも、**立てずに終了コード 2**、理由と `HINT`（`git config progress.port …` か `--port`）を標準エラーに出した。立てていないことは、別のアプリ（C1）ではログの区切りの行が増えないことと `server.py --port 18218` のプロセスが 0 本であること、応答なし（C2）では区切りの行が増えないこと（2 → 2）で確かめた。別の repo・旧版の 2 通りは終了コードと理由だけ（どちらも 18218 以外の番号なので下流のログには関わらない） | 満たす |

### V4 の 4 通り（下流 `/workspace` で呼んだ）

| 何が握っていたか | 判定 | 出た理由 |
|---|---|---|
| `python3 -m http.server 18218`（404 を返す別のアプリ） | C、2 | 「進捗一覧ではない」 |
| listen だけして応答しない socket（18218） | C、2（2.1 秒） | 「応答なし（別のもの、または高負荷）」 |
| 上流の clone を cwd にして立てた進捗一覧（`--port 18990`） | C、2 | 「別の repo の進捗一覧（commonDir …/tpl-tree/.git）」 |
| **メインのセッションが動かしている進捗一覧 127.0.0.1:18765**（`/api/identity` の無い旧版。止めていない） | C、2 | 「`/api/identity` の無い古い進捗一覧の可能性。そのプロセスを手で止める」。呼んだ後も `GET /` は 200 のまま |

★ 測定の手違い: 応答なしの 1 回目は、直前の `http.server` を止めた直後で socket の bind が `Address already in use` に失敗し（`SO_REUSEADDR` 無し）、空いた 18218 で `ensure.py` が本当にサーバーを立てた（終了コード 0、pid 2159885。A の正しい動き）。それを `--stop` で止め、`SO_REUSEADDR` を付けて測り直したのが上表の結果。下流のログの区切りの行が 2 本なのはこの回のため。

18765 は下流の番号（18218）ではないので、下流の本物の衝突ではない（`--port 18765` で当てた）。
★ ただし **18765 は 18000〜18999 の範囲の中にある**ので、下流が `portsAttributes` を取り込むと、手で立てたこのサーバーの転送にも `requireLocalPort` が掛かる（仕様 §4-3 が副作用として受け入れたもの。記録のみ）。

### V1 の検出力（`ensure.py` の変異。1 つずつ入れ、`git init` した写しで `test_progress_ensure` を走らせた）

| 変異 | 結果 |
|---|---|
| なし（基準） | OK |
| 式の法を 1000 → 999 | 落ちた（failures=2） |
| `commonDir` の比較から `realpath` を外す | 落ちた |
| `commonDir` が違っても B にする | 落ちた |
| C でも起動する | 落ちた（errors=2） |
| B でも起動する | 落ちた |
| 10 秒の待ち切れで子を止めない | 落ちた |
| 範囲外の上書きを通す | 落ちた |
| `--stop` の cmdline の確認を外す | 落ちた |
| timeout を A（立っていない）に分ける | 落ちた |
| origin が無いときディレクトリ名 `workspace` を使う | 落ちた |

変異は単体テストが届く関数（式・上書き・判定・待ち・止める）の中だけに入れた。**`start_server` の Popen の引数（`ensure.py:132-134` の `start_new_session`・`stdout=log`・`stdin`）と `main()` の配線には入れていない**ので、ここの検出力は示していない（この 2 つが効いていることは V2 で、別の Bash 呼び出しの後もサーバーが残り終了コードが返ったことでだけ見た）。
`git config progress.port` の上書きは、E2 の差し込み（`fake_git`）でだけ確かめた。下流では未設定の経路だけを通した（下流の `.git/config` に書かないため）。/review のテスト観点が使い捨ての repo で本物の git を通し、設定値 18500 → 18500、壊れた config → 終了コード 2 を確かめた（#214 のコメント）。

## goal の成功条件との対応

| goal の場合 | テスト（V1） | 下流での実地 | 判定 |
|---|---|---|---|
| 立っていない | E3・E3b・E5 | V2 の 1 回目（立てて URL） | コンテナの中で満たす（手元のブラウザは未確認） |
| この repo のサーバーが立っている | E3・E5 | V2 の 2 回目・別の worktree から（URL を出すだけ） | コンテナの中で満たす（手元のブラウザは未確認） |
| 番号が別のものに使われている（コンテナの中） | E3・E4 | V4 の 4 通り | 満たす |
| 手元でのずれ（requireLocalPort） | E6（範囲の 3 箇所の一致） | V3a（文書どおり）／V3b（実際に効くか） | V3a 満たす／**V3b 未確認** |

negative の意味（goal）に照らすと: コンテナの中の 3 つの場合で誤った URL を出す経路は見つからなかった。
**手元でのずれ**は、下流で `portsAttributes` が入っていない現状では**まだ黙って起こりうる**（2026-10-23 と同じ形）。下流 #970 の取り込みと手元の VS Code での測定が済むまで、この項目は判定を出せない。

## 下流に残したもの

- サーバーは全部止めた（18218・18990 とも connect 拒否）。メインのセッションの 18765 は触っていない
- ensure.py が書いた下流の `/workspace/.git/progress-server.log`（区切りの行 2 本）は測定後に消した（測定前は無かった）
