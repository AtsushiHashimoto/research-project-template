<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## スキル一覧

**スキル名の接頭辞は「操作対象の層」を表します。**

### epic 層

| スキル | 用途 |
|-------|------|
| `/epic-cycle <epic番号>` | ゴール達成まで task を繰り返し回す |

### task 層

| スキル | 用途 |
|-------|------|
| `/task-start [説明]` | **現状と目標を対話で確認**して task を作成、既定構成の子 issue を生成、実行確認 |
| `/task-run <task番号>` | task 配下の issue を既定順で自動処理（子は sub-issue API で自動解決） |

### issue 層

| スキル | 用途 |
|-------|------|
| `/issue-create` | **Issue 作成の単一情報源。** 他スキルは `gh issue create` を直接呼ばない |
| `/issue-start <番号>` | issue に着手（ブランチ→Worktree） |
| `/issue-branch [説明]` | 同一 Worktree 内で小タスクを分ける |
| `/issue-report` | 現在の進捗を Issue に報告 |
| `/issue-finish` | issue を完了（レビュー→**マージ**→クローズ） |

### 横断

| スキル | 用途 |
|-------|------|
| `/issue-scan` | 全 Issue の状態をスキャン |
| `/issue-diff` | Issue 仕様と実装の乖離を分析 |
| `/issue-gaps` | 乖離検出・不足 Issue の作成 |
| `/issue-backlog` | バックログ処理 |
| `/issue-unblock` | ブロッカー解消 Issue の作成 |

### コミット

| スキル | 用途 | Issueクローズ |
|-------|------|--------------|
| `/commit` | **ルータ。** 引数から `/commit-only` `/commit-push` `/commit-merge` に振り分ける | 振り分け先による |
| `/commit-only` | ローカルにコミットのみ | ❌ |
| `/commit-push` | コミット＆プッシュ（途中保存） | ❌ |
| `/commit-merge` | コミット＆マージ（タスク完了） | ✅ |

### レビュー

| スキル | 用途 |
|-------|------|
| `/review` | 多角的コードレビュー（複数の観点をサブエージェントで並列レビュー） |
| `/review-spec` | 実装前の仕様レビュー |
| `/review-integrity` | 定期的な実装整合性チェック（報告 issue を起票） |

### QA（ユーザーへの問い合わせ）

| スキル | 用途 |
|-------|------|
| `/qa-setup` | QAシステム（Slack/Discord連携）のセットアップ |
| `/qa-ask` | 質問を `.dev/qa/questions.jsonl` に追記 |
| `/qa-check` | `.dev/qa/answers.jsonl` の未処理回答を確認 |

### テンプレート管理

| スキル | 用途 |
|-------|------|
| `/template-sync` | テンプレートの最新更新を取り込み |
| `/template-contribute` | テンプレートへの改善PRを作成 |

### リリース

| スキル | 用途 |
|-------|------|
| `/release <version>` | 開発用ファイル（`.claude/` `.spec/` `.dev/` 等）を除いたクリーンな成果物を生成し GitHub Release を作成 |

### Worktree管理

| スキル | 用途 |
|-------|------|
| `/worktree-init` | 初回セットアップ（共有データパス・相対パス設定→`/spec-init`） |
| `/worktree-setup` | Worktreeにデータディレクトリを作成 |
| `/worktree-safe-remove` | Worktreeを安全に削除 |

### 仕様・ルール管理

| スキル | 用途 |
|-------|------|
| `/spec-init` | `.spec/` にプロジェクト固有のルール・失敗パターンを対話的に追加（再実行可） |

`.spec/` の3ファイル（`core-rules.md` / `invariants.md` / `known-issues.md`）は
`auto-reviewer` が判断前に**必ず読む**必須コンテキストです。
実プロジェクトの失敗実績から抽出した既定が同梱されており、**既定だけでも動作します**。
プロジェクト固有の内容は `/spec-init` で追加してください。
