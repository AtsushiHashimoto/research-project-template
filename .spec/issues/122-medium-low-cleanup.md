# Issue #122 仕様: integrity review Medium/Low 残件の一括修正

- 状態: approved（auto-reviewer 判断済み。条件と追補6件を反映。ログ: 122-auto-decisions.md）
- 由来: Integrity Review #114 の Medium/Low ＋ #116/#119/#121 からの引き継ぎ

## 棚卸し（着手前に実施）

#116〜#121 で既に解消された項目を除外した結果、残るのは下記。

| # | 項目 | 深刻度 |
|---|---|---|
| A | `.dev/` が規約化されているのに実体が無い（`/issue-backlog` `/issue-unblock` が必ず空振り） | Medium |
| B | QA データが `docs/qa/` のまま（`.dev/` 規約違反＋リリース成果物に QA ログが混入） | Medium |
| C | `qa-setup/SKILL.md` の死参照3件（`docs/qa/SETUP.md` / `requirements.txt` / `qa_bot.py`）＋`start-bot.sh` が孤立 | Medium |
| D | `TEMPLATE_REPO` が3箇所に重複（fork 時に更新漏れ） | Medium |
| E | 既定ブランチ `main` のハードコード。`git checkout main \|\| true` が失敗を握り潰す | Medium |
| F | `docs/security.md` の alias 記述が実装と乖離（既に削除済みの alias を「削除せよ」と案内） | Medium |
| G | `issue-scanner.md` のブランチ判定が `feature/` 接頭辞のみ（survey/fix/experiment 等を作業中と判定しない） | Low |
| H | devcontainer の表示名・hostname が固定（複数プロジェクトで区別不能） | Low |
| I | マジックナンバーに根拠コメントが無い（shm_size 等） | Low |
| J | `--force` 時に `shared_data_path` 等も復元する（#116 からの引き継ぎ） | Medium |
| K | template-sync でローカルに無いファイルが差分として報告されない（#121 からの引き継ぎ） | Medium |
| L | shebang の不統一が残存（#121 からの引き継ぎ） | Low |

### 追補（auto-reviewer が実測で発見した未解消項目）

**棚卸しで取りこぼしていた。** 放置すると goal「Medium/Low 処理済み」が事実に反する。

| # | 項目 | 深刻度 | 扱い |
|---|---|---|---|
| M | docker-compose の無確認 bind mount（`~/.gitconfig` `~/.config/gh`） | Medium | 本 issue で対応 |
| N | `setup-worktree.sh` の実行ビット無し | Medium | 本 issue で対応 |
| O | `.gitignore` 同期の3点非対称（sync に処理が無い） | Medium | 本 issue で対応 |
| P | `.spec/decisions/` `.spec/subsystems/` に sync 経路が無い | Medium | 本 issue で対応 |
| Q | qa 3スキルの frontmatter 欠落 | Low | 本 issue で対応 |
| R | `agents/` 参照の `.claude/` 接頭辞欠落 | Low | 本 issue で対応 |

## 設計

### D1: `.dev/` の実体化（A）

`.dev/.gitkeep` と `.dev/backlog.md` の雛形を追加し、`install.sh` の ITEMS に含める。
`release-export.sh` の除外には既に `.dev` が入っている（確認済み）。

**★ 条件（auto-reviewer）**: install の `--force` はマージコピーなので、素朴に ITEMS へ入れると
**既存プロジェクトの `backlog.md`（ユーザーデータ）が雛形で上書きされる**。
**存在しない場合のみ作成**すること。V に保持確認を追加。

### D2: QA データの移設（B, C）

- `scripts/qa/config.py` の `qa_dir` 既定値を `docs/qa` → `.dev/qa` に変更
- スキル（`qa-ask` `qa-check` `commit-*` `task-run` `issue-finish`）の参照を追随
- `qa-setup/SKILL.md` の死参照3件を実体に合わせる。起動は `scripts/qa/start-bot.sh` に一本化
- `docs/qa/SETUP.md` は**作らない**。手順は `qa-setup/SKILL.md` に集約する（SSOT）

**★ 条件（auto-reviewer）**: 既定値だけ変えると、既存プロジェクトは
**黙って空の `.dev/qa` を見始める**（R-D01 / KI-D03 と同型の silent-wrong）。

1. **legacy `docs/qa` にデータがあれば黙ってフォールバックせず、loud に案内する**
   （移行コマンドを提示する。自動移動はしない）
2. `config.py` だけでなく **`bot.py` と `watcher.py` のハードコード既定値**も追随させる
3. `rules/template/skills.md` と `commit-push` の参照も追随させる（V2 の「参照0」で担保）

### D3: `TEMPLATE_REPO` の一元化（D）

`.claude/template-source.json` を追加し、`install.sh` が配布時に書き出す。
スキル側はそこから読む。fork 検出の grep も `basename` から導出する。

**ただし install.sh 自身の定義は残す**（配布の起点であり、
自分自身をブートストラップできる必要があるため）。

**★ 条件（auto-reviewer）**: ハードコードは実測で**5箇所**（仕様が想定した3箇所に加え
`scripts/template-sync-rules.sh` と `scripts/template-contribute-detect.sh`）。
また既存派生プロジェクトには `template-source.json` が**存在しない**ため、
不在時の扱いを決める必要がある。**不在時はハードコード既定に落とす**が、
これは「設定のデフォルト値」なので **Fallback ホワイトリストに登録する**
（「Fallback なし」の宣言と矛盾させない）。

