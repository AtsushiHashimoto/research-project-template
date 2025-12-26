#!/usr/bin/env bash

# Worktree Data Protection - Initial Setup
# Run this once in the main repository to configure shared data storage

set -euo pipefail

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Worktree Data Protection - Initial Setup${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if already configured
CONFIG_FILE=".claude/worktree-config.json"
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${YELLOW}⚠️  Configuration file already exists:${NC}"
    echo "   $CONFIG_FILE"
    echo ""
    cat "$CONFIG_FILE"
    echo ""
    read -p "Reconfigure? [y/N]: " reconfigure
    if [[ ! "$reconfigure" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        exit 0
    fi
fi

# Get repository root
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")
cd "$REPO_ROOT"

echo "Repository: $REPO_ROOT"
echo ""

# Prompt for shared data storage path
echo -e "${GREEN}Select shared data storage location:${NC}"
echo ""
echo "  1. Default (main repository)"
echo "     Path: $REPO_ROOT/data/shared"
echo "     Use: Same drive as repository, simple setup"
echo ""
echo "  2. Custom path (external drive, NFS, etc.)"
echo "     Use: Large capacity storage, network storage"
echo ""

read -p "Choice [1/2]: " choice

case "$choice" in
    1)
        SHARED_DATA_PATH="data/shared"
        SHARED_DATA_PATH_ABSOLUTE="$REPO_ROOT/data/shared"
        PATH_TYPE="relative"
        STORAGE_TYPE="local"
        NOTE="Default configuration - shared data in main repository (relative path)"
        ;;
    2)
        echo ""
        echo -e "${GREEN}Enter custom storage path:${NC}"
        echo "Examples:"
        echo "  - /mnt/research-data/$REPO_NAME/shared"
        echo "  - /Volumes/ExternalSSD/$REPO_NAME/shared"
        echo "  - ~/Dropbox/$REPO_NAME/shared"
        echo ""
        read -p "Path (absolute): " CUSTOM_PATH

        # Expand tilde
        CUSTOM_PATH="${CUSTOM_PATH/#\~/$HOME}"

        # Validate path
        if [[ ! "$CUSTOM_PATH" = /* ]]; then
            echo -e "${YELLOW}⚠️  Path must be absolute (start with /)${NC}"
            exit 1
        fi

        SHARED_DATA_PATH="$CUSTOM_PATH"
        SHARED_DATA_PATH_ABSOLUTE="$CUSTOM_PATH"
        PATH_TYPE="absolute"

        # Ask for storage type
        echo ""
        echo "Storage type (for documentation):"
        echo "  1. external_ssd"
        echo "  2. external_hdd"
        echo "  3. nfs"
        echo "  4. network"
        echo "  5. other"
        read -p "Choice [1-5]: " storage_choice

        case "$storage_choice" in
            1) STORAGE_TYPE="external_ssd" ;;
            2) STORAGE_TYPE="external_hdd" ;;
            3) STORAGE_TYPE="nfs" ;;
            4) STORAGE_TYPE="network" ;;
            *) STORAGE_TYPE="other" ;;
        esac

        echo ""
        read -p "Note (optional): " NOTE
        [ -z "$NOTE" ] && NOTE="Custom storage configuration"
        ;;
    *)
        echo "Invalid choice. Exiting."
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Configuration:${NC}"
echo "  Shared data path: $SHARED_DATA_PATH"
echo "  Storage type: $STORAGE_TYPE"
echo "  Note: $NOTE"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

read -p "Proceed with this configuration? [Y/n]: " confirm
if [[ "$confirm" =~ ^[Nn]$ ]]; then
    echo "Setup cancelled."
    exit 0
fi

# Create shared data directory structure
echo ""
echo -e "${BLUE}Creating shared data directory structure...${NC}"
mkdir -p "$SHARED_DATA_PATH_ABSOLUTE"/{datasets,results,models}
touch "$SHARED_DATA_PATH_ABSOLUTE"/datasets/.gitkeep
touch "$SHARED_DATA_PATH_ABSOLUTE"/results/.gitkeep
touch "$SHARED_DATA_PATH_ABSOLUTE"/models/.gitkeep

echo -e "${GREEN}✅ Created:${NC}"
echo "   $SHARED_DATA_PATH_ABSOLUTE/datasets/"
echo "   $SHARED_DATA_PATH_ABSOLUTE/results/"
echo "   $SHARED_DATA_PATH_ABSOLUTE/models/"

# Create configuration file
echo ""
echo -e "${BLUE}Creating configuration file...${NC}"
mkdir -p .claude

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$CONFIG_FILE" <<EOF
{
  "version": "1.1",
  "shared_data_path": "$SHARED_DATA_PATH",
  "path_type": "$PATH_TYPE",
  "created_at": "$TIMESTAMP",
  "updated_at": "$TIMESTAMP",
  "storage_type": "$STORAGE_TYPE",
  "note": "$NOTE"
}
EOF

echo -e "${GREEN}✅ Created: $CONFIG_FILE${NC}"

# Display configuration
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Configuration saved to: $CONFIG_FILE"
echo ""
cat "$CONFIG_FILE"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. When creating new worktrees, run /worktree/setup"
echo "  2. When removing worktrees, run /worktree/safe-remove"
echo ""
echo -e "${YELLOW}Important:${NC}"
echo "  - Save important data to data/shared/"
echo "  - Use data/local/ for temporary files"
echo "  - data/local/ will be deleted when worktree is removed"
echo ""
