#!/bin/bash

# Jira Project Manager
# Manages default Jira project and browses tickets

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source the main script functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_COMMIT_SCRIPT="$SCRIPT_DIR/git-commit-gen.sh"

# Load necessary functions from git-commit-gen.sh
JIRA_CONFIG_FILE="$HOME/.config/git-ai/jira-config"
JIRA_CUSTOM_FIELDS_CONFIG="$HOME/.config/git-ai/jira-custom-fields.json"

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
check_credentials() {
    load_jira_credentials
    if [ -z "$JIRA_API_KEY" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_BASE_URL" ]; then
        echo -e "${RED}Error: Jira credentials not configured${NC}"
        echo -e "${YELLOW}Run: gq update (or ./store-api-keys.sh option 4)${NC}"
        exit 1
    fi
}

# Save default project
save_default_project() {
    local project_key="$1"
    mkdir -p "$(dirname "$JIRA_CONFIG_FILE")"
    echo "$project_key" > "$JIRA_CONFIG_FILE"
    chmod 600 "$JIRA_CONFIG_FILE"
}

# Load default project
load_default_project() {
    if [ -f "$JIRA_CONFIG_FILE" ]; then
        cat "$JIRA_CONFIG_FILE"
    fi
}

# List all projects
list_projects() {
    local response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/project/search?maxResults=100" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    if echo "$response" | jq -e '.values' &>/dev/null; then
        echo "$response" | jq -r '.values[] | "\(.key)|\(.name)|\(.projectTypeKey)"'
        return 0
    fi
    return 1
}

# List tickets from project
list_tickets() {
    local project_key="$1"
    local max_results="${2:-20}"
    
    # Try with quoted project key for better compatibility
    local jql="project = \"$project_key\" ORDER BY updated DESC"
    local encoded_jql=$(echo "$jql" | jq -sRr @uri)
    
    # Try API v3 first
    local response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/search?jql=${encoded_jql}&maxResults=${max_results}&fields=summary,status,issuetype,updated" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    # Check if we got valid issues
    if echo "$response" | jq -e '.issues' &>/dev/null 2>&1; then
        local issue_count=$(echo "$response" | jq '.issues | length' 2>/dev/null)
        if [ "$issue_count" -gt 0 ]; then
            echo "$response" | jq -r '.issues[] | "\(.key)|\(.fields.summary)|\(.fields.status.name)|\(.fields.issuetype.name)"'
            return 0
        fi
    fi
    
    # Try API v2 as fallback
    response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/2/search?jql=${encoded_jql}&maxResults=${max_results}&fields=summary,status,issuetype,updated" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    if echo "$response" | jq -e '.issues' &>/dev/null 2>&1; then
        local issue_count=$(echo "$response" | jq '.issues | length' 2>/dev/null)
        if [ "$issue_count" -gt 0 ]; then
            echo "$response" | jq -r '.issues[] | "\(.key)|\(.fields.summary)|\(.fields.status.name)|\(.fields.issuetype.name)"'
            return 0
        fi
    fi
    
    return 1
}

# Show instance selection menu (if multiple instances exist)
select_instance_if_needed() {
    local instances_file="$HOME/.config/git-ai/jira-instances.json"
    
    # Check if instances file exists and has multiple instances
    if [ -f "$instances_file" ] && command -v jq &> /dev/null; then
        local instance_count=$(jq '.instances | length' "$instances_file" 2>/dev/null || echo "0")
        
        if [ "$instance_count" -gt 1 ]; then
            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}Step 1: Select Jira Instance${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            
            local default_instance=$(jq -r '.default // ""' "$instances_file")
            local -a instance_names
            local -a instance_urls
            local index=1
            
            while IFS= read -r line; do
                local name=$(echo "$line" | jq -r '.name')
                local url=$(echo "$line" | jq -r '.base_url')
                instance_names+=("$name")
                instance_urls+=("$url")
                
                local marker=""
                if [ "$name" = "$default_instance" ]; then
                    marker=" ${GREEN}[CURRENT]${NC}"
                fi
                
                printf "${GREEN}%2d.${NC} ${YELLOW}%-20s${NC} %s${marker}\n" \
                    "$index" "$name" "$url"
                ((index++))
            done < <(jq -c '.instances[]' "$instances_file")
            
            echo ""
            read -p "Select instance (1-${#instance_names[@]}) or Enter to use current: " instance_selection
            
            if [ ! -z "$instance_selection" ]; then
                if [[ "$instance_selection" =~ ^[0-9]+$ ]] && [ "$instance_selection" -ge 1 ] && [ "$instance_selection" -le "${#instance_names[@]}" ]; then
                    local selected_name="${instance_names[$((instance_selection-1))]}"
                    local selected_url="${instance_urls[$((instance_selection-1))]}"
                    
                    # Update default instance
                    local temp=$(mktemp)
                    jq ".default = \"$selected_name\"" "$instances_file" > "$temp"
                    mv "$temp" "$instances_file"
                    
                    # Update JIRA_BASE_URL in Keychain
                    security delete-generic-password -a "$USER" -s "JIRA_BASE_URL" 2>/dev/null
                    security add-generic-password -a "$USER" -s "JIRA_BASE_URL" -w "$selected_url" -U
                    
                    # Reload credentials with new base URL
                    JIRA_BASE_URL="$selected_url"
                    
                    echo -e "${GREEN}✓ Switched to instance: $selected_name${NC}"
                    echo ""
                fi
            fi
        fi
    fi
}

# Show project selection menu
select_project() {
    # First, let user select instance if multiple exist
    select_instance_if_needed
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Step 2: Select Jira Project${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}📋 Loading projects from current instance...${NC}"
    
    local projects=$(list_projects)
    if [ -z "$projects" ]; then
        echo -e "${RED}No projects found${NC}"
        exit 1
    fi
    
    echo ""
    
    local -a project_keys
    local index=1
    local current_default=$(load_default_project)
    
    while IFS='|' read -r key name type; do
        project_keys+=("$key")
        local marker=""
        if [ "$key" = "$current_default" ]; then
            marker=" ${GREEN}[CURRENT]${NC}"
        fi
        printf "${GREEN}%2d.${NC} ${YELLOW}%-10s${NC} %s${marker}\n" \
            "$index" "$key" "$name"
        ((index++))
    done <<< "$projects"
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    read -p "Select project number (1-${#project_keys[@]}): " selection
    
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        if [ "$selection" -ge 1 ] && [ "$selection" -le "${#project_keys[@]}" ]; then
            local selected_key="${project_keys[$((selection-1))]}"
            save_default_project "$selected_key"
            echo ""
            echo -e "${GREEN}✓ Default project set to: $selected_key${NC}"
            
            # Show summary
            local current_instance="Unknown"
            if [ -f "$HOME/.config/git-ai/jira-instances.json" ] && command -v jq &> /dev/null; then
                current_instance=$(jq -r '.default // "Unknown"' "$HOME/.config/git-ai/jira-instances.json")
            fi
            
            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${GREEN}✓ Configuration saved:${NC}"
            echo -e "  Instance: ${YELLOW}$current_instance${NC}"
            echo -e "  Project:  ${YELLOW}$selected_key${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            return 0
        fi
    fi
    
    echo -e "${RED}Invalid selection${NC}"
    exit 1
}

# Browse tickets in default or specified project
browse_tickets() {
    local project_key="$1"
    
    if [ -z "$project_key" ]; then
        project_key=$(load_default_project)
        if [ -z "$project_key" ]; then
            echo -e "${YELLOW}No default project set. Please select one:${NC}"
            echo ""
            select_project
            project_key=$(load_default_project)
        fi
    fi
    
    echo ""
    echo -e "${BLUE}📋 Loading tickets from $project_key...${NC}"
    
    local tickets=$(list_tickets "$project_key" 20)
    if [ -z "$tickets" ]; then
        echo -e "${YELLOW}No tickets found in project $project_key${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Recent Tickets in $project_key:${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    while IFS='|' read -r key summary status type; do
        printf "${YELLOW}%-12s${NC} ${BLUE}[%-11s]${NC} ${GREEN}%-8s${NC} %s\n" \
            "$key" "$status" "$type" "$(echo "$summary" | cut -c1-60)"
    done <<< "$tickets"
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}💡 Tip: Use 'git-ai TICKET-ID' to commit with specific ticket${NC}"
}

