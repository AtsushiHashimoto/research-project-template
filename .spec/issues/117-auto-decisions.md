# Issue #117 自動判断ログ

## メタ情報
- 判断日時: 2026-08-01
- 自動処理: /task-run
- 判断対象: .spec/issues/117-skill-name-migration.md（D1〜D5, V1〜V8）
- 親 task goal（#115・変更禁止）: #114 の Critical/High 全解消、Medium/Low まとめ処理、再発防止チェック、既存検証済み動作（#101 V1〜V11、#108 F1〜F6）を壊さない
- 必読コンテキスト: .spec/core-rules.md / invariants.md / known-issues.md — 3ファイルとも既定節あり（S1 非該当）。
  **プロジェクト固有節は3ファイルとも未記入のため、既定のみで判断した**（規定によりログに記録）

## 判断一覧

### 1. D1: 実在スキル名から明示マッピングを機械生成して置換

| 項目 | 内容 |
|------|------|
| 判断 | ⚠️ **警告付き許可**（下記の拘束条件付き） |
| 理由 | マッピング方式自体は妥当。`ls .claude/skills` の実在30スキルと D1 の27ペアを突き合わせ、一致を確認（router の `commit`、単独語の `review` `release` はスラッシュ形を持たないので対象外で正しい）。ファイルパス衝突（`/template/labels` 等・`docs/qa/*`）はペアの第2セグメントが異なるため誤検出しないことをリポジトリ全走査で実証。URL・git ref（`template/contribute-*` 等）との衝突も grep で 0 件を確認 |
| 参照 | `.claude/skills/` 実在一覧、リポジトリ全体 grep、issue #117 本文 |
| 自信度（参考記録） | 80% ※停止判定には使用しない |
| 停止条件チェック | 該当なし（条件を課すことで解消） |

**拘束条件（実装が必ず従うこと）:**

1. **先頭スラッシュ無しの `a/b` 形もマッピング対象に含める。** 実測で、issue #117 が「最優先」と明記する実行経路そのものが bare 形だった:
   - `.claude/skills/commit/SKILL.md:74,82` — `<parameter name="skill">commit/push</parameter>` `commit/merge`（ルータ3分岐の実体）
   - `.claude/skills/commit/SKILL.md:2` — frontmatter description 内 `commit/only, commit/push, or commit/merge`
   - `.claude/skills/issue-finish/SKILL.md:178` — `<parameter name="skill">commit/merge</parameter>`（委譲先）
   - `.claude/skills/issue-backlog/SKILL.md:57` — `Skill(skill="issue/unblock")`
   `/<a>/<b>` のみの置換だと **C2 の最優先項目を1件も直せない**。
2. **境界条件付きで置換する。** 左境界: 直前が `[A-Za-z0-9_./-]` でないこと（`.spec/init` のようなパス断片を保護）。右境界: 直後が `[a-z-]` でも `/` でもないこと（部分一致・ref 断片を保護）。
3. **事前衝突チェック**: 各ペア `a/b` について `git ls-files | grep "a/b"` が 0 件であることを置換前に assert する（現時点で 0 件を確認済み。将来ファイル追加で崩れた場合に silent-wrong になるのを防ぐ。KI-D03 の類推）。

### 2. D2: リネーム済み旧名（/issue-auto /issue-cycle /start-task /finish-task）の置換

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | 旧名→新名の対応はスキル一覧（rules/template/skills.md）と整合。`/start-task` `/finish-task` は install.sh:409-414・setup.sh:74 に現存を実測（issue 本文の行番号 329-335/52,54 は陳腐化しているが実体は残存、仕様は行番号に依存しないので問題なし）。`.spec/core-rules.md:4` の「/issue-auto の自信度ゲート」→ S1 参照への書き換えは #95（自信度ゲート廃止）および auto-reviewer 定義と整合し、現行ルール文書の修正として正当 |
| 参照 | install.sh / setup.sh 実測、auto-reviewer 定義、core-rules.md:4 |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

補足: V2 の grep は bare 形（先頭スラッシュ無しの `issue-auto` 等）も対象に含めること（D1 条件1と同じ理由）。

### 3. D3: 除外範囲（.spec/issues/** docs/surveys/** data/shared/integrity-reviews/**）

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | 「当時の実行記録は書き換えない」は R-D04（記録の再実行なし書き換え禁止）の精神と一致。逆に `.spec/` の3ルールファイルは現行文書なので対象に含めるのが正しい。実測: `.spec/decisions/` `.spec/subsystems/` は空、`docs/` 直下（claude-san.md 等）に旧名ヒット 0 件 — 除外リスト外に取り残される現行文書は無い。仕様書自身（117-skill-name-migration.md）は旧名の対照表を含むが `.spec/issues/**` で除外されるため V1 と矛盾しない設計になっている |
| 参照 | R-D04、リポジトリ実測 |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

補足（助言）: 実装時の走査から `.git/` `worktrees/` `.claude/rules/template.bak-*`（gitignore 対象・存在すれば退避記録）も除外すること。

