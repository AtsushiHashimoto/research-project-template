---
description: Sync updates from research-project-template (テンプレート更新の取り込み)
---

# Template Sync（テンプレート更新の取り込み）

テンプレートリポジトリの最新版をダウンロードし、現在のプロジェクトとの差分を表示・選択的に適用します。

## 用途

- テンプレートの新機能や修正を下流プロジェクトに取り込む
- テンプレートと現在のプロジェクトの差異を確認する

## 対象ファイル

以下のディレクトリ・ファイルが同期対象です：

| パス | 同期方法 |
|------|---------|
| **`.claude/rules/`** | **丸ごと置き換え**（テンプレート由来。プロジェクト固有記述を含まない） |
| `.claude/skills/` | 差分表示→選択適用 |
| `.claude/agents/` | 差分表示→選択適用 |
| `.claude/commands/` | 差分表示→選択適用 |
| `.claude/worktree-config.json` | 差分表示→選択適用 |
| `.devcontainer/` | 差分表示→選択適用 |
| `scripts/` | 差分表示→選択適用 |
| `.spec/*.md` の**既定節** | 差分表示→選択適用（**プロジェクト固有節は触らない**） |
| `.claude/CLAUDE.md` | **差分表示のみ**（自動上書きしない） |

### ★ `.claude/rules/` は丸ごと置き換えてよい

ワークフロールールは `.claude/rules/` に分離されており、
**プロジェクト固有の記述を含まない**設計になっている。そのため上書きしても情報が失われない。

```bash
rm -rf .claude/rules/
cp -r "$TMP_DIR/.claude/rules/" .claude/rules/
```

以前は全ルールが `.claude/CLAUDE.md`（543行）に同居しており、
プロジェクト固有記述と混在するため**自動上書きできなかった**。
その結果 sync のたびにコンフリクトが起き、解決の過程でテンプレート側の更新が捨てられていた。

実測では、あるプロジェクトが **template-sync を7回実施してなお CLAUDE.md の共通率が 4%** だった。
回数を重ねても収束しなかったのは、この構造が原因である。

**`.claude/rules/` にプロジェクト固有の記述を書かないこと。** 書くと sync で失われる。
プロジェクト固有のルールは `.claude/CLAUDE.md` の「プロジェクト固有のルール」節に書く。

## Workflow

### Step 1: テンプレートの最新版をダウンロード

```bash
TEMPLATE_REPO="https://github.com/AtsushiHashimoto/research-project-template"
TMP_DIR=$(mktemp -d)
git clone --depth 1 "$TEMPLATE_REPO" "$TMP_DIR/template" 2>/dev/null
```

### Step 2: 差分の検出

同期対象の各ファイルについて、テンプレートの最新版とローカルファイルを比較します。

```bash
# 対象ディレクトリ
SYNC_TARGETS=(
    ".claude/rules"        # 丸ごと置き換え対象
    ".claude/agents"
    ".claude/commands"
    ".claude/skills"
    ".claude/worktree-config.json"
    ".devcontainer"
    "scripts"
)

# 各ファイルのdiffを取得
for target in "${SYNC_TARGETS[@]}"; do
    diff -rq "$TMP_DIR/template/$target" "$target" 2>/dev/null
done
```

### Step 3: 差分の提示

ユーザーに差分を提示します：

```markdown
## テンプレート更新の検出結果

### 新規ファイル（テンプレートにのみ存在）
- `.claude/commands/new-command.md`

### 変更されたファイル
- `.claude/commands/commit/merge.md` (テンプレート側で更新あり)
- `scripts/safe-remove-worktree.sh` (テンプレート側で更新あり)

### ローカルのみのファイル（テンプレートに存在しない）
- `.claude/commands/custom-command.md` (ローカル追加)

### CLAUDE.md の差分（参考表示のみ）
[diff表示]
```

### Step 4: 選択的な適用

ユーザーに各変更について適用するか確認します：

- **新規ファイル**: 追加するか確認
- **変更されたファイル**: diff を表示し、適用するか確認
- **ローカルのみのファイル**: 何もしない（情報として表示）
- **CLAUDE.md**: diff表示のみ。ユーザーが手動で反映

### Step 5: クリーンアップ

```bash
rm -rf "$TMP_DIR"
```

## Implementation

1. テンプレートを一時ディレクトリにclone
2. 同期対象のファイルを再帰的に比較
3. 差分をカテゴリ別にまとめてユーザーに提示
4. ユーザーの選択に基づいてファイルをコピー
5. 一時ディレクトリを削除

**重要**:
- `.claude/CLAUDE.md` は**絶対に自動上書きしない**（プロジェクト固有の設定を含むため）
- `.claude/rules/` は**丸ごと置き換えてよい**（テンプレート由来。プロジェクト固有記述を含まない設計）
- 適用前に必ずユーザーに確認を取る
- 既存ファイルを上書きする前にバックアップを表示する（diffで確認できる）

## Note

- テンプレートリポジトリのURLは `install.sh` と同じものを使用
- ネットワーク接続が必要
- 逆方向（ローカル→テンプレート）の同期は `/template/contribute` を使用
