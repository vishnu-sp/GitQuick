#!/usr/bin/env bash

# AI-Powered Git Commit Message Generator
# Analyzes git diff and generates conventional commit messages

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get script directory for bundled jq
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "$0" ] && [ "$0" != "-bash" ] && [ "$0" != "-zsh" ] && [ -f "$0" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# Use bundled jq if available, otherwise fall back to system jq
JQ=""
if [ -f "$SCRIPT_DIR/jq-binary" ] && [ -x "$SCRIPT_DIR/jq-binary" ]; then
    JQ="$SCRIPT_DIR/jq-binary"
elif command -v jq &> /dev/null; then
    JQ="jq"
else
    echo -e "${RED}Error: jq is required but not found${NC}" >&2
    echo -e "${YELLOW}Please install jq: brew install jq${NC}" >&2
    exit 1
fi

# Parse command line arguments
WILL_PUSH=false
PUSH_ONLY=false
TICKET_ID_PARAM=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --will-push)
            WILL_PUSH=true
            shift
            ;;
        --push-only)
            PUSH_ONLY=true
            WILL_PUSH=true
            shift
            ;;
        [A-Z][A-Z0-9]*-[0-9]*)
            # Matches Jira ticket ID pattern (e.g., DH-1234, PROJ-456)
            TICKET_ID_PARAM="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}Error: Not a git repository${NC}"
    exit 1
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Push committed changes to remote
push_to_remote() {
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📤 Pushing Changes${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${BLUE}🔄 Pushing branch: $current_branch${NC}"
    
    # Try push with -u flag first (sets upstream), then without if already set
    if git push -u origin "$current_branch" 2>/dev/null || git push origin "$current_branch"; then
        echo -e "${GREEN}✓ Successfully pushed to remote${NC}"
        return 0
    else
        echo -e "${RED}✗ Push failed${NC}" >&2
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Sync with remote before committing
sync_with_remote() {
    # Skip sync if SKIP_SYNC environment variable is set
    if [ "$SKIP_SYNC" = "true" ]; then
        return 0
    fi
    
    local current_branch=$(git branch --show-current)
    local remote=$(git config branch."$current_branch".remote 2>/dev/null || echo "origin")
    
    # Validate remote name - must not be empty and should be a valid remote
    if [ -z "$remote" ] || [ "$remote" = "origin" ]; then
        # Check if origin exists
        if ! git remote get-url origin > /dev/null 2>&1; then
            echo -e "${YELLOW}⚠️  No remote configured. Skipping sync.${NC}"
            return 0
        fi
        remote="origin"
    else
        # Verify the remote exists
        if ! git remote get-url "$remote" > /dev/null 2>&1; then
            echo -e "${YELLOW}⚠️  Remote '$remote' not found. Using 'origin' instead.${NC}"
            if ! git remote get-url origin > /dev/null 2>&1; then
                echo -e "${YELLOW}⚠️  No remote configured. Skipping sync.${NC}"
                return 0
            fi
            remote="origin"
        fi
    fi
    
    echo -e "${BLUE}🔄 Syncing with remote...${NC}"
    echo -e "${BLUE}Fetching latest changes...${NC}"
    
    # Fetch latest changes (silently) - use explicit remote/branch format
    # Use origin explicitly to avoid any ambiguity
    # Validate current branch exists to avoid git treating it as a remote
    if [ -z "$current_branch" ]; then
        echo -e "${YELLOW}⚠️  Could not determine current branch. Skipping sync.${NC}"
        return 0
    fi
    
    if ! git fetch origin "$current_branch" &>/dev/null 2>&1; then
        # If specific branch fetch fails, try fetching all from origin
        if ! git fetch origin &>/dev/null 2>&1; then
            echo -e "${YELLOW}⚠️  Failed to fetch from remote. Continuing...${NC}"
            return 0
        fi
    fi
    
    # Check if local branch has upstream
    local upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
    
    if [ ! -z "$upstream" ]; then
        # Check if there are new changes to pull
        # Use git rev-list to check if remote is ahead of local
        # This compares HEAD (local) to upstream (remote tracking branch)
        local commits_ahead=$(git rev-list --count HEAD.."$upstream" 2>/dev/null)
        local check_status=$?
        
        # Handle error case (upstream might not exist yet, or branches diverged)
        if [ $check_status -ne 0 ] || [ -z "$commits_ahead" ]; then
            commits_ahead=0
        fi
        
        # Convert to integer for comparison (handle empty string)
        commits_ahead=$((commits_ahead + 0))
        
        # If no commits ahead, we're already up to date
        if [ "$commits_ahead" -eq 0 ]; then
            echo -e "${GREEN}✓ No new changes - already up to date${NC}"
            return 0
        fi
        
        # Show what's new before pulling
        echo -e "${BLUE}Pulling latest changes...${NC}"
        echo -e "${YELLOW}New commits to pull: ${commits_ahead}${NC}"
        echo ""
        echo -e "${BLUE}Recent commits:${NC}"
        git log --oneline HEAD.."$upstream" 2>/dev/null | head -5 | sed 's/^/  • /'
        if [ "$commits_ahead" -gt 5 ]; then
            echo -e "  ${YELLOW}... and $((commits_ahead - 5)) more${NC}"
        fi
        echo ""
        
        # Show files changed
        echo -e "${BLUE}Files changed:${NC}"
        local changed_files=$(git diff --name-only HEAD.."$upstream" 2>/dev/null | sort -u)
        local file_count=$(echo "$changed_files" | grep -c . || echo "0")
        
        if [ "$file_count" -gt 0 ]; then
            echo "$changed_files" | head -15 | sed 's/^/  • /'
            if [ "$file_count" -gt 15 ]; then
                echo -e "  ${YELLOW}... and $((file_count - 15)) more file(s)${NC}"
            fi
        else
            echo -e "  ${YELLOW}(no files changed)${NC}"
        fi
        echo ""
        
        # Check for uncommitted changes that might block pull
        local has_uncommitted=$(git diff-index --quiet HEAD -- 2>/dev/null; echo $?)
        if [ $has_uncommitted -ne 0 ]; then
            echo -e "${YELLOW}⚠️  You have uncommitted changes${NC}"
            echo -e "${YELLOW}Changes will be automatically stashed before pull and reapplied after${NC}"
            echo -e "${YELLOW}Manual intervention may be required if conflicts occur${NC}"
            echo ""
        fi
        
        # Try to pull with rebase first (cleaner history)
        # Use --autostash to automatically stash uncommitted changes before pull and reapply after
        # Use explicit remote/branch format to avoid ambiguity
        local pull_output=$(git pull --rebase --autostash "${remote}" "${current_branch}" 2>&1)
        local pull_status=$?
        
        # Check if git mistakenly tried to use branch as remote
        if echo "$pull_output" | grep -q "does not appear to be a git repository"; then
            echo -e "${RED}❌ Error: Git configuration issue detected${NC}"
            echo -e "${YELLOW}Remote: $remote, Branch: $current_branch${NC}"
            echo -e "${YELLOW}Skipping sync to avoid errors${NC}"
            return 0
        fi
        
        # Check if pull was blocked by uncommitted changes
        if echo "$pull_output" | grep -qi "cannot pull.*uncommitted\|index contains uncommitted\|please commit or stash"; then
            echo -e "${YELLOW}⚠️  Pull blocked by uncommitted changes${NC}"
            echo -e "${YELLOW}To sync:${NC}"
            echo "  1. Commit your changes: git add -A && git commit"
            echo "  2. Or stash them: git stash, then pull, then git stash pop"
            echo ""
            echo -e "${YELLOW}Skipping pull. You can commit your changes and try again.${NC}"
            return 0
        fi
        
        # Check if pull actually succeeded
        if [ $pull_status -eq 0 ] && ! echo "$pull_output" | grep -qi "error\|cannot\|failed"; then
            # After successful pull, refresh upstream and verify we're up to date
            # Use explicit remote to avoid ambiguity
            git fetch "${remote}" "${current_branch}" &>/dev/null 2>&1 || true
            
            # Re-check commits ahead after pull
            local commits_after_pull=$(git rev-list --count HEAD.."$upstream" 2>/dev/null || echo "0")
            commits_after_pull=$((commits_after_pull + 0))
            
            if [ "$commits_after_pull" -eq 0 ]; then
                echo -e "${GREEN}✓ Synced successfully - pulled ${commits_ahead} commit(s)${NC}"
                echo -e "${GREEN}✓ Repository is now up to date${NC}"
            else
                # This shouldn't happen, but handle edge cases
                echo -e "${YELLOW}⚠️  Pull completed but ${commits_after_pull} commit(s) still ahead${NC}"
                echo -e "${YELLOW}This may indicate a sync issue. Check: git status${NC}"
            fi
            return 0
        else
            # Pull failed - check why
            if echo "$pull_output" | grep -qi "cannot pull.*uncommitted\|index contains uncommitted"; then
                echo -e "${YELLOW}⚠️  Pull blocked by uncommitted changes${NC}"
                echo -e "${YELLOW}To proceed:${NC}"
                echo "  1. Commit your changes first: git add -A && git commit"
                echo "  2. Or stash them: git stash, then pull, then git stash pop"
                echo ""
                echo -e "${YELLOW}Skipping pull due to uncommitted changes.${NC}"
                return 0
            fi
            
            # Check for autostash conflicts
            if echo "$pull_output" | grep -qi "could not apply autostash\|autostash.*conflict"; then
                echo ""
                echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo -e "${RED}❌ Autostash conflict detected!${NC}"
                echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                echo -e "${YELLOW}Your uncommitted changes could not be automatically reapplied.${NC}"
                echo -e "${YELLOW}They have been saved in the stash.${NC}"
                echo ""
                echo -e "${YELLOW}To recover your changes:${NC}"
                echo "  1. Check what was stashed: git stash list"
                echo "  2. View the stashed changes: git stash show -p"
                echo "  3. Apply the stash: git stash pop"
                echo "  4. Resolve any conflicts manually"
                echo ""
                echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                echo ""
                exit 1
            fi
            
            # Check if we're in a rebase state (conflicts)
            if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ]; then
                # Check for conflicted files
                local conflicted_files=$(git diff --name-only --diff-filter=U 2>/dev/null)
                
                if [ ! -z "$conflicted_files" ]; then
                    echo ""
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo -e "${RED}❌ Merge conflicts detected!${NC}"
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo ""
                    echo -e "${YELLOW}Conflicted files:${NC}"
                    echo "$conflicted_files" | sed 's/^/  • /'
                    echo ""
                    echo -e "${YELLOW}To resolve conflicts:${NC}"
                    echo "  1. Review conflicted files (look for <<<<<<< markers)"
                    echo "  2. Resolve conflicts manually in each file"
                    echo "  3. Stage resolved files: git add <file>"
                    echo "  4. Continue rebase: git rebase --continue"
                    echo "  5. Or abort rebase: git rebase --abort"
                    echo ""
                    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                    echo -e "${RED}Cannot commit until conflicts are resolved.${NC}"
                    echo ""
                    exit 1
                fi
            fi
            
            # Other pull error (not conflicts)
            echo -e "${YELLOW}⚠️  Pull had issues:${NC}"
            echo "$pull_output" | tail -3 | sed 's/^/  /'
            echo ""
            echo -e "${YELLOW}Check status with: git status${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}⚠️  No upstream branch set. Skipping pull.${NC}"
        echo -e "${BLUE}💡 Set upstream with: git push --set-upstream $remote $current_branch${NC}"
        return 0
    fi
}

# ============================================================================
# JIRA INTEGRATION
# ============================================================================

# Config file for storing default Jira project
JIRA_CONFIG_FILE="$HOME/.config/git-ai/jira-config"

# Save default Jira project
save_default_project() {
    local project_key="$1"
    mkdir -p "$(dirname "$JIRA_CONFIG_FILE")"
    echo "$project_key" > "$JIRA_CONFIG_FILE"
    chmod 600 "$JIRA_CONFIG_FILE"
}

# Load default Jira project
load_default_project() {
    if [ -f "$JIRA_CONFIG_FILE" ]; then
        cat "$JIRA_CONFIG_FILE"
    fi
}

# List all Jira projects
list_jira_projects() {
    load_jira_credentials
    
    if [ -z "$JIRA_API_KEY" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_BASE_URL" ]; then
        echo "Error: Jira credentials not configured" >&2
        return 1
    fi
    
    local response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/project/search?maxResults=100" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    if echo "$response" | "$JQ" -e '.values' &>/dev/null; then
        echo "$response" | "$JQ" -r '.values[] | "\(.key)|\(.name)|\(.projectTypeKey)"'
        return 0
    fi
    
    return 1
}

# List recent tickets from a Jira project
list_project_tickets() {
    local project_key="$1"
    local max_results="${2:-20}"
    
    load_jira_credentials
    
    if [ -z "$JIRA_API_KEY" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_BASE_URL" ]; then
        return 1
    fi
    
    # JQL query for recent tickets in project (quoted for compatibility)
    local jql="project = \"$project_key\" ORDER BY updated DESC"
    local encoded_jql=$(echo "$jql" | "$JQ" -sRr @uri)
    
    # Try API v3 first
    local response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/search?jql=${encoded_jql}&maxResults=${max_results}&fields=summary,status,issuetype,updated" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    # Check if we got valid issues
    if echo "$response" | "$JQ" -e '.issues' &>/dev/null 2>&1; then
        local issue_count=$(echo "$response" | "$JQ" '.issues | length' 2>/dev/null)
        if [ "$issue_count" -gt 0 ]; then
            echo "$response" | "$JQ" -r '.issues[] | "\(.key)|\(.fields.summary)|\(.fields.status.name)|\(.fields.issuetype.name)"'
            return 0
        fi
    fi
    
    # Try API v2 as fallback
    response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/2/search?jql=${encoded_jql}&maxResults=${max_results}&fields=summary,status,issuetype,updated" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    if echo "$response" | "$JQ" -e '.issues' &>/dev/null 2>&1; then
        local issue_count=$(echo "$response" | "$JQ" '.issues | length' 2>/dev/null)
        if [ "$issue_count" -gt 0 ]; then
            echo "$response" | "$JQ" -r '.issues[] | "\(.key)|\(.fields.summary)|\(.fields.status.name)|\(.fields.issuetype.name)"'
            return 0
        fi
    fi
    
    return 1
}

# Interactive ticket selection from project
select_ticket_interactive() {
    local project_key="$1"
    
    echo -e "${BLUE}📋 Loading tickets from $project_key...${NC}" >&2
    
    local tickets=$(list_project_tickets "$project_key" 15)
    
    if [ -z "$tickets" ]; then
        echo -e "${YELLOW}No tickets found in project $project_key${NC}" >&2
        return 1
    fi
    
    echo "" >&2
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo -e "${BLUE}Recent Tickets from $project_key:${NC}" >&2
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    echo "" >&2
    
    local -a ticket_ids
    local index=1
    
    while IFS='|' read -r key summary status type; do
        ticket_ids+=("$key")
        printf "${GREEN}%2d.${NC} ${YELLOW}%-12s${NC} ${BLUE}[%-11s]${NC} %s\n" \
            "$index" "$key" "$status" "$(echo "$summary" | cut -c1-60)" >&2
        ((index++))
    done <<< "$tickets"
    
    echo "" >&2
    echo -e "${GREEN}0.${NC} ${YELLOW}Skip${NC} - Auto-detect from branch name" >&2
    echo "" >&2
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}" >&2
    
    read -p "Select ticket number (0-${#ticket_ids[@]}): " selection >&2
    
    if [[ "$selection" =~ ^[0-9]+$ ]]; then
        if [ "$selection" -eq 0 ]; then
            return 1  # Skip selection
        elif [ "$selection" -ge 1 ] && [ "$selection" -le "${#ticket_ids[@]}" ]; then
            echo "${ticket_ids[$((selection-1))]}"
            return 0
        fi
    fi
    
    echo -e "${RED}Invalid selection${NC}" >&2
    return 1
}

# Detect operating system
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            echo "macos"
            ;;
        Linux*)
            # Check if running in WSL
            if [ -f /proc/version ] && grep -qi microsoft /proc/version; then
                echo "windows"  # WSL - use Windows Credential Manager if available
            else
                echo "linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Store API key in macOS Keychain
store_key_macos() {
    local key_name="$1"
    local key_value="$2"
    security add-generic-password \
        -a "$USER" \
        -s "$key_name" \
        -w "$key_value" \
        -U \
        -T /usr/bin/security 2>/dev/null
}

# Retrieve API key from macOS Keychain
get_key_macos() {
    local key_name="$1"
    security find-generic-password -a "$USER" -s "$key_name" -w 2>/dev/null
}

# Store API key in Windows Credential Manager
store_key_windows() {
    local key_name="$1"
    local key_value="$2"
    local credential_name="git-jira-ai-${key_name}"
    
    # Use PowerShell to store in Windows Credential Manager (most reliable)
    if command -v powershell.exe &> /dev/null; then
        powershell.exe -NoProfile -Command "
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class CredentialManager {
                [DllImport(\"advapi32.dll\", CharSet = CharSet.Auto, SetLastError = true)]
                public static extern bool CredWrite(ref Credential credential, int flags);
                [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
                public struct Credential {
                    public int Flags;
                    public int Type;
                    public string TargetName;
                    public string Comment;
                    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
                    public int CredentialBlobSize;
                    public string CredentialBlob;
                    public int Persist;
                    public int AttributeCount;
                    public IntPtr Attributes;
                    public string TargetAlias;
                    public string UserName;
                }
            }
'@
            \$cred = New-Object CredentialManager+Credential
            \$cred.TargetName = \"$credential_name\"
            \$cred.UserName = \"api-key\"
            \$cred.CredentialBlob = \"$key_value\"
            \$cred.CredentialBlobSize = \$cred.CredentialBlob.Length
            \$cred.Type = 1  # Generic credential
            \$cred.Persist = 2  # LocalMachine persistence
            \$result = [CredentialManager]::CredWrite([ref]\$cred, 0)
            exit \$([int](\$result -eq \$false))
        " &>/dev/null
        return $?
    # Fallback to cmdkey (simpler but less secure)
    elif command -v cmdkey &> /dev/null; then
        # Delete existing if present
        cmdkey /delete:"$credential_name" &>/dev/null
        # Add new credential
        echo "$key_value" | cmdkey /add:"$credential_name" /user:"api-key" /pass:stdin &>/dev/null
        return $?
    fi
    
    return 1
}

# Retrieve API key from Windows Credential Manager
get_key_windows() {
    local key_name="$1"
    local credential_name="git-jira-ai-${key_name}"
    
    # Check if credential exists
    if command -v cmdkey &> /dev/null; then
        cmdkey /list:"$credential_name" 2>/dev/null | grep -q "$credential_name" || return 1
    fi
    
    # Try PowerShell to retrieve password
    # Note: This requires PowerShell and may need user interaction on first access
    if command -v powershell.exe &> /dev/null; then
        # Use Windows Credential Manager API via PowerShell
        local result=$(powershell.exe -NoProfile -Command "
            Add-Type -TypeDefinition @'
            using System;
            using System.Runtime.InteropServices;
            public class CredentialManager {
                [DllImport(\"advapi32.dll\", CharSet = CharSet.Auto, SetLastError = true)]
                public static extern bool CredRead(string target, int type, int reservedFlag, out IntPtr credentialPtr);
                [DllImport(\"advapi32.dll\", CharSet = CharSet.Auto, SetLastError = true)]
                public static extern bool CredFree(IntPtr credential);
                [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
                public struct Credential {
                    public int Flags;
                    public int Type;
                    public IntPtr TargetName;
                    public IntPtr Comment;
                    public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
                    public int CredentialBlobSize;
                    public IntPtr CredentialBlob;
                    public int Persist;
                    public int AttributeCount;
                    public IntPtr Attributes;
                    public IntPtr TargetAlias;
                    public IntPtr UserName;
                }
            }
'@
            \$ptr = New-Object IntPtr
            if ([CredentialManager]::CredRead(\"$credential_name\", 1, 0, [ref]\$ptr)) {
                \$cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure(\$ptr, [Type][CredentialManager+Credential])
                \$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(\$cred.CredentialBlob, \$cred.CredentialBlobSize)
                [CredentialManager]::CredFree(\$ptr)
                Write-Output \$password
            }
        " 2>/dev/null)
        
        if [ ! -z "$result" ] && [ "$result" != "null" ]; then
            echo "$result"
            return 0
        fi
    fi
    
    # Fallback: Try simple PowerShell approach (may not work without CredentialManager module)
    if command -v powershell.exe &> /dev/null; then
        local result=$(powershell.exe -NoProfile -Command "
            \$cred = Get-StoredCredential -Target '$credential_name' -ErrorAction SilentlyContinue
            if (\$cred) { \$cred.GetNetworkCredential().Password }
        " 2>/dev/null)
        
        if [ ! -z "$result" ] && [ "$result" != "null" ]; then
            echo "$result"
            return 0
        fi
    fi
    
    return 1
}

# Store API key in Linux Secret Service (libsecret)
store_key_linux() {
    local key_name="$1"
    local key_value="$2"
    
    if command -v secret-tool &> /dev/null; then
        echo "$key_value" | secret-tool store --label="git-jira-ai ${key_name}" api-key "$key_name" value "$key_value" 2>/dev/null
    fi
}

# Retrieve API key from Linux Secret Service
get_key_linux() {
    local key_name="$1"
    
    if command -v secret-tool &> /dev/null; then
        secret-tool lookup api-key "$key_name" 2>/dev/null
    else
        return 1
    fi
}

# Store API key using OS-specific method
store_api_key() {
    local key_name="$1"
    local key_value="$2"
    local os=$(detect_os)
    
    case "$os" in
        macos)
            store_key_macos "$key_name" "$key_value"
            ;;
        windows)
            store_key_windows "$key_name" "$key_value"
            ;;
        linux)
            store_key_linux "$key_name" "$key_value"
            ;;
        *)
            return 1
            ;;
    esac
}

# Retrieve API key using OS-specific method
get_api_key() {
    local key_name="$1"
    local os=$(detect_os)
    local value=""
    
    case "$os" in
        macos)
            value=$(get_key_macos "$key_name")
            ;;
        windows)
            value=$(get_key_windows "$key_name")
            if [ $? -ne 0 ] || [ -z "$value" ]; then
                # Windows Credential Manager retrieval is complex, fall back to .env
                return 1
            fi
            ;;
        linux)
            value=$(get_key_linux "$key_name")
            ;;
        *)
            return 1
            ;;
    esac
    
    if [ ! -z "$value" ]; then
        echo "$value"
        return 0
    fi
    
    return 1
}

# Load AI provider credentials from secure storage
load_ai_credentials() {
    local os=$(detect_os)
    
    # Try OS-specific secure storage first
    if [ -z "$CURSOR_API_KEY" ]; then
        CURSOR_API_KEY=$(get_api_key "CURSOR_API_KEY")
    fi
    
    if [ -z "$OPENAI_API_KEY" ]; then
        OPENAI_API_KEY=$(get_api_key "OPENAI_API_KEY")
    fi
    
    if [ -z "$ANTHROPIC_API_KEY" ]; then
        ANTHROPIC_API_KEY=$(get_api_key "ANTHROPIC_API_KEY")
    fi
    
    # Fallback to SOPS encrypted file if OS-specific storage fails
    if [ -f "$HOME/Documents/secrets/api-keys.yaml" ] && command -v sops &> /dev/null; then
        if [ -z "$CURSOR_API_KEY" ]; then
            CURSOR_API_KEY=$(sops --decrypt --extract '["CURSOR_API_KEY"]' "$HOME/Documents/secrets/api-keys.yaml" 2>/dev/null)
        fi
        if [ -z "$OPENAI_API_KEY" ]; then
            OPENAI_API_KEY=$(sops --decrypt --extract '["OPENAI_API_KEY"]' "$HOME/Documents/secrets/api-keys.yaml" 2>/dev/null)
        fi
        if [ -z "$ANTHROPIC_API_KEY" ]; then
            ANTHROPIC_API_KEY=$(sops --decrypt --extract '["ANTHROPIC_API_KEY"]' "$HOME/Documents/secrets/api-keys.yaml" 2>/dev/null)
        fi
    fi
    
    # Fallback to env file if both OS-specific and SOPS fail
    if [ -f "$HOME/.env.api-keys" ]; then
        # Source the file to load any keys not already set
        if [ -z "$CURSOR_API_KEY" ] || [ -z "$OPENAI_API_KEY" ] || [ -z "$ANTHROPIC_API_KEY" ]; then
            source "$HOME/.env.api-keys" 2>/dev/null
        fi
    fi
}

# Load Jira credentials from secure storage
load_jira_credentials() {
    local os=$(detect_os)
    
    # Try OS-specific secure storage first
    if [ -z "$JIRA_API_KEY" ]; then
        JIRA_API_KEY=$(get_api_key "JIRA_API_KEY")
    fi
    
    if [ -z "$JIRA_EMAIL" ]; then
        JIRA_EMAIL=$(get_api_key "JIRA_EMAIL")
    fi
    
    if [ -z "$JIRA_BASE_URL" ]; then
        JIRA_BASE_URL=$(get_api_key "JIRA_BASE_URL")
    fi
    
    # Fallback to SOPS encrypted file if OS-specific storage fails
    if [ -z "$JIRA_API_KEY" ] && [ -f "$HOME/Documents/secrets/api-keys.yaml" ] && command -v sops &> /dev/null; then
        JIRA_API_KEY=$(sops --decrypt --extract '["JIRA_API_KEY"]' "$HOME/Documents/secrets/api-keys.yaml" 2>/dev/null)
        JIRA_EMAIL=$(sops --decrypt --extract '["JIRA_EMAIL"]' "$HOME/Documents/secrets/api-keys.yaml" 2>/dev/null)
        JIRA_BASE_URL=$(sops --decrypt --extract '["JIRA_BASE_URL"]' "$HOME/Documents/secrets/api-keys.yaml" 2>/dev/null)
    fi
    
    # Fallback to env file if both OS-specific and SOPS fail
    if [ -z "$JIRA_API_KEY" ] && [ -f "$HOME/.env.api-keys" ]; then
        source "$HOME/.env.api-keys"
    fi
}

# Extract Jira ticket ID from branch name or commit message
extract_jira_ticket() {
    local branch_name=$(git branch --show-current)
    local commit_msg="$1"
    
    # Try to extract from branch name first (e.g., feature/PROJ-123-description or PROJ-123-description)
    local ticket_from_branch=$(echo "$branch_name" | grep -oE '[A-Z]{2,10}-[0-9]+' | head -1)
    
    if [ ! -z "$ticket_from_branch" ]; then
        echo "$ticket_from_branch"
        return 0
    fi
    
    # Try to extract from commit message (e.g., "feat: PROJ-123 add feature")
    local ticket_from_commit=$(echo "$commit_msg" | grep -oE '[A-Z]{2,10}-[0-9]+' | head -1)
    
    if [ ! -z "$ticket_from_commit" ]; then
        echo "$ticket_from_commit"
        return 0
    fi
    
    return 1
}

# Fetch Jira ticket details (for enhancing commit messages)
fetch_jira_ticket_details() {
    local ticket_id="$1"
    
    # Load credentials
    load_jira_credentials
    
    # Check if we have required credentials
    if [ -z "$JIRA_API_KEY" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_BASE_URL" ]; then
        return 1
    fi
    
    # Try API v3 first
    local response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}?fields=summary,description,issuetype,status" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    # Try API v2 if v3 fails
    if ! echo "$response" | "$JQ" -e '.fields' &>/dev/null 2>&1; then
        response=$(curl -s -X GET \
            "${JIRA_BASE_URL}/rest/api/2/issue/${ticket_id}?fields=summary,description,issuetype,status" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    fi
    
    # Check if request was successful
    if echo "$response" | "$JQ" -e '.fields' &>/dev/null 2>&1; then
        local summary=$(echo "$response" | "$JQ" -r '.fields.summary' 2>/dev/null)
        local description=$(echo "$response" | "$JQ" -r '.fields.description.content[0].content[0].text // .fields.description // "No description"' 2>/dev/null | head -c 500)
        local issue_type=$(echo "$response" | "$JQ" -r '.fields.issuetype.name' 2>/dev/null)
        local status=$(echo "$response" | "$JQ" -r '.fields.status.name' 2>/dev/null)
        
        # Return formatted ticket details
        echo "Ticket: $ticket_id - $summary"
        echo "Type: $issue_type | Status: $status"
        if [ ! -z "$description" ] && [ "$description" != "null" ] && [ "$description" != "No description" ]; then
            echo "Description: $description"
        fi
        return 0
    fi
    
    return 1
}

# Build commit URL from remote URL
build_commit_url() {
    local commit_sha="$1"
    local remote_url=$(git config --get remote.origin.url 2>/dev/null)
    
    if [ -z "$remote_url" ]; then
        return 1
    fi
    
    # Convert SSH to HTTPS format and extract repo info
    local repo_url=""
    
    # Handle SSH format: git@github.com:user/repo.git
    if [[ "$remote_url" =~ ^git@([^:]+):(.+)\.git$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        repo_url="https://${host}/${repo}"
    # Handle HTTPS format: https://github.com/user/repo.git
    elif [[ "$remote_url" =~ ^https://([^/]+)/(.+)\.git$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        repo_url="https://${host}/${repo}"
    # Handle HTTPS without .git
    elif [[ "$remote_url" =~ ^https://(.+)$ ]]; then
        repo_url="https://${BASH_REMATCH[1]}"
        repo_url="${repo_url%.git}"
    fi
    
    if [ -z "$repo_url" ]; then
        return 1
    fi
    
    # Detect platform and build commit URL
    if [[ "$repo_url" =~ github\.com ]]; then
        echo "${repo_url}/commit/${commit_sha}"
    elif [[ "$repo_url" =~ gitlab\.com ]] || [[ "$repo_url" =~ gitlab ]]; then
        echo "${repo_url}/-/commit/${commit_sha}"
    elif [[ "$repo_url" =~ bitbucket\.org ]]; then
        echo "${repo_url}/commits/${commit_sha}"
    elif [[ "$repo_url" =~ atlassian\.net ]]; then
        echo "${repo_url}/commits/${commit_sha}"
    else
        # Generic format (works for most Git hosting platforms)
        echo "${repo_url}/commit/${commit_sha}"
    fi
    
    return 0
}

# Generate JIRA comment with OpenAI
generate_jira_comment_with_openai() {
    local prompt="$1"
    local api_key="${OPENAI_API_KEY}"
    local model="${OPENAI_MODEL:-gpt-4.1-mini}"
    
    if [ -z "$api_key" ]; then
        return 1
    fi
    
    local response=$(curl -s -X POST https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "{
            \"model\": \"$model\",
            \"messages\": [
                {\"role\": \"system\", \"content\": \"You are a helpful senior developer writing informal updates to your team. Write naturally and conversationally, like you're explaining what you did to a colleague. Output ONLY the comment text itself - no meta-commentary or explanations about what you're writing.\"},
                {\"role\": \"user\", \"content\": $(echo "$prompt" | "$JQ" -Rs .)}
            ],
            \"temperature\": 0.7,
            \"max_tokens\": 2000
        }" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        return 1
    fi
    
    local comment=$(echo "$response" | "$JQ" -r '.choices[0].message.content' 2>/dev/null)
    
    if [ ! -z "$comment" ] && [ "$comment" != "null" ] && [ ${#comment} -gt 50 ]; then
        echo "$comment"
        return 0
    fi
    
    return 1
}

# Generate JIRA comment with Claude
generate_jira_comment_with_claude() {
    local prompt="$1"
    local api_key="${ANTHROPIC_API_KEY}"
    
    if [ -z "$api_key" ]; then
        return 1
    fi
    
    # Properly escape the prompt for JSON
    local prompt_json=$(echo "$prompt" | "$JQ" -Rs .)
    
    local response=$(curl -s https://api.anthropic.com/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"claude-3-5-sonnet-20241022\",
            \"max_tokens\": 2000,
            \"temperature\": 0.7,
            \"system\": \"You are a helpful senior developer writing informal updates to your team. Write naturally and conversationally, like you're explaining what you did to a colleague. Output ONLY the comment text itself - no meta-commentary or explanations about what you're writing.\",
            \"messages\": [
                {\"role\": \"user\", \"content\": $prompt_json}
            ]
        }" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        return 1
    fi
    
    local comment=$(echo "$response" | "$JQ" -r '.content[0].text' 2>/dev/null)
    
    if [ ! -z "$comment" ] && [ "$comment" != "null" ] && [ ${#comment} -gt 50 ]; then
        echo "$comment"
        return 0
    fi
    
    return 1
}

# Generate JIRA comment with Cursor CLI
generate_jira_comment_with_cursor() {
    local prompt="$1"
    
    # Find cursor-agent in common locations
    local cursor_agent_path=""
    if command -v cursor-agent &> /dev/null; then
        cursor_agent_path="cursor-agent"
    else
        # Check common installation paths
        local cursor_paths=(
            "$HOME/.local/bin/cursor-agent"
            "/usr/local/bin/cursor-agent"
            "$HOME/.cursor/bin/cursor-agent"
            "/opt/homebrew/bin/cursor-agent"
        )
        
        for path in "${cursor_paths[@]}"; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                cursor_agent_path="$path"
                break
            fi
        done
    fi
    
    if [ -z "$cursor_agent_path" ]; then
        return 1
    fi
    
    # Ensure CURSOR_API_KEY is loaded
    if [ -z "$CURSOR_API_KEY" ]; then
        CURSOR_API_KEY=$(security find-generic-password -a "$USER" -s "CURSOR_API_KEY" -w 2>/dev/null)
        # Also try SOPS if available
        if [ -z "$CURSOR_API_KEY" ] && [ -f "$HOME/Documents/secrets/api-keys.yaml" ] && command -v sops &> /dev/null; then
            CURSOR_API_KEY=$(sops --decrypt --extract '["CURSOR_API_KEY"]' "$HOME/Documents/secrets/api-keys.yaml" 2>/dev/null)
        fi
    fi
    
    # Export CURSOR_API_KEY so it's available to the subprocess
    if [ ! -z "$CURSOR_API_KEY" ]; then
        export CURSOR_API_KEY
    fi
    
    # Try cursor-agent - first without API key (in case authenticated via login), then with API key
    local response=""
    local exit_code=1
    
    # First, try without API key (might be authenticated via cursor-agent login)
    # Use --print flag for non-interactive output, prompt as argument
    response=$("$cursor_agent_path" --print "$prompt" 2>&1)
    exit_code=$?
    
    # If that failed and we have an API key, try with the API key
    if [ $exit_code -ne 0 ] && [ ! -z "$CURSOR_API_KEY" ]; then
        response=$(CURSOR_API_KEY="$CURSOR_API_KEY" "$cursor_agent_path" --print "$prompt" 2>&1)
        exit_code=$?
    fi
    
    # Check for authentication error
    if echo "$response" | grep -qi "authentication required\|login\|unauthorized\|401\|403"; then
        return 1
    fi
    
    # Check for other errors
    if [ $exit_code -ne 0 ]; then
        return 1
    fi
    
    # Check if we got a valid response
    if [ ! -z "$response" ] && [ ${#response} -gt 50 ]; then
        # Clean up the response (remove markdown code blocks if present)
        echo "$response" | sed 's/```[^`]*```//g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
        return 0
    fi
    
    return 1
}

# Clean AI response to remove meta-commentary (matching Python version exactly)
clean_ai_jira_response() {
    local text="$1"
    
    if [ -z "$text" ]; then
        echo "$text"
        return 0
    fi
    
    # List of meta-commentary patterns to detect (matching Python version)
    local meta_patterns=(
        "here's the comment"
        "here is the comment"
        "the comment is"
        "i've generated"
        "i've created"
        "i've written"
        "generated comment"
        "here's what i"
        "let me write"
    )
    
    # Check if the response starts with meta-commentary
    local lower_text=$(echo "$text" | tr '[:upper:]' '[:lower:]')
    local found_pattern=""
    
    for pattern in "${meta_patterns[@]}"; do
        if echo "$lower_text" | grep -q "^$pattern"; then
            found_pattern="$pattern"
            break
        fi
    done
    
    if [ ! -z "$found_pattern" ]; then
        # This is likely meta-commentary, try to find where actual comment starts
        echo -e "${YELLOW}⚠️  Detected meta-commentary in AI response, attempting to clean...${NC}" >&2
        
        # Try to find where the actual comment starts (matching Python logic)
        local actual_comment_lines=""
        local found_start=false
        
        # Read lines and look for typical comment starts
        while IFS= read -r line || [ -n "$line" ]; do
            local line_lower=$(echo "$line" | tr '[:upper:]' '[:lower:]' | xargs)
            if [ "$found_start" = false ]; then
                # Look for typical comment starts (matching Python: 'hey team', 'hi team', 'done with', 'just finished', 'completed')
                if echo "$line_lower" | grep -qE "(hey team|hi team|done with|just finished|completed)"; then
                    found_start=true
                    actual_comment_lines="${actual_comment_lines}${line}"$'\n'
                fi
            else
                actual_comment_lines="${actual_comment_lines}${line}"$'\n'
            fi
        done <<< "$text"
        
        if [ ! -z "$actual_comment_lines" ]; then
            # Remove trailing newline
            echo -n "${actual_comment_lines%$'\n'}"
            return 0
        fi
        
        # If we couldn't find a clear start, return original (matching Python behavior)
        echo -e "${YELLOW}⚠️  Could not identify actual comment, using original response${NC}" >&2
        echo "$text"
        return 0
    fi
    
    echo "$text"
    return 0
}

# Generate detailed Jira comment using AI
generate_jira_comment() {
    local commit_sha="$1"
    local commit_msg="$2"
    local diff_summary="$3"
    local ticket_details="$4"  # Optional: JIRA ticket details
    
    # Get commit URL
    local commit_url=$(build_commit_url "$commit_sha")
    local commit_link=""
    if [ ! -z "$commit_url" ]; then
        commit_link="[View Commit|${commit_url}]"
    fi
    
    # Get commit details
    local branch=$(git branch --show-current)
    local author=$(git config user.name)
    local email=$(git config user.email)
    local commit_date=$(git log -1 --pretty=format:'%ai' HEAD 2>/dev/null || date '+%Y-%m-%d %H:%M:%S')
    local files_changed=$(echo "$diff_summary" | grep -c '|' || echo "0")
    
    # Build natural, conversational prompt (matching Python version exactly)
    local prompt
    prompt=$(cat <<PROMPT_EOF
CRITICAL INSTRUCTION: Output ONLY the Jira comment text itself. Do NOT include any meta-commentary, explanations, or descriptions about what you're writing. Your output will be posted directly to Jira.

Write an informal Jira comment update from a developer who just completed a task. Write it like you're explaining what you did to your team lead or project manager - casual, conversational, but still professional.

CONTEXT:
- Commit: $commit_msg
- SHA: $commit_sha
- Branch: $branch
- Files changed: $files_changed
- Commit link: $commit_url
$(if [ ! -z "$ticket_details" ]; then echo "- Ticket context: $ticket_details"; fi)

CODE CHANGES:
$diff_summary

IMPORTANT STYLE GUIDELINES:
1. Write in FIRST PERSON ("I completed", "I fixed", "I updated") - like a developer writing their own update
2. Be CASUAL and CONVERSATIONAL - use contractions, natural language, avoid formal structure
3. Sound HUMAN - vary your sentence structure, use natural transitions
4. Be BRIEF but informative - don't over-explain
5. Use plain text formatting - NO markdown or fancy formatting
6. Include practical details that matter for testing
7. DON'T use section headers like "Summary:", "Issue:", etc. - just write naturally
8. Start with a brief statement like "Hey team, I've completed the [task name]" or "Done with [task]" or similar

REQUIRED CONTENT (but write it naturally, not as sections):
1. Brief intro saying you completed the task
2. What the issue/requirement was (in plain terms)
3. What you fixed/changed (technical but in layman terms - explain WHAT you did, not just HOW)
4. Link to commit
5. How to test it (practical steps)
6. Any additional notes (edge cases, things to watch, etc.)

EXAMPLE TONE (adapt to the actual commit):
"Hey team, just finished up the user authentication task.

The issue was that users were getting logged out randomly when switching between tabs. Turned out the session token wasn't being refreshed properly.

Here's what I fixed:
- Updated the token refresh logic to check expiry every 5 minutes instead of just on page load
- Added a background service that keeps the session alive as long as the user is active
- Fixed a race condition where multiple tabs could trigger conflicting refresh requests

Commit: $commit_url

To test this:
1. Log in to the app
2. Open it in multiple tabs
3. Leave it idle for 10-15 minutes, then try to do something (like click on a button)
4. You should stay logged in and everything should work normally
5. Also try switching between tabs rapidly - no weird logout behavior

Watch out for:
- The background service runs every 5 mins, so it might take a bit to see the effect
- If you're testing with a dev account, make sure the token expiry is set to something reasonable (not 1 year!)

Let me know if you see any issues!"

REMEMBER: Output ONLY the comment text. Start directly with something like "Hey team" or "Done with". Do NOT write things like "Here's the comment:" or "The comment is ready" or any other meta-text. Your output will be posted directly to Jira.
PROMPT_EOF
)

    local comment=""
    
    # Try OpenAI first
    if [ ! -z "$OPENAI_API_KEY" ]; then
        echo -e "${BLUE}🤖 Generating natural comment with OpenAI...${NC}" >&2
        comment=$(generate_jira_comment_with_openai "$prompt")
        if [ $? -eq 0 ] && [ ! -z "$comment" ]; then
            comment=$(clean_ai_jira_response "$comment")
            echo "$comment"
            return 0
        fi
    fi
    
    # Try Claude
    if [ ! -z "$ANTHROPIC_API_KEY" ]; then
        echo -e "${BLUE}🤖 Generating natural comment with Claude...${NC}" >&2
        comment=$(generate_jira_comment_with_claude "$prompt")
        if [ $? -eq 0 ] && [ ! -z "$comment" ]; then
            comment=$(clean_ai_jira_response "$comment")
            echo "$comment"
            return 0
        fi
    fi
    
    # Try Cursor CLI (cursor-agent)
    # Check if cursor-agent exists (either in PATH or common locations)
    local cursor_agent_found=false
    if command -v cursor-agent &> /dev/null; then
        cursor_agent_found=true
    else
        # Check common installation paths
        local cursor_paths=(
            "$HOME/.local/bin/cursor-agent"
            "/usr/local/bin/cursor-agent"
            "$HOME/.cursor/bin/cursor-agent"
            "/opt/homebrew/bin/cursor-agent"
        )
        
        for path in "${cursor_paths[@]}"; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                cursor_agent_found=true
                break
            fi
        done
    fi
    
    if [ "$cursor_agent_found" = true ]; then
        echo -e "${BLUE}🎨 Generating natural comment with Cursor AI...${NC}" >&2
        comment=$(generate_jira_comment_with_cursor "$prompt")
        if [ $? -eq 0 ] && [ ! -z "$comment" ]; then
            comment=$(clean_ai_jira_response "$comment")
            echo "$comment"
            return 0
        fi
    fi
    
    # Fallback to structured comment if AI fails (using markdown)
    echo -e "${YELLOW}⚠️  No AI available. Using fallback template...${NC}" >&2
    echo -e "${YELLOW}💡 Options for AI-powered comments:${NC}" >&2
    echo -e "  • Set OPENAI_API_KEY (uses your API credits)" >&2
    echo -e "  • Set ANTHROPIC_API_KEY (uses your API credits)" >&2
    if command -v cursor-agent &> /dev/null; then
        echo -e "  • Authenticate cursor-agent: cursor-agent login" >&2
        echo -e "    Or set: export CURSOR_API_KEY='your-key'" >&2
    else
        echo -e "  • Install Cursor CLI: curl https://cursor.com/install -fsS | bash" >&2
        echo -e "    Then run: cursor-agent login" >&2
    fi
    
    # Enhanced fallback template for testers and PMs - only include sections with available information
    local fallback_comment="## 🔗 Commit Information

${commit_link:-Commit: $commit_sha}
**Branch:** $branch | **Files Changed:** $files_changed | **Date:** $commit_date | **Author:** $author

## 📋 Summary

$commit_msg

## 📁 Areas Affected

$diff_summary
"
    
    # Only add sections if we have ticket details
    if [ ! -z "$ticket_details" ]; then
        fallback_comment="${fallback_comment}
## 🔍 What Was the Issue?

See JIRA ticket for issue details.

"
    fi
    
    fallback_comment="${fallback_comment}## 🧪 How to Test

1. Pull the latest changes from branch: \`$branch\`
2. Review the areas affected above
3. Test the features related to the changes
4. Verify the application works as expected
5. Check that existing functionality still works correctly

## ⚠️ What to Watch For

- Review the changes above to determine specific impacts
- Verify any configuration or dependency changes
- Test related functionality thoroughly
- Watch for any user-facing changes or impacts
"
    
    echo "$fallback_comment"
    
    return 0
}

# Convert plain text to ADF (Atlassian Document Format)
# Simple helper function to convert text to ADF content array (no markdown parsing)
parse_text_to_adf_content() {
    local text="$1"
    # Strip any markdown markers that might have been generated
    # Use parameter expansion and tr to remove * characters (more reliable than sed with special chars)
    local clean_text="$text"
    # Remove ** markers first (double asterisks)
    clean_text="${clean_text//\*\*/}"
    # Remove any remaining single * markers
    clean_text="${clean_text//\*/}"
    # Remove markdown links [text](url) -> text (using sed for regex)
    clean_text=$(echo "$clean_text" | sed 's/\[\([^]]*\)\]([^)]*)/\1/g')
    # Convert to ADF text node
    local escaped_text=$(echo "$clean_text" | "$JQ" -Rs .)
    if [ -z "$escaped_text" ] || [ "$escaped_text" = "null" ]; then
        # Fallback: manually escape
        escaped_text="\"$clean_text\""
    fi
    echo "[{\"type\": \"text\", \"text\": $escaped_text}]"
}

convert_to_adf() {
    local text="$1"
    
    # For now, use a simpler approach: wrap in a panel for better visual appeal
    # and split into paragraphs, preserving headings and lists
    
    local adf_content='[]'
    local in_list=false
    local list_items='[]'
    
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip completely empty lines
        if [ -z "$(echo "$line" | tr -d '[:space:]')" ]; then
            # If we were in a list, close it
            if [ "$in_list" = true ]; then
                adf_content=$(echo "$adf_content" | "$JQ" \
                    --argjson items "$list_items" \
                    '. += [{"type": "bulletList", "content": $items}]')
                list_items='[]'
                in_list=false
            fi
            continue
        fi
        
        # Handle headings (## Title or ### Title)
        if [[ "$line" =~ ^###+[[:space:]](.+)$ ]] || [[ "$line" =~ ^##[[:space:]](.+)$ ]]; then
            # Close any open list
            if [ "$in_list" = true ]; then
                adf_content=$(echo "$adf_content" | "$JQ" \
                    --argjson items "$list_items" \
                    '. += [{"type": "bulletList", "content": $items}]')
                list_items='[]'
                in_list=false
            fi
            
            local heading_text="${BASH_REMATCH[1]}"
            local heading_content=$(parse_text_to_adf_content "$heading_text")
            adf_content=$(echo "$adf_content" | "$JQ" \
                --argjson content "$heading_content" \
                '. += [{
                    "type": "heading",
                    "attrs": {"level": 2},
                    "content": $content
                }]')
        # Handle bullet list items (- item or * item)
        elif [[ "$line" =~ ^[[:space:]]*[-*][[:space:]](.+)$ ]]; then
            local item_text="${BASH_REMATCH[1]}"
            local item_content=$(parse_text_to_adf_content "$item_text")
            list_items=$(echo "$list_items" | "$JQ" \
                --argjson content "$item_content" \
                '. += [{
                    "type": "listItem",
                    "content": [{
                        "type": "paragraph",
                        "content": $content
                    }]
                }]')
            in_list=true
        # Handle numbered list items (1. item)
        elif [[ "$line" =~ ^[[:space:]]*[0-9]+\.[[:space:]](.+)$ ]]; then
            # Close bullet list if open
            if [ "$in_list" = true ]; then
                adf_content=$(echo "$adf_content" | "$JQ" \
                    --argjson items "$list_items" \
                    '. += [{"type": "bulletList", "content": $items}]')
                list_items='[]'
                in_list=false
            fi
            
            local item_text="${BASH_REMATCH[1]}"
            local item_content=$(parse_text_to_adf_content "$item_text")
            # Add as a paragraph for now (ADF ordered lists are complex)
            # Prepend bullet to content array
            local merged_content=$(echo "$item_content" | "$JQ" '. = [{"type": "text", "text": "• "}] + .')
            adf_content=$(echo "$adf_content" | "$JQ" \
                --argjson content "$merged_content" \
                '. += [{
                    "type": "paragraph",
                    "content": $content
                }]')
        # Regular paragraph
        else
            # Close any open list
            if [ "$in_list" = true ]; then
                adf_content=$(echo "$adf_content" | "$JQ" \
                    --argjson items "$list_items" \
                    '. += [{"type": "bulletList", "content": $items}]')
                list_items='[]'
                in_list=false
            fi
            
            local para_content=$(parse_text_to_adf_content "$line")
            adf_content=$(echo "$adf_content" | "$JQ" \
                --argjson content "$para_content" \
                '. += [{
                    "type": "paragraph",
                    "content": $content
                }]')
        fi
    done <<< "$text"
    
    # Close any remaining list
    if [ "$in_list" = true ]; then
        adf_content=$(echo "$adf_content" | "$JQ" \
            --argjson items "$list_items" \
            '. += [{"type": "bulletList", "content": $items}]')
    fi
    
    # Return ADF document
    "$JQ" -n --argjson content "$adf_content" \
        '{
            type: "doc",
            version: 1,
            content: $content
        }'
}

# Post comment to Jira ticket
post_jira_comment() {
    local ticket_id="$1"
    local comment="$2"
    
    # Load credentials
    load_jira_credentials
    
    # Check if we have required credentials
    if [ -z "$JIRA_API_KEY" ] || [ -z "$JIRA_EMAIL" ] || [ -z "$JIRA_BASE_URL" ]; then
        echo -e "${YELLOW}⚠️  Jira credentials not configured. Skipping Jira update.${NC}" >&2
        echo -e "${BLUE}💡 To enable Jira updates, store credentials using:${NC}" >&2
        echo "   security add-generic-password -a \"\$USER\" -s \"JIRA_API_KEY\" -w \"your-api-key\"" >&2
        echo "   security add-generic-password -a \"\$USER\" -s \"JIRA_EMAIL\" -w \"your-email\"" >&2
        echo "   security add-generic-password -a \"\$USER\" -s \"JIRA_BASE_URL\" -w \"https://your-domain.atlassian.net\"" >&2
        return 1
    fi
    
    echo -e "${BLUE}📝 Updating Jira ticket $ticket_id...${NC}" >&2
    
    # Convert comment to ADF format
    local adf_body=$(convert_to_adf "$comment" 2>&1)
    local convert_status=$?
    
    # Validate ADF body
    if [ $convert_status -ne 0 ] || [ -z "$adf_body" ]; then
        echo -e "${RED}Error: Failed to convert comment to ADF format${NC}" >&2
        echo -e "${YELLOW}Debug output: ${adf_body:0:500}${NC}" >&2
        return 1
    fi
    
    # Validate JSON structure
    if ! echo "$adf_body" | "$JQ" empty 2>/dev/null; then
        echo -e "${RED}Error: ADF conversion produced invalid JSON${NC}" >&2
        echo -e "${YELLOW}Debug - ADF body (first 500 chars): ${adf_body:0:500}${NC}" >&2
        return 1
    fi
    
    # Check if ADF body has content
    local content_count=$(echo "$adf_body" | "$JQ" '.content | length' 2>/dev/null || echo "0")
    if [ "$content_count" -eq 0 ]; then
        echo -e "${RED}Error: ADF body has no content${NC}" >&2
        echo -e "${YELLOW}Debug - Full ADF body: $adf_body${NC}" >&2
        return 1
    fi
    
    # Prepare JSON payload
    local json_payload=$("$JQ" -n \
        --argjson body "$adf_body" \
        '{body: $body}' 2>&1)
    
    if [ $? -ne 0 ] || [ -z "$json_payload" ] || ! echo "$json_payload" | "$JQ" empty 2>/dev/null; then
        echo -e "${RED}Error: Failed to create JSON payload${NC}" >&2
        echo -e "${YELLOW}Debug - Payload error: $json_payload${NC}" >&2
        return 1
    fi
    
    # Post comment to Jira
    local response=$(curl -s -X POST \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}/comment" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" \
        -d "$json_payload" 2>&1)
    
    # Check if the request was successful
    if echo "$response" | "$JQ" -e '.id' &>/dev/null; then
        echo -e "${GREEN}✓ Jira ticket $ticket_id updated successfully${NC}" >&2
        local comment_url="${JIRA_BASE_URL}/browse/${ticket_id}"
        echo -e "${BLUE}🔗 View ticket: ${comment_url}${NC}" >&2
        return 0
    else
        echo -e "${YELLOW}⚠️  Failed to update Jira ticket${NC}" >&2
        if echo "$response" | grep -qi "unauthorized\|authentication\|401"; then
            echo -e "${RED}Authentication failed. Check your JIRA_API_KEY and JIRA_EMAIL${NC}" >&2
        elif echo "$response" | grep -qi "not found\|404"; then
            echo -e "${RED}Ticket $ticket_id not found${NC}" >&2
        else
            echo -e "${YELLOW}Response: $(echo "$response" | head -c 200)${NC}" >&2
        fi
        return 1
    fi
}

# Update Jira custom field (timetracking fields)
update_jira_timetracking() {
    local ticket_id="$1"
    local field_name="$2"
    local value="$3"
    
    # Load credentials
    load_jira_credentials
    
    # Format time value for Jira (e.g., "2h", "3.5h")
    # Check if value has decimal
    if [[ "$value" == *.* ]]; then
        # Has decimal - keep it
        local time_value="${value}h"
    else
        # No decimal - add as integer
        local time_value="${value}h"
    fi
    
    # Prepare JSON payload based on field name
    local json_payload=""
    if [ "$field_name" = "originalEstimate" ]; then
        json_payload=$("$JQ" -n \
            --arg time "$time_value" \
            '{fields: {timetracking: {originalEstimate: $time}}}')
    elif [ "$field_name" = "remainingEstimate" ]; then
        json_payload=$("$JQ" -n \
            --arg time "$time_value" \
            '{fields: {timetracking: {remainingEstimate: $time}}}')
    else
        echo -e "${RED}Unknown timetracking field: $field_name${NC}" >&2
        return 1
    fi
    
    # Debug: show payload
    # echo -e "${BLUE}Debug - Payload: $json_payload${NC}" >&2
    
    # Update field in Jira
    local http_code=$(curl -s -w "%{http_code}" -o /tmp/jira_response_$$.txt -X PUT \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" \
        -d "$json_payload")
    
    local response=$(cat /tmp/jira_response_$$.txt)
    rm -f /tmp/jira_response_$$.txt
    
    # Check HTTP status code (204 = success with no content)
    if [ "$http_code" = "204" ] || [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✓ Updated $field_name: ${value} hours${NC}" >&2
        return 0
    else
        echo -e "${YELLOW}⚠️  Failed to update $field_name (HTTP $http_code)${NC}" >&2
        if [ ! -z "$response" ]; then
            echo -e "${YELLOW}Response: $(echo "$response" | head -c 200)${NC}" >&2
        fi
        return 1
    fi
}

# Update Jira custom field by custom field ID
update_jira_custom_field() {
    local ticket_id="$1"
    local field_id="$2"
    local value="$3"
    
    # Load credentials
    load_jira_credentials
    
    # Prepare JSON payload - check if value is numeric
    local json_payload=""
    if [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        # Numeric value - pass as number
        json_payload=$("$JQ" -n \
            --arg fieldId "$field_id" \
            --argjson value "$value" \
            '{fields: {($fieldId): $value}}')
    else
        # String value
        json_payload=$("$JQ" -n \
            --arg fieldId "$field_id" \
            --arg value "$value" \
            '{fields: {($fieldId): $value}}')
    fi
    
    # Update field in Jira
    local response=$(curl -s -X PUT \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" \
        -d "$json_payload" 2>&1)
    
    # Check if the request was successful
    if [ $? -eq 0 ] && ([ -z "$response" ] || echo "$response" | "$JQ" -e 'has("errorMessages") | not' &>/dev/null); then
        echo -e "${GREEN}✓ Updated custom field $field_id: ${value}${NC}" >&2
        return 0
    else
        echo -e "${YELLOW}⚠️  Failed to update custom field${NC}" >&2
        echo -e "${YELLOW}Response: $(echo "$response" | head -c 200)${NC}" >&2
        return 1
    fi
}

# Get available transitions for a ticket
get_jira_transitions() {
    local ticket_id="$1"
    
    # Load credentials
    load_jira_credentials
    
    # Get transitions
    local response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}/transitions" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    # Check if the request was successful
    if echo "$response" | "$JQ" -e '.transitions' &>/dev/null; then
        echo "$response"
        return 0
    else
        echo -e "${YELLOW}⚠️  Failed to get transitions${NC}" >&2
        return 1
    fi
}

# Transition Jira ticket to new status
transition_jira_ticket() {
    local ticket_id="$1"
    local transition_id="$2"
    
    # Load credentials
    load_jira_credentials
    
    # Prepare JSON payload
    local json_payload=$("$JQ" -n \
        --arg transitionId "$transition_id" \
        '{transition: {id: $transitionId}}')
    
    # Transition ticket
    local response=$(curl -s -X POST \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}/transitions" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" \
        -d "$json_payload" 2>&1)
    
    # Check if the request was successful (POST returns 204 on success with no body)
    if [ $? -eq 0 ] && ([ -z "$response" ] || echo "$response" | "$JQ" -e 'has("errorMessages") | not' &>/dev/null); then
        echo -e "${GREEN}✓ Ticket status updated${NC}" >&2
        return 0
    else
        echo -e "${YELLOW}⚠️  Failed to transition ticket${NC}" >&2
        echo -e "${YELLOW}Response: $(echo "$response" | head -c 200)${NC}" >&2
        return 1
    fi
}

# Get list of assignable users for a ticket
get_jira_assignable_users() {
    local ticket_id="$1"
    
    # Load credentials
    load_jira_credentials
    
    # Get assignable users
    local response=$(curl -s -X GET \
        "${JIRA_BASE_URL}/rest/api/3/user/assignable/search?issueKey=${ticket_id}&maxResults=50" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" 2>&1)
    
    if echo "$response" | "$JQ" -e '. | length > 0' &>/dev/null; then
        echo "$response"
        return 0
    else
        return 1
    fi
}

# Assign ticket to user
assign_jira_ticket() {
    local ticket_id="$1"
    local account_id="$2"
    
    # Load credentials
    load_jira_credentials
    
    # Prepare JSON payload
    local json_payload=$("$JQ" -n \
        --arg accountId "$account_id" \
        '{accountId: $accountId}')
    
    # Assign ticket
    local response=$(curl -s -X PUT \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}/assignee" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" \
        -d "$json_payload" 2>&1)
    
    # Check if the request was successful
    if [ $? -eq 0 ] && ([ -z "$response" ] || echo "$response" | "$JQ" -e 'has("errorMessages") | not' &>/dev/null); then
        return 0
    else
        echo -e "${YELLOW}Response: $(echo "$response" | head -c 200)${NC}" >&2
        return 1
    fi
}

# Add comment with user mentions
add_jira_comment_with_mentions() {
    local ticket_id="$1"
    local user_ids="$2"  # Comma-separated account IDs
    
    # Load credentials
    load_jira_credentials
    
    # Build mention text
    local mention_text="FYI: "
    local mention_nodes='[]'
    
    # Split user_ids by comma and build ADF mention nodes
    IFS=',' read -ra USER_ARRAY <<< "$user_ids"
    for user_id in "${USER_ARRAY[@]}"; do
        user_id=$(echo "$user_id" | xargs)  # trim whitespace
        if [ ! -z "$user_id" ]; then
            # Add mention node to array
            mention_nodes=$(echo "$mention_nodes" | "$JQ" --arg id "$user_id" \
                '. += [{type: "mention", attrs: {id: $id}}]')
            # Add space after each mention
            mention_nodes=$(echo "$mention_nodes" | "$JQ" '. += [{type: "text", text: " "}]')
        fi
    done
    
    # Build ADF comment body
    local adf_body=$("$JQ" -n \
        --argjson mentions "$mention_nodes" \
        '{
            version: 1,
            type: "doc",
            content: [
                {
                    type: "paragraph",
                    content: ([{type: "text", text: "FYI: "}] + $mentions)
                }
            ]
        }')
    
    # Prepare JSON payload
    local json_payload=$("$JQ" -n \
        --argjson body "$adf_body" \
        '{body: $body}')
    
    # Post comment to Jira
    local response=$(curl -s -X POST \
        "${JIRA_BASE_URL}/rest/api/3/issue/${ticket_id}/comment" \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}" \
        -d "$json_payload" 2>&1)
    
    # Check if the request was successful
    if echo "$response" | "$JQ" -e '.id' &>/dev/null; then
        return 0
    else
        echo -e "${YELLOW}Response: $(echo "$response" | head -c 200)${NC}" >&2
        return 1
    fi
}

# Prompt for additional Jira updates after comment is posted
prompt_additional_jira_updates() {
    local ticket_id="$1"
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📊 Additional Jira Updates${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Prompt for Original Estimate (custom field in your Jira)
    echo -e "${YELLOW}Update Original Estimate (hrs)?${NC}"
    printf "Enter value in hours (or press Enter to skip): "
    read original_estimate
    original_estimate=$(echo "$original_estimate" | xargs)
    
    # Check if it's a valid number
    if [[ "$original_estimate" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "${BLUE}📝 Updating Original Estimate...${NC}"
        # Custom field ID for "Original Estimate (hrs)"
        # To find: gq jira find-field "original estimate"
        local original_estimate_field_id="${JIRA_ORIGINAL_ESTIMATE_FIELD_ID:-customfield_10633}"
        update_jira_custom_field "$ticket_id" "$original_estimate_field_id" "$original_estimate"
    elif [ ! -z "$original_estimate" ]; then
        echo -e "${YELLOW}⚠️  Invalid value. Skipping Original Estimate update.${NC}"
    else
        echo -e "${BLUE}ℹ️  Skipping Original Estimate update${NC}"
    fi
    
    echo ""
    
    # Prompt for Actual Dev Efforts (custom field)
    echo -e "${YELLOW}Update Actual Dev Efforts (hrs)?${NC}"
    printf "Enter value in hours (or press Enter to skip): "
    read actual_dev_efforts
    actual_dev_efforts=$(echo "$actual_dev_efforts" | xargs)
    
    # Check if it's a valid number
    if [[ "$actual_dev_efforts" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        echo -e "${BLUE}📝 Updating Actual Dev Efforts...${NC}"
        # Custom field ID for "Actual Dev Efforts (hrs)"
        # To find custom field IDs: gq jira find-field "field name"
        local actual_dev_field_id="${JIRA_ACTUAL_DEV_FIELD_ID:-customfield_10634}"
        update_jira_custom_field "$ticket_id" "$actual_dev_field_id" "$actual_dev_efforts"
    elif [ ! -z "$actual_dev_efforts" ]; then
        echo -e "${YELLOW}⚠️  Invalid value. Skipping Actual Dev Efforts update.${NC}"
    else
        echo -e "${BLUE}ℹ️  Skipping Actual Dev Efforts update${NC}"
    fi
    
    echo ""
    
    # Prompt for status transition
    echo -e "${YELLOW}Update ticket status?${NC}"
    printf "Check available statuses? (Y/n): "
    read check_status
    check_status=$(echo "$check_status" | tr '[:upper:]' '[:lower:]' | xargs)
    
    if [ "$check_status" != "n" ] && [ "$check_status" != "no" ]; then
        echo -e "${BLUE}📋 Fetching available transitions...${NC}"
        local transitions=$(get_jira_transitions "$ticket_id")
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${BLUE}Available status transitions:${NC}"
            echo "$transitions" | "$JQ" -r '.transitions[] | "\(.id): \(.name) → \(.to.name)"' | nl -w2 -s'. '
            echo ""
            
            printf "Enter transition number (or press Enter to skip): "
            read transition_choice
            transition_choice=$(echo "$transition_choice" | xargs)
            
            if [[ "$transition_choice" =~ ^[0-9]+$ ]]; then
                # Get the transition ID for the chosen option
                local transition_id=$(echo "$transitions" | "$JQ" -r ".transitions[$((transition_choice - 1))].id")
                local transition_name=$(echo "$transitions" | "$JQ" -r ".transitions[$((transition_choice - 1))].name")
                
                if [ ! -z "$transition_id" ] && [ "$transition_id" != "null" ]; then
                    echo -e "${BLUE}📝 Transitioning ticket to: $transition_name${NC}"
                    transition_jira_ticket "$ticket_id" "$transition_id"
                else
                    echo -e "${YELLOW}⚠️  Invalid transition choice${NC}"
                fi
            elif [ ! -z "$transition_choice" ]; then
                echo -e "${YELLOW}⚠️  Invalid choice. Skipping status update.${NC}"
            else
                echo -e "${BLUE}ℹ️  Skipping status update${NC}"
            fi
        fi
    else
        echo -e "${BLUE}ℹ️  Skipping status update${NC}"
    fi
    
    echo ""
    
    # Prompt for assignee change
    echo -e "${YELLOW}Change ticket assignee?${NC}"
    printf "Select assignee? (Y/n): "
    read change_assignee
    change_assignee=$(echo "$change_assignee" | tr '[:upper:]' '[:lower:]' | xargs)
    
    if [ "$change_assignee" != "n" ] && [ "$change_assignee" != "no" ]; then
        echo -e "${BLUE}📋 Fetching assignable users...${NC}"
        local users=$(get_jira_assignable_users "$ticket_id")
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${BLUE}Assignable users:${NC}"
            echo "$users" | "$JQ" -r 'to_entries[] | "\(.key + 1). \(.value.displayName) (\(.value.emailAddress // "no email"))"'
            echo ""
            
            printf "Enter user number (or press Enter to skip): "
            read user_choice
            user_choice=$(echo "$user_choice" | xargs)
            
            if [[ "$user_choice" =~ ^[0-9]+$ ]]; then
                # Get the account ID for the chosen user
                local account_id=$(echo "$users" | "$JQ" -r ".[$((user_choice - 1))].accountId")
                local user_name=$(echo "$users" | "$JQ" -r ".[$((user_choice - 1))].displayName")
                
                if [ ! -z "$account_id" ] && [ "$account_id" != "null" ]; then
                    echo -e "${BLUE}📝 Assigning ticket to: $user_name${NC}"
                    if assign_jira_ticket "$ticket_id" "$account_id"; then
                        echo -e "${GREEN}✓ Ticket assigned to $user_name${NC}"
                    else
                        echo -e "${YELLOW}⚠️  Failed to assign ticket${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠️  Invalid user choice${NC}"
                fi
            elif [ ! -z "$user_choice" ]; then
                echo -e "${YELLOW}⚠️  Invalid choice. Skipping assignee change.${NC}"
            else
                echo -e "${BLUE}ℹ️  Skipping assignee change${NC}"
            fi
        fi
    else
        echo -e "${BLUE}ℹ️  Skipping assignee change${NC}"
    fi
    
    echo ""
    
    # Prompt for tagging users
    echo -e "${YELLOW}Tag users in a comment?${NC}"
    printf "Tag users? (Y/n): "
    read tag_users
    tag_users=$(echo "$tag_users" | tr '[:upper:]' '[:lower:]' | xargs)
    
    if [ "$tag_users" != "n" ] && [ "$tag_users" != "no" ]; then
        echo -e "${BLUE}📋 Fetching assignable users...${NC}"
        local users=$(get_jira_assignable_users "$ticket_id")
        
        if [ $? -eq 0 ]; then
            echo ""
            echo -e "${BLUE}Available users:${NC}"
            echo "$users" | "$JQ" -r 'to_entries[] | "\(.key + 1). \(.value.displayName) (\(.value.emailAddress // "no email"))"'
            echo ""
            echo -e "${YELLOW}💡 Enter multiple numbers separated by commas (e.g., 1,3,5)${NC}"
            
            printf "Enter user number(s) (or press Enter to skip): "
            read user_choices
            user_choices=$(echo "$user_choices" | xargs)
            
            if [ ! -z "$user_choices" ]; then
                # Parse user choices (comma-separated)
                local account_ids=""
                local user_names=""
                
                IFS=',' read -ra CHOICE_ARRAY <<< "$user_choices"
                for choice in "${CHOICE_ARRAY[@]}"; do
                    choice=$(echo "$choice" | xargs)  # trim whitespace
                    
                    if [[ "$choice" =~ ^[0-9]+$ ]]; then
                        local account_id=$(echo "$users" | "$JQ" -r ".[$((choice - 1))].accountId")
                        local user_name=$(echo "$users" | "$JQ" -r ".[$((choice - 1))].displayName")
                        
                        if [ ! -z "$account_id" ] && [ "$account_id" != "null" ]; then
                            if [ -z "$account_ids" ]; then
                                account_ids="$account_id"
                                user_names="$user_name"
                            else
                                account_ids="$account_ids,$account_id"
                                user_names="$user_names, $user_name"
                            fi
                        fi
                    fi
                done
                
                if [ ! -z "$account_ids" ]; then
                    echo -e "${BLUE}📝 Tagging users: $user_names${NC}"
                    if add_jira_comment_with_mentions "$ticket_id" "$account_ids"; then
                        echo -e "${GREEN}✓ Users tagged: $user_names${NC}"
                    else
                        echo -e "${YELLOW}⚠️  Failed to tag users${NC}"
                    fi
                else
                    echo -e "${YELLOW}⚠️  No valid users selected${NC}"
                fi
            else
                echo -e "${BLUE}ℹ️  Skipping user tagging${NC}"
            fi
        fi
    else
        echo -e "${BLUE}ℹ️  Skipping user tagging${NC}"
    fi
    
    echo ""
    echo -e "${GREEN}✓ All updates completed${NC}"
}

# Update Jira ticket after successful commit (only on push)
update_jira_after_commit() {
    local commit_msg="$1"
    
    # Only update Jira when pushing (git-aip or git-ps)
    if [ "$WILL_PUSH" != "true" ]; then
        return 0
    fi
    
    # Push changes to remote first
    if ! push_to_remote; then
        echo -e "${YELLOW}⚠️  Skipping Jira update due to push failure${NC}"
        return 1
    fi
    
    local ticket_id=""
    
    # Priority 1: Use ticket ID from parameter
    if [ ! -z "$TICKET_ID_PARAM" ]; then
        ticket_id="$TICKET_ID_PARAM"
    # Priority 2: Use auto-detected ticket ID from branch name (JIRA_TICKET_ID)
    elif [ ! -z "$JIRA_TICKET_ID" ]; then
        ticket_id="$JIRA_TICKET_ID"
    else
        # No ticket ID found - prompt user
        echo ""
        echo -e "${GREEN}✓ Pushing completed${NC}"
        echo -e "${YELLOW}Want to update Jira?${NC}"
        printf "If yes, enter ticket ID (or press Enter to skip): "
        read user_ticket_id
        user_ticket_id=$(echo "$user_ticket_id" | xargs)
        
        # If user pressed Enter without entering anything, skip Jira update
        if [ -z "$user_ticket_id" ]; then
            echo -e "${BLUE}ℹ️  Skipping Jira update${NC}"
            return 0
        fi
        
        # Use the ticket ID entered by user
        ticket_id="$user_ticket_id"
    fi
    
    if [ -z "$ticket_id" ]; then
        return 0
    fi
    
    echo ""
    echo -e "${BLUE}🎫 Updating Jira ticket: $ticket_id${NC}"
    
    # Ask if user wants to update Jira
    echo -e "${YELLOW}Add commit details as comment to Jira ticket?${NC}"
    printf "Update Jira ticket? (Y/n): "
    read update_jira
    update_jira=$(echo "$update_jira" | tr '[:upper:]' '[:lower:]' | xargs)
    
    # Default to yes if empty or 'y'
    if [ "$update_jira" = "n" ] || [ "$update_jira" = "no" ]; then
        echo -e "${BLUE}ℹ️  Skipping Jira update${NC}"
        return 0
    fi
    
    # Get the latest commit SHA and details
    local commit_sha=$(git rev-parse --short HEAD)
    local commit_author=$(git log -1 --pretty=format:'%an')
    local commit_date=$(git log -1 --pretty=format:'%ai')
    
    # Get a summary of changes (files changed and stats)
    local diff_summary=$(git show --stat --pretty="" HEAD | head -20)
    
    # Get ticket details (use already fetched if available, otherwise fetch now)
    local ticket_details=""
    if [ ! -z "$ticket_id" ]; then
        # Check if we already have JIRA_DETAILS for this ticket
        if [ ! -z "$JIRA_DETAILS" ] && echo "$JIRA_DETAILS" | grep -q "$ticket_id"; then
            ticket_details="$JIRA_DETAILS"
            echo -e "${GREEN}✓ Using previously fetched ticket details${NC}"
        else
            # Fetch ticket details now
            echo -e "${BLUE}📋 Fetching ticket details from Jira...${NC}"
            ticket_details=$(fetch_jira_ticket_details "$ticket_id" 2>/dev/null)
            if [ $? -eq 0 ] && [ ! -z "$ticket_details" ]; then
                echo -e "${GREEN}✓ Loaded ticket context${NC}"
            else
                echo -e "${YELLOW}⚠️  Could not fetch ticket details from Jira${NC}"
            fi
        fi
    fi
    
    # Generate detailed comment
    echo -e "${BLUE}🤖 Generating detailed Jira comment with AI...${NC}"
    local jira_comment=$(generate_jira_comment "$commit_sha" "$commit_msg" "$diff_summary" "$ticket_details")
    
    if [ -z "$jira_comment" ]; then
        echo -e "${RED}Failed to generate Jira comment${NC}"
        return 1
    fi
    
    # Show preview
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📝 Preview of Jira Comment:${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "$jira_comment"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Ask for confirmation to post
    read -p "Post this comment to Jira $ticket_id? (Y/n): " confirm_post
    confirm_post=$(echo "$confirm_post" | tr '[:upper:]' '[:lower:]' | xargs)
    
    # Default to yes if empty or 'y'
    if [ "$confirm_post" = "n" ] || [ "$confirm_post" = "no" ]; then
        echo -e "${YELLOW}❌ Jira update cancelled${NC}"
        return 0
    fi
    
    # Post to Jira
    if post_jira_comment "$ticket_id" "$jira_comment"; then
        # After successfully posting comment, prompt for additional updates
        prompt_additional_jira_updates "$ticket_id"
    fi
}

# ============================================================================
# END JIRA INTEGRATION
# ============================================================================

# ============================================================================
# HANDLE PUSH-ONLY MODE (for gq push command)
# ============================================================================
if [ "$PUSH_ONLY" = "true" ]; then
    # Load AI provider credentials from secure storage
    load_ai_credentials
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}📤 Push Only Mode${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Push first
    if ! push_to_remote; then
        echo -e "${RED}✗ Push failed${NC}"
        exit 1
    fi
    
    # Then update Jira with the latest commit info
    local commit_msg=$(git log -1 --pretty=%B)
    update_jira_after_commit "$commit_msg"
    exit 0
fi

# ============================================================================
# NORMAL COMMIT FLOW
# ============================================================================

# Load AI provider credentials from secure storage
load_ai_credentials

# Sync before committing
sync_with_remote

# Check if there are staged changes
if git diff --cached --quiet; then
    echo -e "${YELLOW}No staged changes found. Staging all changes...${NC}"
    git add -A
    if git diff --cached --quiet; then
        echo -e "${RED}No changes to commit${NC}"
        exit 1
    fi
fi

# Get the git diff
DIFF=$(git diff --cached)

if [ -z "$DIFF" ]; then
    echo -e "${RED}No changes detected${NC}"
    exit 1
fi

# Try to fetch Jira ticket details for better commit messages
JIRA_CONTEXT=""
JIRA_TICKET_ID=""

# Check if ticket ID was passed as argument
if [ -z "$TICKET_ID_PARAM" ]; then
    # No ticket ID passed - try to extract from branch name
    echo -e "${BLUE}🔍 No ticket ID provided, checking branch name...${NC}"
    EXTRACTED_TICKET=$(extract_jira_ticket)
    if [ $? -eq 0 ] && [ ! -z "$EXTRACTED_TICKET" ]; then
        JIRA_TICKET_ID="$EXTRACTED_TICKET"
        echo -e "${GREEN}✓ Auto-detected ticket from branch: ${YELLOW}$JIRA_TICKET_ID${NC}"
    else
        echo -e "${YELLOW}⚠️  No ticket ID found in branch name${NC}"
    fi
else
    # Priority 1: Use ticket ID from parameter
    JIRA_TICKET_ID="$TICKET_ID_PARAM"
    echo -e "${BLUE}🎫 Using specified ticket: $JIRA_TICKET_ID${NC}"
fi

# Fetch ticket details if we have a ticket ID
if [ ! -z "$JIRA_TICKET_ID" ]; then
    echo -e "${BLUE}📋 Fetching ticket details from Jira...${NC}"
    JIRA_DETAILS=$(fetch_jira_ticket_details "$JIRA_TICKET_ID" 2>/dev/null)
    if [ $? -eq 0 ] && [ ! -z "$JIRA_DETAILS" ]; then
        echo -e "${GREEN}✓ Loaded ticket context${NC}"
        JIRA_CONTEXT="

Context from Jira Ticket $JIRA_TICKET_ID:
$JIRA_DETAILS

"
    else
        echo -e "${YELLOW}⚠️  Could not fetch ticket details from Jira${NC}"
    fi
fi

# Method 1: Using OpenAI API (if API key is set)
generate_with_openai() {
    local api_key="${OPENAI_API_KEY}"
    local model="${OPENAI_MODEL:-gpt-4.1-mini}"
    
    if [ -z "$api_key" ]; then
        return 1
    fi
    
    # Truncate diff if too long (keep last 4000 chars for context)
    local diff_truncated
    if [ ${#DIFF} -gt 4000 ]; then
        diff_truncated="${DIFF: -4000}"
    else
        diff_truncated="$DIFF"
    fi
    
    local prompt="Analyze the following git diff and generate a meaningful, grammatically correct conventional commit message.

CRITICAL REQUIREMENTS:
1. Analyze the ACTUAL CODE CHANGES, not just file names
2. Understand what functionality was added, fixed, or modified
3. Write a grammatically correct, meaningful subject line
4. Use proper English grammar and complete sentences
5. Focus on WHAT changed and WHY it matters, not HOW it was implemented
6. DO NOT just list file names - describe the actual changes

Format: type(scope): subject

Types to use:
- feat: New feature or functionality
- fix: Bug fix or error correction
- docs: Documentation changes
- style: Code style/formatting (no logic changes)
- refactor: Code restructuring without changing behavior
- perf: Performance improvements
- test: Adding or updating tests
- chore: Maintenance tasks, dependencies, config
- ci: CI/CD changes

Rules:
- Keep subject under 72 characters
- Use imperative mood (e.g., 'add feature' not 'added feature')
- Be specific and descriptive
- Example: 'feat(auth): add password reset functionality' NOT 'update auth.ts'
${JIRA_CONTEXT}
Git diff:
\`\`\`diff
$diff_truncated
\`\`\`

Generate ONLY the commit message in the format 'type(scope): subject' - nothing else, no explanations:"

    # Escape prompt for JSON
    local prompt_json=$(echo "$prompt" | "$JQ" -Rs . 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$prompt_json" ]; then
        return 1
    fi
    
    local response=$(curl -s https://api.openai.com/v1/chat/completions \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $api_key" \
        -d "{
            \"model\": \"$model\",
            \"messages\": [
                {\"role\": \"system\", \"content\": \"You are an expert git commit message generator. Analyze code changes deeply and generate meaningful, grammatically correct commit messages. Focus on WHAT changed functionally, not just file names. Use proper English grammar.\"},
                {\"role\": \"user\", \"content\": $prompt_json}
            ],
            \"temperature\": 0.2,
            \"max_tokens\": 150
        }" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        return 1
    fi
    
    # Check for API errors
    if echo "$response" | "$JQ" -e '.error' &>/dev/null; then
        local error_msg=$(echo "$response" | "$JQ" -r '.error.message' 2>/dev/null)
        echo -e "${YELLOW}⚠️  OpenAI API error: ${error_msg}${NC}" >&2
        return 1
    fi
    
    # Extract commit message using "$JQ"
    local message=$(echo "$response" | "$JQ" -r '.choices[0].message.content' 2>/dev/null)
    
    if [ ! -z "$message" ] && [ "$message" != "null" ] && [ ${#message} -gt 5 ]; then
        echo "$message" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -1
        return 0
    fi
    
    return 1
}

# Method 2: Using Claude API (if API key is set)
generate_with_claude() {
    local api_key="${ANTHROPIC_API_KEY}"
    
    if [ -z "$api_key" ]; then
        return 1
    fi
    
    local diff_truncated
    if [ ${#DIFF} -gt 4000 ]; then
        diff_truncated="${DIFF: -4000}"
    else
        diff_truncated="$DIFF"
    fi
    
    local prompt="Analyze this git diff and generate a meaningful, grammatically correct conventional commit message.

CRITICAL REQUIREMENTS:
1. Analyze the ACTUAL CODE CHANGES, not just file names
2. Understand what functionality was added, fixed, or modified
3. Write a grammatically correct, meaningful subject line
4. Use proper English grammar and complete sentences
5. Focus on WHAT changed and WHY it matters, not HOW it was implemented
6. DO NOT just list file names - describe the actual changes

Format: type(scope): subject

Types: feat (new feature), fix (bug fix), docs (documentation), style (formatting), refactor (restructuring), perf (performance), test (tests), chore (maintenance), ci (CI/CD)

Rules:
- Keep subject under 72 characters
- Use imperative mood (e.g., 'add feature' not 'added feature')
- Be specific and descriptive
- Example: 'feat(auth): add password reset functionality' NOT 'update auth.ts'
${JIRA_CONTEXT}
\`\`\`diff
$diff_truncated
\`\`\`

Generate ONLY the commit message in format 'type(scope): subject' - nothing else:"

    # Escape prompt for JSON
    local prompt_json=$(echo "$prompt" | "$JQ" -Rs . 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$prompt_json" ]; then
        return 1
    fi
    
    local response=$(curl -s https://api.anthropic.com/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: $api_key" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"claude-3-5-sonnet-20241022\",
            \"max_tokens\": 150,
            \"messages\": [
                {\"role\": \"user\", \"content\": $prompt_json}
            ]
        }" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$response" ]; then
        return 1
    fi
    
    # Check for API errors
    if echo "$response" | "$JQ" -e '.error' &>/dev/null; then
        local error_msg=$(echo "$response" | "$JQ" -r '.error.message' 2>/dev/null)
        echo -e "${YELLOW}⚠️  Anthropic API error: ${error_msg}${NC}" >&2
        return 1
    fi
    
    # Extract commit message using "$JQ"
    local message=$(echo "$response" | "$JQ" -r '.content[0].text' 2>/dev/null)
    
    if [ ! -z "$message" ] && [ "$message" != "null" ] && [ ${#message} -gt 5 ]; then
        echo "$message" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -1
        return 0
    fi
    
    return 1
}

# Method 3: Rule-based generation (fallback)
generate_rule_based() {
    local diff_lower=$(echo "$DIFF" | tr '[:upper:]' '[:lower:]')
    local commit_type="chore"
    local scope=""
    local subject=""
    
    # Analyze actual code changes, not just file names
    local added_lines=$(echo "$DIFF" | grep -c "^\+" || echo "0")
    local removed_lines=$(echo "$DIFF" | grep -c "^-" || echo "0")
    
    # Determine commit type based on diff content and patterns
    if echo "$DIFF" | grep -qE "^\+.*(function|class|export|def|async|const.*=.*\(|interface|type)"; then
        commit_type="feat"
        subject="add new functionality"
    elif echo "$diff_lower" | grep -qE "(add|new|create|implement|feature|introduce)"; then
        commit_type="feat"
        # Try to extract what was added
        if echo "$diff_lower" | grep -qE "(function|method|handler|service|controller)"; then
            subject="add new functionality"
        elif echo "$diff_lower" | grep -qE "(endpoint|route|api)"; then
            subject="add new API endpoint"
        elif echo "$diff_lower" | grep -qE "(validation|validator|check)"; then
            subject="add validation logic"
        elif echo "$diff_lower" | grep -qE "(config|configuration|setting)"; then
            subject="add configuration option"
        else
            subject="add new feature"
        fi
    elif echo "$diff_lower" | grep -qE "(fix|bug|error|issue|problem|resolve|correct|repair)"; then
        commit_type="fix"
        # Try to extract what was fixed
        if echo "$diff_lower" | grep -qE "(null|undefined|exception|error|crash)"; then
            subject="fix null reference error"
        elif echo "$diff_lower" | grep -qE "(validation|validate|check)"; then
            subject="fix validation logic"
        elif echo "$diff_lower" | grep -qE "(typo|spelling|grammar)"; then
            subject="fix typo"
        elif echo "$diff_lower" | grep -qE "(timeout|time|delay)"; then
            subject="fix timeout issue"
        else
            subject="fix bug"
        fi
    elif echo "$diff_lower" | grep -qE "(refactor|restructure|reorganize|clean|extract|simplify)"; then
        commit_type="refactor"
        if echo "$diff_lower" | grep -qE "(extract|move|split)"; then
            subject="refactor code structure"
        elif echo "$diff_lower" | grep -qE "(rename|renaming)"; then
            subject="refactor variable names"
        else
            subject="refactor code"
        fi
    elif echo "$diff_lower" | grep -qE "(test|spec|specs|it\(|describe\(|expect)"; then
        commit_type="test"
        if echo "$diff_lower" | grep -qE "(add|new|create)"; then
            subject="add test cases"
        else
            subject="update tests"
        fi
    elif echo "$diff_lower" | grep -qE "(doc|readme|comment|\.md)"; then
        commit_type="docs"
        subject="update documentation"
    elif echo "$diff_lower" | grep -qE "(style|format|indent|whitespace|prettier|eslint)"; then
        commit_type="style"
        subject="format code style"
    elif echo "$diff_lower" | grep -qE "(perf|performance|optimize|speed|fast|slow)"; then
        commit_type="perf"
        subject="improve performance"
    elif echo "$diff_lower" | grep -qE "(dependenc|package\.json|yarn|npm|pip|requirements)"; then
        commit_type="chore"
        subject="update dependencies"
    elif echo "$diff_lower" | grep -qE "(docker|dockerfile|\.dockerignore)"; then
        commit_type="chore"
        subject="update Docker configuration"
    elif echo "$diff_lower" | grep -qE "(\.env|config|configuration|setting)"; then
        commit_type="chore"
        subject="update configuration"
    else
        # Default: analyze what changed
        if [ "$added_lines" -gt "$removed_lines" ] && [ "$added_lines" -gt 10 ]; then
            commit_type="feat"
            subject="add new functionality"
        elif [ "$removed_lines" -gt "$added_lines" ] && [ "$removed_lines" -gt 10 ]; then
            commit_type="refactor"
            subject="remove unused code"
        else
            commit_type="chore"
            subject="update code"
        fi
    fi
    
    # Try to extract scope from file paths and content
    local files=$(git diff --cached --name-only | head -5)
    if echo "$files" | grep -qE "(api|endpoint|route|controller)"; then
        scope="api"
    elif echo "$files" | grep -qE "(auth|login|user|account)"; then
        scope="auth"
    elif echo "$files" | grep -qE "(test|spec|__tests__)"; then
        scope="test"
    elif echo "$files" | grep -qE "(docker|dockerfile)"; then
        scope="docker"
    elif echo "$files" | grep -qE "(\.env|config|configuration)"; then
        scope="config"
    elif echo "$files" | grep -qE "(ui|component|view|page)"; then
        scope="ui"
    elif echo "$files" | grep -qE "(service|service\.ts|service\.js)"; then
        scope="service"
    fi
    
    # Format: type(scope): subject
    if [ ! -z "$scope" ]; then
        echo "$commit_type($scope): $subject"
    else
        echo "$commit_type: $subject"
    fi
}

# Generate with Cursor CLI (cursor-agent) - fully automated
generate_with_cursor_cli() {
    # Find cursor-agent in common locations
    local cursor_agent_path=""
    if command -v cursor-agent &> /dev/null; then
        cursor_agent_path="cursor-agent"
    else
        # Check common installation paths
        local cursor_paths=(
            "$HOME/.local/bin/cursor-agent"
            "/usr/local/bin/cursor-agent"
            "$HOME/.cursor/bin/cursor-agent"
            "/opt/homebrew/bin/cursor-agent"
        )
        
        for path in "${cursor_paths[@]}"; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                cursor_agent_path="$path"
                break
            fi
        done
    fi
    
    if [ -z "$cursor_agent_path" ]; then
        return 1
    fi
    
    # Ensure CURSOR_API_KEY is loaded (in case it wasn't loaded earlier)
    if [ -z "$CURSOR_API_KEY" ]; then
        CURSOR_API_KEY=$(security find-generic-password -a "$USER" -s "CURSOR_API_KEY" -w 2>/dev/null)
        # Also try SOPS if available
        if [ -z "$CURSOR_API_KEY" ] && [ -f "$HOME/Documents/secrets/api-keys.yaml" ] && command -v sops &> /dev/null; then
            CURSOR_API_KEY=$(sops --decrypt --extract '["CURSOR_API_KEY"]' "$HOME/Documents/secrets/api-keys.yaml" 2>/dev/null)
        fi
    fi
    
    # Export CURSOR_API_KEY so it's available to the subprocess
    if [ ! -z "$CURSOR_API_KEY" ]; then
        export CURSOR_API_KEY
    fi
    
    local diff_truncated
    
    # Truncate diff if too long (keep last 8000 chars for better context)
    if [ ${#DIFF} -gt 8000 ]; then
        diff_truncated="${DIFF: -8000}"
    else
        diff_truncated="$DIFF"
    fi
    
    # Create prompt for cursor-agent
    local prompt="Analyze this git diff and generate a meaningful, grammatically correct conventional commit message.

CRITICAL REQUIREMENTS:
1. Analyze the ACTUAL CODE CHANGES, not just file names
2. Understand what functionality was added, fixed, or modified
3. Write a grammatically correct, meaningful subject line
4. Use proper English grammar and complete sentences
5. Focus on WHAT changed and WHY it matters, not HOW it was implemented
6. DO NOT just list file names - describe the actual changes

Format: type(scope): subject

Types: feat (new feature), fix (bug fix), docs (documentation), style (formatting), refactor (restructuring), perf (performance), test (tests), chore (maintenance), ci (CI/CD)

Rules:
- Keep subject under 72 characters
- Use imperative mood (e.g., 'add feature' not 'added feature')
- Be specific and descriptive
- Example: 'feat(auth): add password reset functionality' NOT 'update auth.ts'
- Return ONLY the commit message, nothing else
${JIRA_CONTEXT}
Git diff:
\`\`\`diff
$diff_truncated
\`\`\`

Generate ONLY the commit message in format 'type(scope): subject':"
    
    # Try cursor-agent - first without API key (in case authenticated via login), then with API key
    local response=""
    local exit_code=1
    
    # First, try without API key (might be authenticated via cursor-agent login)
    # Use --print flag for non-interactive output, prompt as argument
    response=$("$cursor_agent_path" --print "$prompt" 2>&1)
    exit_code=$?
    
    # If that failed and we have an API key, try with the API key
    if [ $exit_code -ne 0 ] && [ ! -z "$CURSOR_API_KEY" ]; then
        response=$(CURSOR_API_KEY="$CURSOR_API_KEY" "$cursor_agent_path" --print "$prompt" 2>&1)
        exit_code=$?
    fi
    
    # Check for authentication error
    if echo "$response" | grep -qi "authentication required\|login\|unauthorized\|401\|403"; then
        echo -e "${YELLOW}⚠️  cursor-agent requires authentication${NC}" >&2
        echo -e "${YELLOW}Options:${NC}" >&2
        echo -e "  1. Run: cursor-agent login" >&2
        echo -e "  2. Or add CURSOR_API_KEY to Keychain:${NC}" >&2
        echo -e "     security add-generic-password -a \"\$USER\" -s \"CURSOR_API_KEY\" -w \"your-api-key\"" >&2
        echo -e "  3. Or set: export CURSOR_API_KEY='your-key'" >&2
        return 1
    fi
    
    # Check for other errors
    if [ $exit_code -ne 0 ]; then
        echo -e "${YELLOW}⚠️  cursor-agent error (exit code: $exit_code):${NC}" >&2
        if [ ! -z "$response" ]; then
            echo "$response" | head -5 | sed 's/^/  /' >&2
        else
            echo -e "  ${YELLOW}No error message returned${NC}" >&2
        fi
        return 1
    fi
    
    # Check if we got a valid response
    if [ ! -z "$response" ] && [ ${#response} -gt 5 ]; then
        # Clean up the response
        # Remove markdown code blocks
        local cleaned=$(echo "$response" | sed 's/```[^`]*```//g')
        # Extract the first line that looks like a commit message (contains type(scope): or type:)
        local commit_msg=$(echo "$cleaned" | grep -E "^(feat|fix|docs|style|refactor|perf|test|chore|ci)(\([^)]+\))?:" | head -1)
        
        # If we found a commit message format, use it
        if [ ! -z "$commit_msg" ]; then
            echo "$commit_msg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
            return 0
        fi
        
        # Otherwise, try to extract the first meaningful line (not empty, not just whitespace, not a heading)
        cleaned=$(echo "$cleaned" | grep -v "^#" | grep -v "^$" | grep -v "^Conventional\|^If you\|^**If\|^Update\|^Generate" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        if [ ! -z "$cleaned" ] && [ ${#cleaned} -gt 10 ] && [ ${#cleaned} -lt 100 ]; then
            echo "$cleaned"
            return 0
        fi
        
        # Last resort: show what we got for debugging
        echo -e "${YELLOW}⚠️  cursor-agent response doesn't match expected format:${NC}" >&2
        echo "$response" | head -10 | sed 's/^/  /' >&2
    fi
    
    echo -e "${YELLOW}⚠️  cursor-agent returned empty or invalid response${NC}" >&2
    if [ ! -z "$response" ]; then
        echo -e "${YELLOW}Raw response (first 20 lines):${NC}" >&2
        echo "$response" | head -20 | sed 's/^/  /' >&2
    fi
    return 1
}

# Main generation logic
generate_commit_message() {
    local message=""
    
    # Try OpenAI first
    if [ ! -z "$OPENAI_API_KEY" ]; then
        echo -e "${BLUE}🤖 Generating commit message with OpenAI...${NC}" >&2
        message=$(generate_with_openai)
        if [ $? -eq 0 ] && [ ! -z "$message" ]; then
            echo "$message"
            return 0
        fi
    fi
    
    # Try Claude
    if [ ! -z "$ANTHROPIC_API_KEY" ]; then
        echo -e "${BLUE}🤖 Generating commit message with Claude...${NC}" >&2
        message=$(generate_with_claude)
        if [ $? -eq 0 ] && [ ! -z "$message" ]; then
            echo "$message"
            return 0
        fi
    fi
    
    # Try Cursor CLI (cursor-agent) - requires authentication
    # Check if cursor-agent exists (either in PATH or common locations)
    local cursor_agent_found=false
    if command -v cursor-agent &> /dev/null; then
        cursor_agent_found=true
    else
        # Check common installation paths
        local cursor_paths=(
            "$HOME/.local/bin/cursor-agent"
            "/usr/local/bin/cursor-agent"
            "$HOME/.cursor/bin/cursor-agent"
            "/opt/homebrew/bin/cursor-agent"
        )
        
        for path in "${cursor_paths[@]}"; do
            if [ -f "$path" ] && [ -x "$path" ]; then
                cursor_agent_found=true
                break
            fi
        done
    fi
    
    if [ "$cursor_agent_found" = true ]; then
        echo -e "${BLUE}🎨 Generating commit message with Cursor AI...${NC}" >&2
        message=$(generate_with_cursor_cli)
        if [ $? -eq 0 ] && [ ! -z "$message" ]; then
            echo "$message"
            return 0
        fi
        # Error message already shown by generate_with_cursor_cli
    fi
    
    # Fallback to rule-based
    echo -e "${YELLOW}⚠️  No AI available. Using rule-based generation...${NC}" >&2
    echo -e "${YELLOW}💡 Options for AI-powered messages:${NC}" >&2
    echo -e "  • Set OPENAI_API_KEY (uses your API credits)" >&2
    echo -e "  • Set ANTHROPIC_API_KEY (uses your API credits)" >&2
    if command -v cursor-agent &> /dev/null; then
        echo -e "  • Authenticate cursor-agent: cursor-agent login" >&2
        echo -e "    Or set: export CURSOR_API_KEY='your-key'" >&2
    else
        echo -e "  • Install Cursor CLI: curl https://cursor.com/install -fsS | bash" >&2
        echo -e "    Then run: cursor-agent login" >&2
    fi
    echo -e "    Note: cursor-agent uses Cursor subscription credits (Free tier: limited)" >&2
    generate_rule_based
}

# Generate the commit message
COMMIT_MSG=$(generate_commit_message)

if [ -z "$COMMIT_MSG" ]; then
    echo -e "${RED}Failed to generate commit message${NC}"
    exit 1
fi

# Clean up the message (remove quotes, extra whitespace)
COMMIT_MSG=$(echo "$COMMIT_MSG" | sed 's/^"//;s/"$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -1)

# Get repository information
CURRENT_BRANCH=$(git branch --show-current)
CURRENT_USER=$(git config user.name)
CURRENT_EMAIL=$(git config user.email)
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "No remote")

# Parse remote URL to extract username/repo info
REMOTE_USER=""
REPO_NAME=""
REPO_FULL_NAME=""

if [ "$REMOTE_URL" != "No remote" ]; then
    # Handle SSH URLs (git@host:user/repo.git)
    if echo "$REMOTE_URL" | grep -q "@"; then
        # Extract from SSH format: git@github.com:user/repo.git
        REPO_FULL_NAME=$(echo "$REMOTE_URL" | sed -E 's/.*@[^:]+:([^/]+\/[^/]+)(\.git)?$/\1/' | sed 's/\.git$//')
    else
        # Handle HTTPS URLs (https://host/user/repo.git)
        REPO_FULL_NAME=$(echo "$REMOTE_URL" | sed -E 's|.*://[^/]+/([^/]+/[^/]+)(\.git)?$|\1|' | sed 's/\.git$//')
    fi
    
    if [ ! -z "$REPO_FULL_NAME" ] && [ "$REPO_FULL_NAME" != "$REMOTE_URL" ]; then
        REMOTE_USER=$(echo "$REPO_FULL_NAME" | cut -d'/' -f1)
        REPO_NAME=$(echo "$REPO_FULL_NAME" | cut -d'/' -f2-)
    else
        # Fallback: use directory name
        REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "Unknown")
    fi
else
    # No remote, use local repo name
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "Unknown")
fi

# Show preview with context
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📝 Commit Preview${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Show repository information
echo -e "${YELLOW}Repository Information:${NC}"
echo -e "  ${BLUE}Branch:${NC}        ${GREEN}$CURRENT_BRANCH${NC}"
if [ "$REMOTE_URL" != "No remote" ]; then
    echo -e "  ${BLUE}Remote URL:${NC}    ${GREEN}$REMOTE_URL${NC}"
    if [ ! -z "$REMOTE_USER" ]; then
        echo -e "  ${BLUE}Remote User:${NC}   ${GREEN}$REMOTE_USER${NC}"
    fi
    if [ ! -z "$REPO_NAME" ]; then
        echo -e "  ${BLUE}Repository:${NC}    ${GREEN}$REPO_NAME${NC}"
    fi
else
    echo -e "  ${BLUE}Remote:${NC}        ${YELLOW}No remote configured${NC}"
    if [ ! -z "$REPO_NAME" ]; then
        echo -e "  ${BLUE}Repository:${NC}    ${GREEN}$REPO_NAME${NC} (local only)"
    fi
fi
echo -e "  ${BLUE}Committing as:${NC} ${GREEN}$CURRENT_USER${NC} <${GREEN}$CURRENT_EMAIL${NC}>"

# Show Jira ticket URL if available
if [ ! -z "$JIRA_TICKET_ID" ]; then
    # Try to get base URL from instances or keychain
    TICKET_BASE_URL=""
    
    # Try instances file first
    if [ -f "$HOME/.config/git-ai/jira-instances.json" ] && command -v "$JQ" &> /dev/null; then
        default_instance=$("$JQ" -r '.default // ""' "$HOME/.config/git-ai/jira-instances.json" 2>/dev/null)
        if [ ! -z "$default_instance" ]; then
            TICKET_BASE_URL=$("$JQ" -r ".instances[] | select(.name == \"$default_instance\") | .base_url" "$HOME/.config/git-ai/jira-instances.json" 2>/dev/null)
        fi
    fi
    
    # Fallback to keychain
    if [ -z "$TICKET_BASE_URL" ]; then
        TICKET_BASE_URL=$(security find-generic-password -a "$USER" -s "JIRA_BASE_URL" -w 2>/dev/null)
    fi
    
    # Display ticket URL if we have base URL
    if [ ! -z "$TICKET_BASE_URL" ]; then
        TICKET_URL="${TICKET_BASE_URL}/browse/${JIRA_TICKET_ID}"
        echo -e "  ${BLUE}Jira Ticket:${NC}   ${GREEN}${TICKET_URL}${NC}"
    else
        echo -e "  ${BLUE}Jira Ticket:${NC}   ${GREEN}${JIRA_TICKET_ID}${NC}"
    fi
fi
echo ""

# Show changed files
CHANGED_FILES=$(git diff --cached --name-only)
FILE_COUNT=$(echo "$CHANGED_FILES" | wc -l | tr -d ' ')
echo -e "${YELLOW}Files to commit (${FILE_COUNT}):${NC}"
echo "$CHANGED_FILES" | head -10 | sed 's/^/  • /'
if [ "$FILE_COUNT" -gt 10 ]; then
    echo -e "  ${YELLOW}... and $((FILE_COUNT - 10)) more${NC}"
fi
echo ""

# Show diff stats
echo -e "${YELLOW}Changes summary:${NC}"
git diff --cached --stat | tail -1 | sed 's/^/  /'
echo ""

# Show generated commit message
echo -e "${GREEN}Generated commit message:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}$COMMIT_MSG${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Ask for confirmation with better options
echo -e "${YELLOW}Options:${NC}"
echo -e "  ${GREEN}Y${NC} or ${GREEN}Enter${NC} - Use this message and commit"
echo -e "  ${BLUE}d${NC} - Show diff preview"
echo -e "  ${BLUE}e${NC} - Edit the message"
echo -e "  ${BLUE}r${NC} - Regenerate message (if AI available)"
echo -e "  ${RED}n${NC} - Cancel"
echo ""
read -p "Confirm: " confirm
confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')

# Handle diff preview
if [[ "$confirm" =~ ^[Dd]$ ]]; then
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}📋 Diff Preview${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    git diff --cached | head -100
    if [ $(git diff --cached | wc -l) -gt 100 ]; then
        echo ""
        echo -e "${YELLOW}... (showing first 100 lines, ${RED}$(git diff --cached | wc -l)${YELLOW} total lines)${NC}"
    fi
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}Options:${NC}"
    echo -e "  ${GREEN}Y${NC} or ${GREEN}Enter${NC} - Use this message and commit"
    echo -e "  ${BLUE}e${NC} - Edit the message"
    echo -e "  ${BLUE}r${NC} - Regenerate message"
    echo -e "  ${RED}n${NC} - Cancel"
    echo ""
    read -p "Confirm: " confirm
    confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
fi

# Normalize input
confirm=$(echo "$confirm" | tr '[:upper:]' '[:lower:]' | xargs)

case "$confirm" in
    r|regenerate)
        # Regenerate message
        echo -e "${BLUE}🔄 Regenerating commit message...${NC}"
        COMMIT_MSG=$(generate_commit_message)
        if [ -z "$COMMIT_MSG" ]; then
            echo -e "${RED}Failed to regenerate commit message${NC}"
            exit 1
        fi
        COMMIT_MSG=$(echo "$COMMIT_MSG" | sed 's/^"//;s/"$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -1)
        echo -e "${GREEN}New message: ${BLUE}$COMMIT_MSG${NC}"
        echo ""
        read -p "Use this message? (Y/n/e to edit): " confirm2
        confirm2=$(echo "$confirm2" | tr '[:upper:]' '[:lower:]' | xargs)
        case "$confirm2" in
            e|edit)
                echo "$COMMIT_MSG" > /tmp/git-commit-msg.txt
                ${EDITOR:-nano} /tmp/git-commit-msg.txt
                COMMIT_MSG=$(cat /tmp/git-commit-msg.txt | head -1)
                rm -f /tmp/git-commit-msg.txt
                if [ -z "$COMMIT_MSG" ]; then
                    echo -e "${RED}Empty commit message. Cancelled.${NC}"
                    exit 1
                fi
                git commit -m "$COMMIT_MSG"
                echo -e "${GREEN}✓ Committed successfully${NC}"
                update_jira_after_commit "$COMMIT_MSG"
                ;;
            n|no)
                echo -e "${YELLOW}❌ Commit cancelled${NC}"
                exit 0
                ;;
            y|yes|"")
                git commit -m "$COMMIT_MSG"
                echo -e "${GREEN}✓ Committed successfully${NC}"
                update_jira_after_commit "$COMMIT_MSG"
                ;;
            *)
                echo -e "${YELLOW}❌ Invalid input. Commit cancelled.${NC}"
                exit 1
                ;;
        esac
        ;;
    n|no|cancel)
        echo -e "${YELLOW}❌ Commit cancelled${NC}"
        exit 0
        ;;
    e|edit)
        # Edit the message
        echo "$COMMIT_MSG" > /tmp/git-commit-msg.txt
        ${EDITOR:-nano} /tmp/git-commit-msg.txt
        COMMIT_MSG=$(cat /tmp/git-commit-msg.txt | head -1)
        rm -f /tmp/git-commit-msg.txt
        if [ -z "$COMMIT_MSG" ]; then
            echo -e "${RED}Empty commit message. Cancelled.${NC}"
            exit 1
        fi
        echo ""
        echo -e "${BLUE}Committing with message: ${COMMIT_MSG}${NC}"
        git commit -m "$COMMIT_MSG"
        echo -e "${GREEN}✓ Committed successfully${NC}"
        update_jira_after_commit "$COMMIT_MSG"
        ;;
    y|yes|"")
        # Default: use the message (Y, yes, or Enter)
        echo ""
        echo -e "${BLUE}Committing with message: ${COMMIT_MSG}${NC}"
        git commit -m "$COMMIT_MSG"
        echo -e "${GREEN}✓ Committed successfully${NC}"
        update_jira_after_commit "$COMMIT_MSG"
        ;;
    *)
        # Invalid input - don't commit
        echo -e "${RED}❌ Invalid input: '$confirm'${NC}"
        echo -e "${YELLOW}Valid options: Y (yes), n (no), e (edit), d (diff), r (regenerate)${NC}"
        echo -e "${YELLOW}Commit cancelled for safety.${NC}"
        exit 1
        ;;
esac
