# Issue #118 仕様: スキルが使うラベルと setup-labels.sh の整合

- 状態: approved（auto-reviewer 判断済み。警告3件を反映。ログ: 118-auto-decisions.md）
- 由来: Integrity Review #114 C3 ＋ Medium/Low 各1件

## 背景

スキルが `gh issue create --label X` で使うラベルのうち5種が `scripts/setup-labels.sh`
にも `labels.md` にも定義されていない。**未定義ラベルを渡すと gh は 422 で失敗する**ため、
当該ステップが必ず落ちる（#114 の Issue 投稿自体がラベル無しを強いられたのが実例）。

## 設計: 5ラベルの処遇

| ラベル | 使用箇所 | 判断 | 理由 |
|---|---|---|---|
| `review-integrity` | `review-integrity/SKILL.md:180` | **定義を追加** | 定期レビュー報告 issue を一覧できることに運用価値がある。種類ラベルではなく「報告」用途なので、`labels.md` に**報告ラベル**の節を新設する |
| `test` | `review-integrity/SKILL.md:261` | **`validation` に置換** | 定義済みラベルで意味が一致する（実装が仕様どおり動くかの確認）。新設不要 |
| `subtask` | `issue-branch/SKILL.md:68` | **削除** | `issue-hierarchy.md` の階層表が「小タスク＝ラベル **—**」と定めており、ラベルを付けること自体が規約違反。**単純に削除する**（種類ラベルを付けると階層表と矛盾するため付けない — auto-reviewer 指摘） |
| `gap-fixed` | `issue-gaps/SKILL.md:22,63,97-99,362` | **削除（コメント記録に置換）** | 「乖離が解消された」という状態変化は `out-of-date` ラベルの**除去**で既に表現されている。同じ状態を2通りで表さない（`labels.md` の in-progress 廃止と同じ理由）。解消の内容はコメントに残す |
| `qa-pending` | `issue-finish/SKILL.md:114,119` | **記述を削除** | 当該行はコメントアウトされた擬似コードで、実行経路ではない。QA issue の作成は `/qa-ask` が担うため、issue-finish に古い擬似コードを残さない |

**実装時の逸脱（記録）**: 119行目は削除ではなく `user-action`（定義済み）への置換とした。
QA issue は「ユーザー対応が必要」という状態を持つため、ラベル欄を空にするより
既存の状態ラベルを指すほうが読み手に正確なため（検証1周目の指摘で明文化）。

## 付随する修正

### D2: labels.md と setup-labels.sh の説明文の乖離（Medium）

ラベル名16件は一致しているが説明文が4件ずれている。**GitHub 上に実際に表示されるのは
スクリプト側の文言**なので、`labels.md` の表をスクリプトに合わせる。

### D3: setup-labels.sh の `-h|--help`（Low）

現状 `--help` を渡すと**ヘルプではなくラベル作成が走る**（`--prune` 以外は全て作成へ
フォールスルー）。他スクリプトと同じく `-h|--help` と不明引数エラーを実装する。

### D4: 再発防止（quality-check への検査追加）

**スキルが使うラベルが setup-labels.sh に定義済みかを機械検査する。**
#117 で追加した `scripts/check-skill-references.sh` と同じ位置づけで、
`scripts/check-skill-labels.sh` を追加し `quality-check.sh` から呼ぶ。

- 抽出: `.claude/skills/**` の `--label "X"` / `--add-label X` / `--remove-label X`
- 照合: `setup-labels.sh` の `LABELS` 配列
- 除外: コメント行（`#` 始まり）と、シェル変数（`$...`）
- **`{a|b|c}` 形式は除外せず `|` で分割して各候補を照合する** — 一律除外すると
  **今回の `test` が隠れていたのと同じ形の退行を検出できない**（auto-reviewer 指摘）
- 除外を行う場合は**件数を必ず表示**（無言の切り捨て禁止。#117 の踏襲）。
  ただし数えるのは「ラベル指定を含むのに除外した行」だけ（全コメント行を数えても意味がない）
- **追加（検証1周目）**: D2 のドリフト自体を再発防止するため、
  `labels.md` と `setup-labels.sh` の**説明文の一致**も同スクリプトで検査する
  （Markdown の装飾 `**` と `` ` `` は落として比較）

## Fallback ホワイトリスト

なし。

## 検証チェックリスト

- [ ] V1: `.claude/skills/**` が使う全ラベルが `setup-labels.sh` の `LABELS` に存在する（機械照合）
- [ ] V2: `subtask` `gap-fixed` `qa-pending` `test`（ラベルとして）の使用が 0 件
- [ ] V3: `review-integrity` が `setup-labels.sh` と `labels.md` の両方に存在する
- [ ] V4: `labels.md` の説明文が `setup-labels.sh` と一致（`review-integrity` 追加後の **17件**全て）
- [ ] V5: `setup-labels.sh --help` がヘルプを表示して exit 0、不明引数は exit 1、
      **ラベル作成が走らない**こと
- [ ] V6: `setup-labels.sh` の skip 経路（#116 で入れた終了コード 2 と案内）が退行していない
- [ ] V7: `check-skill-labels.sh` が (a) 正常時 PASS (b) 未定義ラベルの混入で FAIL
      (c) `{a|undefined|c}` 形式の未定義候補も検出 (d) 除外件数を表示 (e) `--help` が動作
- [ ] V8: quality-check PASS（#117 の skill-refs 検査も引き続き PASS）
