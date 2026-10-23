---
name: task-start
description: 現状と目標を対話で確認して task を作成し、既定構成の子 issue を生成する
argument-hint: [task の説明] [--epic N]
metadata:
  harness: shared
---

実行前に `.claude/rules/template/agent-runtime.md` を読み、現在のエージェントで同じゲートを実施する。
必須の実行機能が無い場合は、変更・投稿・委譲の前に停止する。


# Task Start

**task 層の入口。** 現在の状態と目標の状態を対話で引き出し、task と既定構成の子 issue を作る。
両側を聞き出す理由と聞き方は `.claude/rules/template/issue-hierarchy.md`「★ 現在の状態と目標の状態を必ず対話で確認する」。

1. **epic**: `--epic` の goal を読み上げる（無ければ open な epic から選ぶか新規 epic かを聞く）。
   `bash scripts/read-premises.sh <epic番号>` で前提を読み、質問が前提と矛盾しないようにする。goal は書き換えない
2. **現在の状態を聞く**（毎回聞き直す。前の task の記述を引き継がない）:
   どこまでできているか / 信用してよい部分と怪しい部分 / 使えるデータ・環境・資源 / 試して駄目だったこと
3. **目標の状態を聞く**: 成功と言えるもの 1 つ / 誰に見せるか / 何が解消されるか / 既存の類似 /
   どうなったら「ダメだった」と判断するか（negative の意味の事前登録）/ 期限と手間。
   成功条件は「数値超え」にせず「正しく測って判定を出す」形で記録する
4. **本文を書く**: `references/task-body.md` の雛形と「未確定」の書式で一時ファイルに書く。
   差分（現在 → 目標）が明確でなければ task はまだ切れない。そう伝えて中断する
5. **task を作る**（本文は必ず `--body-file` で渡す。無いと issue-create.sh が止まる）:

```
Skill(skill="issue-create", args="--type task --title <題> --parent <epic番号> --body-file <本文ファイル>")
```

6. **既定構成の子 issue を作る**: 構成は `issue-hierarchy.md`「既定の task 構成（必須）」が単一情報源。
   省くなら task 本文に理由を書く。2 周目以降も survey は作る（不要なら判断を記録して閉じる）

```
Skill(skill="issue-create", args="--type survey --title <題> --parent <task番号>")
```

7. 作った task と子 issue の一覧（未確定の項目と担当を含む）を示し、`/task-run <task番号>` で進める

**未確定が残るのは問題ない。担当が書かれていないことが問題**（担当の無い空白はエージェントが goal を発明して埋める）。
即答できない項目は `/qa-ask` で非同期に聞く。