# List all instances
list_all_instances() {
    local instances_file="$HOME/.config/git-ai/jira-instances.json"
    
    if [ ! -f "$instances_file" ] || ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}No instances configured${NC}"
        echo ""
        echo -e "${BLUE}Add instances with:${NC}"
        echo "  jira add NAME URL"
        echo ""
        echo "Example:"
        echo "  jira add prod https://company.atlassian.net"
        return 1
    fi
    
    local default=$(jq -r '.default // ""' "$instances_file")
    local instances=$(jq -r '.instances[] | "\(.name)|\(.base_url)"' "$instances_file")
    
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

# Add new instance
add_new_instance() {
    local name="$1"
    local base_url="$2"
    
    if [ -z "$name" ] || [ -z "$base_url" ]; then
        echo -e "${RED}Error: Missing arguments${NC}"
        echo "Usage: jira add NAME URL"
        echo ""
        echo "Example:"
        echo "  jira add prod https://company.atlassian.net"
        return 1
    fi
    
    # Remove trailing slash
    base_url="${base_url%/}"
    
    local instances_file="$HOME/.config/git-ai/jira-instances.json"
    mkdir -p "$(dirname "$instances_file")"
    
    # Initialize if doesn't exist
    if [ ! -f "$instances_file" ]; then
        echo '{"instances": [], "default": null}' > "$instances_file"
        chmod 600 "$instances_file"
    fi
    
    # Check if instance already exists
    local exists=$(jq -r ".instances[] | select(.name == \"$name\") | .name" "$instances_file" 2>/dev/null)
    
    if [ ! -z "$exists" ]; then
        # Update existing
        local temp=$(mktemp)
        jq ".instances |= map(if .name == \"$name\" then .base_url = \"$base_url\" else . end)" "$instances_file" > "$temp"
        mv "$temp" "$instances_file"
        echo -e "${GREEN}✓ Updated instance: $name${NC}"
    else
        # Add new
        local temp=$(mktemp)
        jq ".instances += [{\"name\": \"$name\", \"base_url\": \"$base_url\"}]" "$instances_file" > "$temp"
        mv "$temp" "$instances_file"
        echo -e "${GREEN}✓ Added instance: $name${NC}"
    fi
    
    # Set as default if it's the first one
    local count=$(jq '.instances | length' "$instances_file")
    if [ "$count" -eq 1 ]; then
        local temp=$(mktemp)
        jq ".default = \"$name\"" "$instances_file" > "$temp"
        mv "$temp" "$instances_file"
        
        # Update Keychain
        security delete-generic-password -a "$USER" -s "JIRA_BASE_URL" 2>/dev/null
        security add-generic-password -a "$USER" -s "JIRA_BASE_URL" -w "$base_url" -U
        
        echo -e "${GREEN}✓ Set as default instance${NC}"
    fi
}

