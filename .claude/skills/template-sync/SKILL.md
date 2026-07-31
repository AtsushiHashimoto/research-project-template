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
| **`.claude/rules/template/`** | **ディレクトリごと置き換え**（`scripts/template-sync-rules.sh`。ローカル改変は退避） |
| `.claude/rules/*.md`（直下） | **触らない**。例外: 旧構造からの移行時（`template/` 不在）のみ、テンプレートと同名ファイルは移行処理される |
| `.claude/skills/` | 差分表示→選択適用 |
| `.claude/agents/` | 差分表示→選択適用 |
| `.claude/commands/` | 差分表示→選択適用 |
| `.claude/worktree-config.json` | 差分表示→選択適用 |
| `.devcontainer/` | 差分表示→選択適用 |
| `scripts/` | 差分表示→選択適用 |
| `.spec/*.md` の**既定節** | 差分表示→選択適用（**プロジェクト固有節は触らない**） |
| `.claude/CLAUDE.md` | **差分表示のみ**（自動上書きしない） |

### ★ `.claude/rules/template/` だけを置き換える

ワークフロールールは `.claude/rules/template/` に隔離されており、
**同期対象が機械的に確定する**。`rules/` 直下はプロジェクトローカル用で、sync は触らない。

```
.claude/rules/
├── template/          ← テンプレート由来。sync がディレクトリごと置き換える
│   ├── issue-hierarchy.md
│   ├── ...
│   └── MANIFEST.sha256    ← 前回 sync 時点の各ファイルの sha256
└── *.md               ← プロジェクトローカルのルール。sync は一切触らない
```

以前は全ルールが `.claude/CLAUDE.md`（543行）に同居しており、
プロジェクト固有記述と混在するため**自動上書きできなかった**。
その結果 sync のたびにコンフリクトが起き、解決の過程でテンプレート側の更新が捨てられていた。

実測では、あるプロジェクトが **template-sync を7回実施してなお CLAUDE.md の共通率が 4%** だった。
回数を重ねても収束しなかったのは、この構造が原因である。

**`.claude/rules/template/` にプロジェクト固有の記述を書かないこと。**
書いても失われはしないが（下記のとおり退避される）、還流できずに毎回退避され続ける。
プロジェクト固有のルールは `.claude/rules/` 直下か
`.claude/CLAUDE.md` の「プロジェクト固有のルール」節に書く。

#### 置き換えの規律（`scripts/template-sync-rules.sh` が実装している）

| 要件 | 内容 |
|---|---|
| **残骸の除去** | 実行冒頭で前回失敗の残骸 `.claude/rules/.template.new/` を除去する（残っていると `cp -r` が入れ子にコピーする） |
| **アトミック性** | 一時領域 `.template.new/` に展開 → `rm -rf template/` → `mv` で入れ替える。`rm -rf` してから `cp` は**禁止**（cp 失敗時に部分適用状態になる） |
| **改変の退避** | `template/MANIFEST.sha256` と現ファイルを照合し、不一致のファイルを `.claude/rules/template.bak-<YYYYMMDD-HHMMSS>/template/` にコピーしてから置き換える。MANIFEST が無い場合（初回・旧構造）は**全ファイルを改変扱い**で退避する |
| **サマリ表示** | 退避したファイル数と一覧を表示し、`/template-contribute` の実行を促す（**還流候補を黙って破壊しない**） |
| **旧構造の孤児** | `rules/` 直下にテンプレート既知名の `.md` が残っている場合（#91 フラット世代）、新版とハッシュ一致するものだけ削除し、**一致を証明できないものは退避**する（既定は削除ではなく退避）。未知の名前はローカルルールとして保持する |
| **失敗時** | 取得・展開に失敗したら**何も変更せず非0 exit ＋ エラーメッセージ**。無言の exit 0 は sync 済みと誤認させるため禁止 |

スクリプトを使わず手で実行しないこと。上記のどれか1つでも欠けると還流候補が消える。

## Workflow

### Step 1: テンプレートの最新版をダウンロード

**取得に失敗したら、そこで中止する。** 部分適用も無言終了もしない。

