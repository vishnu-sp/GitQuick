#!/bin/bash

# Git Helper Scripts for Drive Health Monorepo
# Usage: source git-helpers.sh or add to .zshrc

# Enable extended pattern matching for bash/zsh compatibility
if [ -n "$BASH_VERSION" ]; then
    shopt -s extglob
elif [ -n "$ZSH_VERSION" ]; then
    setopt RE_MATCH_PCRE 2>/dev/null || true
    setopt BASH_REMATCH 2>/dev/null || true
fi

# Get current branch name
get_current_branch() {
  git branch --show-current
}

# Check if working directory is clean
is_clean() {
  git diff-index --quiet HEAD --
}

# Quick commit with conventional commit format
# Usage: gcommit feat "add user authentication"
gcommit() {
  local type=$1
  local message=$2
  
  if [ -z "$type" ] || [ -z "$message" ]; then
    echo "Usage: gcommit <type> <message>"
    echo "Types: feat, fix, docs, style, refactor, test, chore"
    return 1
  fi
  
  git add -A
  git commit -m "$type: $message"
}

# Create feature branch from dev/main
# Usage: gfeature feature-name
gfeature() {
  local branch_name=$1
  
  if [ -z "$branch_name" ]; then
    echo "Usage: gfeature branch-name"
    return 1
  fi
  
  # Try to checkout dev first, fallback to main
  if git show-ref --verify --quiet refs/heads/dev; then
    git checkout dev
    git pull origin dev
  elif git show-ref --verify --quiet refs/heads/main; then
    git checkout main
    git pull origin main
  fi
  
  git checkout -b "feature/$branch_name"
}

# Create hotfix branch
# Usage: ghotfix fix-name
ghotfix() {
  local branch_name=$1
  
  if [ -z "$branch_name" ]; then
    echo "Usage: ghotfix fix-name"
    return 1
  fi
  
  # Try main first, fallback to master
  if git show-ref --verify --quiet refs/heads/main; then
    git checkout main
    git pull origin main
  elif git show-ref --verify --quiet refs/heads/master; then
    git checkout master
    git pull origin master
  fi
  
  git checkout -b "hotfix/$branch_name"
}

# Squash last N commits
# Usage: gsquash 3 "new commit message"
gsquash() {
  local count=$1
  local message=$2
  
  if [ -z "$count" ] || [ -z "$message" ]; then
    echo "Usage: gsquash <number-of-commits> <new-message>"
    return 1
  fi
  
  git reset --soft HEAD~$count
  git commit -m "$message"
}

# Interactive rebase last N commits
# Usage: grebase 5
grebase() {
  local count=${1:-5}
  git rebase -i HEAD~$count
}

# Show files changed in last commit
gshow() {
  git show --name-status HEAD
}

# Show commit history for a file
# Usage: ghistory path/to/file
ghistory() {
  if [ -z "$1" ]; then
    echo "Usage: ghistory <file-path>"
    return 1
  fi
  git log --follow --pretty=format:"%h - %an, %ar : %s" -- "$1"
}

# Find commits by message
# Usage: gfind "search term"
gfind() {
  if [ -z "$1" ]; then
    echo "Usage: gfind <search-term>"
    return 1
  fi
  git log --all --grep="$1" --oneline
}

# Show who last modified each line
# Usage: gblame path/to/file
gblame() {
  if [ -z "$1" ]; then
    echo "Usage: gblame <file-path>"
    return 1
  fi
  git blame "$1"
}

# Undo last commit (keep changes)
gundo() {
  git reset --soft HEAD~1
  echo "Last commit undone. Changes are still staged."
}

# Undo last commit (discard changes)
gundohard() {
  read "?This will discard all changes. Are you sure? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    git reset --hard HEAD~1
    echo "Last commit and changes discarded."
  fi
}

# Show branch comparison
# Usage: gcompare branch1 branch2
gcompare() {
  local branch1=${1:-HEAD}
  local branch2=${2:-origin/$(git branch --show-current)}
  git log --oneline --graph --left-right "$branch1...$branch2"
}

