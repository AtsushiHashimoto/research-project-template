# Claude の入口

@../AGENTS.md
@../.spec/core-rules.md
@../.spec/invariants.md
@../.spec/known-issues.md

共通指示の原本は `AGENTS.md`。プロジェクト固有の概要・制約はそちらを編集する。
Claude 固有の呼出は既存の Skill / Task / Agent を使い、共通スキルにある実行契約に従う。
`.claude/rules/` は Claude の自動読込に任せ、paths 付きルールは対象操作・話題に応じて読む。
Codex 固有の `.codex/instructions.md` は読み込まない。
