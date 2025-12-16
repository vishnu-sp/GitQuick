#!/bin/bash

# Git CLI Wrapper - AI-Powered Git Commands
# Usage: gq [command] [options]
# 
# Commands:
#   gq              # Commit with AI (default)
#   gq commit       # Commit with AI
#   gq push         # Push current branch
#   gq pull         # Pull latest changes
#   gq cp           # Commit and push with AI
#   gq pr           # Create pull request
#   gq status       # Show git status
#   gq jira         # Jira integration
#   gq help         # Show help

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory
# Detect script location dynamically - works when sourced or executed directly
SCRIPT_DIR=""

# Method 1: Use BASH_SOURCE if available (when script is sourced or executed)
if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Method 2: Use $0 if script is executed directly
elif [ -n "$0" ] && [ "$0" != "-bash" ] && [ "$0" != "-zsh" ] && [ -f "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# If still not found, try to find from PATH or current directory
if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SCRIPT_DIR" ]; then
    # Try to find git-cli.sh in PATH
    if command -v git-cli.sh &> /dev/null; then
        SCRIPT_DIR="$(dirname "$(command -v git-cli.sh)")"
    # Try current directory
    elif [ -f "./git-cli.sh" ]; then
        SCRIPT_DIR="$(pwd)"
    fi
fi

# Final check - if still not found, show error
if [ -z "$SCRIPT_DIR" ] || [ ! -d "$SCRIPT_DIR" ]; then
    echo -e "${RED}Error: Could not determine script directory${NC}" >&2
    echo -e "${YELLOW}Please ensure git-cli.sh is in a valid directory or run 'gq init' to configure${NC}" >&2
    return 1 2>/dev/null || exit 1
fi

GIT_COMMIT_GEN="$SCRIPT_DIR/git-commit-gen.sh"
GIT_HELPERS="$SCRIPT_DIR/git-helpers.sh"
JIRA_MANAGER="$SCRIPT_DIR/jira-manager.sh"

# Check if git-commit-gen.sh exists
if [ ! -f "$GIT_COMMIT_GEN" ]; then
    echo -e "${RED}Error: git-commit-gen.sh not found at $GIT_COMMIT_GEN${NC}" >&2
    echo -e "${YELLOW}Looking in: $SCRIPT_DIR${NC}" >&2
    return 1
fi

# Initialize gq - setup paths and configure credentials
init_gq() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Git Quick (gq) - Initialization${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Detect shell
    local shell_config=""
    local shell_name=""
    if [ -n "$ZSH_VERSION" ]; then
        shell_config="$HOME/.zshrc"
        shell_name="zsh"
    elif [ -n "$BASH_VERSION" ]; then
        shell_config="$HOME/.bashrc"
        shell_name="bash"
    else
        echo -e "${YELLOW}Warning: Could not detect shell. Defaulting to ~/.zshrc${NC}"
        shell_config="$HOME/.zshrc"
        shell_name="zsh"
    fi
    
    echo -e "${BLUE}Detected shell: ${GREEN}${shell_name}${NC}"
    echo -e "${BLUE}Config file: ${GREEN}${shell_config}${NC}"
    echo ""
    
    # Use the global SCRIPT_DIR (already detected at script load)
    local script_dir="$SCRIPT_DIR"
    
    # Verify script directory exists and contains required files
    if [ -z "$script_dir" ] || [ ! -d "$script_dir" ] || [ ! -f "$script_dir/git-commit-gen.sh" ]; then
        echo -e "${RED}Error: Script directory not found or invalid${NC}" >&2
        echo -e "${YELLOW}Please ensure you're running this from the automation directory${NC}" >&2
        echo -e "${YELLOW}Or run: cd /path/to/automation && ./git-cli.sh init${NC}" >&2
        return 1
    fi
    
    # Check if already configured
    local gq_function_exists=false
    if [ -f "$shell_config" ] && grep -q "gq()" "$shell_config" 2>/dev/null; then
        gq_function_exists=true
        echo -e "${YELLOW}⚠️  gq function already exists in ${shell_config}${NC}"
        printf "Do you want to reconfigure? (y/N): "
        read -r reconfigure
        # Trim whitespace and convert to lowercase for comparison
        reconfigure=$(echo "$reconfigure" | tr '[:upper:]' '[:lower:]' | xargs)
        if [[ "$reconfigure" == "y" ]] || [[ "$reconfigure" == "yes" ]]; then
            gq_function_exists=false
            echo -e "${BLUE}Reconfiguring paths...${NC}"
        else
            echo -e "${BLUE}Skipping path configuration...${NC}"
        fi
    fi
    
    # Configure shell paths
    if [ "$gq_function_exists" = false ]; then
        echo ""
        echo -e "${BLUE}📝 Configuring shell paths...${NC}"
        
        # Create backup
        if [ -f "$shell_config" ]; then
            cp "$shell_config" "${shell_config}.backup.$(date +%Y%m%d_%H%M%S)"
            echo -e "${GREEN}✓ Created backup: ${shell_config}.backup.*${NC}"
        fi
        
        # Add gq function
        cat >> "$shell_config" << EOF

# Git Quick (gq) - AI-Powered Git Automation CLI
# Added by gq init on $(date)
if [ -f "$script_dir/git-cli.sh" ]; then
    source "$script_dir/git-cli.sh"
    gq() {
        git_cli_main "\$@"
    }
fi
EOF
        
        echo -e "${GREEN}✓ Added gq function to ${shell_config}${NC}"
        echo ""
        echo -e "${YELLOW}⚠️  Please run: ${GREEN}source ${shell_config}${NC} to reload your shell"
        echo ""
    fi
    
    # Configure credentials
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Credential Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ -f "$script_dir/store-api-keys.sh" ]; then
        bash "$script_dir/store-api-keys.sh"
    else
        echo -e "${RED}Error: store-api-keys.sh not found at $script_dir/store-api-keys.sh${NC}" >&2
        return 1
    fi
}

