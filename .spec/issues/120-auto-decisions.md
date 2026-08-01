# Issue #120 自動判断ログ

## メタ情報
- 判断日時: 2026-08-01
- 自動処理: /task-run（auto-reviewer による代理判断）
- 判断対象: .spec/issues/120-model-policy-wiring.md（D1〜D5）
- 必読コンテキスト: .spec/core-rules.md / invariants.md / known-issues.md（3ファイルとも存在、既定節あり）
  - **注記**: 3ファイルとも「プロジェクト固有」節は未記入。既定のみで判断した（auto-reviewer.md の規定によりこれは続行可・要記録事項）

## ゴール書き換えチェック（最優先）

親 task #115 の goal（「#114 の Critical/High が全て解消し、Medium/Low がまとめ issue で処理済み。
再発防止チェックが入っている。既存の検証済み動作（#101 V1〜V11、#108 F1〜F6）を壊さない」）を
D1〜D5 のいずれも書き換えていない。V6（既定の解決結果不変）は goal の「既存動作を壊さない」条項を
直接検証しており整合。→ **goal 書き換えなし**。
ただし D1 は issue #120 の H4 チェックボックスの範囲を一部カバーしていない（下記 D1 参照）。
これは goal の書き換えではなくスコープの欠落であり、警告付き許可の条件として扱う。

## 判断一覧

### 1. D1: call-site への model 指定の追加

| 項目 | 内容 |
|------|------|
| 質問 | 未配線 call-site に `model="$(bash scripts/resolve-model.sh <role>)"` を追加してよいか |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | 配線パターンは既配線の task-run/SKILL.md:145,176,225 と完全に同型（既存パターン踏襲）。role 割当は model-policy.md の call-site 表・role 定義と整合（issue-gaps の Phase1=mechanical / Phase2=verification への分割、epic-cycle Phase Final=abstract-review の追加は role 定義の趣旨に合致し、V1 で表と実装の一致を機械確認する前提で妥当）。**警告**: issue #120 の H4 チェックボックスは「/issue-backlog・unblock」を配線対象に明記しているが、D1 の表に無く、除外理由も仕様に書かれていない。実測では issue-backlog/SKILL.md:67、issue-unblock/SKILL.md:73,109 に計3つの Task() 呼び出しが実在する。**条件**: (a) この3 call-site も role を割り当てて配線し model-policy.md の表に追記する、または (b) 除外する場合はその理由を仕様と issue #120 に明記する。どちらも行わない場合、task #115 goal の「Critical/High が全て解消」を満たさない |
| 参照 | model-policy.md（call-site 表・role 定義）、task-run/SKILL.md:145,176,225、04-interface.md H4、06-wiring-test.md、issue #120 本文、grep 実測（issue-backlog:67 / issue-unblock:73,109） |
| 自信度（参考記録） | 85% ※停止判定には使用しない |
| 停止条件チェック | 該当なし |

### 2. D2: agents の role frontmatter の解決規約

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | `role:` frontmatter は Claude Code が解釈しない独自キーであり（04-interface.md High）、「呼び出し側スキルが resolve-model.sh で解決して model= に渡す」規約は、既に動いている実装（task-run:145 が auto-reviewer 呼び出しに abstract-review を解決して渡している）の明文化であって新規パターンではない。agent 定義側を `model: inherit` のまま維持することで「モデル名を2箇所に書かない」（model-policy.md 注意節、dev-guidelines.md の単一情報源原則）を保つ。issue が提示した代替案（subagent_type ネイティブ呼び出しへの移行）より変更が小さく、既存の検証済み動作を壊さない（goal の制約に適合） |
| 参照 | model-policy.md 注意節、dev-guidelines.md（SSOT）、task-run/SKILL.md:145、04-interface.md |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

### 3. D3: planning role の配線（epic-cycle Step 4）

| 項目 | 内容 |
|------|------|
| 判断 | ⚠️ 警告付き許可 |
| 理由 | issue #120 H4 は「配線するか、role を削除」の二択を提示しており、D3 は前者を選択（削除しない理由も明記されている）。Step 4「結果駆動の次 task 判断」は planning role の定義（タスク分解、設計の骨子）に合致する。**警告**: epic-cycle Step 4 には現在 Task() 呼び出しが存在しない（実測: epic-cycle の Task() は Phase Final の1箇所のみ）。したがって配線には新規サブエージェント呼び出しの追加が伴う。Step 4 は KI-D14（ゴール勝手変更）に直結する箇所であり、規律1〜3（投機禁止・goal 不変・survey skip 禁止）が本文に明記されている。**条件**: 新設するサブエージェント呼び出しの prompt に、epic の goal 原文と規律1〜2（少なくとも「goal を書き換えない」「結果が出てから作る」）を必ず埋め込むこと。埋め込まない配線は KI-D14 の再発経路になるため不可 |
| 参照 | epic-cycle/SKILL.md:120-153,177、known-issues.md KI-D14、issue #120 本文、model-policy.json（planning 定義） |
| 自信度（参考記録） | 75% |
| 停止条件チェック | 該当なし |

