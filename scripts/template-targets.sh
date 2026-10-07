#!/usr/bin/env bash
# 配布/同期/還流の対象の単一情報源。source して template_targets <mode> を呼ぶ。
# local/生成物/個人設定は対象外。AGENTS/CLAUDE は install で初回のみ、sync で参考差分のみ。
template_targets() {
  case "$1" in
    install|sync|contribute-dirs|contribute-files|reference) ;;
    *) echo "ERROR: template_targets: 不明な mode: $1" >&2; return 2 ;;
  esac
  local path modes
  while read -r path modes; do
    case ",$modes," in *",$1,"*) printf '%s\n' "$path" ;; esac
  done <<'TARGETS'
.claude/skills install,sync,contribute-dirs
.claude/agents install,sync,contribute-dirs
.claude/rules install
.claude/rules/template contribute-dirs
.claude/worktree-config.json install,sync,contribute-files
.claude/model-policy.json install,sync,contribute-files
.devcontainer install,sync,contribute-dirs
scripts install,sync,contribute-dirs
install.sh install,sync,contribute-files
.spec install
.dev install
.codex/instructions.md install,sync,contribute-files
.codex/instructions/template.md install,sync,contribute-files
AGENTS.md reference
.claude/CLAUDE.md reference
TARGETS
}
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  template_targets "${1:-}"
fi
