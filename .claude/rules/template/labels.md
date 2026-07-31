<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

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
| `experiment` | **仮説は正しいか**（設計の正しさ） | `data/shared/experiments/` に3点セット保存＋実験の規律（`.claude/rules/template/experiment-discipline.md`）を通過 |
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
