---
name: commit-push
description: stage 済みの変更をコミットして push する（途中保存。issue は閉じない）
argument-hint: --issue <N> --message <題>
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Commit & Push（途中保存）

入れるファイルを `git add <ファイル名>` で名指しで stage してから呼ぶ。

```
bash scripts/flow/commit.sh push --issue <N> --message <題>
```

- 変更が無くても未 push のコミットがあれば push だけ行う
- issue は閉じない。完了なら `/issue-finish`