# Remove instance
remove_instance() {
    local name="$1"
    
    if [ -z "$name" ]; then
        echo -e "${RED}Error: Missing instance name${NC}"
        echo "Usage: jira remove NAME"
        return 1
    fi
    
    local instances_file="$HOME/.config/git-ai/jira-instances.json"
    
    if [ ! -f "$instances_file" ]; then
        echo -e "${RED}No instances configured${NC}"
        return 1
    fi
    
    local temp=$(mktemp)
    jq ".instances |= map(select(.name != \"$name\"))" "$instances_file" > "$temp"
    mv "$temp" "$instances_file"
    
    # If removed instance was default, clear default
    local default=$(jq -r '.default // ""' "$instances_file")
    if [ "$default" = "$name" ]; then
        temp=$(mktemp)
        jq '.default = null' "$instances_file" > "$temp"
        mv "$temp" "$instances_file"
    fi
    
    echo -e "${GREEN}✓ Removed instance: $name${NC}"
}

# Show help
# Custom field management functions
load_custom_fields() {
    if [ -f "$JIRA_CUSTOM_FIELDS_CONFIG" ]; then
        cat "$JIRA_CUSTOM_FIELDS_CONFIG"
    else
        echo '{"fields": []}'
    fi
}

save_custom_fields() {
    local fields_json="$1"
    mkdir -p "$(dirname "$JIRA_CUSTOM_FIELDS_CONFIG")"
    echo "$fields_json" > "$JIRA_CUSTOM_FIELDS_CONFIG"
    chmod 600 "$JIRA_CUSTOM_FIELDS_CONFIG"
}

