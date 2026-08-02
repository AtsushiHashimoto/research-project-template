# Issue #121 自動判断ログ

## メタ情報
- 判断日時: 2026-08-02
- 自動処理: /task-run（task #115 配下）
- 判断対象: .spec/issues/121-quality-check-effective.md（D1〜D5＋Fallback 1件）
- 必読コンテキスト: .spec/core-rules.md / invariants.md / known-issues.md — 3ファイルとも存在し既定節あり。
  **「プロジェクト固有」節は3ファイルとも未記入のため、既定のみで判断した**（判断確度低下の自覚あり）

## 判断一覧

### 1. D1: bash 3.2 互換（mapfile 置換・shebang 統一）

| 項目 | 内容 |
|------|------|
| 質問 | mapfile → while read 置換、shebang を `#!/usr/bin/env bash` に統一してよいか |
| 判断 | ✅ 許可 |
| 理由 | 実在バグの修正（macOS bash 3.2 で `SH_FILES: unbound variable` により MANIFEST 検査到達前に異常終了＝完了ゲート自体が silent-wrong）。既存パターン（他 scripts/*.sh は既に `#!/usr/bin/env bash`。`#!/bin/bash` 残存は quality-check.sh / commit-merge.sh / claude-san のみ）への統一であり新規パターンではない |
| 実装上の注意 | bash 3.2 + `set -u` では**空配列の `"${arr[@]}"` 展開自体がエラー**になる（`${#arr[@]}` は初期化済みなら安全）。現行の「件数を確認してから展開」ガード（L92-95 と同型）を while-read 版でも必ず維持すること |
| 参照 | scripts/quality-check.sh L91、#114 H8、KI-D07（ゲートが動いていない状態） |
| 自信度（参考記録） | 95% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 2. D2: shellcheck 導入＋無言スキップの解消

| 項目 | 内容 |
|------|------|
| 質問 | Dockerfile に shellcheck 追加、未インストール時は skip でなく警告（RAN_ANY に数えない）でよいか |
| 判断 | ✅ 許可 |
| 理由 | 「検査対象が無い」と「検査系が入っていない」の区別は R-D05（失敗0件と実行0件は違う）の趣旨そのもの。現行 L88-89 の `skip "shellcheck (未インストール)"` が #114 H8 の無言スキップの実体であり、その解消は本 issue の目的に直結 |
| 参照 | R-D05、KI-D07/KI-D08、scripts/quality-check.sh L86-97 |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

### 3. Fallback: 「shellcheck 未インストールでも exit 1 にしない」

| 項目 | 内容 |
|------|------|
| 質問 | 完了ゲートを緩めるこの Fallback は R-D01（silent fallback 禁止）に抵触しないか |
| 判断 | ⚠️ 警告付き許可（条件付き） |
| 理由 | R-D01 が禁止するのは「**黙って**受理する」こと。本 Fallback は (a) 警告を目立たせる (b) サマリに未実行として必ず列挙 (c) RAN_ANY に数えない (d) D5 の CI（shellcheck 導入済み ubuntu）が backstop として必ず検査する、の4点で loud かつ補完付きであり、silent-wrong の構造（クラッシュせず気づかれない）を持たない。逆に exit 1 にすると、shellcheck 無しホスト環境で `/commit-merge` の完了ゲートが常時閉じ、KI-D08 型の「RED 常態化→誰も見なくなる」を別経路で誘発する |
| **許可の条件** | ① **D5 の CI が同一 issue 内で実際に導入されること。この Fallback の妥当性は「必ずどこかで検査が走る」に依存しており、D5 が落ちた場合この許可は無効（禁止に戻る）** ② 未実行がある場合、最終バナーを素の「All quality checks passed」のままにしない（例:「passed（未実行検査あり: N 件）」）。「実行0件≠失敗0件」の区別を exit code だけでなく表示にも反映すること（R-D05） |
| 参照 | R-D01、R-D05、auto-reviewer Fallback 基準（ホワイトリスト3種のいずれにも該当しないが、silent でない旨が仕様に明記されているため個別判断） |
| 自信度（参考記録） | 80% |
| 停止条件チェック | 該当なし |

### 4. D3: 検査対象の拡張（scripts/qa/*.py、claude-san）

| 項目 | 内容 |
|------|------|
| 質問 | scripts/qa を TARGETS に追加、shebang 判定で claude-san をシェル検査対象にしてよいか |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | H8 の「そもそも検査対象外」への対処として方向は正しい。ただし下記の残余と実装注意がある |
| **警告1（残余）** | **テンプレートリポジトリ自体には pyproject.toml が無い**（実測）。D3 は「pyproject があれば TARGETS に追加」であり、本リポジトリでは scripts/qa/*.py（10ファイル）は依然として実質未検査のまま。issue #121 本文は「TARGETS に追加 **or pyproject 同梱**」の二択を示しており、仕様は前者のみを採用した。D4 のサマリで「未実行（pyproject.toml が無い）」と可視化されるため silent ではないが、**H8 の「scripts/qa が対象外」はテンプレート上では部分未解消**。実装時に (a) CI で `uvx ruff check scripts/qa` 等の standalone 実行を加える、または (b) 残余を明示した follow-up issue を立てる、のいずれかを行うこと |
| **警告2（ゲート即 RED 防止）** | claude-san（`#!/bin/bash`、tmux 起動スクリプト）が新たに shellcheck 対象に入る。**既存の指摘があれば本 issue 内で修正（または根拠付き directive）しないと、マージ直後から完了ゲートが RED になる**（KI-D08）。新規に対象へ入る全ファイルに対し実装中に shellcheck を通すこと（V8 の対象拡大版） |
| 実装上の注意（shebang 判定） | `git ls-files` を走査し、`*.sh` で既収集のものは除外（二重検査防止）。先頭行のみ読む（`head -n1`、バイナリ対策で `head -c` 併用可）。判定は `#!/bin/sh` `#!/bin/bash` `#!/usr/bin/env bash` 等にマッチし、`#!/usr/bin/env python3` 等を誤検出しない正規表現にする（例: `^#!.*/(env[[:space:]]+)?(ba)?sh([[:space:]]|$)`）。worktrees/ は gitignore 対象なので ls-files で自然に除外される |
| 参照 | scripts/quality-check.sh L63-66・L91、claude-san 先頭行（実測 `#!/bin/bash`）、リポジトリに pyproject.toml 無し（実測） |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

