---
paths:
  - ".claude/skills/**"
  - ".claude/agents/**"
  - ".claude/model-policy*.json"
  - "scripts/resolve-model.sh"
---

<!-- [Template] research-project-template 由来。プロジェクト固有の記述は AGENTS.md に書くこと -->

## モデル割当の詳細（call-site の対応表・fallback・overrides）

規則の要約は `model-policy.md`（常に読み込まれる）。ここはスキル・エージェント・ポリシーを触るときの詳細。

### role の一覧

| role | 内容 | 既定 |
|---|---|---|
| `planning` | 実装計画の策定、タスク分解、設計の骨子 | opus |
| `abstract-review` | 仕様レビュー、設計レビュー、代理判断 | opus |
| `implementation` | コードの実装・修正 | opus |
| `verification` | 実装と仕様の突き合わせ、コードレビュー、整合性チェック | opus |
| `mechanical` | 集計・分類・フォーマット確認 | haiku |

未定義の role は `inherit`（セッションのモデルを継承）になります。

抽象系 role（`planning` / `abstract-review`）の既定は以前 fable だったが、Opus 5 系が利用可能になったため opus に統一した。alias `opus` の解決先はクライアント版に依存する（Claude Code ≥ 2.1.280 で Opus 5 系。古いクライアントでは旧 Opus）。

### call-site の割当

| 呼び出し箇所 | role |
|---|---|
| `/review-spec` の各サブエージェント | `abstract-review` |
| `/review-spec` 3-4b（epic goal 整合チェッカー） | `abstract-review` |
| `auto-reviewer` の代理判断 | `abstract-review` |
| `/task-run` の issue ごとのワーカー（Step 1〜5 を実行し短く報告） | なし（セッションのモデルを継承） |
| `/task-run` Step 2（実装） | `implementation` |
| `/task-run` Step 4-2（仕様整合性チェック） | `verification` |
| `/review` の設計観点（アーキテクチャレビュー） | `abstract-review` |
| `/review` のコード観点（リスク／テスト／Fallback／仕様充足／ロジック／Best Practice／UI-UX） | `verification` |
| `/issue-scan` の集計 | `mechanical` |
| `/issue-diff` の乖離分析 | `verification` |
| `/issue-gaps` Phase 1（scan の集計） | `mechanical` |
| `/issue-gaps` Phase 2（乖離分析） | `verification` |
| `/review-integrity` Phase 1（6 エージェントの探索） | `verification` |
| `/review-integrity` Phase 3（前回との差分分析） | `verification` |
| `/epic-cycle` Step 2・3（`/issue-gaps`・`/review-integrity` を実行して件数だけ返す） | なし（セッションのモデルを継承。中の役は各スキルの表のとおり） |
| `/epic-cycle` Step 4（次 task の要否判断の下書き） | `planning` |
| `/epic-cycle` Phase Final（ゴール達成判定） | `abstract-review` |
| `/issue-backlog` Phase 2（着手可能項目の特定） | `mechanical` |
| `/issue-unblock` Phase 2（ブロッカー分類） | `mechanical` |
| `/issue-unblock` Phase 3（Gap 分析） | `mechanical` |

**この表は実装と一致していること。** 追加・変更したら対応する SKILL.md 側の
`resolve-model.sh <role>` 呼び出しも同時に更新する（片側だけ直さない）。

### 利用枠の上限に当たったとき

`disabled` に追加すると、そのモデルを primary に持つ role は **fallback に降ります**。

```bash
bash scripts/resolve-model.sh --disable opus    # 枠を使い切ったとき
bash scripts/resolve-model.sh --enable  opus    # 復帰したとき
bash scripts/resolve-model.sh --list            # 現在の解決結果を確認
```

**書き込み先は `.claude/model-policy.local.json`（gitignore 対象）です。**
枠上限は個人・一時的な事情なので、共有される `.claude/model-policy.json` は書き換えません。
これにより通常運用で **git が汚れません**（汚れると `/template-contribute` の
偽の還流候補になります）。

読み取りは **local + 本体 + 環境変数の和**です。本体 json の `disabled` も
後方互換で読みます（旧バージョンが書き込んでいた場合のため）。
`--enable` は **両方のファイルから削除**し、環境変数などで解除しきれない残存が
あれば警告して非ゼロ終了します（「enable したつもりが fallback のまま」を防ぐため）。

一時的に切り替えるだけなら環境変数でも指定できます（設定ファイルより優先）。

```bash
MODEL_POLICY_DISABLE=opus /task-run #101
```

fallback は配列の順に降ります（既定は `opus → sonnet`）。全て無効なら `inherit` になります。

### プロジェクト固有の上書き

`.claude/model-policy.json` の `overrides` に書きます。

```json
"overrides": { "implementation": "sonnet" }
```

適用状況は `--list` の `OVERRIDE` 列で確認できます（`適用中` / `disabled のため未適用` / `-`）。

### 注意

- **メインのモデルを切り替えても、role が定義されていない呼び出しは追従します。**
  planning を別のモデル（例: fable）にしたい場合でも、実装の call-site が `implementation` role で
  呼ばれていれば opus のままになります
- エージェント定義（`.claude/agents/*.md`）の frontmatter には `role` を書きます。
  `model:` は `inherit` のままにし、実際の割当は本ポリシーで決めます
  （モデル名を2箇所に書かないため）
- **`role:` frontmatter は Claude Code が解釈しない独自キーです。**
  したがって **agent の role を解決して `model=` に渡すのは呼び出し側スキルの責務**です。
  スキルは agent 定義の `role:` を読み、`resolve-model.sh` で解決した結果を
  `Task(...)` / `Agent(...)` の `model=` に渡します。書かなければ何も効きません

  ```
  Task(subagent_type="general-purpose", model="$(bash scripts/resolve-model.sh abstract-review)", prompt="
  .claude/agents/auto-reviewer.md の定義に従って ...
  ")
  ```