# Update API keys and credentials
update_gq() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Update Credentials${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if [ -f "$SCRIPT_DIR/store-api-keys.sh" ]; then
        bash "$SCRIPT_DIR/store-api-keys.sh"
    else
        echo -e "${RED}Error: store-api-keys.sh not found${NC}" >&2
        return 1
    fi
}

# Show current configuration
show_config() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Current Configuration${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Shell configuration
    local shell_config=""
    if [ -n "$ZSH_VERSION" ]; then
        shell_config="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        shell_config="$HOME/.bashrc"
    fi
    
    if [ -n "$shell_config" ] && [ -f "$shell_config" ]; then
        if grep -q "gq()" "$shell_config" 2>/dev/null; then
            echo -e "${GREEN}✓ Shell configured: ${shell_config}${NC}"
        else
            echo -e "${YELLOW}⚠ Shell not configured: ${shell_config}${NC}"
        fi
    fi
    echo ""
    
    # AI Provider
    echo -e "${YELLOW}AI Provider:${NC}"
    local ai_provider="None"
    if [ ! -z "$CURSOR_API_KEY" ] || security find-generic-password -a "$USER" -s "CURSOR_API_KEY" &>/dev/null; then
        ai_provider="Cursor AI"
    elif [ ! -z "$OPENAI_API_KEY" ] || security find-generic-password -a "$USER" -s "OPENAI_API_KEY" &>/dev/null; then
        ai_provider="OpenAI"
    elif [ ! -z "$ANTHROPIC_API_KEY" ] || security find-generic-password -a "$USER" -s "ANTHROPIC_API_KEY" &>/dev/null; then
        ai_provider="Anthropic (Claude)"
    fi
    echo "  Provider: $ai_provider"
    echo ""
    
    # Jira Configuration
    echo -e "${YELLOW}Jira Configuration:${NC}"
    local jira_email=$(security find-generic-password -a "$USER" -s "JIRA_EMAIL" -w 2>/dev/null)
    local jira_base_url=$(security find-generic-password -a "$USER" -s "JIRA_BASE_URL" -w 2>/dev/null)
    local jira_api_key=$(security find-generic-password -a "$USER" -s "JIRA_API_KEY" -w 2>/dev/null)
    
    if [ ! -z "$jira_email" ] && [ ! -z "$jira_base_url" ] && [ ! -z "$jira_api_key" ]; then
        echo -e "  ${GREEN}✓ Email: ${jira_email}${NC}"
        echo -e "  ${GREEN}✓ Base URL: ${jira_base_url}${NC}"
        echo -e "  ${GREEN}✓ API Key: Configured${NC}"
        
        # Show default project if configured
        local jira_config_file="$HOME/.config/git-ai/jira-config"
        if [ -f "$jira_config_file" ]; then
            local default_project=$(cat "$jira_config_file" 2>/dev/null)
            if [ ! -z "$default_project" ]; then
                echo -e "  ${GREEN}✓ Default Project: ${default_project}${NC}"
            fi
        fi
    else
        echo -e "  ${YELLOW}⚠ Not configured${NC}"
        echo -e "  Run: ${GREEN}gq update${NC} to configure"
    fi
    echo ""
    
    # Credential Storage
    echo -e "${YELLOW}Credential Storage:${NC}"
    echo "  Method: macOS Keychain"
    echo ""
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Show help
show_help() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Git Quick CLI - AI-Powered Git Commands${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Usage:${NC}"
    echo "  gq [command] [options]"
    echo ""
    echo -e "${YELLOW}Configuration Commands:${NC}"
    echo -e "  ${GREEN}gq init${NC}                 Initialize and configure gq"
    echo -e "  ${GREEN}gq update${NC}               Update API keys and credentials"
    echo -e "  ${GREEN}gq config${NC}               Show current configuration"
    echo ""
    echo -e "${YELLOW}Git Commands:${NC}"
    echo -e "  ${GREEN}gq${NC}                    Commit with AI (default)"
    echo -e "  ${GREEN}gq commit [TICKET-ID]${NC} Commit with AI (optional ticket ID)"
    echo -e "  ${GREEN}gq push${NC}               Push current branch"
    echo -e "  ${GREEN}gq pull${NC}               Pull latest changes"
    echo -e "  ${GREEN}gq cp [TICKET-ID]${NC}     Commit and push with AI"
    echo -e "  ${GREEN}gq pr [base-branch]${NC}   Create pull request"
    echo -e "  ${GREEN}gq status${NC}             Show git status"
    echo ""
    echo -e "${YELLOW}Branch Commands:${NC}"
    echo -e "  ${GREEN}gq branch TICKET-ID${NC}   Create branch from ticket"
    echo -e "  ${GREEN}gq branch TYPE TICKET${NC} Create typed branch (feature/bugfix/hotfix)"
    echo -e "  ${GREEN}gq branch TYPE NAME${NC}   Create branch without ticket"
    echo ""
    echo -e "${YELLOW}Jira Commands:${NC}"
    echo -e "  ${GREEN}gq jira select${NC}        Select instance + project"
    echo -e "  ${GREEN}gq jira list [PROJECT]${NC} List tickets in project"
    echo -e "  ${GREEN}gq jira add NAME URL${NC}  Add new Jira instance"
    echo -e "  ${GREEN}gq jira instances${NC}     List all instances"
    echo -e "  ${GREEN}gq jira remove NAME${NC}   Remove instance"
    echo -e "  ${GREEN}gq jira current${NC}       Show current config"
    echo ""
    echo -e "${YELLOW}Jira Custom Fields:${NC}"
    echo -e "  ${GREEN}gq jira find-field \"term\"${NC}  Find field IDs"
    echo -e "  ${GREEN}gq jira set-field NAME ID${NC}   Add/update field"
    echo -e "  ${GREEN}gq jira remove-field NAME${NC}   Remove field"
    echo -e "  ${GREEN}gq jira list-fields${NC}         Show configured fields"
    echo -e "  ${GREEN}gq jira help${NC}                Show Jira help"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  gq init                # First-time setup"
    echo "  gq                    # Commit with AI"
    echo "  gq commit DH-1234     # Commit with ticket ID"
    echo "  gq branch DH-1234     # Create branch from ticket"
    echo "  gq branch feature DH-1234  # Create feature branch"
    echo "  gq jira select        # Setup Jira project"
    echo "  gq jira list          # Browse tickets"
    echo "  gq cp DH-1234         # Commit and push with ticket"
    echo "  gq pr main            # Create PR to main branch"
    echo ""
    echo -e "${YELLOW}Quick Tips:${NC}"
    echo "  • First time: ${GREEN}gq init${NC}"
    echo "  • Setup Jira: ${GREEN}gq jira select${NC}"
    echo "  • Browse tickets: ${GREEN}gq jira list${NC}"
    echo "  • Use ticket ID: ${GREEN}gq commit DH-1234${NC}"
    echo ""
}

# Show Jira help
show_jira_help() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Jira Integration Commands${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Instance Management:${NC}"
    echo "  gq jira add NAME URL       - Add new Jira instance"
    echo "  gq jira instances          - List all instances"
    echo "  gq jira remove NAME        - Remove instance"
    echo ""
    echo -e "${YELLOW}Project Management:${NC}"
    echo "  gq jira select             - Select instance + project"
    echo "  gq jira current            - Show current configuration"
    echo ""
    echo -e "${YELLOW}Browse Tickets:${NC}"
    echo "  gq jira list               - List tickets in default project"
    echo "  gq jira list PROJECT-KEY   - List tickets in specific project"
    echo ""
    echo -e "${YELLOW}Custom Fields Management:${NC}"
    echo "  gq jira find-field \"term\"   - Search for field IDs in Jira"
    echo "  gq jira set-field NAME ID  - Add/update custom field config"
    echo "  gq jira remove-field NAME  - Remove custom field from config"
    echo "  gq jira list-fields        - Show all configured fields"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  gq jira add prod https://company.atlassian.net"
    echo "  gq jira add staging https://staging.atlassian.net"
    echo "  gq jira instances          # See all instances"
    echo "  gq jira select             # Choose instance + project"
    echo "  gq jira list               # Show tickets"
    echo "  gq jira find-field \"actual dev\"  # Find custom field ID"
    echo "  gq jira set-field \"Actual Dev Efforts (hrs)\" customfield_10634"
    echo "  gq jira list-fields        # See configured fields"
    echo "  gq commit DH-1234          # Commit with ticket"
    echo ""
}

# Show Branch help
show_branch_help() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Branch Management Commands${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Create Branches:${NC}"
    echo "  gq branch TICKET-ID              - Create branch with interactive type"
    echo "  gq branch feature TICKET-ID      - Create feature/TICKET-ID-description"
    echo "  gq branch bugfix TICKET-ID       - Create bugfix/TICKET-ID-description"
    echo "  gq branch hotfix TICKET-ID       - Create hotfix/TICKET-ID-description"
    echo "  gq branch feature NAME           - Create feature/NAME (no ticket)"
    echo ""
    echo -e "${YELLOW}Branch Naming Format:${NC}"
    echo "  TYPE/TICKET-ID-description"
    echo ""
    echo -e "${YELLOW}Examples:${NC}"
    echo "  gq branch DBMA-163               # Interactive: feature/DBMA-163-add-oauth"
    echo "  gq branch feature DBMA-163       # Creates: feature/DBMA-163-description"
    echo "  gq branch bugfix DBMA-164        # Creates: bugfix/DBMA-164-description"
    echo "  gq branch hotfix DBMA-165        # Creates: hotfix/DBMA-165-description"
    echo "  gq branch feature oauth-system   # Creates: feature/oauth-system"
    echo ""
    echo -e "${YELLOW}Naming Best Practices:${NC}"
    echo "  ✓ Include ticket ID for traceability"
    echo "  ✓ Use type prefix (feature/bugfix/hotfix)"
    echo "  ✓ Add brief description (lowercase, hyphens)"
    echo "  ✓ Keep it concise (< 50 characters total)"
    echo ""
}

# Sanitize branch name part
sanitize_branch_name() {
    local name="$1"
    # Convert to lowercase, replace spaces/underscores with hyphens, remove special chars
    echo "$name" | tr '[:upper:]' '[:lower:]' | tr ' _' '-' | sed 's/[^a-z0-9-]//g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//'
}

# Add comment to Jira ticket (reuse existing logic from git-commit-gen.sh)
add_jira_comment() {
    local ticket_id="$1"
    local comment="$2"
    
    # Load Jira credentials
    local JIRA_API_KEY=$(security find-generic-password -a "$USER" -s "JIRA_API_KEY" -w 2>/dev/null)
    local JIRA_EMAIL=$(security find-generic-password -a "$USER" -s "JIRA_EMAIL" -w 2>/dev/null)
    local JIRA_BASE_URL=$(security find-generic-password -a "$USER" -s "JIRA_BASE_URL" -w 2>/dev/null)
    
    if [ -z "$JIRA_API_KEY" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_BASE_URL" ]; then
        return 1
    fi
    
    # Prepare JSON payload in Atlassian Document Format (ADF)
    local json_payload=$(jq -n \
        --arg text "$comment" \
        '{
            body: {
                type: "doc",
                version: 1,
                content: [
                    {
                        type: "paragraph",
                        content: [
                            {
                                type: "text",
                                text: $text
                            }
                        ]
                    }
                ]
            }
        }')
    
    # Add comment via Jira API
    local response=$(curl -s -X POST \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}/comment" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" \
        -d "$json_payload" 2>&1)
    
    if echo "$response" | jq -e '.id' &>/dev/null 2>&1; then
        return 0
    else
        # Debug: show error
        echo -e "${YELLOW}API Response: $(echo "$response" | head -c 200)${NC}" >&2
        return 1
    fi
}

# Prompt to update Jira after push
# No longer needed - using git-commit-gen.sh with --push-only flag

# Get Jira ticket info (summary and issue type)
get_jira_ticket_info() {
    local ticket_id="$1"
    
    # Load Jira credentials
    local JIRA_API_KEY=$(security find-generic-password -a "$USER" -s "JIRA_API_KEY" -w 2>/dev/null)
    local JIRA_EMAIL=$(security find-generic-password -a "$USER" -s "JIRA_EMAIL" -w 2>/dev/null)
    local JIRA_BASE_URL=$(security find-generic-password -a "$USER" -s "JIRA_BASE_URL" -w 2>/dev/null)
    
    if [ -z "$JIRA_API_KEY" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_BASE_URL" ]; then
        return 1
    fi
    
    # Fetch ticket info from Jira (summary and issue type)
    local response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}?fields=summary,issuetype" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    if echo "$response" | jq -e '.fields.summary' &>/dev/null; then
        # Return both summary and issue type separated by |
        local summary=$(echo "$response" | jq -r '.fields.summary')
        local issue_type=$(echo "$response" | jq -r '.fields.issuetype.name')
        echo "${summary}|${issue_type}"
        return 0
    fi
    
    return 1
}

# Map Jira issue type to branch type
map_issue_type_to_branch_type() {
    local issue_type="$1"
    
    # Convert to lowercase (portable way for bash/zsh)
    issue_type=$(echo "$issue_type" | tr '[:upper:]' '[:lower:]')
    
    case "$issue_type" in
        bug|defect)
            echo "bugfix"
            ;;
        hotfix|incident|critical)
            echo "hotfix"
            ;;
        story|task|feature|enhancement|improvement|epic)
            echo "feature"
            ;;
        *)
            echo "feature"  # Default
            ;;
    esac
}

