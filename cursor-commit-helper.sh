#!/bin/bash

# Cursor AI Commit Message Helper
# This script helps generate commit messages using Cursor's AI

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Error: Not a git repository"
    exit 1
fi

# Get staged changes
if git diff --cached --quiet; then
    echo "No staged changes. Staging all changes..."
    git add -A
    if git diff --cached --quiet; then
        echo "No changes to commit"
        exit 1
    fi
fi

# Get diff
DIFF=$(git diff --cached)

# Truncate if too long
if [ ${#DIFF} -gt 4000 ]; then
    DIFF="${DIFF: -4000}"
fi

# Create prompt file
PROMPT_FILE="/tmp/cursor-commit-$(date +%s).md"

cat > "$PROMPT_FILE" <<EOF
# Generate Git Commit Message

Analyze the following git diff and generate a conventional commit message.

## Git Diff

\`\`\`diff
$DIFF
\`\`\`

## Requirements

- Format: \`type(scope): subject\`
- Types: feat, fix, docs, style, refactor, perf, test, chore, ci
- Subject must be under 72 characters
- Be concise and descriptive
- Focus on what changed, not how

## Generated Commit Message

EOF

echo -e "${GREEN}✓ Created prompt file:${NC}"
echo -e "${BLUE}$PROMPT_FILE${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Open this file in Cursor"
echo "  2. Place cursor at the end of the file"
echo "  3. Press Cmd+I (or Ctrl+I) to open Composer"
echo "  4. Ask: 'Generate a conventional commit message for this diff'"
echo "  5. Copy the generated message"
echo ""
echo -e "${BLUE}Opening file in Cursor...${NC}"

# Try to open in Cursor
if command -v cursor &> /dev/null; then
    cursor "$PROMPT_FILE" &
elif [ ! -z "$CURSOR_BIN" ]; then
    "$CURSOR_BIN" "$PROMPT_FILE" &
else
    # Fallback: open with default editor
    ${EDITOR:-nano} "$PROMPT_FILE"
fi

echo ""
read "?Press Enter after you've generated the message in Cursor: "
read "?Paste the generated commit message: " COMMIT_MSG

if [ ! -z "$COMMIT_MSG" ]; then
    echo ""
    echo -e "${GREEN}Committing with message:${NC}"
    echo -e "${BLUE}$COMMIT_MSG${NC}"
    echo ""
    read "?Confirm commit? (Y/n): " confirm
    if [[ ! "$confirm" =~ ^[Nn]$ ]]; then
        git commit -m "$COMMIT_MSG"
        echo -e "${GREEN}✓ Committed successfully${NC}"
    else
        echo "Cancelled"
    fi
else
    echo "No message provided. Cancelled."
fi

# Cleanup
rm -f "$PROMPT_FILE"
