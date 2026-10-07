# {{PROJECT_NAME}} プロジェクト設定

## プロジェクト概要

{{PROJECT_DESCRIPTION}}

**研究者**: {{RESEARCHER_NAME}}
**開始日**: {{START_DATE}}

---

## 重要な注意事項

1. **常に worktree を使用**: メインディレクトリで直接作業しない
2. **Issue なしで作業しない**: すべてのタスクは Issue から開始
3. **進捗は Issue に記録**: コミット前に必ず報告
4. **ゴールは変更しない**: 結果に合わせて goal を書き換えない。変更が必要なら新しい epic を立てる
5. **ネガティブ結果を安易に受け入れない**: まず実装バグ・実験設定ミスを疑う
6. **ルールは絶対**: このファイルおよび `.claude/rules/` に記載された全てのルール、スキルで定義されたワークフローは必ず従う
7. **省略・逸脱する前に確認**: ルールから外れる行為をする場合は、事前に一言ユーザーに確認を取る。自己判断で「不要」「単純だから省略」と決めない

---

## ルールの所在

汎用的なワークフロールールは **`.claude/rules/template/`** に分割されています。
Claude は rules を自動で読み込みます。Codex は `.codex/instructions.md` の手順で
`python3 scripts/agent-rules.py` が列挙する常時ルールを読み、対象ファイルに応じて
同コマンドにパスを渡して `paths:` 付きルールも読みます。話題による選択は `template/on-demand.md` を参照。
ローカルルールをテンプレートより後に読み、明示された上書きを適用します。

| ファイル | 内容 |
|---|---|
| `template/issue-hierarchy.md` | epic / task / issue の3層構造、既定の task 構成、ゴールの不変性 |
| `template/labels.md` | ラベル運用ルール、GitHub ネイティブ sub-issue |
| `template/skills.md` | スキル一覧（層ごと）（必要なときだけ） |
| `template/model-policy.md` | サブエージェントのモデル割当（role → model）の規則 |
| `template/model-policy-callsites.md` | call-site の対応表、fallback、overrides（必要なときだけ） |
| `template/git-workflow.md` | コミット・PR・Git Worktree 管理 |
| `template/experiment-discipline.md` | ネガティブ結論の扱い、matched-engineering |
| `template/dev-guidelines.md` | コード品質、研究ノート、ブランチ命名 |
| `template/deliverables.md` | 成果物の保存場所、進捗報告 |
| `template/data-protection.md` | Worktree データ保護、モデル保存 |
| `template/optional-features.md` | Ollama、Shared Resource Manager、Claude Code 認証（必要なときだけ） |
| `template/premises.md` | ユーザー確定の前提の記録場所（大前提=`.spec/invariants.md` / epic 前提）と必読・即時追記 |
| `template/premises-migration.md` | 前提の置き場所の移行手順（必要なときだけ） |
| `template/doc-principles.md` | README と AGENTS.md の書き分け、アカウント層（`~/.claude/`）の使い分け |
| `template/env-node-and-claude-install.md` | Claude Code（native build）の導入要件・Node 要件・移行手順（必要なときだけ） |
| `template/on-demand.md` | 必要なときだけ読み込まれるルールの一覧と、常に効く要点 |

### このファイルに書くもの / rules に書くもの

| 内容 | 書く場所 |
|---|---|
| **プロジェクト固有**の概要・制約・ドメイン知識 | **このファイル** |
| 全プロジェクト共通のワークフロールール | `.claude/rules/template/`（テンプレート由来） |
| このプロジェクト専用のワークフロールール | `.claude/rules/` 直下に `*.md` を追加 |

**★ `.claude/rules/` 直下はローカル用、`template/` は書き換え禁止です。**

| 場所 | 位置づけ | `/template-sync` の扱い |
|---|---|---|
| `.claude/rules/*.md`（直下） | プロジェクトローカルのルール | **触らない**（例外: `template/` が無い旧構造からの移行時のみ、テンプレートと同名のファイルは移行対象として削除/退避される） |
| `.claude/rules/template/**` | テンプレート由来 | **ディレクトリごと置き換える** |

`template/` 配下を直接書き換えないでください。改変が検出されると sync 時に
`.claude/rules/template.bak-<日時>/` へ退避され、テンプレートへの**還流候補**として
`/template-contribute` に回されます（改変が消えることはありませんが、
プロジェクト固有の記述は還流できないため `template/` には書かないこと）。

---

## 必須コンテキスト

`.spec/` の3ファイルは `auto-reviewer` が判断前に**必ず読む**必須コンテキストです。

| ファイル | 内容 |
|---|---|
| `.spec/core-rules.md` | 絶対ルール |
| `.spec/invariants.md` | 変更禁止の設計判断 |
| `.spec/known-issues.md` | 過去の失敗パターン |

実プロジェクトの失敗実績から抽出した既定が同梱されており、**既定だけでも動作します**。
プロジェクト固有の内容は `/spec-init` で追加してください。

---

## プロジェクト固有のルール

<!-- ここにこのプロジェクト特有のルール・制約・ドメイン知識を書く -->

**プロジェクト大前提（ユーザー確定事項）は `.spec/invariants.md` の固有節が単一情報源。**
両エージェントとも毎セッションこのファイルを必ず読む（運用は `.claude/rules/template/premises.md`）。

## エージェント別の入口

共通ルール・スキルの呼出契約は `.claude/rules/template/agent-runtime.md`。
Claude は `.claude/CLAUDE.md` からこのファイルを import し、`.claude/rules/` を読み込む。
Codex は、このファイルに続いて **`.codex/instructions.md` を必ず読み**、そこに従って
必須 `.spec/` 3ファイルと共通 rules を読む。Codex 固有指示は Claude には適用しない。
共通変更を `.codex/` に複製しない。個人の承認・認証・表示設定はテンプレートの対象外。



（未記入）
