# Issue #116 仕様: install.sh 初期化経路の修正

- 状態: approved（auto-reviewer 判断済み。要確認フラグ4件を下記に反映。ログ: 116-auto-decisions.md）
- 実装条件（auto-reviewer）:
  - D2: まずラッパー（worktree-init/init.sh）直呼びの可否を検証し、可能なら SSOT を優先。複製する場合は相互参照コメント必須
  - D4: `set -e` 下のため `if [ -f ... ]; then ...; fi` 形式でガード
  - D5: 生成ブロックだけでなく値収集プロンプトも分岐の外に出す（V5 を正とする）
  - Fallback: setup-labels 失敗時の案内メッセージは必須（メッセージ無し `|| true` への劣化は禁止）
- 由来: Integrity Review #114 C1/H1/H2/H3 ＋ Medium 2件。根拠は
  `data/shared/integrity-reviews/2026-08-01T0943/01-structure.md` / `03-todo-magic.md` / `06-wiring-test.md`

## 設計

### D1: GITIGNORE_ENTRIES の修正（C1）

- `install.sh:268` の `.worktrees/` → `worktrees/` に修正
- `.claude/rules/template.bak-*/` と `.claude/model-policy.local.json` をエントリに追加
  （どちらもワークフロー自身が生成する非コミット対象）
- 恒久策（GITIGNORE_ENTRIES とテンプレート .gitignore の完全 SSOT 化）は #122 の
  「.gitignore 同期の3点非対称」で扱う。本 issue は誤記の修正とエントリ追加まで

### D2: setup-labels の自動実行（H2）

- install.sh の初期化ステップを `scripts/init-data.sh` 直呼びから
  `worktree-init/init.sh` と同等の3点実行（configure-worktree-paths → setup-labels → init-data）に変更
- ラッパー（.claude/skills/worktree-init/init.sh）を直接呼ぶと install 時点の
  カレントディレクトリ問題があるため、install.sh 内で3スクリプトを順に呼ぶ形でよい
  （ただし呼び出し順序はラッパーと同一に保つ）
- gh 未認証環境では setup-labels が失敗しうる → 失敗しても install 全体は落とさず
  「後で bash scripts/setup-labels.sh を実行せよ」と案内（インストールの主目的はファイル配置のため）

### D3: sed -i の BSD/GNU 互換化（H3）

- `install.sh:238-241` と `setup.sh:20-27` の `sed -i "s|..|..|g" file` を
  `sed -i.bak "s|..|..|g" file && rm -f file.bak` 形式に変更（両実装で動作する唯一の共通形）

### D4: claude-san の扱い（H1）

- **配布はしない**（ITEMS に追加しない）。理由: claude-san は tmux+autoclaude 前提の
  ホスト用ランチャで、#51 のクローズ判断（task-run 系自動化が主線）と整合。
  配布物を増やすより依存を切る方向に倒す
- `.devcontainer/post-create.sh:38` の symlink 作成を `[ -f "$(pwd)/claude-san" ] &&` でガード
  （テンプレート自身と clone 派生では従来どおり動作、install 派生では dangling を作らない）

### D5: template-substitutions.json 生成の修正（Medium）

- 生成ブロックを「CLAUDE.md 不在」分岐の外に移動（既存 CLAUDE.md があっても生成）
- 非対話で値が全て空の場合は**書き出さない**（存在するのに無効、を防ぐ）

### D6: setup.sh の整理（Medium）

- worktree-config.json への死んだ sed（{{CREATED_AT}}/{{UPDATED_AT}}）を削除
- worktree-config.json の固定タイムスタンプは、install.sh / setup.sh 実行時に現在時刻を書き込む
- setup.sh のプレースホルダ置換を install.sh と同じサニタイズ付きロジックに揃える
  （完全な1本化＝setup.sh 廃止の判断は #122 で扱う。本 issue は挙動の同等化まで）

## Fallback ホワイトリスト

- D2 の「setup-labels 失敗でも install 続行＋案内」のみ（理由: インストールの主目的は
  ファイル配置であり、gh 未認証はインストール時点で正常にありうる状態のため。
  黙って握り潰さず、必ず案内メッセージを出す）

## 検証チェックリスト

- [ ] V1: フィクスチャ（既存 .gitignore 持ちの git repo）へ install 後、`git check-ignore worktrees/x` がマッチし `.worktrees` 文字列がリポジトリに存在しない
- [ ] V2: install 後の .gitignore に template.bak / model-policy.local.json のエントリがある
- [ ] V3: install ログに setup-labels の実行（または未認証時の案内）が出る
- [ ] V4: BSD sed（macOS ホスト）で対話 install がフィクスチャで完走し、プレースホルダが置換される
- [ ] V5: 既存 CLAUDE.md 持ちプロジェクトへの install でも substitutions.json が生成される（対話時）。非対話・空値では生成されない
- [ ] V6: post-create.sh が claude-san 不在時に symlink を作らない（bash -n ＋ ロジック確認）
- [ ] V7: #108 F1/F5/F6 のフィクスチャ（fresh install / --force 再インストール）が引き続き PASS
- [ ] V8: quality-check PASS
- [ ] V9: worktree-config.json に死んだ sed が無く、install/setup 実行後の created_at/updated_at が実行時刻になる
- [ ] V10: setup.sh 側も BSD sed で完走し、特殊文字（`|` や `&`）を含む入力値でも置換が壊れない（sed エスケープ確認）