add_custom_field() {
    local field_name="$1"
    local field_id="$2"
    local field_type="${3:-text}"
    
    if [ -z "$field_name" ] || [ -z "$field_id" ]; then
        echo -e "${RED}Error: Field name and ID are required${NC}"
        echo -e "${YELLOW}Usage: gq jira set-field \"Field Name\" customfield_XXXXX [type]${NC}"
        return 1
    fi
    
    # Load existing fields
    local fields=$(load_custom_fields)
    
    # Check if field already exists
    local existing=$(echo "$fields" | jq -r --arg name "$field_name" '.fields[] | select(.name == $name) | .id')
    
    if [ ! -z "$existing" ]; then
        # Update existing field
        fields=$(echo "$fields" | jq --arg name "$field_name" --arg id "$field_id" --arg type "$field_type" \
            '.fields = [.fields[] | if .name == $name then {name: $name, id: $id, type: $type, enabled: true} else . end]')
        echo -e "${GREEN}✓ Updated field: $field_name${NC}"
    else
        # Add new field
        fields=$(echo "$fields" | jq --arg name "$field_name" --arg id "$field_id" --arg type "$field_type" \
            '.fields += [{name: $name, id: $id, type: $type, enabled: true}]')
        echo -e "${GREEN}✓ Added field: $field_name${NC}"
    fi
    
    save_custom_fields "$fields"
    echo -e "${BLUE}Field ID: $field_id${NC}"
}

remove_custom_field() {
    local field_name="$1"
    
    if [ -z "$field_name" ]; then
        echo -e "${RED}Error: Field name is required${NC}"
        echo -e "${YELLOW}Usage: gq jira remove-field \"Field Name\"${NC}"
        return 1
    fi
    
    # Load existing fields
    local fields=$(load_custom_fields)
    
    # Check if field exists
    local existing=$(echo "$fields" | jq -r --arg name "$field_name" '.fields[] | select(.name == $name) | .id')
    
    if [ -z "$existing" ]; then
        echo -e "${YELLOW}⚠️  Field not found: $field_name${NC}"
        return 1
    fi
    
    # Remove field
    fields=$(echo "$fields" | jq --arg name "$field_name" '.fields = [.fields[] | select(.name != $name)]')
    save_custom_fields "$fields"
    echo -e "${GREEN}✓ Removed field: $field_name${NC}"
}

