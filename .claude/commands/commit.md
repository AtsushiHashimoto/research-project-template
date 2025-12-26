---
description: Smart commit router - routes to commit-only, commit-push, or commit-merge
argument-hint: [省略可 | push | merge | 自然言語]
---

# Commit Router

引数に基づいて適切なコミットワークフローを実行します。

## 3つのコミットスキル

| スキル | 用途 | Push | PR作成 | Issueクローズ |
|-------|------|------|-------|--------------|
| `/commit-only` | ローカル保存 | ❌ | ❌ | ❌ |
| `/commit-push` | 途中保存 | ✅ | ❌ | ❌ |
| `/commit-merge` | タスク完了 | ✅ | ✅ | ✅ |

## Usage

```bash
/commit                      # commit-only（ローカル保存）
/commit push                 # commit-push（途中保存）
/commit pushも               # commit-push (自然言語)
/commit merge                # commit-merge (タスク完了・Issueクローズ)
/commit 完了                 # commit-merge (自然言語)
/commit pushとmergeも        # commit-merge (自然言語)
```

## Routing Rules

### 引数なし
```bash
/commit
```
→ Skillツールで `/commit-only` を呼び出す

### 引数が "push"
```bash
/commit push
```
→ Skillツールで `/commit-push` を呼び出す
→ **Issueは開いたまま**（途中保存用）

### 引数が "merge"
```bash
/commit merge
```
→ Skillツールで `/commit-merge` を呼び出す
→ **Issueをクローズ**（タスク完了用）

### 自然言語解釈
```bash
/commit [任意のテキスト]
```

引数を解析：
- **"push" を含む**（例: "pushも", "プッシュ", "プッシュして"）
  → Skillツールで `/commit-push` を呼び出す（Issueは開いたまま）

- **"merge", "完了", "マージ", "終了", "finish" を含む**
  → Skillツールで `/commit-merge` を呼び出す（Issueをクローズ）

- **それ以外**
  → Skillツールで `/commit-only` を呼び出す（デフォルト）

## Implementation

引数: "$1"

上記ルールに従って、Skillツールを使用して適切なコマンドを実行してください：

```xml
<invoke name="Skill">
<parameter name="skill">commit-push</parameter>
</invoke>
```

または

```xml
<invoke name="Skill">
<parameter name="skill">commit-merge</parameter>
</invoke>
```

など。

## Examples

| 入力 | 実行されるコマンド | Issueクローズ |
|------|------------------|--------------|
| `/commit` | `/commit-only` | ❌ |
| `/commit push` | `/commit-push` | ❌ |
| `/commit pushも` | `/commit-push` | ❌ |
| `/commit merge` | `/commit-merge` | ✅ |
| `/commit 完了` | `/commit-merge` | ✅ |
| `/commit pushとmergeして完了` | `/commit-merge` | ✅ |

## 重要な注意

- `/commit merge` = タスク完了 = **Issueクローズ + Worktree削除**
- Issueをクローズしたくない場合は `/commit push` を使用
- `/commit merge` は品質チェック（レビュー）を含む完全なワークフローを実行します
