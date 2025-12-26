#!/usr/bin/env bash

# Worktree Data Protection - Setup Data Directories
# Run this after creating a new worktree

set -euo pipefail

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Worktree Data Protection - Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get repository root
REPO_ROOT=$(git rev-parse --show-toplevel)
CURRENT_DIR=$(pwd)

# Check if running in a worktree
if ! git worktree list | grep -q "$(basename "$CURRENT_DIR")"; then
    echo -e "${RED}⚠️  This does not appear to be a worktree.${NC}"
    echo "Current directory: $CURRENT_DIR"
    echo ""
    echo "Run this command in a worktree directory (e.g., ../delta-clip-dev-issue12)"
    exit 1
fi

echo "Worktree: $CURRENT_DIR"

# Find main repository
MAIN_REPO=$(git worktree list | head -1 | awk '{print $1}')
CONFIG_FILE="$MAIN_REPO/.claude/worktree-config.json"

echo "Main repository: $MAIN_REPO"
echo ""

# Check if configuration exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}❌ Configuration file not found:${NC}"
    echo "   $CONFIG_FILE"
    echo ""
    echo -e "${YELLOW}Please run /worktree/init in the main repository first.${NC}"
    exit 1
fi

# Read configuration
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq not installed. Using simple parsing.${NC}"
    SHARED_DATA_PATH=$(grep '"shared_data_path"' "$CONFIG_FILE" | cut -d'"' -f4)
    PATH_TYPE=$(grep '"path_type"' "$CONFIG_FILE" | cut -d'"' -f4 || echo "absolute")
else
    SHARED_DATA_PATH=$(jq -r '.shared_data_path' "$CONFIG_FILE")
    PATH_TYPE=$(jq -r '.path_type // "absolute"' "$CONFIG_FILE")
fi

# Resolve relative path to absolute path based on main repository
if [ "$PATH_TYPE" = "relative" ]; then
    SHARED_DATA_PATH="$MAIN_REPO/$SHARED_DATA_PATH"
    echo "Resolved path: $SHARED_DATA_PATH"
fi

echo -e "${GREEN}Configuration:${NC}"
cat "$CONFIG_FILE"
echo ""

# Check if already set up
if [ -L "data/shared" ]; then
    echo -e "${YELLOW}⚠️  data/shared symlink already exists:${NC}"
    ls -la data/shared
    echo ""
    read -p "Recreate? [y/N]: " recreate
    if [[ ! "$recreate" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
    rm data/shared
fi

if [ -d "data/local" ]; then
    echo -e "${YELLOW}⚠️  data/local directory already exists${NC}"
    echo ""
    read -p "Recreate? [y/N]: " recreate_local
    if [[ ! "$recreate_local" =~ ^[Yy]$ ]]; then
        echo "Skipping data/local creation."
    else
        rm -rf data/local
    fi
fi

# Create data/local directory structure
echo -e "${BLUE}Creating data/local structure...${NC}"
mkdir -p data/local/{cache,temp,debug}
touch data/local/.gitkeep
touch data/local/cache/.gitkeep
touch data/local/temp/.gitkeep
touch data/local/debug/.gitkeep

echo -e "${GREEN}✅ Created:${NC}"
echo "   data/local/cache/"
echo "   data/local/temp/"
echo "   data/local/debug/"
echo ""

# Create symbolic link to shared data
echo -e "${BLUE}Creating symbolic link to shared data...${NC}"
ln -s "$SHARED_DATA_PATH" data/shared

echo -e "${GREEN}✅ Created symlink:${NC}"
echo "   data/shared -> $SHARED_DATA_PATH"
echo ""

# Verify setup
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Directory structure:"
ls -la data/
echo ""

echo -e "${BLUE}Usage:${NC}"
echo "  - Save important data to: data/shared/"
echo "    (preserved across worktrees)"
echo ""
echo "  - Save temporary data to: data/local/"
echo "    (deleted when worktree is removed)"
echo ""

echo -e "${GREEN}Examples:${NC}"
echo "  # Important dataset"
echo "  mv large_dataset.json data/shared/datasets/"
echo ""
echo "  # Temporary cache"
echo "  mv preprocessed_batch.pkl data/local/cache/"
echo ""

echo -e "${YELLOW}Remember:${NC}"
echo "  Use /worktree/safe-remove to safely delete this worktree"
echo ""