# Create branch with ticket ID
create_branch_from_ticket() {
    local branch_type="$1"
    local ticket_id="$2"
    local custom_desc="$3"
    
    # Validate we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository${NC}" >&2
        return 1
    fi
    
    echo ""
    echo -e "${BLUE}🎫 Analyzing ticket: ${YELLOW}${ticket_id}${NC}"
    
    # Try to get Jira ticket info (summary and issue type)
    local suggested_desc=""
    local jira_issue_type=""
    local auto_detected_type=""
    
    echo -e "${BLUE}📋 Fetching ticket info from Jira...${NC}"
    local ticket_info=$(get_jira_ticket_info "$ticket_id" 2>/dev/null)
    
    if [ $? -eq 0 ] && [ ! -z "$ticket_info" ]; then
        local ticket_summary=$(echo "$ticket_info" | cut -d'|' -f1)
        jira_issue_type=$(echo "$ticket_info" | cut -d'|' -f2)
        
        echo -e "${GREEN}✓ Found: ${NC}${ticket_summary}"
        echo -e "${GREEN}✓ Type:  ${NC}${jira_issue_type}"
        
        # Auto-detect branch type from Jira issue type
        auto_detected_type=$(map_issue_type_to_branch_type "$jira_issue_type")
        
        # Create suggested description from summary (first 3-4 words)
        suggested_desc=$(echo "$ticket_summary" | awk '{print tolower($1"-"$2"-"$3)}' | head -c 30)
        suggested_desc=$(sanitize_branch_name "$suggested_desc")
    else
        echo -e "${YELLOW}⚠ Could not fetch ticket info (Jira not configured or ticket not found)${NC}"
    fi
    
    # If no type specified, use auto-detected or ask interactively
    if [ -z "$branch_type" ]; then
        if [ ! -z "$auto_detected_type" ]; then
            # Auto-detected from Jira
            echo ""
            echo -e "${GREEN}✓ Auto-detected branch type: ${YELLOW}${auto_detected_type}${GREEN} (from Jira)${NC}"
            printf "Press Enter to accept or type 1-3 to change (1=feature, 2=bugfix, 3=hotfix): "
            read type_selection
            
            if [ -z "$type_selection" ]; then
                branch_type="$auto_detected_type"
            else
                case "$type_selection" in
                    1) branch_type="feature" ;;
                    2) branch_type="bugfix" ;;
                    3) branch_type="hotfix" ;;
                    *) branch_type="$auto_detected_type" ;;
                esac
            fi
        else
            # Ask interactively
            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${YELLOW}Select Branch Type:${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            echo -e "${GREEN}1.${NC} feature  - New feature or enhancement"
            echo -e "${GREEN}2.${NC} bugfix   - Bug fix"
            echo -e "${GREEN}3.${NC} hotfix   - Critical production fix"
            echo ""
            printf "Select type (1-3) [1]: "
            read type_selection
            
            case "${type_selection:-1}" in
                1) branch_type="feature" ;;
                2) branch_type="bugfix" ;;
                3) branch_type="hotfix" ;;
                *) branch_type="feature" ;;
            esac
        fi
    fi
    
    echo ""
    echo -e "${BLUE}🌿 Creating ${YELLOW}${branch_type}${BLUE} branch for: ${YELLOW}${ticket_id}${NC}"
    
    # Get description from user
    local description="$custom_desc"
    if [ -z "$description" ]; then
        echo ""
        if [ ! -z "$suggested_desc" ]; then
            printf "Enter description [${suggested_desc}]: "
            read description
            description="${description:-$suggested_desc}"
        else
            printf "Enter description (brief, lowercase): "
            read description
        fi
    fi
    
    # Sanitize description
    description=$(sanitize_branch_name "$description")
    
    # Build branch name
    local branch_name="${branch_type}/${ticket_id}"
    if [ ! -z "$description" ]; then
        branch_name="${branch_name}-${description}"
    fi
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Branch Name:${NC} ${GREEN}${branch_name}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Check if branch already exists
    if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
        echo -e "${YELLOW}⚠ Branch already exists. Switching to it...${NC}"
        git checkout "$branch_name"
        return 0
    fi
    
    # Create and checkout branch
    echo -e "${BLUE}🌿 Creating branch from current branch...${NC}"
    if git checkout -b "$branch_name"; then
        echo ""
        echo -e "${GREEN}✓ Successfully created and switched to branch: ${branch_name}${NC}"
        echo ""
        echo -e "${YELLOW}Next steps:${NC}"
        echo "  1. Make your changes"
        echo "  2. Commit: ${GREEN}gq commit${NC} or ${GREEN}gq commit ${ticket_id}${NC}"
        echo "  3. Push: ${GREEN}gq push${NC}"
        echo "  4. Create PR: ${GREEN}gq pr${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Failed to create branch${NC}" >&2
        return 1
    fi
}

