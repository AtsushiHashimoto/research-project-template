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

汎用的なワークフロールールは **`.claude/rules/`** に分割されています。
これらは**セッション開始時に自動で読み込まれる**ため、明示的な参照は不要です。

| ファイル | 内容 |
|---|---|
| `issue-hierarchy.md` | epic / task / issue の3層構造、既定の task 構成、ゴールの不変性 |
| `labels.md` | ラベル運用ルール、GitHub ネイティブ sub-issue |
| `skills.md` | スキル一覧（層ごと） |
| `model-policy.md` | サブエージェントのモデル割当（role → model）、枠上限時のフォールバック |
| `git-workflow.md` | コミット・PR・Git Worktree 管理 |
| `experiment-discipline.md` | ネガティブ結論の扱い、matched-engineering |
| `dev-guidelines.md` | コード品質、研究ノート、ブランチ命名 |
| `deliverables.md` | 成果物の保存場所、進捗報告 |
| `data-protection.md` | Worktree データ保護、モデル保存 |
| `optional-features.md` | Ollama、Claude Code 認証 |
| `doc-principles.md` | README と CLAUDE.md の書き分け |

### このファイルに書くもの / rules に書くもの

| 内容 | 書く場所 |
|---|---|
| **プロジェクト固有**の概要・制約・ドメイン知識 | **このファイル** |
| 全プロジェクト共通のワークフロールール | `.claude/rules/` |

**`.claude/rules/` はテンプレート由来です。** `/template-sync` が丸ごと差し替えるため、
プロジェクト固有の記述を書かないでください（更新時に失われます）。

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

（未記入）
