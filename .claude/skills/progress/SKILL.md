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

agent が中身を読むときは、出た URL に続けて `curl -s <URL>api/tree.json` で JSON を取る（`view` が表示中の木）。
絞り込みは query で足す: `?closed=1`（close 済みも含める）・`?label=<ラベル>`・`?q=<文字列>`（200 文字まで。`&` で組み合わせる）。
