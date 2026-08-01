# Issue #119 仕様: issue-create SSOT の徹底とスキル一覧・README の実体同期

- 状態: approved（auto-reviewer 判断済み。穴3件を D1' で解決、V11/V12 を追加。ログ: 119-auto-decisions.md）
- 由来: Integrity Review #114 の H5/H6/H9/C4 ＋ Medium 数件

## 設計

### D1: `gh issue create` 直呼びの解消（H5）

`issue-create/SKILL.md` が「Issue 作成の唯一の実装。他スキルは `gh issue create` を
直接呼ばない」と宣言しているのに、5スキル8箇所が違反している。

| ファイル | 箇所 | 用途 |
|---|---|---|
| `issue-branch/SKILL.md` | 55 | 子 issue 作成 |
| `issue-unblock/SKILL.md` | 140, 172 | ブロッカー解消 issue |
| `issue-gaps/SKILL.md` | 260, 302 | 不足 issue / 未追跡実装の issue |
| `issue-backlog/SKILL.md` | 114 | バックログの issue 化 |
| `review-integrity/SKILL.md` | 178, 259 | レビュー報告 issue / 修正 issue |

**全て `Skill(skill="issue-create", args="...")` 呼び出しに置き換える。**

`/issue-create` が対応していない要素は次の2つ。呼び出し後に `gh issue edit` で付与する
（issue-create 自体を肥大化させない）:

- 状態ラベル（`user-action` `blocked`）— issue-create は種類ラベルのみ扱う
- 報告ラベル（`review-integrity`）

### D1': issue-create の拡張（auto-reviewer が検出した穴の解決）

D1 をそのまま適用すると、次の3パターンが **issue-create では表現できず作成不能**になる。
呼び出し側を例外にするのではなく、**issue-create を最小限拡張して SSOT を成立させる**。

| 穴 | 現状の制約 | 解決 |
|---|---|---|
| **H-a** 小タスク（`issue-branch`）| `--type` が種類ラベル必須、かつ階層チェックが「issue の親は task」を強制 | 階層表に**小タスク**の行を追加（親＝issue 層を許可）。`--type` に**種類ラベルを付けてよい**が、小タスクは worktree を共有するだけで層としては issue と同じなので、`--parent <issue番号>` を許可する |
| **H-b** 報告 issue（`review-integrity`）| `--type` は種類ラベルのみ。`review-integrity` は報告ラベル | `--type` の受理範囲を「**`setup-labels.sh` に定義済みのラベル**」に広げる（種類／報告のいずれも可）。定義済みか否かの検査は既存の Step 1 がそのまま使える |
| **H-c** 親なし issue（`issue-unblock` / `issue-backlog` / report） | 「epic 以外は原則必須」の解釈が自動処理で非決定的 | `--parent` 省略を**明示的に許可**し、その場合は「単独 issue」として作成する。ただし**省略した旨を出力に必ず表示**する（黙って親なしにしない） |
| **W-d** ループ内の複数作成 | bash の for ループから Skill は呼べない | 呼び出し側の記述を「各項目について `/issue-create` を呼ぶ」というエージェント駆動の反復に書き換える（bash ループで gh を回す形をやめる） |

あわせて **`--extra-label`** を追加する。状態ラベル（`user-action` `blocked`）を
呼び出し後の `gh issue edit` で付けると2ステップになり、
「issue-create を通せば必ず正しく作られる」という SSOT の意味が薄れるため。

### D2: レースコンディションのある ID 取得の除去（H5）

`issue-branch/SKILL.md:73` の
`gh issue list --limit 1 --json number --jq '.[0].number'` は
`issue-create/SKILL.md` が**「禁止」と名指ししている**パターン。
並行 worktree が前提の本テンプレートでは他タスクの issue 番号を掴む。
`/issue-create` 経由にすれば URL 由来の番号が返るので自然に解消する。

### D3: skills.md の実体同期（H6）

未掲載6スキルを追加し、`/commit` の説明を実体（ルータ）に直す。

| 追加するスキル | 節 |
|---|---|
| `/commit-only` | コミット |
| `/review-spec` `/review-integrity` | レビュー |
| `/qa-setup` `/qa-ask` `/qa-check` | QA（新設） |

`/commit` は「ローカルにコミットのみ」ではなく**ルータ**（`commit-only`/`commit-push`/
`commit-merge` に振り分ける）。`/commit-only` を別行にする。

### D4: `/review` のサブエージェント数の不整合（C4）

`review/SKILL.md` 内で「6つ」「8つ」「7回」、`skills.md` で「3つ」と4通りある。
**件数を書かない**形に統一する（`Step 3 の各観点`）。件数は増減するため、
書けば必ずどこかがずれる。

### D5: README 3言語のスキル表（Medium）

README のスキル表は旧表記のうえ epic/task 層が丸ごと欠落している。
`doc-principles.md` の「同じ情報を両方に書かない」に照らし、
**表を削除して `skills.md` への参照に置き換える**。Quick Start の代表例のみ残す。
Directory Structure 図も実体に合わせる（存在しない `.claude/commands/` を削除し、
`rules/` `agents/` `.spec/` を追加）。

### D6: issue-hierarchy.md ⇔ task-start の重複（H9）

4ブロック（既定構成表・survey 理由・ゴール不変性・現状/目標の対話確認）が
ほぼ全文で二重掲載されており、既に内容差が発生している
（`bug（単独）` vs `bug（単独。validation を伴う場合あり）`）。

**`issue-hierarchy.md` を SSOT とし、`task-start/SKILL.md` は参照に置き換える。**
ただし**対話の質問文そのもの**（Step 2/3 の質問リスト）は task-start 固有の手順なので残す。

内容差は **`issue-hierarchy.md` 側（`bug（単独）`）を正**とする。
「validation を伴う場合あり」は既定構成の例外であり、
task 本文に理由を書けば逸脱できる既存規定でカバーされるため、表に書かない。

## Fallback ホワイトリスト

なし。

## 検証チェックリスト

- [ ] V1: `grep -rn "gh issue create" .claude/skills` が `issue-create/SKILL.md` と
      「直接呼ばない」旨の記述以外に 0 件
- [ ] V2: `gh issue list --limit 1` 由来の ID 取得が 0 件
- [ ] V3: `ls .claude/skills` と skills.md 掲載スキルの差分が 0
- [ ] V4: `/commit` がルータとして説明され、`/commit-only` が別行にある
- [ ] V5: `review/SKILL.md` と skills.md にサブエージェントの**件数表記が無い**
- [ ] V6: README 3言語にスキル表が無く、skills.md への参照がある。
      Directory Structure に `.claude/commands/` が無く `rules/` `agents/` `.spec/` がある
- [ ] V7: `task-start/SKILL.md` に既定構成表・survey 理由・ゴール不変性の**本文が無く**
      `issue-hierarchy.md` への参照になっている。対話の質問文は残っている
- [ ] V8: 既定構成表の内容差が解消（`bug（単独）` に統一）
- [ ] V9: quality-check PASS（#117 の skill-refs、#118 の skill-labels を含む）
- [ ] V11: 各呼び出し元で、状態ラベル／報告ラベルが `--extra-label` または
      後付け手順として**明示されている**（黙って落ちていない）
- [ ] V12: issue-create が「親なし」「親＝issue 層（小タスク）」「報告ラベル」の
      3パターンを停止させずに扱えることが SKILL.md 上で読み取れる
- [ ] V10: **再発防止** — skills.md と `ls .claude/skills` の差分検査を
      `check-skill-references.sh` に追加し、両方向（差分ありで FAIL / 一致で PASS）を確認
