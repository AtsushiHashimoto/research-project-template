# Issue #119 自動判断ログ

## メタ情報
- 判断日時: 2026-08-02
- 自動処理: /task-run（auto-reviewer による代理判断）
- 対象仕様: .spec/issues/119-issue-create-ssot.md（D1〜D6）
- 親 task: #115（goal は変更していない）

## 必読コンテキストの状態

- .spec/core-rules.md: 既定あり / プロジェクト固有 **未記入**
- .spec/invariants.md: 既定あり / プロジェクト固有 **未記入**
- .spec/known-issues.md: 既定あり / プロジェクト固有 **未記入**
- 判定: 続行可（既定節あり）。**プロジェクト固有のルールが未登録のため、既定のみで判断した。**

## 判断一覧

### 1. D1: `gh issue create` 直呼びの解消（8箇所を issue-create 経由に）

| 項目 | 内容 |
|------|------|
| 質問 | 8箇所を Skill(skill="issue-create") に置き換える。各呼び出し元の要求を issue-create が満たせるか |
| 判断 | ⚠️ 警告付き許可（下記の仕様の穴 H-a〜H-c を仕様に追記・解決してから実装すること） |
| 理由 | SSOT 方針自体は dev-guidelines「単一情報源の原則」と issue-create 自身の宣言に合致。ただし issue-create の現行引数仕様（--type 必須＝種類ラベル、親は task 限定・違反時は警告して停止、--parent 原則必須）を実際に照合した結果、**そのまま置き換えると壊れる呼び出し元が存在する** |
| 参照 | issue-create/SKILL.md（Step 1/2/4/6、呼び出し元表）、issue-branch/SKILL.md:55,72、issue-unblock/SKILL.md:140,172、issue-gaps/SKILL.md:260,302、review-integrity/SKILL.md:178,259、issue-backlog/SKILL.md:114、rules/template/labels.md、rules/template/issue-hierarchy.md |
| 自信度（参考記録） | 78% ※停止判定には使用しない |
| 停止条件チェック | 該当なし（穴は指摘可能かつ解決方針が既存ルールから導出可能なため、警告付き許可で前進） |

**検出した仕様の穴（実装前に仕様へ解決方針を追記すること）:**

- **H-a: issue-branch の小タスクは issue-create で表現できない。**
  issue-hierarchy.md の表で小タスク層は種類ラベル「—」（ラベル無し）だが、issue-create は
  `--type`（種類ラベル）必須で、Step 2 の階層チェックが「issue の親は task」を強制し
  違反時は停止する。issue-branch の子 issue は**親が issue 層**なのでそのままでは作成不能。
  解決案: (1) issue-create に小タスクモード（親=issue 層を許可、ラベル無し）を最小追加する、
  または (2) issue-branch を「文書化された例外」とし V1 の除外リストに明記する。
  ※(1) を採る場合も epic/task/issue の既存階層チェックは緩めないこと（勝手に補正しない挙動を保持）。
- **H-b: review-integrity の報告 issue（L178）は種類ラベルを持たない。**
  labels.md 上 `review-integrity` は種類ラベルではなく**報告ラベル**であり、現行実装は
  種類ラベル無しで作成している。issue-create は --type 必須なので、仕様 D1 の
  「呼び出し後に gh issue edit で報告ラベルを付与」だけでは**初回の --type に入れる値が無い**
  （誤った種類ラベルが付くか、後で剥がすハックになる）。
  解決案: issue-create の --type に報告ラベルを許可（親なし可）するか、報告 issue を例外として文書化。
- **H-c: 親なし issue の扱いが未定義。**
  issue-unblock / issue-backlog / review-integrity 修正 issue は親 task を持たない。
  issue-create は「--parent は epic 以外原則必須」で、自動処理では「原則」の解釈が
  非決定的。親なし作成をどう扱うか（許可条件・記録）を仕様に明記すること。
  issue-gaps の `Parent: #元issue` も親が issue 層であり H-a と同類（なお現行の本文
  `Parent:` 記載は labels.md「親子は本文テキストに書かない」と不整合。置き換え時に整理可能）。
- **W-d（警告・穴ではない）: bash の for ループ内から Skill は呼べない。**
  issue-unblock / issue-gaps / issue-backlog の複数作成ループは、エージェント駆動の反復
  （1件ずつ Skill 呼び出し→Step 6 出力から URL/番号を取得）に書き換える必要がある。
  番号取得自体は issue-create Step 6 が URL と番号を出力するため充足される。
- 状態ラベル（user-action/blocked）・報告ラベルの後付け方針（gh issue edit）は妥当。
  issue-create を肥大化させない方針とも整合する（ただし H-b の初回 --type 問題は残るため上記参照）。

### 2. D2: レースコンディションのある ID 取得の除去

| 項目 | 内容 |
|------|------|
| 質問 | issue-branch の `gh issue list --limit 1` による番号取得を除去してよいか |
| 判断 | ✅ 許可 |
| 理由 | issue-create/SKILL.md が「❌ 禁止」と名指しするパターンそのもの。並行 worktree 前提で他タスクの番号を掴む実バグ。条件: H-a の解決で issue-branch が直呼び例外として残る場合でも、`URL=$(gh issue create ...)` → `${URL##*/}` 方式への置き換えは必須 |
| 参照 | issue-branch/SKILL.md:72、issue-create/SKILL.md Step 4 |
| 自信度（参考記録） | 95% |
| 停止条件チェック | 該当なし |

### 3. D3: skills.md の実体同期