# Create branch without ticket ID
create_branch_simple() {
    local branch_type="$1"
    local branch_name="$2"
    
    # Validate we're in a git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository${NC}" >&2
        return 1
    fi
    
    # Sanitize name
    branch_name=$(sanitize_branch_name "$branch_name")
    
    # Build full branch name
    local full_name="${branch_type}/${branch_name}"
    
    echo ""
    echo -e "${BLUE}🌿 Creating branch: ${GREEN}${full_name}${NC}"
    
    # Check if branch already exists
    if git show-ref --verify --quiet "refs/heads/${full_name}"; then
        echo -e "${YELLOW}⚠ Branch already exists. Switching to it...${NC}"
        git checkout "$full_name"
        return 0
    fi
    
    # Create and checkout branch
    if git checkout -b "$full_name"; then
        echo -e "${GREEN}✓ Successfully created and switched to branch: ${full_name}${NC}"
        echo ""
        return 0
    else
        echo -e "${RED}✗ Failed to create branch${NC}" >&2
        return 1
    fi
}

# Main CLI handler function
# This function can be aliased to any name (gai, gq, gitz, etc.)
git_cli_main() {
    local command="${1:-commit}"
    local ticket_id=""
    local args=()
    
    # Check for ticket ID in arguments (pattern: PROJECT-123)
    # Also check for --will-push flag
    # BUT: Skip this for branch/jira/config/init/update commands (they handle their own parsing)
    local will_push=false
    if [[ "$command" != "branch" ]] && [[ "$command" != "br" ]] && [[ "$command" != "jira" ]] && [[ "$command" != "config" ]] && [[ "$command" != "init" ]] && [[ "$command" != "update" ]]; then
        for arg in "$@"; do
            if [[ "$arg" == "--will-push" ]]; then
                will_push=true
            elif [[ "$arg" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
                ticket_id="$arg"
            else
                args+=("$arg")
            fi
        done
        
        # Reconstruct arguments without ticket ID
        set -- "${args[@]}"
        command="${1:-commit}"
    fi
    
    case "$command" in
        commit|"")
            # Commit with AI
            if [ "$will_push" = true ]; then
                # This is from 'cp' command
                if [ -z "$ticket_id" ]; then
                    bash "$GIT_COMMIT_GEN" --will-push
                else
                    bash "$GIT_COMMIT_GEN" --will-push "$ticket_id"
                fi
            else
                # Regular commit
                if [ -z "$ticket_id" ]; then
                    bash "$GIT_COMMIT_GEN"
                else
                    bash "$GIT_COMMIT_GEN" "$ticket_id"
                fi
            fi
            ;;
        push)
            # Push current branch
            local current_branch=$(git branch --show-current 2>/dev/null)
            if [ -z "$current_branch" ]; then
                echo -e "${RED}Error: Not a git repository or no branch checked out${NC}" >&2
                return 1
            fi
            
            # Try to extract ticket ID from branch name
            local branch_ticket=$(echo "$current_branch" | grep -oE '[A-Z]{2,10}-[0-9]+' | head -1)
            if [ ! -z "$branch_ticket" ]; then
                echo -e "${BLUE}📤 Pushing branch: ${GREEN}$current_branch${NC}"
                echo -e "${BLUE}🎫 Associated ticket: ${YELLOW}$branch_ticket${NC}"
            else
                echo -e "${BLUE}📤 Pushing branch: $current_branch${NC}"
            fi
            
            # Use git-commit-gen.sh with --push-only flag for full Jira flow
                if [ ! -z "$branch_ticket" ]; then
                bash "$GIT_COMMIT_GEN" --push-only "$branch_ticket"
            else
                # No ticket ID, just push
                if git push -u origin "$current_branch" 2>/dev/null || git push origin "$current_branch"; then
                    echo -e "${GREEN}✓ Successfully pushed${NC}"
            else
                echo -e "${RED}✗ Push failed${NC}" >&2
                return 1
                fi
            fi
            ;;
        pull)
            # Pull latest changes
            echo -e "${BLUE}📥 Pulling latest changes...${NC}"
            git pull
            ;;
        cp)
            # Commit and push with AI
            shift  # Remove 'cp' from arguments
            if [ -z "$ticket_id" ] && [ $# -gt 0 ] && [[ "$1" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
                ticket_id="$1"
            fi
            if [ -z "$ticket_id" ]; then
                bash "$GIT_COMMIT_GEN" --will-push
            else
                bash "$GIT_COMMIT_GEN" --will-push "$ticket_id"
            fi
            ;;
        pr)
            # Create pull request - works like gq cp but creates PR instead of just pushing
            shift  # Remove 'pr' from arguments
            local base_branch="${1:-}"
            
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BLUE}🔍 DEBUG: Starting PR creation${NC}"
            echo -e "${BLUE}   Base branch: ${base_branch}${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            
            # Validate we're in a git repository
            echo -e "${BLUE}🔍 Checking if in git repository...${NC}"
            if ! git rev-parse --git-dir > /dev/null 2>&1; then
                echo -e "${RED}Error: Not a git repository${NC}" >&2
                return 1
            fi
            echo -e "${GREEN}✓ In git repository${NC}"
            echo ""
            
            # Validate base_branch is not a remote name
            echo -e "${BLUE}🔍 Validating base branch is not a remote name...${NC}"
            if [ ! -z "$base_branch" ]; then
                local remotes=$(git remote)
                echo -e "${BLUE}   Available remotes: ${remotes}${NC}"
                if echo "$remotes" | grep -q "^${base_branch}$"; then
                    echo -e "${RED}Error: '$base_branch' is a remote name, not a branch name${NC}" >&2
                    echo -e "${YELLOW}Did you mean one of these branches?${NC}"
                    git branch -r | grep "origin/$base_branch" | sed 's|origin/||' | head -5
                    echo -e "${YELLOW}Usage: gq pr <branch-name>${NC}"
                    echo -e "${YELLOW}Example: gq pr main  (not 'gq pr origin')${NC}"
                    return 1
                fi
                echo -e "${GREEN}✓ '$base_branch' is not a remote name${NC}"
            fi
            echo ""
            
            # Extract ticket ID from branch name if present
            echo -e "${BLUE}🔍 Getting current branch...${NC}"
            local current_branch=$(git branch --show-current 2>&1)
            local branch_status=$?
            echo -e "${BLUE}   Current branch: $current_branch (status: $branch_status)${NC}"
            
            local ticket_id=""
            if [ ! -z "$current_branch" ]; then
                echo -e "${BLUE}🔍 Extracting ticket ID from branch name...${NC}"
                ticket_id=$(echo "$current_branch" | grep -oE '[A-Z]{2,10}-[0-9]+' | head -1)
                echo -e "${BLUE}   Ticket ID: $ticket_id${NC}"
            fi
            echo ""
            
            # Check for uncommitted changes - commit them first (like gq cp)
            echo -e "${BLUE}🔍 Checking for uncommitted changes...${NC}"
            local has_changes=false
            if ! git diff-index --quiet HEAD -- 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
                has_changes=true
            fi
            echo -e "${BLUE}   Has uncommitted changes: $has_changes${NC}"
            echo ""
            
            if [ "$has_changes" = true ]; then
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${BLUE}📝 Committing Changes${NC}"
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                
                # Commit with AI (like gq commit) - skip sync to avoid errors
                # Use --no-sync flag if available, or skip sync in git-commit-gen.sh
                if [ -z "$ticket_id" ]; then
                    # Temporarily disable sync by setting environment variable
                    SKIP_SYNC=true bash "$GIT_COMMIT_GEN" 2>&1
                else
                    SKIP_SYNC=true bash "$GIT_COMMIT_GEN" "$ticket_id" 2>&1
                fi
                
                local commit_status=$?
                if [ $commit_status -ne 0 ]; then
                    echo -e "${RED}✗ Commit failed. Cannot create PR.${NC}" >&2
                    return 1
                fi
            fi
            
            # Check if branch is pushed - push if needed (like gq push)
            # First verify remote exists and is accessible
            echo -e "${BLUE}🔍 Verifying remote 'origin' exists...${NC}"
            local remote_check=$(git remote get-url origin 2>&1)
            local remote_status=$?
            echo -e "${BLUE}   Remote URL: $remote_check (status: $remote_status)${NC}"
            echo ""
            
            if [ $remote_status -ne 0 ]; then
                echo -e "${RED}✗ Error: No 'origin' remote configured${NC}" >&2
                echo -e "${YELLOW}Please configure a remote: git remote add origin <url>${NC}" >&2
                return 1
            fi
            
            # Verify we can access the remote
            echo -e "${BLUE}🔍 Getting remote URL...${NC}"
            local remote_url=$(git remote get-url origin 2>&1)
            echo -e "${BLUE}   Remote URL: $remote_url${NC}"
            echo ""
            
            if [ -z "$remote_url" ]; then
                echo -e "${RED}✗ Error: Cannot get remote URL for 'origin'${NC}" >&2
                return 1
            fi
            
            # Get upstream branch - use full ref to avoid ambiguity
            echo -e "${BLUE}🔍 Getting upstream branch...${NC}"
            local upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>&1)
            local upstream_status=$?
            echo -e "${BLUE}   Upstream: $upstream (status: $upstream_status)${NC}"
            echo ""
            
            # Validate upstream format (should be like "origin/branch-name")
            if [ ! -z "$upstream" ] && [[ ! "$upstream" =~ ^[^/]+/ ]]; then
                echo -e "${YELLOW}⚠️  Invalid upstream format: $upstream${NC}"
                upstream=""
            fi
            if [ -z "$upstream" ]; then
                echo ""
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${BLUE}📤 Pushing Branch${NC}"
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                echo -e "${BLUE}Branch '$current_branch' is not pushed to remote${NC}"
                echo -e "${BLUE}Pushing branch to origin...${NC}"
                
                # Try push with -u first (sets upstream)
                local push_output=$(git push -u origin "$current_branch" 2>&1)
                local push_status=$?
                
                if [ $push_status -eq 0 ]; then
                    echo -e "${GREEN}✓ Successfully pushed${NC}"
                else
                    echo -e "${RED}✗ Push failed${NC}" >&2
                    echo "$push_output" | head -5 >&2
                    echo -e "${YELLOW}Please check your remote configuration and try:${NC}" >&2
                    echo -e "${YELLOW}  git push -u origin $current_branch${NC}" >&2
                    return 1
                fi
            else
                # Branch has upstream, verify it's pushed and up-to-date
                # Extract remote and branch from upstream (e.g., "origin/feature/xxx")
                local upstream_remote=$(echo "$upstream" | cut -d'/' -f1)
                local upstream_branch=$(echo "$upstream" | cut -d'/' -f2-)
                
                # Verify upstream remote exists
                if ! git remote get-url "$upstream_remote" > /dev/null 2>&1; then
                    echo -e "${YELLOW}⚠️  Upstream remote '$upstream_remote' not found, pushing to origin${NC}"
                    local push_output=$(git push -u origin "$current_branch" 2>&1)
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ Successfully pushed${NC}"
                    else
                        echo -e "${RED}✗ Push failed${NC}" >&2
                        echo "$push_output" | head -5 >&2
                        return 1
                    fi
                else
                    local local_sha=$(git rev-parse HEAD 2>/dev/null)
                    # Use full upstream ref to avoid ambiguity
                    local remote_sha=$(git rev-parse "$upstream" 2>/dev/null 2>&1)
                    
                    if [ $? -ne 0 ] || [ -z "$remote_sha" ]; then
                        # Remote branch might not exist yet, try to push
                        echo ""
                        echo -e "${YELLOW}⚠️  Remote branch not found${NC}"
                        echo -e "${BLUE}Pushing branch...${NC}"
                        local push_output=$(git push -u origin "$current_branch" 2>&1)
                        if [ $? -eq 0 ]; then
                            echo -e "${GREEN}✓ Successfully pushed${NC}"
                        else
                            echo -e "${RED}✗ Push failed${NC}" >&2
                            echo "$push_output" | head -5 >&2
                            return 1
                        fi
                    elif [ "$local_sha" != "$remote_sha" ]; then
                        echo ""
                        echo -e "${YELLOW}⚠️  Local branch is ahead of remote${NC}"
                        echo -e "${BLUE}Pushing latest commits...${NC}"
                        local push_output=$(git push origin "$current_branch" 2>&1)
                        if [ $? -eq 0 ]; then
                            echo -e "${GREEN}✓ Successfully pushed${NC}"
                        else
                            echo -e "${RED}✗ Push failed${NC}" >&2
                            echo "$push_output" | head -5 >&2
                            return 1
                        fi
                    fi
                fi
            fi
            
            # First, update Jira with commit info (before creating PR)
            if [ ! -z "$ticket_id" ]; then
                echo ""
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${BLUE}🎫 Updating Jira with Commit Info${NC}"
                echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                
                # Get commit info
                local commit_sha=$(git rev-parse --short HEAD 2>/dev/null)
                local commit_msg=$(git log -1 --pretty=%B 2>/dev/null)
                local commit_url=""
                
                # Build commit URL
                local remote_url=$(git config --get remote.origin.url 2>/dev/null)
                if [[ "$remote_url" =~ ^git@([^:]+):(.+)\.git$ ]]; then
                    local temp="${remote_url#git@}"
                    local git_host="${temp%%:*}"
                    local git_repo="${temp#*:}"
                    git_repo="${git_repo%.git}"
                    
                    # Construct commit URL (works for GitLab and GitHub)
                    commit_url="https://${git_host}/${git_repo}/-/commit/${commit_sha}"
                    
                    echo -e "${GREEN}📝 Commit Details:${NC}"
                    echo -e "   SHA: ${commit_sha}"
                    echo -e "   Message: ${commit_msg}"
                    echo -e "   URL: ${commit_url}"
                    echo ""
                    
                    # Call Jira update via git-commit-gen.sh (reuse existing logic)
                    # Note: This will prompt for Jira update
                    if [ -f "$GIT_COMMIT_GEN" ]; then
                        # Use environment variable to trigger Jira update in push-only mode
                        WILL_PUSH=true JIRA_TICKET_ID="$ticket_id" bash "$GIT_COMMIT_GEN" --push-only "$ticket_id" 2>&1 | grep -E "Jira|✓|✗|⚠" || true
                    fi
                fi
            fi
            
            # Now create PR and update Jira with PR link
            echo ""
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo -e "${BLUE}📝 Creating Pull Request${NC}"
            echo -e "${BLUE}   base_branch: $base_branch${NC}"
            echo -e "${BLUE}   ticket_id: $ticket_id${NC}"
            echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            echo ""
            
            if [ -f "$GIT_HELPERS" ]; then
                # Source the file to load functions (don't capture output in subshell)
                source "$GIT_HELPERS" 2>&1
                local source_status=$?
                if [ $source_status -ne 0 ]; then
                    echo -e "${RED}Error sourcing git-helpers.sh${NC}" >&2
                    return 1
                fi
                
                # Verify function is available
                if ! type create_pull_request &>/dev/null; then
                    echo -e "${RED}Error: create_pull_request function not found after sourcing${NC}" >&2
                    return 1
                fi
                
                # Pass ticket_id as environment variable for Jira update
                if [ ! -z "$ticket_id" ]; then
                    export JIRA_TICKET_ID="$ticket_id"
                fi
                
                create_pull_request "$base_branch" "" "" "$ticket_id"
            else
                echo -e "${RED}Error: git-helpers.sh not found at $GIT_HELPERS${NC}" >&2
                return 1
            fi
            ;;
        status|st)
            # Show git status
            git status
            ;;
        branch|br)
            # Branch management
            shift  # Remove 'branch' from arguments
            local arg1="$1"
            local arg2="$2"
            local arg3="$3"
            
            if [ -z "$arg1" ]; then
                show_branch_help
                return 0
            fi
            
            # Check if arg1 is help
            if [[ "$arg1" =~ ^(help|--help|-h)$ ]]; then
                show_branch_help
                return 0
            fi
            
            # Pattern 1: gq branch TICKET-ID (interactive type selection)
            if [[ "$arg1" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
                create_branch_from_ticket "" "$arg1" "$arg2"
                return $?
            fi
            
            # Pattern 2: gq branch TYPE TICKET-ID [description]
            # Pattern 3: gq branch TYPE NAME
            local branch_type="$arg1"
            local identifier="$arg2"
            
            # Validate branch type
            if [[ ! "$branch_type" =~ ^(feature|bugfix|hotfix|feat|bug|fix)$ ]]; then
                echo -e "${RED}Error: Invalid branch type '$branch_type'${NC}" >&2
                echo -e "${YELLOW}Valid types: feature, bugfix, hotfix${NC}" >&2
                return 1
            fi
            
            # Normalize type names
            case "$branch_type" in
                feat) branch_type="feature" ;;
                bug|fix) branch_type="bugfix" ;;
            esac
            
            if [ -z "$identifier" ]; then
                echo -e "${RED}Error: Missing branch name or ticket ID${NC}" >&2
                echo ""
                show_branch_help
                return 1
            fi
            
            # Check if identifier is a ticket ID
            if [[ "$identifier" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
                # Pattern 2: Create branch with ticket ID
                create_branch_from_ticket "$branch_type" "$identifier" "$arg3"
            else
                # Pattern 3: Create branch without ticket
                create_branch_simple "$branch_type" "$identifier"
            fi
            ;;
        init)
            # Initialize gq - setup paths and configure credentials
            init_gq
            ;;
        update)
            # Update API keys and credentials
            update_gq
            ;;
        config)
            # Show current configuration
            show_config
            ;;
        jira)
            # Jira commands - delegate to jira-manager.sh
            shift  # Remove 'jira' from arguments
            local jira_command="${1:-list}"
            
            if [ ! -f "$JIRA_MANAGER" ]; then
                echo -e "${RED}Error: jira-manager.sh not found at $JIRA_MANAGER${NC}" >&2
                return 1
            fi
            
            case "$jira_command" in
                help|--help|-h)
                    show_jira_help
                    ;;
                *)
                    # Pass all arguments to jira-manager.sh
                    bash "$JIRA_MANAGER" "$@"
                    ;;
            esac
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            # Check if it's a ticket ID
            if [[ "$command" =~ ^[A-Z][A-Z0-9]*-[0-9]+$ ]]; then
                # Treat as ticket ID for commit
                bash "$GIT_COMMIT_GEN" "$command"
            else
                echo -e "${RED}Error: Unknown command '$command'${NC}" >&2
                echo ""
                show_help
                return 1
            fi
            ;;
    esac
}

# If script is executed directly (not sourced), run the command
if [[ -n "${BASH_SOURCE[0]}" ]] && [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    git_cli_main "$@"
fi

# Note: git_cli_main function is now available when sourced
# Call it from your shell function (e.g., gq() in .zshrc)
