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
| `.claude/worktree-config.json` | 差分表示→選択適用 |
| `.claude/model-policy.json` | 差分表示→選択適用 |
| `.devcontainer/` | 差分表示→選択適用 |
| `scripts/` | 差分表示→選択適用 |
| `.spec/*.md` の**既定節** | **マーカー間を自動差し替え**（`scripts/sync-spec-defaults.sh`。**プロジェクト固有節は触らない**） |
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

### Step 3: `.spec/*.md` の既定節の同期（スクリプトに委譲）

```bash
bash scripts/sync-spec-defaults.sh --source "$TMP_DIR/template" || {
    echo "⚠️ .spec の既定節を同期できなかったファイルがあります（上のサマリを参照）。" >&2
    SPEC_SYNC_FAILED=1
}
```

- 差し替えるのは `# 既定の` 〜 `# プロジェクト固有` の**直前**まで。
  固有節（`# プロジェクト固有` 以降）は**一切触らない**
- 事前に確認したい場合は `--dry-run` を付けて実行する
- **マーカーが見つからないファイルはスキップされ、非0 exit になる。**
  サマリに出たファイル名を**そのままユーザーに伝える**（握りつぶさない）。
  スキップされたファイルはテンプレートの更新が届いていないので、
  マーカーを手で復旧してから再実行する
- 旧世代の `.spec/*.md`（`## auto-reviewer への指示` 節が固有節の**後ろ**にある）では、
  スクリプトが旧位置の同名節を自動で除去する（新旧の重複防止）。除去した旨がサマリに出る

### Step 4: 旧構造（543行世代 CLAUDE.md）の移行判定

**検出条件: `.claude/rules/` が存在しない。**

```bash
if [ ! -d .claude/rules ]; then
    echo "旧構造（543行世代の CLAUDE.md）を検出しました。"
fi
```

この世代はワークフロールールが `.claude/CLAUDE.md` に固有記述と混在しています。
**混在したままでは自動上書きできず、sync のたびにテンプレート側の更新が捨てられます**
（実測: 7回 sync してなお共通率 4%）。

#### 対話モード

1. **新しい `.claude/rules/template/` を配置する**（Step 2 のスクリプトが行う。
   `template/` 不在なので移行モードで動作する）
2. **重複部分を diff で提示する。** 既存 `CLAUDE.md` と、テンプレート**旧版**の
   CLAUDE.md（`git -C "$TMP_DIR/template" show <旧タグ/コミット>:.claude/CLAUDE.md`、
   取得できなければ現行 `rules/template/*.md` の内容）を突き合わせ、
   「テンプレート由来でそのまま残っている段落」を列挙する

   ```bash
   git -C "$TMP_DIR/template" log --oneline -- .claude/CLAUDE.md | tail -20
   diff -u <(git -C "$TMP_DIR/template" show "$OLD_REV:.claude/CLAUDE.md") .claude/CLAUDE.md
   ```

3. **固有部分の抽出は必ずユーザー確認つきで行う。**
   - 「この段落はテンプレート由来なので削除してよいか」を**1件ずつ確認**する
   - **自動では1行も削らない**（固有記述の自動削除は禁止）
   - 残す判断のものは `.claude/CLAUDE.md` の「プロジェクト固有のルール」節に移す
4. 置き換え後の `CLAUDE.md` をユーザーに提示し、承認を得てから書き込む

#### auto モード（`/task-run` 経由）

**移行は行わない。** 対話で確認できないため、固有記述を失う危険がある。

代わりに `user-action` ラベルつきの issue を **`/issue-create` 経由で**起票し、処理を止めずに次へ進む
（`gh` コマンドで直接作成しない。`.claude/rules/template/skills.md` の単一情報源の原則）。

1. 以下の本文を一時ファイル（例: `$TMP_DIR/migration-issue.md`）に書き出す:

   ```markdown
   ## 背景

   /template-sync が旧構造（.claude/rules/ が存在しない）を検出しました。
   CLAUDE.md にワークフロールールとプロジェクト固有記述が混在しているため、
   テンプレートの更新が自動で取り込めない状態です。

   ## 対応

   対話モードで `/template-sync` を実行し、重複部分の diff を確認しながら
   固有記述を切り出してください（自動移行は行いません）。

   ## 注意

   - 固有記述の自動削除は禁止。1件ずつ確認すること
   ```

