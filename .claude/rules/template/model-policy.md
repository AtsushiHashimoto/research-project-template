## モデル割当（role → model）

サブエージェントのモデルは**呼び出し箇所（call-site）の役割（role）**で決める（issue のラベルや層ではない）。

- **スキルに具体的なモデル名を書かない。** `MODEL=$(bash scripts/resolve-model.sh <role>)` で引き、`Agent(... model=...)` に渡す。
  role → モデルの単一情報源は `.claude/model-policy.json`
- role: `planning` / `abstract-review` / `implementation` / `verification`（既定 opus）、`mechanical`（haiku）。未定義は `inherit`
- エージェント定義の `role:` frontmatter は Claude Code が解釈しない。**解決して `model=` に渡すのは呼び出し側スキルの責務**
- 利用枠の上限: `bash scripts/resolve-model.sh --disable opus`（復帰は `--enable`、確認は `--list`）。
  書き込み先は gitignore 対象の `.claude/model-policy.local.json`（共有の json は書き換えない）

call-site の対応表・fallback・overrides の詳細は `model-policy-callsites.md`
（スキル・エージェント・model-policy を触ったときに読み込まれる）。
