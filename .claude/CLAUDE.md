# {{PROJECT_NAME}} プロジェクト設定

## プロジェクト概要

{{PROJECT_DESCRIPTION}}

**研究者**: {{RESEARCHER_NAME}}
**開始日**: {{START_DATE}}

---

## Issue 階層

Issue は **epic / task / issue の3層**で構成します。親子関係は **GitHub ネイティブの sub-issue** で表し、
種別は**ラベル**で表します。

| 層 | ラベル | 役割 | worktree | マージ |
|---|---|---|---|---|
| **epic** | `epic` | ゴール。task をまとめる | 持たない | しない |
| **task** | `task` | 1つのまとまった仕事 | 持たない | しない |
| **issue** | 種類ラベル | 実作業 | **1つ持つ** | **個別にマージ** |
| 小タスク | — | 分割不要な粒度 | 親と共有 | 親と一緒 |

**Issue の単位と worktree の単位は別です。** worktree を持つのは issue 層だけです。
これにより、task 内の各 issue が個別にマージされ、main との乖離が溜まりません。

### 既定の task 構成（必須）

task の下には以下の順で issue を置きます。**省略する場合は task 本文に理由を記載**してください。

```
task
 ├─ 1. survey       既存手法・先行研究の調査（novelty / baseline 監査）
 ├─ 2. spec         仕様の作成・レビュー
 ├─ 3. feature      実装
 ├─ 4. validation   実装は仕様どおり動くか（実装の正しさ）
 └─ 5. experiment   仮説は正しいか（設計の正しさ）
```

| task の種類 | 既定の構成 |
|---|---|
| 新手法の検証 | survey → spec → feature → validation → experiment |
| 既存実装の改善 | spec → feature → validation |
| バグ修正 | bug（単独） |
| 調査のみ | survey（単独） |
| 基盤整備 | spec → feature → validation |

**`validation` が PASS して初めて `experiment` の negative を信じてよい。**
実装の正しさと設計の正しさを別の issue に分けることで、negative が出たときに
「設計が悪い」のか「実装がバグっている」のかを切り分けられます。

### survey を先頭に置く理由

**novelty / baseline 監査を手順そのものにするためです。**
「既存手法で既に解けるか」の確認が後回しになると、複数段を消化した後に
「古典手法で厳密に解ける」と判明して全結果が無価値になります（実際に観測された失敗）。

**2周目以降も survey を skip しません。** 内容は「ゼロからの調査」ではなく
「ここまでの結果を踏まえて追加サーベイが必要か」の検討です。
不要と判断した場合も、skip ではなく判断の記録を残して閉じます。
**結果が出るたびに探すべき場所が変わる**ためです。

### ★ ゴールの不変性

**epic の goal は変更しません。** 追加 task を作る際は既存の goal を読み直し、
「この goal に照らして必要か」を判断します。

**結果に合わせて goal を書き換えることは禁止です。** これは実際に観測された失敗で、
書き換えると以降の判断すべてが新しい goal を基準に行われ、**ずれが自己強化**します。

goal 自体を変える必要がある場合は、**新しい epic を立てます。**
旧 epic は「この goal は達成されなかった」という記録として閉じます。

### 新規タスク開始時の手順

1. **`/task-start` で task を作成**
   - 現在の状態と目標の状態を**対話で確認**する（下記）
   - 既定構成の子 issue が自動生成される
   - 最後に実行するかを確認され、yes なら `/task-run` へ

2. **`/issue-start` で個別 issue に着手**
   - ブランチと worktree が作られる
   - `/task-run` 経由なら自動で行われる

3. **`/issue-finish` で issue ごとにマージ**
   - 溜めてから一括マージしない

### ★ 現在の状態と目標の状態を必ず対話で確認する

**ユーザーはほとんどの場合、十分な量の説明をしません。** 本人にとって自明な前提が
言語化されないためです。しかも欠けるのは目標だけでなく、**現状の認識も共有が崩れています。**

task とは「**現在地から目的地までの距離**」です。どちらか一方だけ合意しても距離を測り違えます。

- **受け取った説明をそのまま記録しない。** 両側を能動的に聞き出す
- **平易な言葉で聞く。** 「成功条件を定義してください」ではなく本人の言葉で答えられる質問にする
- **答えられない項目は推測で埋めない。** 「未確定」として残す
- **現状は task ごとに確認し直す。** 前の task の記述を引き継がない

