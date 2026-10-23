---
name: commit-only
description: stage 済みの変更をコミットする（push しない）
argument-hint: --issue <N> --message <題>
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Commit Only

入れるファイルを `git add <ファイル名>` で名指しで stage してから呼ぶ。

```
bash scripts/flow/commit.sh only --issue <N> --message <題>
```

- 未 stage・未追跡しか無ければ止まり、一覧と `git add` の例を出す
- push もするなら `/commit-push`、完了なら `/issue-finish`