### 4. D4: 「CLAUDE.md の◯◯参照」の宛先修正

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | 修正先ファイル（labels.md / experiment-discipline.md / issue-hierarchy.md）は全て `.claude/rules/template/` に実在を確認。`.claude/workflows/` の不存在も確認。参照切れの実ファイルへの付け替えであり、単一情報源の原則にも沿う。V6 が存在検証を担保 |
| 参照 | `.claude/rules/template/` 実在一覧 |
| 自信度（参考記録） | 90% |
| 停止条件チェック | 該当なし |

### 5. D5: `/commit push`（ルータ引数記法）の温存

| 項目 | 内容 |
|------|------|
| 判断 | ✅ 許可 |
| 理由 | `/commit push`（空白区切り）はルータの引数付き呼び出しで、現在も有効な記法。マッピングペアは `commit/push`（スラッシュ）なので機械置換と衝突しない。commit/SKILL.md の Usage 例（`/commit push` → 内部で commit-push へ委譲）の動作は温存される。ただしルータ内部の委譲先表記（bare `commit/push` 等）は D1 条件1により置換対象 — この区別（「ユーザー向け引数記法は温存 / 内部委譲先のスキル名は置換」）を実装時に混同しないこと |
| 参照 | `.claude/skills/commit/SKILL.md` 実測 |
| 自信度（参考記録） | 95% |
| 停止条件チェック | 該当なし |

### 6. 検証チェックリスト V1〜V8 の十分性

| 項目 | 内容 |
|------|------|
| 判断 | ⚠️ 警告付き許可（V3 の具体化と V9 の追加を拘束条件とする） |
| 理由 | 骨格は妥当だが、(a) V1/V2 が leading-slash 形しか見ないなら実行経路の bare 形が素通りする、(b) V3 の「参照数が減っていない」は抽出器が未定義で判定者により結果が割れる、(c) issue #117 の完了条件「quality-check にスキル参照名の実在検証を追加（再発防止）」が仕様に欠落しており、親 task goal の「再発防止チェックが入っている」を満たせない |
| 自信度（参考記録） | 85% |
| 停止条件チェック | S4 を検討したが、下記の拘束的具体化により PASS/FAIL 判定可能となるため停止しない |

**拘束条件（V の具体化）:**

- **V1/V2**: grep は `/a/b` と bare `a/b` の両形を境界条件付き（D1 条件2）で対象にする。
- **V3 の具体的手順**（これを V3 の定義とする）:
  1. 置換前: 各マッピングペアについて `git ls-files | grep -c "<a>/<b>"` = 0 を assert（パス衝突なしの事前証明）
  2. 置換後: `git diff` の全 hunk について「削除行にマッピング適用＝追加行」となることをスクリプトで機械照合（マッピング外の変更が混入していないことの直接証明）
  3. 既知のパス表記（`rules/template/*.md` の11ファイル名、`docs/qa/` 表記）の出現数が置換前後で不変であることを grep で確認
- **V5**: スキル名の抽出対象に `Skill(skill="...")`・`<parameter name="skill">...</parameter>`・本文中の `/name` 表記を明示的に含める。
- **V7**: `git diff --stat -- .spec/issues docs/surveys data/shared/integrity-reviews`（本判断ログと 117 の仕様の状態更新を除く）が空であることで判定する。
- **V9（追加。issue 完了条件より）**: `scripts/quality-check.sh` に「`.claude/skills/**/SKILL.md`・README・install.sh/setup.sh 中のスキル参照名が `ls .claude/skills` に実在すること」の検査を追加し、PASS することを確認する。これは goal の拡大ではなく、issue #117 本文の完了条件（再発防止）を仕様に反映するもの。

## ゴール書き換えチェック

- 親 task #115 の goal の変更: **なし**
- V9 の追加は issue #117 本文の完了条件・親 goal「再発防止チェックが入っている」の**既存範囲内**であり、範囲の拡大ではない（解釈の明確化として記録）

## 停止判断

- 該当した停止条件: **なし**（S1〜S6 すべて非該当）
  - S1: `.spec/` 3ファイル存在・既定節あり。プロジェクト固有節は未記入（続行可・記録済み）
  - S2: 親 goal は確定済み
  - S3: invariants / core-rules への抵触なし（D3 はむしろ R-D04 に整合）
  - S4: V3 の曖昧さを検討したが、本ログの拘束的具体化で判定可能に解消
  - S5: 既存パターン（明示マッピング・記録の不改竄）に沿った設計
  - S6: experiment ではないため対象外

## 要確認フラグ（停止には至らないが不確実性が残る項目）

- [ ] issue 本文の行番号（install.sh:329-335 / setup.sh:52,54）は現行と不一致（実体は 409-414 / 74,77）。実装は行番号でなくパターンで特定すること
- [ ] `worktree-safe-remove` のようにハイフン2個の名前は `<a>-<b>` 機械分割が一意でない。D1 の表（`/worktree/safe-remove`）を正とし、`/worktree/safe/remove` 形は検索のみ行い存在しないことを確認
- [ ] 置換は `.claude/rules/template/**` に旧名ヒットが現状 0 件のため MANIFEST 差分は発生しない見込みだが、V8 は必ず実行すること