| 項目 | 内容 |
|------|------|
| 質問 | 未掲載6スキル追加と /commit のルータ化説明 |
| 判断 | ✅ 許可 |
| 理由 | 実測で確認: `ls .claude/skills` に commit-only / qa-ask / qa-check / qa-setup / review-spec / review-integrity が存在し skills.md に未掲載（ちょうど6件）。commit/SKILL.md は frontmatter で "Smart commit router" と宣言しており「ローカルにコミットのみ」は誤記 |
| 参照 | ls .claude/skills、commit/SKILL.md:2、rules/template/skills.md |
| 自信度（参考記録） | 95% |
| 停止条件チェック | 該当なし |

### 4. D4: /review のサブエージェント数を件数非記載に統一

| 項目 | 内容 |
|------|------|
| 質問 | 件数を書かない形に統一してよいか |
| 判断 | ✅ 許可 |
| 理由 | 実測で確認: review/SKILL.md 内に「6つ」(L7,46,48)「8つ」(L321)「7回」(L385)、skills.md に「3つ」の計4通りが並存。件数は増減するため書けば必ずずれる。単一情報源の原則に合致 |
| 参照 | review/SKILL.md、rules/template/skills.md、dev-guidelines.md |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

### 5. D5: README 3言語のスキル表削除（skills.md 参照に置き換え）

| 項目 | 内容 |
|------|------|
| 質問 | README からスキル表を削除して発見性が落ちないか |
| 判断 | ⚠️ 警告付き許可 |
| 理由 | doc-principles「同じ情報を両方に書かない」に合致し、表が既に陳腐化している事実自体が重複維持コストの実証。Quick Start の代表例を残す設計で最低限の発見性は保たれる。警告: (1) skills.md への参照は**明示的なファイルパス**（`.claude/rules/template/skills.md`）で、Quick Start 近傍の目立つ位置に置くこと（README は外部者が最初に読む文書のため）。(2) 3言語すべてで同一の扱いにすること。Directory Structure 修正は事実訂正（`.claude/commands/` の不存在を実測確認済み） |
| 参照 | README.md:81,106,121、doc-principles.md、ls 確認 |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

### 6. D6: issue-hierarchy.md を SSOT、task-start は参照に

| 項目 | 内容 |
|------|------|
| 質問 | task-start の自動処理としての実効性が落ちないか（参照先を読まずに手順を省略するリスク） |
| 判断 | ✅ 許可 |
| 理由 | `.claude/rules/template/*.md` は**セッション開始時に自動読込される**（CLAUDE.md 明記）ため、issue-hierarchy.md の内容は task-start 実行時に常にコンテキストへ載っており、「参照先を読まない」リスクは通常のファイル参照と質的に異なり低い。対話の質問文（task-start 固有の手順）を残す線引きも適切。内容差は実測確認（task-start:130 `bug（単独。validation を伴う場合あり）` vs issue-hierarchy:35 `bug（単独）`）。issue-hierarchy 側を正とする判断は妥当: 「validation を伴う場合」は既存の逸脱規定（省略・変更は task 本文に理由を記載）でカバーされ、表に例外を書き込むと SSOT の表自体が肥大化する |
| 参照 | task-start/SKILL.md:122-200、issue-hierarchy.md、CLAUDE.md「ルールの所在」 |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし |

### 7. V1〜V10 の十分性

| 項目 | 内容 |
|------|------|
| 判断 | ⚠️ 概ね十分だが追加を要求 |
| 理由 | V9（既存 quality-check 全 PASS）が親 task goal「検証済み動作を壊さない」を担い、V10 が再発防止を担う構成は良い。ただし D1 の後付けラベル手順と新呼び出しパターンの検証が欠けている |
| 追加要求 | **V11**: 置き換え後の各呼び出し元に、必要な後付けラベル手順（user-action / blocked / review-integrity）が残っていること。**V12**: issue-create が新しい呼び出しパターン（親なし・親=issue 層の小タスク・報告 issue）を停止させずに扱えること、または例外として文書化され V1 の除外リストと一致していること |
| 自信度（参考記録） | 85% |
| 停止条件チェック | 該当なし（S4 には非該当: 既存チェックリストは全項目 PASS/FAIL 判定可能） |

## 停止判断

該当なし。S1〜S6 いずれにも該当しない。

- S1: `.spec/` 3ファイルは既定節が揃っている（プロジェクト固有節は未記入だが続行可の規定）
- S2: 親 task #115 の goal は確定しており解釈の分岐なし
- S3: invariants / core-rules への抵触なし（むしろ SSOT 原則に沿う方向の変更）
- S4: 検証チェックリストあり、全項目判定可能
- S5: 既存パターン（SSOT、issue-create 一元化）への回帰であり新奇な設計ではない
- S6: experiment ではない（ドキュメント/スキル整備）

## goal 書き換えチェック

- 親 task #115 goal の書き換え: **なし**
- D5 は Medium を本 issue で処理するが、goal「Medium/Low がまとめ issue で処理済み」の
  成功条件を変えるものではない（処理済みになる事実は同じ）。範囲拡大・縮小に非該当

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] H-a/H-b の解決方針（issue-create の最小拡張 vs 文書化された例外）はどちらでも
      goal を満たすが、「issue-create を肥大化させない」（仕様 D1）と「例外ゼロの SSOT」の
      トレードオフ。実装時にどちらを採ったか issue に記録すること
- [ ] .spec/ 3ファイルのプロジェクト固有節が未記入のまま運用中（テンプレート開発
      リポジトリ自体なので許容範囲だが、記録として残す）
