---
name: commit
description: コミットのルータ。only / push / merge のどれかに解決して scripts/flow/commit.sh を呼ぶ
argument-hint: [only|push|merge|自然言語]
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Commit（ルータ）

```
bash scripts/flow/commit.sh only  --issue <N> --message <題>
bash scripts/flow/commit.sh push  --issue <N> --message <題>
bash scripts/flow/commit.sh merge <N> [<TASK>] [<worktree>]
```

| 入力に含まれる語 | 解決先 |
|---|---|
| push / プッシュ | `push` |
| merge / マージ / 完了 / finish | `/issue-finish`（close まで行う本筋） |
| それ以外・引数なし | `only` |

- **入れるファイルを `git add <ファイル名>` で名指しで stage してから**呼ぶ（スクリプトは stage しない）
- `--issue <N>` は必須（ブランチ名は task 番号なので issue 番号を取れない）