2. `/issue-create` で起票する。移行はどの task にも属さない単発作業のため `--parent` は付けない:

   ```
   Skill(skill="issue-create", args="--type chore --title 'chore: 543行世代の CLAUDE.md を .claude/rules/template/ 構造へ移行する' --body-file $TMP_DIR/migration-issue.md")
   ```

3. 作成された issue に状態ラベルを付与する（種類ラベル以外は `/issue-create` の対象外のため）:

   ```bash
   gh issue edit "$ISSUE_ID" --add-label user-action
   ```

Issue 番号を完了報告に記録し、sync の残りの Step は通常どおり続行する。

### Step 5: その他の差分の検出

同期対象の各ファイルについて、テンプレートの最新版とローカルファイルを比較します。
`.claude/rules/` は Step 2、`.spec/*.md` は Step 3 で処理済みなので**含めない**。

```bash
# 対象（rules と .spec は処理済み）。install.sh の ITEMS / contribute-detect と対称に保つ
SYNC_TARGETS=(
    ".claude/agents"
    ".claude/skills"
    ".claude/worktree-config.json"
    ".claude/model-policy.json"
    ".devcontainer"
    "scripts"
)

# 各ファイルのdiffを取得
for target in "${SYNC_TARGETS[@]}"; do
    diff -rq "$TMP_DIR/template/$target" "$target" 2>/dev/null
done
```

### Step 6: 差分の提示

ユーザーに差分を提示します：

```markdown
## テンプレート更新の検出結果

### 新規ファイル（テンプレートにのみ存在）
- `.claude/skills/new-skill/SKILL.md`

### 変更されたファイル
- `.claude/skills/commit-merge/SKILL.md` (テンプレート側で更新あり)
- `scripts/safe-remove-worktree.sh` (テンプレート側で更新あり)

### ローカルのみのファイル（テンプレートに存在しない）
- `.claude/skills/custom-skill/SKILL.md` (ローカル追加)

### CLAUDE.md の差分（参考表示のみ）
[diff表示]
```

### Step 7: 選択的な適用

ユーザーに各変更について適用するか確認します：

- **新規ファイル**: 追加するか確認
- **変更されたファイル**: diff を表示し、適用するか確認
- **ローカルのみのファイル**: 何もしない（情報として表示）
- **CLAUDE.md**: diff表示のみ。ユーザーが手動で反映

### Step 8: クリーンアップ

```bash
rm -rf "$TMP_DIR"
```

## Implementation

1. テンプレートを一時ディレクトリにclone（失敗したら中止。非0 exit）
2. `.claude/rules/template/` を `scripts/template-sync-rules.sh` で同期（退避サマリを必ず報告）
3. `.spec/*.md` の既定節を `scripts/sync-spec-defaults.sh` で同期（スキップ報告を必ず伝える）
4. 旧構造（`.claude/rules/` 不在）なら CLAUDE.md の移行判定（auto モードでは issue 起票のみ）
5. その他の同期対象ファイルを再帰的に比較
6. 差分をカテゴリ別にまとめてユーザーに提示
7. ユーザーの選択に基づいてファイルをコピー
8. 一時ディレクトリを削除

**重要**:
- `.claude/CLAUDE.md` は**絶対に自動上書きしない**（プロジェクト固有の設定を含むため）
- `.claude/rules/template/` は**ディレクトリごと置き換える**（ローカル改変は退避してから）
- `.claude/rules/` 直下（ローカルルール）には触らない（**例外は旧構造からの移行時のみ**。`template/` が既に存在する場合は同名ファイルも意図的なローカル上書きとして保持される）
- `.spec/` の**プロジェクト固有節**（`# プロジェクト固有` 以降）は**絶対に触らない**
- 543行世代の CLAUDE.md 移行は**対話モードのみ**。auto モードでは `user-action` issue を起票する
- 適用前に必ずユーザーに確認を取る
- 既存ファイルを上書きする前にバックアップを表示する（diffで確認できる）

## Note

- テンプレートリポジトリのURLは `install.sh` と同じものを使用
- ネットワーク接続が必要
- 逆方向（ローカル→テンプレート）の同期は `/template/contribute` を使用
