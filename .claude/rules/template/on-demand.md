<!-- [Template] research-project-template 由来。プロジェクト固有の記述は .claude/CLAUDE.md に書くこと -->

## 必要なときだけ読み込まれるルール

次のファイルは frontmatter の `paths:` により、**該当するファイルを Read したときだけ**読み込まれる（常時は読み込まれない）。
該当ファイルを触らずにその話題を扱うときは、自分で Read する。

| ファイル | 内容 | 読み込まれるきっかけ |
|---|---|---|
| `skills.md` | スキル一覧（層ごと） | `.claude/skills/**`、README |
| `model-policy-callsites.md` | call-site → role の対応表、fallback、overrides | スキル・エージェント・`model-policy*.json`・`resolve-model.sh` |
| `env-node-and-claude-install.md` | Claude Code の導入と Node の要件・移行手順 | `.devcontainer/**` |
| `optional-features.md` | Ollama、Shared Resource Manager（GPU・ポートの排他）、Claude Code 認証 | `.devcontainer/**`、`scripts/resource.sh`、`data/shared/resources/**` |
| `premises-migration.md` | 前提の置き場所の移行手順 | `.spec/invariants.md`、`read-premises.sh` |

常に効く要点:
- **Claude Code は native build（`claude install latest`）で入れ、≥ 2.1.280 を確認する**（古いと Opus 5 系が一覧に出ない。`npm i -g` は使わない）。
- 複数の worktree・セッションで GPU やポートを奪い合うときは `bash scripts/resource.sh acquire <名前> -- <コマンド>` で排他する。