### D4: 既定ブランチの扱い（E）

**検出ではなく規約化を選ぶ。** `git-workflow.md` に「既定ブランチは `main` 固定」を明記し、
`git checkout main 2>/dev/null || true` の**握り潰しをやめる**（失敗したら停止）。

理由: 検出（`symbolic-ref`）は remote 設定に依存し、ローカル専用リポジトリで失敗する。
テンプレートの想定運用は `main` 固定であり、規約として明示するほうが挙動が読める。
握り潰しの解消が本質（feature ブランチに居たまま後続処理が進むのが実害）。

### D5: `docs/security.md` の更新（F）

alias は 2026-04-01 に削除済みで、現在は `post-start.sh` の `claude()` ラッパーが担う。
記述を実装に合わせる。

### D6: `issue-scanner` のブランチ判定（G）

`grep "feature/${ISSUE_ID}"` → `grep -E "/${ISSUE_ID}-"` に変更し、全接頭辞に対応する。

### D7: devcontainer の表示名（H）とマジックナンバー（I）

- `name` に `${localWorkspaceFolderBasename}` を使う
  （**★ 条件: この変数は devcontainer.json 専用で docker-compose.yml では展開されない**。
  `hostname` は別手段——指定の削除等——で対応し、実機確認まで V9 を PASS にしない）
- `shm_size` 等に「なぜこの値か」「更新方針」をコメント

### D8: `--force` 時の設定復元（J）

`created_at` と同様、`shared_data_path` / `path_type` / `storage_type` も
上書き前の値へ復元する。**データ保存先の silent reset を防ぐ**（INV-D03 に関わる）。

**★ 条件**: パスは `&` `|` 等を含みうるので `sanitize_sed` を必ず通す
（#116 で同型の sed インジェクションを踏んでいる）。V10 に特殊文字フィクスチャを追加。

### D9: template-sync の新規ファイル検出（K）

`diff -rq` はローカルに無いファイルでエラーになり握り潰されている。
**テンプレート側にあってローカルに無いファイルを「新規」として必ず報告する**ように直す。

**★ 条件（auto-reviewer）**: `2>/dev/null` の全面除去ではなく**存在チェックで新規報告**する実装にすること。
また **`.dev` は ITEMS に入れても SYNC_TARGETS には入れない**
（`backlog.md` はユーザーデータなので、毎回の偽差分と上書き提案を恒久生成してしまう）。
この非対称が意図的である旨をコメントに明記する。

### D10: shebang の統一（L）

`#!/bin/bash` の残存を `#!/usr/bin/env bash` に統一する。

## Fallback ホワイトリスト

1. **`template-source.json` 不在時にハードコードの既定 URL へ落ちる**（D3）。
   既存派生プロジェクトには当該ファイルが無いため。設定のデフォルト値に該当する。
   ただし**不在であることは出力に表示する**（黙って落ちない）。

D4 は握り潰しの**除去**であり Fallback の追加ではない。
D2 の legacy `docs/qa` は**フォールバックさせない**（loud に案内する）ので対象外。

## 検証チェックリスト

- [ ] V1: `.dev/backlog.md` が存在し、install の ITEMS に含まれる。`/issue-backlog` が空振りしない
- [ ] V2: QA の既定パスが `.dev/qa` になり、`docs/qa` への参照が 0（履歴記録を除く）
- [ ] V3: qa-setup の死参照 3件が解消し、起動手順が `start-bot.sh` を指す
- [ ] V4: `TEMPLATE_REPO` の実体が1箇所になり、スキルはそこから読む
- [ ] V5: `commit-merge.sh` の `checkout main` が失敗時に停止する（フィクスチャで確認）
- [ ] V6: `git-workflow.md` に「既定ブランチは main 固定」が明記されている
- [ ] V7: `docs/security.md` の記述が実装（post-start.sh のラッパー）と一致
- [ ] V8: issue-scanner が `survey/` `fix/` 等のブランチも作業中と判定する
- [ ] V9: devcontainer の name/hostname が可変になり、マジックナンバーに根拠コメントがある
- [ ] V10: `--force` 再インストールで `shared_data_path` 等が保持される（フィクスチャ）
- [ ] V11: template-sync がテンプレート新規ファイルを「新規」として報告する（フィクスチャ）
- [ ] V12: `git ls-files` 中の `#!/bin/bash` が 0
- [ ] V13: quality-check PASS（既存3検査を含む）。shellcheck は Docker 経由で確認
- [ ] V14: `--force` 再インストールで既存の `.dev/backlog.md` が**上書きされない**
- [ ] V15: legacy `docs/qa` にデータがある状態で loud な案内が出る（黙って無視しない）
- [ ] V16: `template-source.json` 不在時にハードコード既定へ落ち、**その旨が表示される**
- [ ] V17: 追補 M〜R の各項目が解消（bind mount ガード / 実行ビット / .gitignore 同期 /
      .spec サブディレクトリの sync 経路 / qa 3スキルの frontmatter / agents 参照の接頭辞）
- [ ] V18: `.dev` が SYNC_TARGETS に**入っていない**ことと、その理由コメントがある
