---
name: issue-create
description: Issue 作成の単一情報源。epic/task/issue のいずれも作成し、親子リンクを張る
argument-hint: --type <epic|task|issue-type> --title <題> [--parent <N>] [--body-file <F>]
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Issue Create

**Issue 作成の唯一の入口。** 他のスキル・手作業で `gh issue create` を直に呼ばない。

```
bash scripts/flow/issue-create.sh --type <T> --title <題> [--parent <P>]
                                  [--body-file <F>] [--extra-label <L>]...
```

- `--type`: `epic` / `task` / 種類ラベル / 報告ラベル（`scripts/setup-labels.sh` が定義）
- `--parent` を省くと単独 issue（その旨を出力する）。階層に合わない親子は止まる
- `--body-file` を省くと種類ごとの雛形。**task は `/task-start` が本文を作って `--body-file` で渡す**
- stdout は `作成: #<N>` の 1 行だけ（機械が読む）。説明は stderr
- 状態ラベルは `--extra-label` で同時に付ける（`user-action` `blocked`）