詳細な質問の型は `/task-start` を参照してください。

### Git Worktree の使用（必須）

並行タスクでブランチがコンタミネーション（混入）しないよう、**必ず worktree を作成**して作業します。

```bash
git worktree add --relative-paths worktrees/issue5 feature/5-add-dataset-loader
cd worktrees/issue5
```

- **`worktrees/`（ドット無し）** に作る（`.gitignore` の対象）
- **`--relative-paths` は必須**（理由は後述「Git Worktree 管理」）

---

## ラベル運用ルール

**ラベル定義の実体は `scripts/setup-labels.sh` です。** 増減する場合は
スクリプトとこの表の両方を更新してください（新規プロジェクトでは同スクリプトが自動実行されます）。

### 階層ラベル

| ラベル | 用途 |
|--------|------|
| `epic` | ゴール。worktree は持たない |
| `task` | 1つのまとまった仕事。worktree は持たない |

### 種類ラベル（issue 層。必須、1つ選ぶ）

| ラベル | 用途 | 完了条件 |
|--------|------|----------|
| `survey` | 既存手法・先行研究の調査 | `docs/surveys/` に結果を残す |
| `spec` | 仕様の作成・レビュー | `.spec/issues/` に仕様を残す |
| `feature` | 新機能・実装 | 機能が動作する |
| `validation` | **実装は仕様どおり動くか**（実装の正しさ） | 動く/動かないの判定 |
| `experiment` | **仮説は正しいか**（設計の正しさ） | `data/shared/experiments/` に3点セット保存＋[実験の規律](#実験の規律ネガティブ結論の扱い)を通過 |
| `bug` | バグ修正 | バグが解消 |
| `docs` | ドキュメント | ドキュメント更新完了 |
| `refactor` | リファクタリング | コード改善完了 |
| `chore` | CI設定、依存更新など | 設定完了 |

**`validation` と `experiment` を混同しないこと。** 実装の正しさを確認せずに
仮説の検証結果を信じると、実装バグを「手法が効かない」と誤読します。

### 状態ラベル

| ラベル | 用途 |
|--------|------|
| `blocked` | 他Issueや外部要因で待ち |
| `out-of-date` | 古くなったIssue。自動処理でスキップ |
| `user-action` | ユーザー対応が必要。自動処理でスキップ |

### 終了ラベル（クローズ時、該当時のみ）

| ラベル | 用途 |
|--------|------|
| `wontfix` | やらないことにした |
| `duplicate` | 重複 |

### ★ `in-progress` ラベルは使わない

**作業中の判定はブランチの有無で行います。** 同じ状態をラベルとブランチの2通りで
表現すると必ず食い違うためです（実際に、付与157件のうち126件が closed issue に
残留していた事例があります）。

### Issue 間の関係性

**親子関係は GitHub ネイティブの sub-issue で表します。** 本文テキストには書きません。

```bash
# 親子を張る（-F で integer 指定。-f だと 422 になる）
CHILD_ID=$(gh api "repos/$REPO/issues/$CHILD" --jq '.id')
gh api -X POST "repos/$REPO/issues/$PARENT/sub_issues" -F sub_issue_id="$CHILD_ID"

# 確認
gh issue view $CHILD --json parent -q '.parent.number'
gh api "repos/$REPO/issues/$PARENT/sub_issues" --jq '.[].number'
```

通常は `/issue-create` が自動で行うため、直接叩く必要はありません。

親子以外の関係は本文またはコメントに記述します。

```markdown
## 関係
- Blocked by: #7
- Related: #12
```

---

## 成果物の保存場所

### survey の成果物

```
docs/surveys/
└── YYYY-MM-DD_topic-name.md
```

### experiment の成果物（3点セット）

```
data/shared/experiments/
└── YYYY-MM-DD_experiment-name/
    ├── data/              # 生データ
    │   └── results.csv
    ├── figures/           # 可視化
    │   └── plot.png
    └── README.md          # 実験内容・結論
```

---

## 進捗報告のルール

- **途中経過は Issue のコメントに Markdown で報告**
  - コードを書いた後、コミット前に進捗を Issue に報告
  - 報告内容：
    - 完了した作業
    - 現在のブロッカー（あれば）
    - 次のステップ

---

## コミットのルール

- コミットメッセージには必ず Issue を参照: `Fixes #ISSUE_ID` または `Refs #ISSUE_ID`
- Conventional Commits 形式を推奨:
  - `feat(scope): description` - 新機能
  - `fix(scope): description` - バグ修正
  - `docs(scope): description` - ドキュメント
  - `refactor(scope): description` - リファクタリング
  - `test(scope): description` - テスト追加

---

## プルリクエストのルール

- ブランチでの作業完了後、PR を作成
- PR タイトルに Issue 番号を含める
- PR 説明に `Closes #ISSUE_ID` を記載してリンク

---

## スキル一覧

**スキル名の接頭辞は「操作対象の層」を表します。**

### epic 層

| スキル | 用途 |
|-------|------|
| `/epic-cycle <epic番号>` | ゴール達成まで task を繰り返し回す |

### task 層

| スキル | 用途 |
|-------|------|
| `/task-start [説明]` | **現状と目標を対話で確認**して task を作成、既定構成の子 issue を生成、実行確認 |
| `/task-run <task番号>` | task 配下の issue を既定順で自動処理（子は sub-issue API で自動解決） |

### issue 層

| スキル | 用途 |
|-------|------|
| `/issue-create` | **Issue 作成の単一情報源。** 他スキルは `gh issue create` を直接呼ばない |
| `/issue-start <番号>` | issue に着手（ブランチ→Worktree） |
| `/issue-branch [説明]` | 同一 Worktree 内で小タスクを分ける |
| `/issue-report` | 現在の進捗を Issue に報告 |
| `/issue-finish` | issue を完了（レビュー→**マージ**→クローズ） |

### 横断

| スキル | 用途 |
|-------|------|
| `/issue-scan` | 全 Issue の状態をスキャン |
| `/issue-diff` | Issue 仕様と実装の乖離を分析 |
| `/issue-gaps` | 乖離検出・不足 Issue の作成 |
| `/issue-backlog` | バックログ処理 |
| `/issue-unblock` | ブロッカー解消 Issue の作成 |

### コミット

| スキル | 用途 | Issueクローズ |
|-------|------|--------------|
| `/commit` | ローカルにコミットのみ | ❌ |
| `/commit-push` | コミット＆プッシュ（途中保存） | ❌ |
| `/commit-merge` | コミット＆マージ（タスク完了） | ✅ |

### レビュー

| スキル | 用途 |
|-------|------|
| `/review` | 多角的コードレビュー（3つのサブエージェントで並列レビュー） |

### テンプレート管理

| スキル | 用途 |
|-------|------|
| `/template-sync` | テンプレートの最新更新を取り込み |
| `/template-contribute` | テンプレートへの改善PRを作成 |

### Worktree管理

| スキル | 用途 |
|-------|------|
| `/worktree-init` | 初回セットアップ（共有データパス・相対パス設定→`/spec-init`） |
| `/worktree-setup` | Worktreeにデータディレクトリを作成 |
| `/worktree-safe-remove` | Worktreeを安全に削除 |

### 仕様・ルール管理

| スキル | 用途 |
|-------|------|
| `/spec-init` | `.spec/` にプロジェクト固有のルール・失敗パターンを対話的に追加（再実行可） |

`.spec/` の3ファイル（`core-rules.md` / `invariants.md` / `known-issues.md`）は
`auto-reviewer` が判断前に**必ず読む**必須コンテキストです。
実プロジェクトの失敗実績から抽出した既定が同梱されており、**既定だけでも動作します**。
プロジェクト固有の内容は `/spec-init` で追加してください。

---

## Git Worktree 管理

### Worktree 作成の標準パターン

```bash
# 新しい Issue #N のブランチと worktree を作成
git worktree add --relative-paths worktrees/issueN feature/N-description
cd worktrees/issueN
```

### ★ `--relative-paths` が必須な理由

`git worktree add` は既定で `.git` 参照を**絶対パス**で2箇所に書き込む:

```
worktrees/issueN/.git        → gitdir: <絶対パス>/.git/worktrees/issueN
.git/worktrees/issueN/gitdir → <絶対パス>/worktrees/issueN/.git
```

devcontainer はリポジトリを `/workspace` にマウントするため、**ホストとコンテナで絶対パスが一致しない**。
結果として **worktree を作成した側の環境でしか git / gh が動かない**（双方向に壊れる）。

| 作成場所 | 書き込まれるパス | 壊れる環境 |
|---|---|---|
| devcontainer 内 | `/workspace/...` | ホスト |
| ホスト | `/Users/...` | devcontainer 内 |

`--relative-paths` を付けると相対パスで書かれ、両環境から解決できる（git 2.48 以降）。

`scripts/configure-worktree-paths.sh` が `worktree.useRelativePaths=true` を設定するため、
通常は自動で有効になる（devcontainer 起動時と `/worktree-init` 実行時）。
上記のコマンド例で明示しているのは、設定が無い環境でも安全にするため。

### 既存の壊れた worktree を復旧する

```bash
# 現在の環境から見た正しいパスに書き換える
git worktree repair
```

**実行した環境でのみ有効**なので、恒久対策は相対パス化のほう。

### 並行作業の例

```
project-name/                    # メインリポジトリ
├── worktrees/                   # Worktree用ディレクトリ（.gitignore対象）
│   ├── issue5/                  # feature/5-description
│   ├── issue7/                  # survey/7-description
│   └── issue9/                  # fix/9-description
├── data/
│   └── shared/                  # 共有データ（全worktreeからアクセス可能）
└── src/                         # メインブランチのソース
```

---

## Worktree データ保護

### 概要

Worktree削除時に重要データ（データセット、実験結果）が失われないよう、データディレクトリを以下のように分離します：

- **`data/shared/`**: 重要データ（全Worktreeで共有、削除時も保護）
- **`data/local/`**: 一時データ（Worktree削除時に一緒に削除）

### データの保存先

**重要データ（保存）:**
```bash
# データセット
mv large_dataset.json data/shared/datasets/

# 実験結果
mv experiment_results.csv data/shared/results/

# 学習済みモデル・ダウンロードモデル
mv best_model.pt data/shared/models/
mv pretrained_weights.pth data/shared/models/
```

**一時データ（削除OK）:**
```bash
# キャッシュ
mv preprocessed_batch.pkl data/local/cache/

# デバッグ出力
mv debug_images/ data/local/debug/
```

### モデル保存の注意事項

**重要**: ダウンロードしたモデル（事前学習モデル、ベースラインモデルなど）は**絶対に `/tmp` に保存しない**。

- ❌ `/tmp/models/` — devcontainer rebuild で消える
- ❌ `~/.cache/` — devcontainer rebuild で消える
- ✅ `data/shared/models/` — 永続化される

```bash
# 正しい例
wget -O data/shared/models/resnet50.pth https://example.com/resnet50.pth

# Pythonでダウンロードする場合も保存先を指定
torch.hub.set_dir("data/shared/models")
```

---

## 開発ガイドライン

### コード品質
- テストを書いてからコミット
- 新機能にはドキュメントを追加
- リファクタリング時は既存のテストが通ることを確認
- **対症療法的修正の禁止**: 想定される挙動と異なる振る舞いに対して、挙動を上書きする形での修正は保守性を低下させるため禁止。根本原因を特定し修正すること
- **単一情報源の原則（Single Source of Truth）**: 同じ情報を複数箇所で定義しない。修正時に複数箇所を変更する必要がない設計にすること

### 研究ノート
- 実験結果は Issue に記録
- ハイパーパラメータの変更履歴を残す
- データセットのバージョン管理

### 実験の規律（ネガティブ結論の扱い）

**最初の実験がそのまま正しく動くことはまずない。** negative な結果を見たら、結論を出す前に必ず下記を通すこと。

#### 1. まず実装バグ・実験設定ミスを疑う

- **ネガティブ（null/negative）は、まず実装バグ・実験設定ミスを疑う。** 検出力(power)が担保されていない null は「本物の科学的 null」ではなく「テスト/実装が壊れていて何も検出できないだけ」のアーティファクトでありうる。
- **positive/sanity control を必須化**: 「効くはずの状況（planted 効果・手法が効くべき合成タスク）で手法/テストが実際に検出・改善する」ことを先に示す。control が PASS して初めて実タスクの null を信頼する。
- **実装正当性を独立オラクルの test で pin**: matched-compute は params/epochs だけでなく *effective-fit*（train fit が同等か）も確認。loss が実際に適用されているか、masking/sampler 等が正しいかを test で固定し、null が「損失が実は効いていない」等のバグでないことを確認。
- **harness に positive control が無ければ issue 化**して検出力を確認する。

#### 2. 比較の公平性を保つ（matched-engineering）

**「negative を疑う」規律を過剰適用すると、逆方向の失敗が起きる。** baseline に提案手法が持たない工夫を投入し、不公平な比較で「提案手法が負けた＝意味がない」と結論してしまう事例が実際に観測されている。

- **matched-engineering**: baseline に加えた工夫は、**提案手法にも同等に適用する**。適用しない場合は理由を明示し、その比較は「提案手法の優位性の検証」ではなく「**baseline の上限測定**」として記録する。
- **baseline 強化の記録義務**: baseline に何を足したかを実験記録に必ず残す。後から比較の妥当性を検証できるようにする。
- **「提案手法が負けた」も negative result である。** 上記1のトリアージ手続きの対象に含める。baseline 側の実装・設定にバグが無いことも同様に確認する。

#### 3. 敵対的に検証する

- **レビュー時に敵対的に検証**: negative を見たら「この null はバグ/設定ミスで説明できないか?」を必ず問う。**false-positive と false-negative の両方を疑う**のが規律。
- **最初の原因仮説に飛びつかない**: もっともらしい説明が一度言語化されると、証拠が曖昧でも以降の反復がそれに固着する。原因候補は複数立ててから絞る。

#### 4. 結論を格付けする

Issue に記録する際、negative result は必ず以下のいずれかに格付けする。**既定は `unverified-negative`**。

| 格付け | 意味 |
|--------|------|
| `unverified-negative` | 上記1〜3 が未完了。**結論として扱ってはいけない** |
| `verified-negative` | 上記1〜3 を全て通過した negative result |
| `implementation-bug` | 調べたら実装ミス・設定不備だった |

#### 由来

- weavenet2 で確立された規律（2026-07-29、同 #1089）をテンプレートへ還流したもの
- 契機は weavenet2 #1077 で「見かけの HARM」が setup 交絡＝false-negative と判明した事例
- 「2. 比較の公平性」は #78 の実態調査で観測された過剰適用の失敗モードへの対処として追加

### ブランチの命名規則
- `feature/ISSUE_ID-description` - 新機能
- `survey/ISSUE_ID-description` - 調査
- `experiment/ISSUE_ID-description` - 実験
- `fix/ISSUE_ID-description` - バグ修正
- `docs/ISSUE_ID-description` - ドキュメント

---

## 重要な注意事項

1. **常に worktree を使用**: メインディレクトリで直接作業しない
2. **Issue なしで作業しない**: すべてのタスクは Issue から開始
3. **進捗は Issue に記録**: コミット前に必ず報告
4. **ルールは絶対**: このファイルに記載された全てのルール、スキルで定義されたワークフローは必ず従う
5. **省略・逸脱する前に確認**: ルールから外れる行為をする場合は、事前に一言ユーザーに確認を取る。自己判断で「不要」「単純だから省略」と決めない

---

## オプション機能の設定

### Ollama（ローカルLLM）

Ollamaのモデル永続化は事前設定済み（`data/shared/ollama_models/`）。使用するにはDockerfileにインストールコマンドを追加：

```dockerfile
# .devcontainer/Dockerfile に追加
RUN curl -fsSL https://ollama.com/install.sh | sh
```

コンテナ再ビルド後、以下で使用可能：
```bash
ollama serve &          # サーバー起動
ollama pull llama3.2    # モデルダウンロード
ollama run llama3.2     # 実行
```

### Claude Code認証

認証情報はプロジェクト専用のDocker volumeで永続化。初回のみ `claude` を実行して認証。コンテナ再ビルド後も自動的に維持される。

**注意**: ホストや他のdevcontainerとは認証情報が分離されているため、各プロジェクトで初回認証が必要。

---

## ドキュメント原則

### What vs How

- **README（What）**: このプロジェクトは何か、何ができるか、何が含まれているか
- **CLAUDE.md（How）**: どうやって作業するか、どういうルールで進めるか

### 変更時の注意

- 手順やルールの追加・変更は CLAUDE.md に記載
- プロジェクト概要やセットアップ手順は README に記載
- 同じ情報を両方に書かない（Single Source of Truth）
