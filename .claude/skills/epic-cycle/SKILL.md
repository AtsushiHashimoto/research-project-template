---
description: epic のゴール達成まで task を繰り返し回す（旧 /issue-cycle）
argument-hint: <epic番号> [最大サイクル数]
---

# Epic Cycle

**epic 1つを収束まで回す。** task を実行し、結果から次の task を生成することを繰り返す。

```
/epic-cycle #100          # 収束まで（最大10サイクル）
/epic-cycle #100 3回まで   # 最大3サイクル
/epic-cycle #100 1回だけ
```

## Concept

```
epic #100（goal は不変）
  │
  ├─ Cycle 1
  │   ├─ /task-run #101      task 配下の issue を既定順で処理
  │   ├─ /issue-gaps         仕様と実装の乖離を検出
  │   ├─ /review-integrity   バグパターン・品質チェック
  │   └─ 結果駆動で次 task を生成（投機禁止）
  │
  ├─ Cycle 2
  │   └─ ...
  │
  └─ 収束: 未完了 task = 0 ∧ gaps = 0 ∧ integrity クリーン
      → epic のゴール達成判定
```

## ★ far-goal モードについて

かつて別建ての「far-goal モード」（遠いゴールを段に分けて1段ずつ進める仕組み）を
検討していたが、**#92 の epic / task / issue 階層がその役割を包含する**ため導入しない。

| 旧 far-goal の概念 | 本階層での表現 |
|---|---|
| 遠いゴール | **epic** |
| 段 | **task 配下の issue** |
| 段ごとの検証ゲート | validation / experiment issue |
| 段ごとに PR + review して merge | **issue ごとに必ずマージ**（`/task-run` Step 5） |
| 最終段まで issue をクローズしない | epic は全 task 完了までクローズしない |
| 結果駆動の次段生成 | 本スキルの Step 4（投機禁止） |

**同じことを表す仕組みを2つ持たない。**

## Workflow

### Phase 0: 引数パース

- epic 番号（必須）
- 最大サイクル数: `3回まで` → 3 / `1回だけ` → 1 / 省略 → 10

### Phase 1: 初期化

#### Step 1-1: epic の goal を読む

```bash
gh issue view "$EPIC" --json title,body,labels
```

**goal を明示的に読み上げる。以降のサイクルで一度も書き換えないこと。**

#### Step 1-2: スナップショットとユーザー確認

```bash
git branch "pre-epic/$(date +%Y%m%d-%H%M%S)" main
```

```
┌─────────────────────────────────────────────────────────────┐
│ /epic-cycle #100 実行確認                                    │
├─────────────────────────────────────────────────────────────┤
│ epic: 手法Xの確立                                            │
│ goal: <goal を引用。これは変更されません>                    │
│                                                              │
│ 未完了の task: #101, #107                                    │
│ 最大サイクル: 10                                             │
│ スナップショット: pre-epic/20260731-160000                   │
│                                                              │
│ 実行しますか？                                               │
└─────────────────────────────────────────────────────────────┘
```

### Phase 2-N: サイクル実行

#### Step 1: 未完了 task を処理

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/issues/$EPIC/sub_issues" --jq '.[]|select(.state=="open")|.number'
```

各 task に対して:

```
Skill(skill="task-run", args="#${TASK}")
```

#### Step 2: `/issue-gaps`

仕様と実装の乖離を検出。新規 issue は**該当 task 配下**に作る（`/issue-create --parent`）。

#### Step 3: `/review-integrity`

バグパターン・デッドコード・配線不備を検出。

**検出された問題は深刻度に関わらず全て issue 化する。**

| 深刻度 | ラベル | issue 化 | 配置 |
|--------|--------|---------|------|
| Critical / High | `bug` | 個別 | 独立 task を立てる |
| Medium / Low | `chore` | まとめて1件 | 独立 task を立てる |

`/issue-create` を使うこと（`gh issue create` を直接呼ばない）。

#### Step 4: 結果駆動の task 生成

experiment / validation の結果を読み、次の task が必要かを判断する。

**★ この Step には3つの規律がある。**

##### 規律1: 投機禁止

**結果が出てから作る。** 「おそらく次はこれが必要だろう」で先回りして task を作らない。

##### 規律2: goal は変更しない。確認する

追加 task を作る前に、**epic の goal を読み直す**。
そのうえで「この goal に照らして、この追加は必要か」を判断する。

**結果に合わせて goal を書き換えることは禁止。**

これは実際に観測された失敗である。goal が書き換わると以降の判断すべてが
新しい goal を基準に行われ、**ずれが自己強化する**。
書き換えた時点の記録が残らなければ、後から検知することもできない。

goal 自体を変える必要がある場合は、**新しい epic を立てる。**
旧 epic は「この goal は達成されなかった」という記録として閉じる。

##### 規律3: 2周目以降も survey を skip しない

新しい task は `/task-start` の既定構成に従う。
**2周目以降でも survey issue を必ず置く。**

内容は「ゼロからの調査」ではなく
**「ここまでの結果を踏まえて追加サーベイが必要か」の検討**である。
不要と判断した場合も、skip ではなく判断の記録を残して閉じる。

**結果が出るたびに探すべき場所が変わる。** 1周目に監査したから十分、とはならない。

#### Step 5: 収束判定

```python
if 未完了task == 0 and gaps == 0 and integrity_clean:
    収束
elif cycle_count >= max_cycles:
    最大サイクル到達で停止
else:
    次サイクルへ
```

#### Step 6: サイクルスナップショット

```bash
git branch "epic-${EPIC}-cycle-${N}/$(date +%Y%m%d-%H%M%S)" HEAD
```

### Phase Final: epic のゴール達成判定

**全 task 完了後、epic の goal に照らして達成判定を行う。**

```
Task(subagent_type="general-purpose", prompt="
epic #${EPIC} のゴールが達成されたか判定してください。

## ゴール（変更禁止・作成時のまま）
${EPIC_GOAL}

## 実施した task と結果
${TASK_RESULTS}

## 判定
- 達成 / 部分達成 / 未達成
- **ゴールを書き換えて「達成」にしないこと**
- 全 task が negative で終わった場合は、.spec/known-issues.md の KI-D11 に従い
  「それ自体が異常信号」として扱い、共通のワークフロー欠陥がないか検討すること
")
```

#### ★ 全方向 negative だった場合

`.spec/known-issues.md` KI-D11 に該当する。

> 個々の negative が独立に正しいとは限らない。**共通のワークフロー上の欠陥**
> （実装バグの見逃し、不公平な baseline、検出力不足、ゲート順序の誤り）が
> 全体に効いている可能性がある

**「この研究方向には見込みが無い」と総括して終えてはならない。**
少なくとも1方向について positive control と実装検証をやり直してから総括する。

## Safety Features

| # | 内容 |
|---|---|
| 1 | ハード上限10サイクル |
| 2 | 自信度 < 50% で停止 |
| 3 | サイクルごとのスナップショット |
| 4 | goal 未確定の task を検出したら停止（`/task-run` が判定） |
| 5 | 全方向 negative を異常信号として扱う |

## Options

| オプション | 説明 |
|-----------|------|
| `--max N` | 最大サイクル数 |
| `--dry-run` | 計画のみ表示 |
| `--skip-backlog` | バックログ処理をスキップ |

## Related Skills

| スキル | 関係 |
|-------|------|
| `/task-run` | 各サイクルで task を処理 |
| `/task-start` | 結果駆動で次 task を作成 |
| `/issue-gaps` | 乖離検出 |
| `/review-integrity` | 品質チェック |
| `/issue-backlog` | 収束後のバックログ処理 |
