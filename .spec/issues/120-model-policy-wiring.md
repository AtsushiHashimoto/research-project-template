# Issue #120 仕様: model-policy の call-site 配線を完成させる

- 状態: approved（auto-reviewer 判断済み・警告3件の条件を反映。ログ: 120-auto-decisions.md）
- 由来: Integrity Review #114 H4（10 call-site 中2つのみ配線）。仕様の根拠は #114 と
  `data/shared/integrity-reviews/2026-08-01T0943/04-interface.md` / `06-wiring-test.md`

## 設計

### D1: call-site への model 指定の追加

`model-policy.md` の call-site 表に列挙された箇所のうち未配線の Task() 呼び出しに
`model="$(bash scripts/resolve-model.sh <role>)"` を追加する。

| SKILL.md | 箇所 | role |
|---|---|---|
| review | 設計観点のサブエージェント | abstract-review |
| review | コード観点のサブエージェント | verification |
| issue-scan | 集計 | mechanical |
| issue-diff | 乖離分析 | verification |
| issue-gaps | Phase1 scan | mechanical |
| issue-gaps | Phase2 diff 分析 | verification |
| review-integrity | Phase1 の6探索エージェント | verification |
| epic-cycle | Phase Final 達成判定 | abstract-review |
| issue-backlog | 分類・集計の Task()（1箇所） | mechanical |
| issue-unblock | ブロッカー分類・解消判定の Task()（2箇所） | mechanical |

（auto-reviewer 指摘: backlog/unblock は issue #120 のチェックボックスに明記されており漏らさない）
task-run / review-spec は配線済み（変更しない）。

### D2: agents の role frontmatter の解決規約

`.claude/agents/*.md` の `role:` は Claude Code が解釈しない独自キーであるため、
**呼び出し側スキルが agent の role を resolve-model.sh で解決して model= に渡す**ことを
`model-policy.md` の注意節に明記する。agent 定義側は `model: inherit` のまま（2箇所に書かない原則は維持）。

### D3: planning role の配線

`planning` role を `/epic-cycle` Step 4（結果駆動の次 task 判断）に配線する（call-site 表に追記）。
削除はしない（メインモデル切替時の追従性のため定義は残す価値がある）。

**auto-reviewer 条件**: Step 4 に新設する Task() の prompt には、epic goal の原文と
規律（goal 不変・投機禁止・survey 不 skip）を必ず埋め込むこと（KI-D14 直結箇所のため）。

### D4: --disable の汚染分離

`resolve-model.sh --disable/--enable` の書き込み先を `.claude/model-policy.local.json`
（gitignore 対象）に変更する。読み取りは local → 本体 の順にマージ
（local の disabled が優先。本体の disabled も後方互換で読む）。
`.gitignore` に `.claude/model-policy.local.json` を追加。
`model-policy.md` の該当節を更新（通常運用で git が汚れない旨）。

**auto-reviewer 条件**: `--enable` は本体 json の legacy `disabled` エントリも解除する
（両ファイルから削除）。解除できない場合は残存を明示出力する（KI-D03 類型の静かな状態不一致を防ぐ）。

### D5: --list の overrides 表示

`--list` の出力に override 適用の有無を表示する。

## Fallback ホワイトリスト

なし（新規 fallback を導入しない。resolve-model.sh 既存の role fallback 連鎖は変更しない）。

## 検証チェックリスト

- [ ] V1: model-policy.md call-site 表の全行について、対応する SKILL.md に `resolve-model.sh <role>` を含む呼び出しが存在する（grep で機械確認）
- [ ] V2: `--disable fable` 実行後に `git status --porcelain` が空。`--list` が fallback（opus）を反映。`--enable fable` で復帰
- [ ] V3: planning role が call-site 表に実 call-site を持つ
- [ ] V4: `--list` に overrides の適用状況が表示される
- [ ] V5: quality-check PASS
- [ ] V6: 既定の解決結果（abstract-review=fable / implementation=opus / mechanical=haiku）が不変

## スコープ外

- 各スキル実行時に実際にそのモデルが使われることの実機確認（次回の実スキル実行が canary）
