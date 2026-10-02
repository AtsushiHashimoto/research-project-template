---
paths:
  - ".spec/invariants.md"
  - "scripts/read-premises.sh"
---

<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## 前提の置き場所の移行手順（既存プロジェクト、一度だけ）

規則本体は `premises.md`。`/template-sync` は `.claude/CLAUDE.md` と `.spec/invariants.md` の固有節を上書きしないため、
一度だけ手で行う（`read-premises.sh` は節が無いと `WARN: … 移行手順` を出す）:

1. `.spec/invariants.md` の `# プロジェクト固有の設計判断` の下に `## ★ プロジェクト大前提（ユーザー確定事項）` 節を作る。
2. `.claude/CLAUDE.md` の「プロジェクト固有のルール」に `@../.spec/invariants.md` の行を足す（リポジトリ内の相対 import）。
3. 進行中の epic 本文に `## 前提（ユーザー確定事項）` 節を足し、これまでに聞いた前提をユーザーに確認して記入する。
