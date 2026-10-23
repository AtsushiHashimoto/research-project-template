---
name: task-run
description: task 配下の issue を既定順に 1 つずつ、issue ごとのワーカーで処理する
argument-hint: <task番号>
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Task Run

```
bash scripts/flow/task-run.sh <task番号>
```

**メイン（ユーザーと話すセッション）は段を読んでワーカーを起動するだけ。** 子 issue の作業は自分で行わない。

1. スクリプトを呼び、**出力を全文読む**（要約しない）
2. 出力の「いまの段: #N」について、`references/worker.md` の起動文でワーカーを 1 つ起動する
3. ワーカーの報告の STATUS で次を決める（`references/worker.md`「メインの動き」）
4. 「全ての子 issue が closed」と出たら、そこに書かれた手順（完了判定・引き継ぎ）を**メインが**行う

## 実行形態

| 役 | 行うこと | 行わないこと |
|---|---|---|
| メイン | `task-run.sh <TASK>` を呼ぶ → #N のワーカーを起動 → STATUS で次を決める | diff・PR 本文・レビュー全文を読む。子 issue の作業 |
| ワーカー | `task-run.sh <TASK>` の「次にやること」を行い、同じ引数で呼び直す | ユーザーへの質問。#N 以外の issue。task・epic の完了判定と引き継ぎ |

- ワーカーは子 issue ごとに 1 つ、既定順に 1 つずつ起動する（並列にしない）
- 判定はスクリプトにある。このファイルには判定を書かない
