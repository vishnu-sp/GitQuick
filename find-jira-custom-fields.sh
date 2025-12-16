#!/bin/bash

# Find Jira Custom Field IDs
# This script helps you find the custom field IDs for your Jira instance

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load Jira credentials
load_jira_credentials() {
    if [ -z "$JIRA_API_KEY" ]; then
        JIRA_API_KEY=$(security find-generic-password -a "$USER" -s "JIRA_API_KEY" -w 2>/dev/null)
    fi
    if [ -z "$JIRA_EMAIL" ]; then
        JIRA_EMAIL=$(security find-generic-password -a "$USER" -s "JIRA_EMAIL" -w 2>/dev/null)
    fi
    if [ -z "$JIRA_BASE_URL" ]; then
        JIRA_BASE_URL=$(security find-generic-password -a "$USER" -s "JIRA_BASE_URL" -w 2>/dev/null)
    fi
}

# Check credentials
load_jira_credentials

if [ -z "$JIRA_API_KEY" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_BASE_URL" ]; then
    echo -e "${RED}Error: Jira credentials not configured${NC}"
    echo -e "${YELLOW}Run: gq update (or ./store-api-keys.sh option 4)${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}🔍 Jira Custom Field Finder${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Fetch all fields
echo -e "${BLUE}📋 Fetching all Jira fields...${NC}"
fields=$(curl -s -X GET \
    "${JIRA_BASE_URL}/rest/api/3/field" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -u "${JIRA_EMAIL}:${JIRA_API_KEY}")

if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to fetch fields${NC}"
    exit 1
fi

# Check if we have a search query
if [ ! -z "$1" ]; then
    search_term="$1"
    echo -e "${YELLOW}Searching for fields matching: '$search_term'${NC}"
    echo ""
    
    # Get matching fields as JSON array
    matching_fields=$(echo "$fields" | jq -c --arg search "$search_term" \
        '[.[] | select(.name | ascii_downcase | contains($search | ascii_downcase)) | {id: .id, name: .name, type: (.schema.type // "unknown"), custom: (.custom // false)}]')
    
    count=$(echo "$matching_fields" | jq 'length')
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No fields found matching: '$search_term'${NC}"
        echo ""
        echo -e "${BLUE}💡 Tips:${NC}"
        echo -e "  • Check your spelling (e.g., 'original' not 'orginal')"
        echo -e "  • Try a shorter search term (e.g., 'estimate' instead of 'original estimate')"
        echo -e "  • Try partial words (e.g., 'dev', 'effort', 'story')"
        echo ""
        echo -e "${BLUE}💡 Common field searches:${NC}"
        echo -e "  ${GREEN}$0 'estimate'${NC}     - Find estimate-related fields"
        echo -e "  ${GREEN}$0 'original'${NC}     - Find Original Estimate field"
        echo -e "  ${GREEN}$0 'actual'${NC}       - Find Actual Dev Efforts field"
        echo -e "  ${GREEN}$0 'dev'${NC}          - Find development-related fields"
        echo -e "  ${GREEN}$0 'story'${NC}        - Find story point fields"
        echo -e "  ${GREEN}$0 'sprint'${NC}       - Find sprint fields"
        echo ""
        echo -e "${BLUE}💡 Show all custom fields:${NC} ${GREEN}$0${NC}"
    else
        echo -e "${GREEN}Found $count field(s) matching '$search_term'${NC}"
        echo ""
        
        # Display numbered list
        echo "$matching_fields" | jq -r 'to_entries[] | 
            "\u001b[33m\(.key + 1). \(.value.name)\u001b[0m\n   ID: \u001b[32m\(.value.id)\u001b[0m | Type: \(.value.type) | Custom: \(if .value.custom then "\u001b[32m✓\u001b[0m" else "\u001b[31m✗\u001b[0m" end)\n"'
        
        # Ask user to select
        echo ""
        echo -e "${YELLOW}Select a field to add to configuration (or press Enter to skip):${NC}"
        read -p "Enter number: " selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$count" ]; then
            # Get selected field
            selected_field=$(echo "$matching_fields" | jq -r ".[$((selection - 1))]")
            field_name=$(echo "$selected_field" | jq -r '.name')
            field_id=$(echo "$selected_field" | jq -r '.id')
            
            echo ""
            echo -e "${BLUE}📝 Adding field to configuration...${NC}"
            
            # Get script directory to call jira-manager
            SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
            JIRA_MANAGER="$SCRIPT_DIR/jira-manager.sh"
            
            if [ -f "$JIRA_MANAGER" ]; then
                bash "$JIRA_MANAGER" set-field "$field_name" "$field_id"
            else
                echo -e "${YELLOW}⚠️  jira-manager.sh not found, showing command instead:${NC}"
                echo -e "${GREEN}gq jira set-field \"$field_name\" $field_id${NC}"
            fi
        elif [ ! -z "$selection" ]; then
            echo -e "${YELLOW}Invalid selection${NC}"
        fi
    fi
else
    echo -e "${YELLOW}Showing all custom fields:${NC}"
    echo ""
    
    # Display all custom fields
    results=$(echo "$fields" | jq -r '.[] | select(.custom == true) | 
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\nID: \(.id)\nName: \(.name)\nType: \(.schema.type // "unknown")\nCustom: \(.custom)\n"')
    
    if [ -z "$results" ]; then
        echo -e "${YELLOW}No custom fields found in this Jira instance${NC}"
    else
        echo "$results"
        count=$(echo "$results" | grep -c "^ID:")
        echo ""
        echo -e "${GREEN}Total custom fields: $count${NC}"
    fi
fi

# Only show usage if no search term was provided
if [ -z "$1" ]; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}💡 Usage:${NC}"
    echo -e "  $0 'search term'      # Search for specific fields"
    echo ""
    echo -e "${YELLOW}💡 Common searches:${NC}"
    echo -e "  $0 'estimate'         # Find estimate-related fields"
    echo -e "  $0 'dev'              # Find development-related fields"
    echo -e "  $0 'effort'           # Find effort-related fields"
    echo -e "  $0 'actual dev'       # Find 'Actual Dev Efforts (hrs)'"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

