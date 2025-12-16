#!/bin/bash

# Configure Original Estimate Field ID
# Helps users find and configure the correct Original Estimate field

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔧 Configure Original Estimate Field${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find Original Estimate fields
echo -e "${BLUE}🔍 Searching for 'Original Estimate' fields...${NC}"
echo ""

"$SCRIPT_DIR/find-jira-custom-fields.sh" "original estimate"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}💡 The correct field has been configured!${NC}"
echo ""
echo -e "If you selected a different field, you can also set it via environment variable:"
echo -e "${GREEN}export JIRA_ORIGINAL_ESTIMATE_FIELD_ID=\"customfield_XXXXX\"${NC}"
echo ""
echo -e "Add to your ${BLUE}~/.zshrc${NC} or ${BLUE}~/.bashrc${NC} to make it permanent"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
