# Issue #212 自動判断ログ

## メタ情報
- 判断日時: 2026-10-24（JST）
- 自動処理: /task-run（auto-reviewer）
- 対象: `.spec/issues/212-progress-launcher.md`（task #211 / epic #210）
- 読んだもの: `.spec/core-rules.md`・`invariants.md`・`known-issues.md`、task #211 本文（`gh issue view 211`。未確定 4 行と子 #212〜#214 を自分で確認）、`scripts/progress/server.py`、`.devcontainer/cpu/devcontainer.json`・`gpu/devcontainer.json`、`.spec/issues/176-progress-server.md`、`README.md:124`、`.claude/rules/template/skills.md`、下流 #970 本文（読むだけ）
- 必読 3 ファイル: 存在し、既定の節もある。**3 ファイルとも「プロジェクト固有」節が未記入で、プロジェクト大前提も未記入なので、既定と epic #210 の前提だけで判断した**（プロジェクト固有の失敗パターンは捕捉できていない）

停止条件: 該当なし

## 判断一覧

### 1. goal・前提との整合

| 項目 | 内容 |
|---|---|
| 判断 | 許可 |
| 理由 | goal の 4 項目に仕様が 1 対 1 で対応する: 起動スクリプト＝§4-1（A/B/C の判定。B は `/api/identity` の `commonDir` で「この repo のものか」まで確かめる）、repo ごとの 18000 番台の固定番号と上書き＝§3-1、`portsAttributes` の `requireLocalPort`＝§4-3、薄い skill＝§4-4。前提 1 の「重複しないように調整しながら」を「自動でずらさない」と読むのは、前提 2（ユーザーが選んだ「固定番号＋ずれ禁止」）が具体化しているもので、goal の範囲を狭めていない（§2 に理由がある）。自動起動（postStartCommand）を範囲外にしたのは goal に無いものを足さないだけで、goal を小さく読んでいない |
| 参照 | task #211「目標の状態」、epic #210 前提 1〜6 |
| 自信度（参考記録） | 85% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 2. 未確定 4 行の解消

| 未確定 | 解消先 | 判定 |
|---|---|---|
| 番号の式・範囲・上書きの置き場所 | §3-1（`18000 + crc32(repo名.lower()) % 1000`、`--port` > `git config progress.port`）。番号 18415・18218・18356 を自分で計算して一致を確認 | 解消 |
| 止め方・ログ | §3-2（`--stop` は生きているサーバーの `pid` に SIGTERM、ログは git common dir） | 解消 |
| `requireLocalPort` が効かない環境 | §3-3（`ssh -L` は `ExitOnForwardFailure=yes` の 1 行、Codespaces 等は範囲外と明記） | 解消 |
| 下流 #970 との衝突 | §3-4。#970 本文の「残す下流の差分」が post-create.sh 3 箇所と install-claude-native.sh 1 行だけであること、下流 `cpu/devcontainer.json` の差分が name・コメント・initializeCommand だけであることを自分で確認 | 解消 |

### 3. 仕様の小さな欠落を直した（goal・前提は変えていない）

| 項目 | 内容 |
|---|---|
| 判断 | 仕様を直した |
| 直した点 | (1) origin の URL の区切りに `:` を含める（`git@github.com:o/r.git` の形）。(2) `git config progress.port` が整数でないときも終了コード 2（式の番号に黙って戻すと R-D01・KI-D03）。E2 に足した。(3) `--stop` の、立っていないとき（0）と 5 秒で止まらないとき（1）の終了コード。(4) 子が先に終了したら判定し直す（同時に 2 回呼ばれて別の呼び出しが立てた場合を 1 にしない）。1 のときも上書きの方法を出す（goal「理由と上書きの方法を出す」を bind の失敗にも効かせる）。(5) `commonDir` の比較を `realpath` で揃える。(6) テストの所要時間: 176 §6 の「progress のテストは合計 1 秒未満」をこの仕様の 3 秒が超えるので、#213 で実測して PR に書くと足した |
| 自信度（参考記録） | 80% |
| 停止条件チェック | 該当なし |

### 4. 176 の制約との関係

| 項目 | 内容 |
|---|---|
| 判断 | 許可 |
| 理由 | 足すのは GET の `/api/identity` だけで、176 §6「GET 以外は 405」と Host 検査（`server.py:163-165,189`）を保つ。`server.py` は 271 行で 300 行以内に収まる見込み。`--port` の既定 8765（`server.py:252`）を変えず番号は `ensure.py` だけが決める（単一情報源） |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし（S5: 新しい設計の理由が書かれている） |

### 5. 測定対象のコード上の実体

| 項目 | 内容 |
|---|---|
| 判断 | 許可 |
| 理由 | 判定・起動・停止の対象がファイルと関数・キーで特定されている（`scripts/progress/ensure.py`、`/api/identity` の `app`・`commonDir`・`pid`、`portsAttributes` の `"18000-18999"`、`.claude/skills/progress/SKILL.md`、`scripts/tests/test_progress_ensure.py` の E1〜E5）。参照行 `server.py:252`・`README.md:124` は実体と一致 |
| 停止条件チェック | 該当なし |

### 6. 停止条件 S1〜S8

| # | 判定 |
|---|---|
| S1 | 該当なし（3 ファイルあり、既定の節あり。固有節は未記入） |
| S2 | 該当なし。goal は確定。未確定 4 行はいずれも `→ spec` の担当付きで、#212 が実在することを task 本文と子一覧で確かめた。成功条件は委譲の placeholder ではない |
| S3 | 該当なし（invariants・ADR に反しない。ログは git common dir、worktree を作らない） |
| S4 | 該当なし（V1〜V4 はいずれも PASS/FAIL を判定できる。V3 は「黙ってずらさない」で判定し、起きたことを記録） |
| S5 | 該当なし（pid ファイルを持たない・環境変数を採らない・主 worktree で立てる等の理由が書かれている） |
| S6〜S8 | 該当なし（spec。negative の結論・close・子の削除の提案ではない） |

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] `requireLocalPort` が衝突時に転送をやめるのか、ずらしたうえで dialog を出すのかは出典に無い（#214 V3 で実測。後者なら goal の「黙ってずらさない」は dialog で満たすことになる）
- [ ] テストが 3 秒まで増える（ユーザーはテスト時間の増加を嫌う。#213 で実測値を PR に書く）
- [ ] 背景で立てるのは呼んだ worktree の `server.py`（主 worktree の版ではない）。別ブランチの実装で立つことがある。読み込みは起動時だけなので、worktree を消しても止まらない
- [ ] `portsAttributes` の範囲指定は 18000〜18999 の他のプロセスにも掛かる（§4-3 で受け入れ済み）
