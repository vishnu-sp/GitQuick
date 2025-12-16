#!/bin/bash

# Jira Debug Tool
# Helps troubleshoot Jira API issues

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load credentials
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

load_jira_credentials

echo -e "${BLUE}🔍 Jira Debug Information${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Configuration:${NC}"
echo "Email: ${JIRA_EMAIL:0:20}..."
echo "Base URL: $JIRA_BASE_URL"
echo "API Key: ${JIRA_API_KEY:0:10}...${JIRA_API_KEY: -5}"
echo ""

# Test authentication
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Testing Authentication...${NC}"
auth_response=$(curl -s -w "\n%{http_code}" \
    "${JIRA_BASE_URL}/rest/api/3/myself" \
    -H "Content-Type: application/json" \
    -u "${JIRA_EMAIL}:${JIRA_API_KEY}")

http_code=$(echo "$auth_response" | tail -1)
response_body=$(echo "$auth_response" | sed '$d')

if [ "$http_code" = "200" ]; then
    echo -e "${GREEN}✓ Authentication successful${NC}"
    echo "User: $(echo "$response_body" | jq -r '.displayName // .name // "Unknown"')"
else
    echo -e "${RED}✗ Authentication failed (HTTP $http_code)${NC}"
    echo "Response: $response_body"
    exit 1
fi
echo ""

# List all accessible projects
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Accessible Projects:${NC}"
projects_response=$(curl -s -w "\n%{http_code}" \
    "${JIRA_BASE_URL}/rest/api/3/project/search?maxResults=50" \
    -H "Content-Type: application/json" \
    -u "${JIRA_EMAIL}:${JIRA_API_KEY}")

http_code=$(echo "$projects_response" | tail -1)
response_body=$(echo "$projects_response" | sed '$d')

if [ "$http_code" = "200" ]; then
    project_count=$(echo "$response_body" | jq -r '.total // 0')
    echo -e "${GREEN}✓ Found $project_count projects${NC}"
    echo ""
    echo "$response_body" | jq -r '.values[] | "  \(.key) - \(.name) (\(.projectTypeKey))"'
else
    echo -e "${RED}✗ Failed to list projects (HTTP $http_code)${NC}"
    echo "Response: $response_body"
fi
echo ""

# Test specific project
if [ ! -z "$1" ]; then
    PROJECT_KEY="$1"
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Testing Project: $PROJECT_KEY${NC}"
    
    # Search for issues
    jql="project = $PROJECT_KEY ORDER BY updated DESC"
    encoded_jql=$(echo "$jql" | jq -sRr @uri)
    
    echo "JQL Query: $jql"
    echo ""
    
    issues_response=$(curl -s -w "\n%{http_code}" \
        "${JIRA_BASE_URL}/rest/api/3/search?jql=${encoded_jql}&maxResults=10&fields=summary,status,issuetype,updated" \
        -H "Content-Type: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}")
    
    http_code=$(echo "$issues_response" | tail -1)
    response_body=$(echo "$issues_response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        total=$(echo "$response_body" | jq -r '.total // 0')
        echo -e "${GREEN}✓ Query successful${NC}"
        echo "Total issues found: $total"
        
        if [ "$total" -gt 0 ]; then
            echo ""
            echo -e "${YELLOW}Recent Issues:${NC}"
            echo "$response_body" | jq -r '.issues[] | "  \(.key) - \(.fields.summary) [\(.fields.status.name)]"'
        else
            echo ""
            echo -e "${YELLOW}No issues found in $PROJECT_KEY${NC}"
            echo ""
            echo -e "${BLUE}Possible reasons:${NC}"
            echo "  1. Project has no issues"
            echo "  2. All issues are in a status you can't see"
            echo "  3. Project key might be wrong (case-sensitive)"
            echo ""
            echo -e "${BLUE}Try:${NC}"
            echo "  - Check project key in Jira web UI"
            echo "  - Verify you have permission to view issues"
            echo "  - Check if project has any issues at all"
        fi
    else
        echo -e "${RED}✗ Query failed (HTTP $http_code)${NC}"
        echo "Response: $response_body"
        
        if echo "$response_body" | grep -qi "does not exist\|could not be found"; then
            echo ""
            echo -e "${YELLOW}Project '$PROJECT_KEY' not found${NC}"
            echo "Check the project key is correct (case-sensitive)"
        fi
    fi
    echo ""
    
    # Try alternative JQL
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}Trying Alternative Query...${NC}"
    
    jql="project = \"$PROJECT_KEY\""
    encoded_jql=$(echo "$jql" | jq -sRr @uri)
    echo "JQL: $jql"
    
    alt_response=$(curl -s -w "\n%{http_code}" \
        "${JIRA_BASE_URL}/rest/api/3/search?jql=${encoded_jql}&maxResults=5" \
        -H "Content-Type: application/json" \
        -u "${JIRA_EMAIL}:${JIRA_API_KEY}")
    
    http_code=$(echo "$alt_response" | tail -1)
    response_body=$(echo "$alt_response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        total=$(echo "$response_body" | jq -r '.total // 0')
        echo -e "${GREEN}Found $total issues${NC}"
    fi
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Usage:${NC}"
echo "  jira-debug              - Check authentication and list projects"
echo "  jira-debug PROJECT-KEY  - Debug specific project"
echo ""