list_custom_fields() {
    local fields=$(load_custom_fields)
    local count=$(echo "$fields" | jq '.fields | length')
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Configured Custom Fields${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No custom fields configured${NC}"
        echo ""
        echo -e "${BLUE}💡 Add a field:${NC} ${GREEN}gq jira set-field \"Field Name\" customfield_XXXXX${NC}"
        echo -e "${BLUE}💡 Find fields:${NC} ${GREEN}gq jira find-field \"search term\"${NC}"
    else
        echo "$fields" | jq -r '.fields[] | "  \u001b[33m\(.name)\u001b[0m\n    ID: \u001b[32m\(.id)\u001b[0m\n    Type: \(.type)\n    Enabled: \(if .enabled then "\u001b[32m✓\u001b[0m" else "\u001b[31m✗\u001b[0m" end)\n"'
    fi
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

find_jira_field() {
    local search_term="$1"
    
    if [ -z "$search_term" ]; then
        echo -e "${RED}Error: Search term is required${NC}"
        echo -e "${YELLOW}Usage: gq jira find-field \"search term\"${NC}"
        echo ""
        echo -e "${BLUE}💡 Examples:${NC}"
        echo -e "  ${GREEN}gq jira find-field \"estimate\"${NC}"
        echo -e "  ${GREEN}gq jira find-field \"actual dev\"${NC}"
        echo -e "  ${GREEN}gq jira find-field \"story\"${NC}"
        return 1
    fi
    
    check_credentials
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}🔍 Jira Custom Field Finder${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Fetch all fields
    echo -e "${BLUE}📋 Fetching all Jira fields...${NC}"
    local fields=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/field" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}")
    
    if [ $? -ne 0 ] || [ -z "$fields" ]; then
        echo -e "${RED}Failed to fetch fields from Jira${NC}"
        return 1
    fi
    
    # Validate JSON response
    if ! echo "$fields" | jq empty 2>/dev/null; then
        echo -e "${RED}Invalid JSON response from Jira API${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Searching for fields matching: '$search_term'${NC}"
    echo ""
    
    # Get matching fields as JSON array
    local matching_fields=$(echo "$fields" | jq -c --arg search "$search_term" \
        '[.[] | select(.name | ascii_downcase | contains($search | ascii_downcase)) | {id: .id, name: .name, type: (.schema.type // "unknown"), custom: (.custom // false)}]' 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$matching_fields" ]; then
        echo -e "${RED}Failed to parse fields${NC}"
        return 1
    fi
    
    local count=$(echo "$matching_fields" | jq 'length' 2>/dev/null || echo "0")
    
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}No fields found matching: '$search_term'${NC}"
        echo ""
        echo -e "${BLUE}💡 Tips:${NC}"
        echo -e "  • Check your spelling (e.g., 'original' not 'orginal')"
        echo -e "  • Try a shorter search term (e.g., 'estimate' instead of 'original estimate')"
        echo -e "  • Try partial words (e.g., 'dev', 'effort', 'story')"
        return 1
    fi
    
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
        local selected_field=$(echo "$matching_fields" | jq -r ".[$((selection - 1))]")
        local field_name=$(echo "$selected_field" | jq -r '.name')
        local field_id=$(echo "$selected_field" | jq -r '.id')
        
        echo ""
        echo -e "${BLUE}📝 Adding field to configuration...${NC}"
        add_custom_field "$field_name" "$field_id"
    elif [ ! -z "$selection" ]; then
        echo -e "${YELLOW}Invalid selection${NC}"
    fi
}

show_help() {
    echo ""
    echo -e "${BLUE}Jira CLI - Project and Instance Manager${NC}"
    echo ""
    echo -e "${YELLOW}Instance Management:${NC}"
    echo "  jira add NAME URL          - Add new Jira instance"
    echo "  jira instances             - List all instances"
    echo "  jira remove NAME           - Remove instance"
    echo ""
    echo -e "${YELLOW}Project Management:${NC}"
    echo "  jira select                - Select instance + project"
    echo "  jira current               - Show current configuration"
    echo ""
    echo -e "${YELLOW}Browse Tickets:${NC}"
    echo "  jira                       - Browse tickets in default project"
    echo "  jira list                  - List tickets in default project"
    echo "  jira list PROJECT-KEY      - List tickets in specific project"
    echo ""
    echo -e "${YELLOW}Custom Fields:${NC}"
    echo "  jira set-field NAME ID     - Add/update custom field"
    echo "  jira remove-field NAME     - Remove custom field"
    echo "  jira list-fields           - List configured fields"
    echo "  jira find-field TERM       - Search for field IDs"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  jira add prod https://company.atlassian.net"
    echo "  jira add staging https://staging.atlassian.net"
    echo "  jira instances             # See all instances"
    echo "  jira select                # Choose instance + project"
    echo "  jira list                  # Show tickets"
    echo "  jira find-field \"actual dev\"  # Find custom field ID"
    echo "  jira set-field \"Actual Dev Efforts (hrs)\" customfield_10634"
    echo "  jira list-fields           # See configured fields"
    echo "  git-ai DH-1234             # Commit with ticket"
    echo ""
}

# Main logic
case "${1:-}" in
    add)
        check_credentials
        add_new_instance "$2" "$3"
        ;;
    instances|list-instances)
        list_all_instances
        ;;
    remove|delete|rm)
        remove_instance "$2"
        ;;
    select|switch|change)
        check_credentials
        select_project
        ;;
    list|ls|browse)
        check_credentials
        browse_tickets "$2"
        ;;
    current|status)
        instances_file="$HOME/.config/git-ai/jira-instances.json"
        current_instance="Unknown"
        current_project=$(load_default_project)
        
        if [ -f "$instances_file" ] && command -v jq &> /dev/null; then
            current_instance=$(jq -r '.default // "Unknown"' "$instances_file")
        fi
        
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BLUE}Current Configuration:${NC}"
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        if [ "$current_instance" != "Unknown" ]; then
            echo -e "  ${YELLOW}Instance:${NC} ${GREEN}$current_instance${NC}"
        else
            echo -e "  ${YELLOW}Instance:${NC} ${RED}Not set${NC}"
        fi
        
        if [ ! -z "$current_project" ]; then
            echo -e "  ${YELLOW}Project:${NC}  ${GREEN}$current_project${NC}"
        else
            echo -e "  ${YELLOW}Project:${NC}  ${RED}Not set${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        
        if [ "$current_instance" = "Unknown" ] || [ -z "$current_project" ]; then
            echo -e "${YELLOW}💡 Run: ${GREEN}jira select${YELLOW} to configure${NC}"
            echo ""
        fi
        ;;
    set-field|add-field)
        add_custom_field "$2" "$3" "$4"
        ;;
    remove-field|delete-field)
        remove_custom_field "$2"
        ;;
    list-fields|fields|show-fields)
        list_custom_fields
        ;;
    find-field|search-field)
        find_jira_field "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        # Default: browse tickets
        check_credentials
        browse_tickets
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
