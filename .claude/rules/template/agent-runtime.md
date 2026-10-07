<!-- [Template] Shared Claude Code / Codex workflow execution contract. -->

## 共通スキルの実行契約

スキル本文は目的・手順・停止条件・入力/出力・レビュー観点の共通原本。
実行前に共有原本の SKILL.md と指定された必読参照を全文確認する。
カタログの name/description は発見用で、提示された抜粋だけで全手順を確認済みにしない。
コード例の `Skill` / `Agent` / `Task` / `SendMessage` は Claude の実行方法で、Codex に存在する API 名ではない。
エージェント固有の実行方法だけを次の契約で置き換え、ステップや判定を削らない。

| 操作 | Claude Code | Codex |
|---|---|---|
| スキルを実行 | Skill / `/<name>` | `$<name>` または共有 SKILL.md を読み同じ手順を実行 |
| ファイル/検索/shell | Read/Grep/Glob/Bash | 公開された read/search/shell ツール |
| 独立レビュー/worker | Agent（旧 Task） | 公開された独立エージェント起動機能 |
| 結果待ち・質問・再開 | Agent/SendMessage の仕様 | 公開された wait/message/resume の仕様 |
| モデル解決 | `resolve-model.sh <role>` | `resolve-model.sh --agent codex <role>` |

スキル/agent の body と必須コンテキストを渡す。`.claude/agents/` の Claude 用 tools/model frontmatter は
Codex の登録ではなく、本文のレビュー基準が共通原本。model は role から解決する。
`$ARGUMENTS` / `${CLAUDE_SKILL_DIR}` 等の Claude 展開は、Codex ではユーザー入力/実際の skill の位置から解決する。
`.claude/` というパス名だけを理由に共通ルールを無視しない。

### 実行前の能力確認

委譲を要求するスキルは開始前に独立エージェント・結果待ち・必要な再開・深さ/枠を確認する。
利用不能なら理由と未実行ゲートを報告して停止する。親本人の自己レビューに置き換えて通過扱いにしない。
同時枠の制約は独立性を維持した小バッチ/順次起動で対処できる。issue 自体の処理順は変えない。
起動失敗やレビュー未取得を「問題なし」にしない。外部送信やマージの許可は reviewer の承認から推測しない。

### ゲートと状態の保持

仕様レビュー → auto-reviewer（要求された場合）→ 実装 → 品質チェック → 仕様整合性 → 多角的 review → PR の
各ゲートを共有スキルに従って記録する。必読欠落、仕様不整合、品質 FAIL は後続・マージを阻止する。
研究の validation 先行、negative の格付け・トリアージ、goal 不変性、S1〜S8 は変更しない。
worker は要求された STATUS/QUESTION/HANDOFF で報告する。止まった worker へユーザー回答を渡し、
Issue の引き継ぎと原文前提を読み直して止まったステップから再開する。

### 共有対象

共有スキルは frontmatter の `metadata.harness: shared` を明示し、本ファイルを参照する。
Claude 専用は `metadata.harness: claude-only`。`scripts/agent-skills.py` が shared のみを公開する。
宣言は能力が存在する環境での手順対応を表し、全環境・全ゲートの実行実績を保証しない。
検証で未実行の CLI/ゲートはその旨を記録し、リンク作成だけを動作実証と呼ばない。