# Count commits by author
gauthors() {
  git shortlog -sn --all
}

# Show commit stats
gstats() {
  git log --stat --summary
}

# Create a backup branch
gbackup() {
  local branch_name="backup/$(date +%Y%m%d-%H%M%S)"
  git branch "$branch_name"
  echo "Created backup branch: $branch_name"
}

# Show all tags
gtags() {
  git tag -l
}

# Create and push tag
# Usage: gtag v1.0.0 "release message"
gtag() {
  local tag=$1
  local message=$2
  
  if [ -z "$tag" ]; then
    echo "Usage: gtag <tag-name> [message]"
    return 1
  fi
  
  if [ -z "$message" ]; then
    git tag -a "$tag" -m "Release $tag"
  else
    git tag -a "$tag" -m "$message"
  fi
  
  git push origin "$tag"
}

# Show current repository info
ginfo() {
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📁 Repository: $(basename $(git rev-parse --show-toplevel))"
  echo "🌿 Current Branch: $(git branch --show-current)"
  echo "📍 Remote URL: $(git remote get-url origin 2>/dev/null || echo 'No remote')"
  echo "📊 Status: $(if is_clean; then echo 'Clean'; else echo 'Has changes'; fi)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  git status --short
}

# Create Pull Request / Merge Request
# Usage: gpr [base-branch] [title] [description] [ticket-id]
# Examples:
#   gpr                    # Create PR to default branch (main/master/dev)
#   gpr main               # Create PR to main branch
#   gpr dev "My PR title" # Create PR to dev with custom title
#   gpr main "Title" "Description" "DH-1234" # Full control with Jira ticket
# Create Pull Request function
# Note: Function renamed from 'gpr' to 'create_pull_request' to avoid conflict
# with Oh My Zsh alias 'gpr' = 'git pull --rebase'
create_pull_request() {
  local base_branch="${1:-}"
  local pr_title="${2:-}"
  local pr_description="${3:-}"
  local ticket_id="${4:-${JIRA_TICKET_ID:-}}"
  local stashed=false
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔍 DEBUG: create_pull_request() function called"
  echo "   base_branch: $base_branch"
  echo "   ticket_id: $ticket_id"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  # Note: Unstaged changes check and push are handled by gq pr before calling this function
  # This function assumes changes are already committed and branch is already pushed
  
  # Get current branch
  echo "🔍 Getting current branch..."
  local current_branch=$(get_current_branch)
  echo "   Current branch: $current_branch"
  echo ""
  
  if [ -z "$current_branch" ]; then
    echo "❌ Error: Could not determine current branch"
    return 1
  fi
  
  # Verify branch is pushed (should already be done by gq pr, but double-check)
  local upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null)
  if [ -z "$upstream" ]; then
    echo "⚠️  Current branch '$current_branch' is not pushed to remote"
    echo "❌ Cannot create PR without pushing branch first"
    echo "💡 Run: git push -u origin $current_branch"
    return 1
  fi
  
  # Get remote URL
  local remote_url=$(git config --get remote.origin.url 2>/dev/null)
  if [ -z "$remote_url" ]; then
    echo "❌ Error: No remote configured"
    return 1
  fi
  
  echo "🔍 Parsing remote URL: $remote_url"
  
  # Parse remote URL to detect platform
  local repo_url=""
  local platform=""
  local host=""
  local repo=""
  
  # Convert SSH to HTTPS and detect platform
  # Handle SSH format: git@host:path/repo.git
  if [[ "$remote_url" =~ ^git@([^:]+):(.+)\.git$ ]]; then
    # Extract host and repo using parameter expansion (works in both bash and zsh)
    local temp="${remote_url#git@}"  # Remove git@ prefix
    host="${temp%%:*}"               # Extract host (everything before :)
    repo="${temp#*:}"                # Extract repo path (everything after :)
    repo="${repo%.git}"              # Remove .git suffix
    
    echo "   ✓ Matched SSH format"
    echo "   Host: $host"
    echo "   Repo: $repo"
    repo_url="https://${host}/${repo}"
    echo "   Constructed URL: $repo_url"
    
    if [[ "$host" =~ github\.com ]]; then
      platform="github"
    elif [[ "$host" =~ gitlab ]] || [[ "$host" =~ gitlab\.com ]]; then
      platform="gitlab"
    elif [[ "$host" =~ bitbucket\.org ]]; then
      platform="bitbucket"
    else
      # For custom domains, try to detect GitLab by checking common patterns
      # Most custom GitLab instances will be detected here
      echo "ℹ️  Custom git host detected: $host"
      echo "   Checking if it's a GitLab instance..."
      # Assume it's GitLab for now (most common for custom domains)
      # You can verify by checking if the URL structure works
      platform="gitlab"
      echo "   Assuming GitLab format"
    fi
  elif [[ "$remote_url" =~ ^https://([^/]+)/(.+)\.git$ ]] || [[ "$remote_url" =~ ^https://([^/]+)/(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
    echo "   ✓ Matched HTTPS format"
    echo "   Host: $host"
    echo "   Repo: $repo"
    repo_url="https://${host}/${repo}"
    repo_url="${repo_url%.git}"
    echo "   Constructed URL: $repo_url"
    
    if [[ "$host" =~ github\.com ]]; then
      platform="github"
    elif [[ "$host" =~ gitlab ]] || [[ "$host" =~ gitlab\.com ]]; then
      platform="gitlab"
    elif [[ "$host" =~ bitbucket\.org ]]; then
      platform="bitbucket"
    else
      # Custom domain - assume GitLab
      echo "ℹ️  Custom git host detected: $host"
      platform="gitlab"
      echo "   Using GitLab format for PR"
    fi
  else
    echo "   ❌ No regex pattern matched!"
    echo "   Remote URL format not recognized"
    return 1
  fi
  
  # Verify we have a valid repo_url
  if [ -z "$repo_url" ] || [ "$repo_url" = "https:///" ]; then
    echo "❌ Error: Failed to parse repository URL"
    echo "   Remote URL: $remote_url"
    echo "   Parsed repo_url: $repo_url"
    return 1
  fi
  
  echo "✓ Final repo_url: $repo_url"
  echo "✓ Platform: $platform"
  echo ""
  
  # Determine base branch if not provided
  if [ -z "$base_branch" ]; then
    # Try common default branches
    if git show-ref --verify --quiet refs/heads/main; then
      base_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
      base_branch="master"
    elif git show-ref --verify --quiet refs/heads/dev; then
      base_branch="dev"
    elif git show-ref --verify --quiet refs/heads/develop; then
      base_branch="develop"
    else
      echo "❌ Error: Could not determine base branch"
      echo "💡 Please specify: gpr <base-branch>"
      return 1
    fi
  fi
  
  # Resolve base branch - use origin/base_branch if local branch doesn't exist
  # First, fetch to ensure we have latest remote refs
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔍 DEBUG: Resolving base branch"
  echo "   base_branch parameter: '$base_branch'"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  
  echo "🔄 Fetching latest remote branches..."
  
  # Validate that base_branch is not accidentally a remote name
  echo "🔍 Checking if '$base_branch' is a remote name..."
  local all_remotes=$(git remote 2>&1)
  echo "   All remotes: $all_remotes"
  
  if echo "$all_remotes" | grep -q "^${base_branch}$"; then
    echo "❌ Error: '$base_branch' appears to be a remote name, not a branch name"
    echo "💡 Use the branch name, not the remote name (e.g., 'main' not 'origin')"
    return 1
  fi
  echo "✓ '$base_branch' is not a remote name"
  echo ""
  
  # Fetch from origin only - use explicit remote name to avoid ambiguity
  echo "🔍 Fetching from origin..."
  local fetch_output=$(git fetch origin --quiet 2>&1)
  local fetch_status=$?
  if [ $fetch_status -ne 0 ]; then
    echo "⚠️  Warning: git fetch failed with status $fetch_status"
    echo "   Error output: $fetch_output"
    echo "   Continuing with local refs..."
  else
    echo "✓ Fetch successful"
  fi
  echo ""
  
  local base_branch_ref="$base_branch"
  if ! git show-ref --verify --quiet "refs/heads/$base_branch" 2>/dev/null; then
    # Local branch doesn't exist, try origin/base_branch
    if git show-ref --verify --quiet "refs/remotes/origin/$base_branch" 2>/dev/null; then
      base_branch_ref="origin/$base_branch"
      echo "ℹ️  Using remote branch: $base_branch_ref (local '$base_branch' doesn't exist)"
    else
      echo "⚠️  Warning: Base branch '$base_branch' not found locally or on origin"
      echo "   Will attempt to create PR anyway (branch may exist on remote but not fetched)"
      # Use just the branch name - GitHub/GitLab will resolve it
      base_branch_ref="$base_branch"
    fi
  fi
  
  # Generate PR title from last commit if not provided
  if [ -z "$pr_title" ]; then
    pr_title=$(git log -1 --pretty=format:"%s" 2>/dev/null)
    if [ -z "$pr_title" ]; then
      pr_title="Update from $current_branch"
    fi
  fi
  
  # Generate PR description from commits if not provided
  if [ -z "$pr_description" ]; then
    # Use base_branch_ref for comparison (handles both local and remote branches)
    # Only try to get commit count if base branch exists
    local commit_count="0"
    local base_exists=false
    
    # Check if base branch exists locally
    if git show-ref --verify --quiet "refs/heads/$base_branch" 2>/dev/null; then
      base_exists=true
      base_branch_ref="$base_branch"
    # Check if base branch exists on remote
    elif git show-ref --verify --quiet "refs/remotes/origin/$base_branch" 2>/dev/null; then
      base_exists=true
      base_branch_ref="origin/$base_branch"
    fi
    
    if [ "$base_exists" = true ]; then
      # Safely get commit count - use full ref to avoid git interpreting as remote
      commit_count=$(git rev-list --count "$base_branch_ref..$current_branch" 2>/dev/null || echo "0")
      
      if [ "$commit_count" != "0" ] && [ "$commit_count" -gt 0 ] 2>/dev/null; then
        pr_description="## Changes\n\n"
        pr_description+="$(git log --oneline "$base_branch_ref..$current_branch" 2>/dev/null | sed 's/^/- /' | head -10)"
        if [ "$commit_count" -gt 10 ] 2>/dev/null; then
          pr_description+="\n\n... and $((commit_count - 10)) more commit(s)"
        fi
      fi
    else
      # Base branch doesn't exist - skip description generation
      echo "⚠️  Base branch '$base_branch' not found - skipping commit list in PR description"
    fi
  fi
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🚀 Creating Pull Request"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "📌 From: $current_branch"
  echo "📌 To:   $base_branch"
  echo "📌 Title: $pr_title"
  echo "📌 Platform: $platform"
  echo "📌 Repo URL: $repo_url"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Create PR based on platform
  # Note: Use base_branch (not base_branch_ref) for PR creation - APIs expect branch name without origin/
  local pr_created=false
  local pr_url=""
  case "$platform" in
    github)
      if command -v gh &> /dev/null; then
        echo "✅ Using GitHub CLI (gh)..."
        # Create PR and capture URL (use base_branch, not base_branch_ref)
        local pr_output=$(gh pr create --base "$base_branch" --head "$current_branch" --title "$pr_title" --body "$pr_description" 2>&1)
        if [ $? -eq 0 ]; then
          pr_created=true
          # Extract PR URL from output (format: https://github.com/owner/repo/pull/123)
          pr_url=$(echo "$pr_output" | grep -oE 'https://[^[:space:]]+/pull/[0-9]+' | head -1)
          if [ -z "$pr_url" ]; then
            # Fallback: construct URL from repo and PR number
            local pr_number=$(echo "$pr_output" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
            if [ ! -z "$pr_number" ]; then
              pr_url="${repo_url}/pull/${pr_number}"
            fi
          fi
          echo "🔗 PR URL: $pr_url"
        else
          echo "❌ Failed to create PR with gh CLI"
          echo "💡 Opening browser instead..."
          pr_url="${repo_url}/compare/${base_branch}...${current_branch}?expand=1"
          open "$pr_url"
          pr_created=true  # Browser opened, consider it initiated
        fi
      else
        echo "⚠️  GitHub CLI (gh) not found. Opening browser..."
        pr_url="${repo_url}/compare/${base_branch}...${current_branch}?expand=1"
        open "$pr_url"
        pr_created=true
      fi
      ;;
    gitlab)
      if command -v glab &> /dev/null; then
        echo "✅ Using GitLab CLI (glab)..."
        local mr_output=$(glab mr create --target-branch "$base_branch" --source-branch "$current_branch" --title "$pr_title" --description "$pr_description" 2>&1)
        if [ $? -eq 0 ]; then
          pr_created=true
          # Extract MR URL from output
          pr_url=$(echo "$mr_output" | grep -oE 'https://[^[:space:]]+/merge_requests/[0-9]+' | head -1)
          if [ -z "$pr_url" ]; then
            local mr_number=$(echo "$mr_output" | grep -oE '!([0-9]+)' | head -1 | tr -d '!')
            if [ ! -z "$mr_number" ]; then
              pr_url="${repo_url}/-/merge_requests/${mr_number}"
            fi
          fi
          echo "🔗 MR URL: $pr_url"
        else
          echo "❌ Failed to create MR with glab CLI"
          echo "💡 Opening browser instead..."
          pr_url="${repo_url}/-/merge_requests/new?merge_request[source_branch]=${current_branch}&merge_request[target_branch]=${base_branch}"
          open "$pr_url"
          pr_created=true
        fi
      else
        echo "⚠️  GitLab CLI (glab) not found. Opening browser..."
        pr_url="${repo_url}/-/merge_requests/new?merge_request[source_branch]=${current_branch}&merge_request[target_branch]=${base_branch}"
        open "$pr_url"
        pr_created=true
      fi
      ;;
    bitbucket)
      echo "⚠️  Bitbucket detected. Opening browser..."
      pr_url="${repo_url}/pull-requests/new?source=${current_branch}&dest=${base_branch}"
      open "$pr_url"
      pr_created=true
      ;;
    *)
      # Unknown platform - shouldn't reach here with improved detection above
      # But handle it gracefully just in case
      echo "⚠️  Platform detection inconclusive"
      echo "   repo_url: $repo_url"
      echo "   platform: $platform"
      
      if [ -z "$repo_url" ]; then
        echo "❌ Error: Could not construct repository URL"
        echo "   Remote URL: $remote_url"
        return 1
      fi
      
      # Try to detect and open based on URL patterns
      if [[ "$repo_url" =~ github ]]; then
        echo "   Detected GitHub pattern, opening compare view..."
        pr_url="${repo_url}/compare/${base_branch}...${current_branch}?expand=1"
        open "$pr_url"
        pr_created=true
      else
        # Default to GitLab format (most common for custom domains)
        echo "   Using GitLab format for custom instance..."
        pr_url="${repo_url}/-/merge_requests/new?merge_request[source_branch]=${current_branch}&merge_request[target_branch]=${base_branch}"
        echo "   Opening: $pr_url"
        open "$pr_url" 2>/dev/null || echo "   Please open manually: $pr_url"
        pr_created=true
      fi
      ;;
  esac
  
  echo ""
  if [ "$pr_created" = true ]; then
    echo "✅ PR creation initiated!"
    
    # Update Jira with PR link if ticket ID is provided
    if [ ! -z "$ticket_id" ] && [ ! -z "$pr_url" ]; then
      echo ""
      echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo -e "${BLUE}🎫 Updating Jira Ticket${NC}"
      echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo ""
      
      # Source git-commit-gen.sh to get Jira functions
      local script_dir=""
      if [ -n "${BASH_SOURCE[0]}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
      elif [ -n "$0" ] && [ "$0" != "-bash" ] && [ "$0" != "-zsh" ] && [ -f "$0" ]; then
        script_dir="$(cd "$(dirname "$0")" && pwd)"
      fi
      
      # Use git-commit-gen.sh functions via bash call
      if [ ! -z "$script_dir" ] && [ -f "$script_dir/git-commit-gen.sh" ]; then
        # Create Jira comment with PR link
        local commit_msg=$(git log -1 --pretty=%B 2>/dev/null || echo "Pull Request created")
        local commit_sha=$(git rev-parse --short HEAD 2>/dev/null || echo "")
        
        # Build PR comment
        local pr_comment="## Pull Request Created\n\n✅ **Pull Request:** [$current_branch → $base_branch]($pr_url)"
        if [ ! -z "$commit_sha" ]; then
          pr_comment="$pr_comment\n\n**Latest Commit:** \`$commit_sha\`\n$commit_msg"
        fi
        
        # Use a helper script or direct function call
        # Since we can't easily source git-commit-gen.sh here, we'll use curl directly
        # Load Jira credentials
        local jira_api_key=$(security find-generic-password -a "$USER" -s "JIRA_API_KEY" -w 2>/dev/null)
        local jira_email=$(security find-generic-password -a "$USER" -s "JIRA_EMAIL" -w 2>/dev/null)
        local jira_base_url=$(security find-generic-password -a "$USER" -s "JIRA_BASE_URL" -w 2>/dev/null)
        
        if [ ! -z "$jira_api_key" ] && [ ! -z "$jira_email" ] && [ ! -z "$jira_base_url" ]; then
          echo -e "${BLUE}📝 Posting PR link to Jira ticket $ticket_id...${NC}"
          
          # Create ADF format comment with PR link
          local adf_body=$(jq -n \
            --arg pr_link_text "$current_branch → $base_branch" \
            --arg pr_url "$pr_url" \
            --arg commit_sha "$commit_sha" \
            --arg commit_msg "$commit_msg" \
            '{
              version: 1,
              type: "doc",
              content: [
                {
                  type: "heading",
                  attrs: {level: 2},
                  content: [{type: "text", text: "Pull Request Created", marks: [{type: "strong"}]}]
                },
                {
                  type: "paragraph",
                  content: [
                    {type: "text", text: "✅ Pull Request: "},
                    {type: "text", text: $pr_link_text, marks: [{type: "link", attrs: {href: $pr_url}}}]
                  ]
                }] + (if ($commit_sha != "") then [
                {
                  type: "paragraph",
                  content: [
                    {type: "text", text: "Latest Commit: ", marks: [{type: "code"}]},
                    {type: "text", text: $commit_sha}
                  ]
                },
                {
                  type: "paragraph",
                  content: [{type: "text", text: $commit_msg}]
                }
                ] else [] end)
            }')
          
          # Post comment to Jira
          local response=$(curl -s -X POST \
            "${jira_base_url}/rest/api/3/issue/${ticket_id}/comment" \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            -u "${jira_email}:${jira_api_key}" \
            -d "{\"body\": $adf_body}" 2>&1)
          
          if echo "$response" | jq -e '.id' &>/dev/null 2>&1; then
            echo -e "${GREEN}✓ Jira ticket $ticket_id updated with PR link${NC}"
            echo -e "${BLUE}🔗 View ticket: ${jira_base_url}/browse/${ticket_id}${NC}"
          else
            echo -e "${YELLOW}⚠️  Could not update Jira ticket${NC}"
            if echo "$response" | grep -qi "unauthorized\|401"; then
              echo -e "${YELLOW}   Authentication failed. Check your Jira credentials.${NC}"
            fi
          fi
        else
          echo -e "${YELLOW}⚠️  Jira credentials not configured. Skipping Jira update.${NC}"
        fi
      fi
    fi
  else
    echo "❌ Failed to create PR"
  fi
  
  # Restore stashed changes if any
  if [ "$stashed" = true ]; then
    echo ""
    echo "📦 Restoring stashed changes..."
    git stash pop 2>/dev/null || echo "⚠️  Note: Some stashed changes may have conflicts"
  fi
}
