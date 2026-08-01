#!/bin/bash
# Research Project Template Setup Script
# Usage: ./setup.sh "Project Name" "Project Description" "Researcher Name"

set -e

PROJECT_NAME="${1:-my-research-project}"
PROJECT_DESCRIPTION="${2:-A research project}"
RESEARCHER_NAME="${3:-Researcher}"
START_DATE=$(date '+%Y-%m-%d')
CREATED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

echo "Setting up research project: $PROJECT_NAME"
echo "Description: $PROJECT_DESCRIPTION"
echo "Researcher: $RESEARCHER_NAME"
echo "Start Date: $START_DATE"
echo ""

# sed -i は GNU と BSD(macOS) で引数解釈が異なる。`-i.bak` + rm が両者で動く唯一の形
sed_inplace() {
    local expr="$1" file="$2"
    sed -i.bak "$expr" "$file" && rm -f "$file.bak"
}

# 置換値に & | \ が含まれると sed の置換文字列として解釈されるためエスケープする
sanitize_sed() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

# Update CLAUDE.md with project info
sed_inplace "s|{{PROJECT_NAME}}|$(sanitize_sed "$PROJECT_NAME")|g" .claude/CLAUDE.md
sed_inplace "s|{{PROJECT_DESCRIPTION}}|$(sanitize_sed "$PROJECT_DESCRIPTION")|g" .claude/CLAUDE.md
sed_inplace "s|{{RESEARCHER_NAME}}|$(sanitize_sed "$RESEARCHER_NAME")|g" .claude/CLAUDE.md
sed_inplace "s|{{START_DATE}}|$(sanitize_sed "$START_DATE")|g" .claude/CLAUDE.md

# Update worktree-config.json のタイムスタンプ
# （テンプレートには固定値が入っているので、実行時刻で上書きする。
#   かつてはプレースホルダ置換だったが、被置換側が実値になったため no-op だった）
sed_inplace "s|\"created_at\": \"[^\"]*\"|\"created_at\": \"$CREATED_AT\"|" .claude/worktree-config.json
sed_inplace "s|\"updated_at\": \"[^\"]*\"|\"updated_at\": \"$CREATED_AT\"|" .claude/worktree-config.json

# Save substitution log for /template-contribute contamination checks
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
cat > ".claude/template-substitutions.json" <<SUBST_EOF
{
  "PROJECT_NAME": "$(json_escape "$PROJECT_NAME")",
  "PROJECT_DESCRIPTION": "$(json_escape "$PROJECT_DESCRIPTION")",
  "RESEARCHER_NAME": "$(json_escape "$RESEARCHER_NAME")",
  "START_DATE": "$(json_escape "$START_DATE")",
  "PROJECT_SLUG": "$(json_escape "$PROJECT_NAME")"
}
SUBST_EOF

# Initialize git repository if not already initialized
if [ ! -d ".git" ]; then
    git init
    echo "Git repository initialized"
fi

# Create initial commit
git add .
git commit -m "Initial project setup

Project: $PROJECT_NAME
Researcher: $RESEARCHER_NAME
Start Date: $START_DATE

$(echo -e "\xF0\x9F\xA4\x96") Generated with [Claude Code](https://claude.com/claude-code)"

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Create a GitHub repository: gh repo create $PROJECT_NAME --public"
echo "2. Push to remote: git remote add origin <url> && git push -u origin main"
echo "3. Start your first task: claude (then use /task-start)"
echo ""
echo "Optional: Human-in-the-loop QA System"
echo "  If you need async Q&A with humans via Slack/Discord, run: /qa-setup"
echo "  This enables Claude to ask questions and wait for answers during tasks."
