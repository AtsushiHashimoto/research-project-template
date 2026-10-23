---
name: epic-cycle
description: epic のゴール達成まで task を繰り返し回す（1 回の呼び出しで 1 段）
argument-hint: <epic番号>
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Epic Cycle

```
bash scripts/flow/epic-cycle.sh <epic番号>
```

1. スクリプトを呼び、**出力を全文読む**（要約しない）
2. 「次にやること」を行い、同じ引数でもう一度呼ぶ

- open な sub-epic があれば止まる。どれを回すかはユーザーに聞く（`/epic-cycle` の対象は葉の epic だけ）
- task の実行は **`/task-run` の「実行形態」に従う**（メインは段を読んでワーカーを起動するだけ）
- 次 task の要否と達成判定は判断である。スクリプトは記録が揃っているかだけを見る