### 4. D4: --disable の汚染分離（model-policy.local.json）

| 項目 | 内容 |
|------|------|
| 判断 | ⚠️ 警告付き許可 |
| 理由 | 通常運用の --disable が model-policy.json を書き換え偽の還流候補を恒久生成する問題（#114 Medium、04-interface.md / 06-wiring-test.md 両観点で検出）への正当な修正。`.claude/settings.local.json` が既に .gitignore:75 にある既存パターンの踏襲であり新規パターンではない。local 不在時に本体のみ読むのは「設定のデフォルト値」であり Fallback ホワイトリスト該当（R-D01 例外）。V2 が完了条件「--disable 後に git status が汚れない」を直接検証する。**警告**: 「本体の disabled も後方互換で読む」仕様のため、本体 json に残った legacy disabled エントリは local への --enable では解除されない。ユーザーが「enable した」と思っても解決結果が fallback のまま、という静かな状態不一致（KI-D03 類型）になり得る。**条件**: --enable は本体側の disabled からも削除する、または本体側に残存する場合はその旨を明示出力すること。黙って不一致を残さない |
| 参照 | core-rules.md R-D01（例外: 設定のデフォルト値）、known-issues.md KI-D03、.gitignore:75、resolve-model.sh:81-91、04-interface.md Medium 行 |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

### 5. D5: --list の overrides 表示

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | #114 Low への対処。表示の追加のみで解決ロジックを変更しない（resolve() は既に overrides 最優先で動作しており、V6 が既定解決の不変を担保）。可観測性の向上であり、既存の検証済み動作を壊すリスクはない |
| 参照 | resolve-model.sh:45-48,69-79、06-wiring-test.md Low 行 |
| 自信度（参考記録） | 95% |
| 停止条件チェック | 該当なし |

## Fallback ホワイトリスト

仕様どおり「新規 fallback なし」を確認。D4 の local→本体マージ読みは設定デフォルト値であり
ホワイトリスト範囲内。resolve-model.sh 既存の role fallback 連鎖には変更なし。

## 停止判断

該当なし（S1〜S6 すべて非該当）。

- S1: .spec/ 3ファイル存在・既定節あり → 非該当（プロジェクト固有節は未記入、上記に記録済み）
- S2: 親 task goal は確定・単一解釈 → 非該当
- S3: invariants.md / ADR 違反なし → 非該当
- S4: 検証チェックリスト V1〜V6 あり、全項目 PASS/FAIL 判定可能（grep / git status / --list 出力で機械判定可） → 非該当
- S5: D1〜D5 いずれも既存パターン踏襲、逸脱箇所（D3 の新規 Task 追加）は理由が仕様と issue に記載 → 非該当
- S6: experiment ではない → 非該当

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] D1 条件: issue-backlog（Task 1箇所）/ issue-unblock（Task 2箇所）の配線 or 除外理由の明記。
      配線する場合の role 割当（例: backlog 分析=mechanical or verification、unblock 分析=verification）は
      role 定義に照らして feature 実装時に決定し、model-policy.md の表に追記すること
- [ ] D3 条件: Step 4 新設サブエージェントの prompt に epic goal 原文＋規律（goal 不変・投機禁止）を埋め込むこと
- [ ] D4 条件: --enable の legacy（本体 json）disabled エントリの扱い（両方から削除 or 明示警告）
- [ ] 再発防止（task goal「再発防止チェック」該当）: quality-check に「skills 内の全 Task()/Agent() 呼び出しが
      model= 配線済み（または除外理由コメントあり）」の grep 検査を追加する価値あり。V1 は表の行しか見ないため、
      表に載っていない call-site の取りこぼし（今回の backlog/unblock がまさにこの形）を将来検出できない

## 事後校正用メモ

自信度は停止判定に使用していない（#95）。D3 を最低値（75%）とした理由:
既存に無い呼び出しの新設を含み、KI-D14 の再発経路に最も近いため。
