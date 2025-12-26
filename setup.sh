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

# Update CLAUDE.md with project info
sed -i "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" .claude/CLAUDE.md
sed -i "s/{{PROJECT_DESCRIPTION}}/$PROJECT_DESCRIPTION/g" .claude/CLAUDE.md
sed -i "s/{{RESEARCHER_NAME}}/$RESEARCHER_NAME/g" .claude/CLAUDE.md
sed -i "s/{{START_DATE}}/$START_DATE/g" .claude/CLAUDE.md

# Update worktree-config.json
sed -i "s/{{CREATED_AT}}/$CREATED_AT/g" .claude/worktree-config.json
sed -i "s/{{UPDATED_AT}}/$CREATED_AT/g" .claude/worktree-config.json

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
echo "3. Start your first task: claude (then use /start-task)"
