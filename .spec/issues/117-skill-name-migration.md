# Issue #117 仕様: 旧スキル名（スラッシュ表記）の全面置換と参照切れの解消

- 状態: approved（auto-reviewer 判断済み。拘束条件を D1' / V9 に反映。ログ: 117-auto-decisions.md）
- 由来: Integrity Review #114 C2/H7 ＋ Medium 2件

## 背景

7月末のスキル一斉リネーム（スラッシュ区切り → ハイフン区切り）で参照側が追従しておらず、
`/commit` ルータの全分岐や `issue-finish` の委譲先など**実行経路が死んでいる**。

## 設計

### D1: 置換は「実在スキル名から作った明示マッピング」でのみ行う

`grep -oE '/(issue|commit|qa|...)/[a-z-]+'` の素朴な一括置換は**危険**。
以下のファイルパス表記が同じ形をしており、壊すと参照が切れる:

| 誤検出する文字列 | 実体 |
|---|---|
| `/template/labels` `/template/skills` ほか | `.claude/rules/template/*.md` のパス |
| `/qa/questions` `/qa/answers` `/qa/requirements` | `docs/qa/*.jsonl` などのパス |

**したがって `ls .claude/skills` の実在名から `<a>-<b>` → `/<a>/<b>` を機械生成し、
そのペアだけを置換する。** 実在しないスキル名は置換対象にしない。

対象（実在30スキルのうちスラッシュ形が存在しうるもの）:

```
/commit/merge /commit/only /commit/push
/epic/cycle
/issue/backlog /issue/branch /issue/create /issue/diff /issue/finish
/issue/gaps /issue/report /issue/scan /issue/start /issue/unblock
/qa/ask /qa/check /qa/setup
/review/integrity /review/spec
/spec/init
/task/run /task/start
/template/contribute /template/sync
/worktree/init /worktree/safe-remove /worktree/setup
```

### D1': bare 形（先頭スラッシュ無し）も対象にする ★auto-reviewer 指摘

**実行経路はむしろ bare 形である。** 見落とすと本 issue の主目的を達成できない。

| 実測箇所 | 表記 |
|---|---|
| `commit/SKILL.md:2,74,82` | `Skill(skill="commit/push")` 等（ルータ3分岐の実体） |
| `issue-finish/SKILL.md:178` | 委譲先 `commit/merge` |
| `issue-backlog/SKILL.md:57` | `Skill(skill="issue/unblock")` |

置換は**境界条件付き**で行う:

- 左境界: 直前が `[A-Za-z0-9_./-]` でないこと（`.spec/init` 等のパス断片を守る）
- 右境界: 直後が `[a-z/-]` でないこと（より長いパスの一部を壊さない）
- 置換前に、各ペアが `git ls-files` の実在パスと衝突しないことを assert する

走査からは `.git/` `worktrees/` `template.bak-*` も除外する。

### D2: リネーム済みスキルの旧名

| 旧名 | 新名 |
|---|---|
| `/issue-auto` `/issue/auto` | `/task-run` |
| `/issue-cycle` `/issue/cycle` | `/epic-cycle` |
| `/start-task` | `/task-start` |
| `/finish-task` | `/issue-finish` |

`.spec/core-rules.md:4` は「`/issue-auto` の**自信度ゲート**」という二重の陳腐化
（リネーム＋#95 で廃止）。停止条件 S1 を参照する記述に書き換える。

### D3: 除外範囲（履歴の改竄を避ける）

以下は**当時の実行記録**なので書き換えない:

- `.spec/issues/**`（過去の仕様・判断ログ）
- `docs/surveys/**`（survey 成果物）
- `data/shared/integrity-reviews/**`（レビュー記録）

ただし `.spec/core-rules.md` `.spec/invariants.md` `.spec/known-issues.md` は
**現行ルール文書**なので対象に含める。

### D4: 「CLAUDE.md の◯◯参照」の宛先修正

節が `.claude/rules/template/` へ移設済みで参照先が失われているものを実ファイルに向ける。

| 場所 | 現在の参照 | 修正先 |
|---|---|---|
| `scripts/setup-labels.sh:8,77` | CLAUDE.md の表 / 「ラベル運用ルール」 | `.claude/rules/template/labels.md` |
| `.spec/core-rules.md` `.spec/invariants.md` `.spec/known-issues.md` | CLAUDE.md「実験の規律」 | `.claude/rules/template/experiment-discipline.md` |
| `.claude/skills/issue-create/SKILL.md:85` | CLAUDE.md「ゴールの不変性」 | `.claude/rules/template/issue-hierarchy.md` |
| `.claude/skills/task-run/SKILL.md:39,132` | CLAUDE.md 参照 | 該当する rules ファイル |
| `.claude/skills/review/SKILL.md:98` | `.claude/workflows/`（存在しない） | `.claude/rules/` |

### D5: `/commit push`（ルータ入力）は温存

`.claude/skills/commit/SKILL.md` はルータで、`/commit push` は**引数付き呼び出しの記法**
として有効。これは置換しない（`/commit/push` とは別物）。

## Fallback ホワイトリスト

なし（置換のみ。新規のエラー処理を導入しない）。

## 検証チェックリスト

- [ ] V1: D1 のマッピング表の全ペアについて、除外範囲を除き旧表記の残存が 0
- [ ] V2: 旧名（`/issue-auto` `/issue-cycle` `/start-task` `/finish-task`）の残存が 0（除外範囲を除く）
- [ ] V3: ファイルパス表記（`rules/template/*.md`、`docs/qa/*.jsonl`）が壊れていない
      — 置換前後で「実在するファイルへの参照数」が減っていないことを確認
- [ ] V4: `/commit` ルータの3分岐が実在スキル名を指す
- [ ] V5: `.claude/skills/*/SKILL.md` が参照するスキル名が全て `ls .claude/skills` に実在
- [ ] V6: D4 の参照先ファイルが全て実在する
- [ ] V7: 除外範囲（`.spec/issues/**` `docs/surveys/**` `data/shared/integrity-reviews/**`）が無変更
- [ ] V8: MANIFEST 再生成後 quality-check PASS
- [ ] V9: **再発防止**（issue #117 の完了条件）— quality-check に「スキル参照名の実在検証」を追加し、
      壊れた参照を仕込むと FAIL、正常時は PASS の両方向をフィクスチャで確認する

V1/V2 は bare 形も grep 対象に含めること。
V3 は「置換前のパス衝突 assert ＋ diff の全 hunk がマッピングに一致 ＋
既知パス表記（`rules/template/*.md` `docs/qa/*`）の出現数が不変」で判定する。
