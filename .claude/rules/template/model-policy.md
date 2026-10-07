## モデル割当（role → model）

サブエージェントのモデルは**呼び出し箇所（call-site）の役割（role）**で決める（issue のラベルや層ではない）。

role は両エージェント共通。以下の省略形のコマンドとモデル例は Claude 用。
Codex は `bash scripts/resolve-model.sh --agent codex <role>` を使い、同じ JSON の
`agents.codex` から解決する。既定は `inherit`（モデル指定を省略）。Claude の別名を渡さない。
Codex の一時無効化は `--agent codex --disable <model>`、環境変数は
`CODEX_MODEL_POLICY_DISABLE`。Claude の disabled/override と分離する。
必須モデル指定に runtime が対応しないときや Codex 候補が全て無効なときは停止する。

- **スキルに具体的なモデル名を書かない。** `MODEL=$(bash scripts/resolve-model.sh <role>)` で引き、`Agent(... model=...)` に渡す。
  role → モデルの単一情報源は `.claude/model-policy.json`
- role: `planning` / `abstract-review` / `implementation` / `verification`（既定 opus）、`mechanical`（haiku）。未定義は `inherit`
- エージェント定義の `role:` frontmatter は Claude Code が解釈しない。**解決して `model=` に渡すのは呼び出し側スキルの責務**
- 利用枠の上限: `bash scripts/resolve-model.sh --disable opus`（復帰は `--enable`、確認は `--list`）。
  書き込み先は gitignore 対象の `.claude/model-policy.local.json`（共有の json は書き換えない）

call-site の対応表・fallback・overrides の詳細は `model-policy-callsites.md`
（スキル・エージェント・model-policy を触ったときに読み込まれる）。
