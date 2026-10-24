---
name: progress
description: 進捗一覧のサーバーを確かめ、立っていなければ立てて URL を出す（止めるときは --stop）
argument-hint: "[--port <18000〜18999>] [--stop]"
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。

`python3 scripts/progress/ensure.py $ARGUMENTS` を実行し、標準出力（URL と注記の 2 行）か標準エラーの理由をそのまま伝える。
止めるときは `--stop`。