### 5. D4: 実行/未実行サマリの必須表示

| 項目 | 内容 |
|------|------|
| 質問 | 最後に「実行した検査」「未実行の検査（理由つき）」を必ず表示する設計でよいか |
| 判断 | ✅ 許可 |
| 理由 | 本 issue の核心であり、R-D05・KI-D07 の趣旨（実行0件を失敗0件と誤認しない）を出力形式として固定するもの。#117〜#119 の「無言の切り捨て禁止」を踏襲 |
| 実装上の注意（既存実装との噛み合い） | 現行の run_check/skip は**名前を記録しない**（RAN_ANY/FAILED のフラグのみ、skip は echo のみ）。サマリには名前＋理由の蓄積が必要。bash 3.2 + `set -u` の空配列展開問題を避けるため、**改行区切り文字列への蓄積**（またはガード付き配列 `${arr[@]+"${arr[@]}"}`）を推奨。skip は現在3つの意味（QUALITY_SCOPE=docs の意図的スキップ／対象ファイル無し／検査系未導入）を兼ねているが、D2 により「検査系未導入」は skip と別関数（warn 等）に分離すること。既存の skip 呼び出しは全て理由を括弧書きで持っているため、そのまま収集できる |
| 参照 | scripts/quality-check.sh L26-39・L139-149 |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

### 6. D5: CI（GitHub Actions）の追加

