#!/bin/bash

# Jira Multi-Instance Manager
# Manages multiple Jira instances with same credentials

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTANCES_FILE="$HOME/.config/git-ai/jira-instances.json"

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    echo "Install with: brew install jq"
    exit 1
fi

# Initialize instances file if it doesn't exist
init_instances_file() {
    mkdir -p "$(dirname "$INSTANCES_FILE")"
    if [ ! -f "$INSTANCES_FILE" ]; then
        echo '{"instances": [], "default": null}' > "$INSTANCES_FILE"
        chmod 600 "$INSTANCES_FILE"
    fi
}

# Add a new instance
add_instance() {
    local name="$1"
    local base_url="$2"
    
    # Remove trailing slash
    base_url="${base_url%/}"
    
    init_instances_file
    
    # Check if instance already exists
    local exists=$(jq -r ".instances[] | select(.name == \"$name\") | .name" "$INSTANCES_FILE")
    
    if [ ! -z "$exists" ]; then
        # Update existing
        local temp=$(mktemp)
        jq ".instances |= map(if .name == \"$name\" then .base_url = \"$base_url\" else . end)" "$INSTANCES_FILE" > "$temp"
        mv "$temp" "$INSTANCES_FILE"
        echo -e "${GREEN}✓ Updated instance: $name${NC}"
    else
        # Add new
        local temp=$(mktemp)
        jq ".instances += [{\"name\": \"$name\", \"base_url\": \"$base_url\"}]" "$INSTANCES_FILE" > "$temp"
        mv "$temp" "$INSTANCES_FILE"
        echo -e "${GREEN}✓ Added instance: $name${NC}"
    fi
    
    # Set as default if it's the first one
    local count=$(jq '.instances | length' "$INSTANCES_FILE")
    if [ "$count" -eq 1 ]; then
        set_default_instance "$name"
    fi
}

# List all instances
list_instances() {
    init_instances_file
    
    local default=$(jq -r '.default // ""' "$INSTANCES_FILE")
    local instances=$(jq -r '.instances[] | "\(.name)|\(.base_url)"' "$INSTANCES_FILE")
    
    if [ -z "$instances" ]; then
        echo -e "${YELLOW}No Jira instances configured${NC}"
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Configured Jira Instances:${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    while IFS='|' read -r name url; do
        local marker=""
        if [ "$name" = "$default" ]; then
            marker=" ${GREEN}[DEFAULT]${NC}"
        fi
        printf "${YELLOW}%-20s${NC} %s${marker}\n" "$name" "$url"
    done <<< "$instances"
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Set default instance
set_default_instance() {
    local name="$1"
    
    init_instances_file
    
    # Check if instance exists
    local exists=$(jq -r ".instances[] | select(.name == \"$name\") | .name" "$INSTANCES_FILE")
    
    if [ -z "$exists" ]; then
        echo -e "${RED}Error: Instance '$name' not found${NC}"
        return 1
    fi
    
    local temp=$(mktemp)
    jq ".default = \"$name\"" "$INSTANCES_FILE" > "$temp"
    mv "$temp" "$INSTANCES_FILE"
    
    # Update JIRA_BASE_URL in Keychain
    local base_url=$(jq -r ".instances[] | select(.name == \"$name\") | .base_url" "$INSTANCES_FILE")
    security delete-generic-password -a "$USER" -s "JIRA_BASE_URL" 2>/dev/null
    security add-generic-password -a "$USER" -s "JIRA_BASE_URL" -w "$base_url" -U
    
    echo -e "${GREEN}✓ Default instance set to: $name ($base_url)${NC}"
}

# Get default instance URL
get_default_url() {
    init_instances_file
    
    local default=$(jq -r '.default // ""' "$INSTANCES_FILE")
    if [ -z "$default" ]; then
        return 1
    fi
    
    jq -r ".instances[] | select(.name == \"$default\") | .base_url" "$INSTANCES_FILE"
}

# Interactive instance selection
select_instance() {
    init_instances_file
    
    local instances=$(jq -r '.instances[] | .name' "$INSTANCES_FILE")
    
    if [ -z "$instances" ]; then
        echo -e "${YELLOW}No instances configured. Let's add one:${NC}"
        echo ""
        read -p "Instance name (e.g., 'production', 'staging'): " name
        read -p "Base URL: " url
        add_instance "$name" "$url"
        set_default_instance "$name"
        return 0
    fi
    
    list_instances
    
    local -a instance_names
    while IFS= read -r name; do
        instance_names+=("$name")
    done <<< "$instances"
    
    echo -e "${YELLOW}Select instance:${NC}"
    local index=1
    for name in "${instance_names[@]}"; do
        echo "  $index. $name"
        ((index++))
    done
    echo ""
    
    read -p "Select instance number (1-${#instance_names[@]}): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        if [ "$selection" -ge 1 ] && [ "$selection" -le "${#instance_names[@]}" ]; then
            local selected="${instance_names[$((selection-1))]}"
            set_default_instance "$selected"
            return 0
        fi
    fi
    
    echo -e "${RED}Invalid selection${NC}"
    return 1
}

# Remove instance
remove_instance() {
    local name="$1"
    
    init_instances_file
    
    local temp=$(mktemp)
    jq ".instances |= map(select(.name != \"$name\"))" "$INSTANCES_FILE" > "$temp"
    mv "$temp" "$INSTANCES_FILE"
    
    # If removed instance was default, clear default
    local default=$(jq -r '.default // ""' "$INSTANCES_FILE")
    if [ "$default" = "$name" ]; then
        temp=$(mktemp)
        jq '.default = null' "$INSTANCES_FILE" > "$temp"
        mv "$temp" "$INSTANCES_FILE"
    fi
    
    echo -e "${GREEN}✓ Removed instance: $name${NC}"
}

# Show help
show_help() {
    echo ""
    echo -e "${BLUE}Jira Multi-Instance Manager${NC}"
    echo ""
    echo "Usage:"
    echo "  jira-instances list                           - List all instances"
    echo "  jira-instances add NAME URL                   - Add new instance"
    echo "  jira-instances select                         - Select default instance"
    echo "  jira-instances default                        - Show default instance"
    echo "  jira-instances remove NAME                    - Remove instance"
    echo ""
    echo "Examples:"
    echo "  jira-instances add prod https://company.atlassian.net"
    echo "  jira-instances add staging https://staging.atlassian.net"
    echo "  jira-instances select"
    echo ""
}

# Main
case "${1:-list}" in
    add)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo -e "${RED}Error: Missing arguments${NC}"
            echo "Usage: jira-instances add NAME URL"
            exit 1
        fi
        add_instance "$2" "$3"
        ;;
    list|ls)
        list_instances
        ;;
    select|switch)
        select_instance
        ;;
    default|current)
        default=$(jq -r '.default // ""' "$INSTANCES_FILE" 2>/dev/null)
        if [ -z "$default" ]; then
            echo -e "${YELLOW}No default instance set${NC}"
        else
            url=$(get_default_url)
            echo -e "${GREEN}Default instance: $default${NC}"
            echo -e "${BLUE}URL: $url${NC}"
        fi
        ;;
    remove|delete|rm)
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Missing instance name${NC}"
            echo "Usage: jira-instances remove NAME"
            exit 1
        fi
        remove_instance "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
