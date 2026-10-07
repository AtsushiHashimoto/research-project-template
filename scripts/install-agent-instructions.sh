#!/usr/bin/env bash
# install.sh から source。既存指示は --force でも上書きしない。
# shellcheck disable=SC2034  # 呼び出し元 installer が状態を読み取る。
# shellcheck source-path=SCRIPTDIR
# shellcheck source=template-targets.sh
source "$(dirname "${BASH_SOURCE[0]}")/template-targets.sh"
# 配布元の各エントリに対応するコピー先を、変更開始前に再帰検査する。
_agent_preflight_path() {
  local root="$1" source_root="$2" reference="$3" cursor component child name
  local -a components
  cursor="$root"
  IFS=/ read -r -a components <<< "$reference"
  for component in "${components[@]}"; do
    cursor="$cursor/$component"
    if [ -L "$cursor" ] || { [ "$cursor" != "$root/$reference" ] && [ -e "$cursor" ] && [ ! -d "$cursor" ]; }; then
      echo "ERROR: distribution path must be repo-local: $reference" >&2
      return 1
    fi
  done
  if [ -L "$source_root/$reference" ]; then
    echo "ERROR: distribution source must not be a symlink: $reference" >&2
    return 1
  fi
  if [ -e "$cursor" ]; then
    if { [ -d "$source_root/$reference" ] && [ ! -d "$cursor" ]; } \
      || { [ -f "$source_root/$reference" ] && [ ! -f "$cursor" ]; }; then
      echo "ERROR: distribution path type mismatch: $reference" >&2
      return 1
    fi
  fi
  if [ -d "$source_root/$reference" ]; then
    for child in "$source_root/$reference/"* "$source_root/$reference/".*; do
      name="${child##*/}"
      case "$name" in .|..) continue ;; esac
      [ -e "$child" ] || [ -L "$child" ] || continue
      _agent_preflight_path "$root" "$source_root" "$reference/$name" || return 1
    done
  fi
}
agent_instruction_preflight() {
  local root="$1" source_root="${2:-$(dirname "${BASH_SOURCE[0]}")/..}" reference
  for reference in .claude .codex .codex/instructions .agents; do
    if [ -L "$root/$reference" ] || { [ -e "$root/$reference" ] && [ ! -d "$root/$reference" ]; }; then
      echo "ERROR: agent directory must be repo-local: $reference" >&2
      return 1
    fi
  done
  while IFS= read -r reference; do
    for reference in "$reference" "$reference.template"; do
      if [ -L "$root/$reference" ] || { [ -e "$root/$reference" ] && [ ! -f "$root/$reference" ]; }; then
        echo "ERROR: instruction entry must be a regular file: $reference" >&2
        return 1
      fi
    done
  done < <(template_targets reference)
  while IFS= read -r reference; do
    _agent_preflight_path "$root" "$source_root" "$reference" || return 1
  done < <(template_targets install)
}
install_agent_instructions() {
  local source_root="$1" project_root="$2"
  agent_instruction_preflight "$project_root" "$source_root" || return 1
  AGENT_INSTRUCTIONS_INSTALLED=false
  AGENT_MIGRATION_REQUIRED=false
  mkdir -p "$project_root/.claude"
  if [ -f "$project_root/AGENTS.md" ]; then
    cp "$source_root/AGENTS.md" "$project_root/AGENTS.md.template"
  elif [ -f "$project_root/.claude/CLAUDE.md" ]; then
    cp "$source_root/AGENTS.md" "$project_root/AGENTS.md.template"
    AGENT_MIGRATION_REQUIRED=true
  else
    cp "$source_root/AGENTS.md" "$project_root/AGENTS.md"
    AGENT_INSTRUCTIONS_INSTALLED=true
  fi
  if [ -f "$project_root/.claude/CLAUDE.md" ]; then
    cp "$source_root/.claude/CLAUDE.md" "$project_root/.claude/CLAUDE.md.template"
  elif [ -f "$project_root/AGENTS.md" ]; then
    cp "$source_root/.claude/CLAUDE.md" "$project_root/.claude/CLAUDE.md"
  fi
  if [ ! -f "$project_root/AGENTS.md" ] || ! grep -qxF '@../AGENTS.md' "$project_root/.claude/CLAUDE.md" \
    || ! grep -qF '.codex/instructions.md' "$project_root/AGENTS.md"; then
    AGENT_MIGRATION_REQUIRED=true
  fi
  if [ "$AGENT_MIGRATION_REQUIRED" = true ]; then
    echo "[agent-instructions] MIGRATION_REQUIRED: compare AGENTS.md.template and .claude/CLAUDE.md.template; preserve project facts, connect @../AGENTS.md, and tell Codex to read .codex/instructions.md; coexistence is not ready" >&2
  else
    echo "[agent-instructions] entries connected; existing project instructions preserved"
  fi
}