```bash
TEMPLATE_REPO="https://github.com/AtsushiHashimoto/research-project-template"
TMP_DIR=$(mktemp -d)
if ! git clone --depth 1 "$TEMPLATE_REPO" "$TMP_DIR/template"; then
    echo "ERROR: テンプレートの取得に失敗しました（ネットワーク / URL を確認）。何も変更していません。" >&2
    rm -rf "$TMP_DIR"
    exit 1
fi
```

### Step 2: `.claude/rules/template/` の同期（スクリプトに委譲）

```bash
bash scripts/template-sync-rules.sh --source "$TMP_DIR/template" || {
    echo "ERROR: rules の同期に失敗しました。" >&2
    rm -rf "$TMP_DIR"
    exit 1
}
```

- 事前に確認したい場合は `--dry-run` を付けて実行する（何も変更しない）
- スクリプトが「還流候補を退避した」と報告したら、**そのままユーザーに伝える**
  （サマリを握りつぶさない）。`/template-contribute` を案内する
- `rules/` 直下のローカルルールには触れない。以降の Step でも対象にしない

### Step 3: その他の差分の検出

同期対象の各ファイルについて、テンプレートの最新版とローカルファイルを比較します。
`.claude/rules/` は Step 2 で処理済みなので**含めない**。

```bash
# 対象ディレクトリ（rules は Step 2 で処理済み）
SYNC_TARGETS=(
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

### Step 4: 差分の提示

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

### Step 5: 選択的な適用

ユーザーに各変更について適用するか確認します：

- **新規ファイル**: 追加するか確認
- **変更されたファイル**: diff を表示し、適用するか確認
- **ローカルのみのファイル**: 何もしない（情報として表示）
- **CLAUDE.md**: diff表示のみ。ユーザーが手動で反映

### Step 6: クリーンアップ

```bash
rm -rf "$TMP_DIR"
```

## ⚠️ 既知の問題: `.spec/*.md` の「auto-reviewer への指示」節の重複

**既存の派生プロジェクトで sync を行う場合の注意。**

`.spec/core-rules.md` / `invariants.md` / `known-issues.md` は、
テンプレート側で `## auto-reviewer への指示` 節を**既定節の末尾**へ移動する予定です
（現在は「プロジェクト固有」節の**後ろ**にあり、その位置ではテンプレート側の更新が
永久に伝播しないため）。

そのため、旧世代の `.spec/*.md` を持つプロジェクトでは、既定節の差し替え後に
**旧位置（固有節の後ろ）に古い同名節が残り、新旧が重複します。**
重複した stale な節は auto-reviewer に矛盾した指示を与えます。

- sync 実行後、`.spec/*.md` に `## auto-reviewer への指示` が**2つ以上ある場合は
  旧位置（固有節の後ろ）のものを削除**してください
- 検出: `grep -c '^## auto-reviewer への指示' .spec/*.md`
- 自動処理（`scripts/sync-spec-defaults.sh` による旧節の検出・除去）は **#80 で実装予定**

## Implementation

1. テンプレートを一時ディレクトリにclone（失敗したら中止。非0 exit）
2. `.claude/rules/template/` を `scripts/template-sync-rules.sh` で同期（退避サマリを必ず報告）
3. その他の同期対象ファイルを再帰的に比較
4. 差分をカテゴリ別にまとめてユーザーに提示
5. ユーザーの選択に基づいてファイルをコピー
6. 一時ディレクトリを削除

**重要**:
- `.claude/CLAUDE.md` は**絶対に自動上書きしない**（プロジェクト固有の設定を含むため）
- `.claude/rules/template/` は**ディレクトリごと置き換える**（ローカル改変は退避してから）
- `.claude/rules/` 直下（ローカルルール）には触らない（**例外は旧構造からの移行時のみ**。`template/` が既に存在する場合は同名ファイルも意図的なローカル上書きとして保持される）
- 適用前に必ずユーザーに確認を取る
- 既存ファイルを上書きする前にバックアップを表示する（diffで確認できる）

## Note

- テンプレートリポジトリのURLは `install.sh` と同じものを使用
- ネットワーク接続が必要
- 逆方向（ローカル→テンプレート）の同期は `/template/contribute` を使用