| 項目 | 内容 |
|------|------|
| 質問 | .github/workflows/quality.yml をテンプレートに同梱し、install.sh ITEMS・sync 対象に加えるのはスコープ妥当か。opt-in にすべきか |
| 判断 | ⚠️ 警告付き許可（**default-on を支持、opt-in にしない**） |
| 理由（スコープ） | #114 H8 の指摘文言に「CI 無し」が明示的に含まれており（実測確認済み）、親 goal「#114 の Critical/High が全て解消」の範囲内。スコープ拡大ではない |
| 理由（opt-in にしない） | 上記 Fallback（項目3）の許可条件①は「必ずどこかで検査が走る」ことに依存する。opt-in にすると派生プロジェクトの既定状態で backstop が消え、**Fallback 許可の前提が崩れて D2 の緩和が silent-wrong に退行する**。安全機構は既定で有効・明示的に無効化、が正しい向き |
| **警告（派生プロジェクトへの負担軽減を実装に含めること）** | ① workflow は軽量単一ジョブ（ubuntu-latest、matrix 無し。quality-check は数十秒想定）にする ② `concurrency` + cancel-in-progress を設定 ③ トリガは push（main）+ PR 程度に絞る ④ **workflow ファイル冒頭コメントに無効化手順を明記**（ファイル削除 or リポジトリ設定で Actions 無効化）。private 派生リポジトリでは Actions 無料枠を消費するため、この案内が opt-out の実効性を担保する |
| 3点対称について | 仕様が install.sh ITEMS / template-sync / contribute-detect の3点対称を明記し V6 で検証する構成は、#114 H1（配布漏れ）の再発防止として適切。contribute-detect.sh L201 のコメント（対称維持の注記）も更新対象に含めること |
| 参照 | #114 H8・H1、scripts/template-contribute-detect.sh L12・L201、install.sh L163（ITEMS） |
| 自信度（参考記録） | 75% |
| 停止条件チェック | 該当なし |

### 7. 検証チェックリスト V1〜V8 の十分性

| 項目 | 内容 |
|------|------|
| 質問 | V1〜V8 で十分か |
| 判断 | ⚠️ 警告付き許可（追加を要求） |
| 理由 | 全項目 PASS/FAIL 判定可能で S4 には該当しない。ただし**「検査が通ること」の検証に偏り、「検査が壊れを検知すること」（positive control）が新規検査系に無い**。#114 H8 の本質は「検査が動いていないのに passed と出る」ことなので、検知方向の確認は必須。issue #121 の完了条件「フィクスチャで検知・通過の**両方向**を確認」とも整合し、goal の拡大ではない |
| **追加すべき項目** | **V9**: 意図的な shellcheck 違反を含むフィクスチャで exit 1 になる（shellcheck 経路の positive control）。**V10**: shebang 判定の両方向 — claude-san が対象に入る（V3 と統合可）＋拡張子なし・非シェルのファイル（例: Python shebang）が対象に**入らない**。**V11（推奨）**: shebang 変更後も commit-merge.sh が動作する |
| 要確認フラグ | Dockerfile への shellcheck 追加は devcontainer rebuild なしに検証できない。rebuild 後の確認を issue コメントに残すこと |
| 参照 | R-D02 の趣旨（検出力未確認の検査系を信用しない）、issue #121 完了条件 |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし（S4 非該当。追加要求は完了条件の具体化であり拡大ではない） |

## goal 書き換えチェック

- 親 task #115 goal「#114 の Critical/High 全解消、Medium/Low まとめ処理、再発防止チェック、既存検証済み動作を壊さない」に対し、本仕様は H8 の解消と再発防止（D4/D5）に閉じている
- D5 の CI は H8 指摘文言（「CI も無い」）に含まれるため**範囲拡大に当たらない**
- goal の書き換え・成功条件の変更: **無し**

## 停止判断

- 該当した停止条件: **無し**（S1: 3ファイル存在・既定節あり / S2: goal 確定 / S3: invariants 抵触なし / S4: チェックリストあり判定可能 / S5: 既存パターンの拡張 / S6: experiment 非該当）
- 前進する

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] `.spec/` 3ファイルの「プロジェクト固有」節が未記入。既定のみで判断した
- [ ] scripts/qa/*.py はテンプレート自体では pyproject 不在のため未検査のまま（D3 警告1）。CI での standalone lint 追加 or follow-up issue のいずれかを実装時に確定させること
- [ ] Dockerfile の shellcheck 追加は rebuild 後に実機確認が必要
- [ ] D5 の Actions 課金・通知負担は派生プロジェクト側の事情に依存。workflow 冒頭の無効化案内で緩和するが、テンプレート README への一言追記も検討余地あり
