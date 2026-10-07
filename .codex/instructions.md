# Codex 固有指示の入口

Codex は `.codex/instructions/template.md` を読み、続いて存在する場合は
`.codex/instructions/local.md` を読む。local はプロジェクト固有で、template-sync は変更しない。
本入口と template.md はテンプレートの管理対象。共通の作業ルールは AGENTS.md と `.claude/rules/` が原本。
Claude はこの入口と配下の Codex 固有指示を読込対象にしない。
