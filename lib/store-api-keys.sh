#!/bin/bash

# Secure API Key Storage Helper
# Automatically detects OS and uses platform-native secure storage

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

# Store API key in Linux Secret Service (libsecret)
store_key_linux() {
    local key_name="$1"
    local key_value="$2"
    
    if command -v secret-tool &> /dev/null; then
        echo "$key_value" | secret-tool store --label="git-jira-ai ${key_name}" api-key "$key_name" value "$key_value" 2>/dev/null
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
            echo "macOS Keychain"
            ;;
        windows)
            store_key_windows "$key_name" "$key_value"
            echo "Windows Credential Manager"
            ;;
        linux)
            store_key_linux "$key_name" "$key_value"
            echo "Linux Secret Service"
            ;;
        *)
            return 1
            ;;
    esac
}

echo "🔐 Secure API Key Storage"
echo "========================="
echo ""

# Check what's already configured
if [ ! -z "$CURSOR_API_KEY" ]; then
    echo "✓ CURSOR_API_KEY is currently set"
else
    echo "✗ CURSOR_API_KEY is not set"
fi

if [ ! -z "$OPENAI_API_KEY" ]; then
    echo "✓ OPENAI_API_KEY is currently set"
else
    echo "✗ OPENAI_API_KEY is not set"
fi

if [ ! -z "$ANTHROPIC_API_KEY" ]; then
    echo "✓ ANTHROPIC_API_KEY is currently set"
else
    echo "✗ ANTHROPIC_API_KEY is not set"
fi

# Check Jira credentials
JIRA_CHECK=$(security find-generic-password -a "$USER" -s "JIRA_API_KEY" -w 2>/dev/null)
if [ ! -z "$JIRA_CHECK" ] || [ ! -z "$JIRA_API_KEY" ]; then
    echo "✓ JIRA_API_KEY is currently set"
else
    echo "✗ JIRA_API_KEY is not set"
fi

echo ""
echo "What would you like to configure?"
echo ""
echo "1. Store AI Provider API Key (Cursor/OpenAI/Anthropic)"
echo "   → Choose storage: macOS Keychain or Environment file"
echo ""
echo "2. Setup Jira Integration"
echo "   → Configure Jira credentials for automatic ticket updates"
echo ""
echo "3. Show current setup"
echo "   → View all configured API keys and credentials"
echo ""
read -p "Choice (1-3): " choice

# Function to select AI provider
select_ai_provider() {
    echo ""
    echo "Select AI Provider:"
    echo ""
    echo "1. Cursor AI (CURSOR_API_KEY)"
    echo "2. OpenAI (OPENAI_API_KEY)"
    echo "3. Anthropic Claude (ANTHROPIC_API_KEY)"
    read -p "Choice (1-3): " provider_choice
    
    case "$provider_choice" in
        1)
            API_KEY_NAME="CURSOR_API_KEY"
            PROVIDER_NAME="Cursor AI"
            ;;
        2)
            API_KEY_NAME="OPENAI_API_KEY"
            PROVIDER_NAME="OpenAI"
            ;;
        3)
            API_KEY_NAME="ANTHROPIC_API_KEY"
            PROVIDER_NAME="Anthropic Claude"
            ;;
        *)
            echo "❌ Invalid choice"
            exit 1
            ;;
    esac
}

case "$choice" in
    1)
        # Store AI Provider API Key
        select_ai_provider
        
        local os=$(detect_os)
        local storage_name=""
        
        case "$os" in
            macos)
                storage_name="macOS Keychain"
                ;;
            windows)
                storage_name="Windows Credential Manager"
                ;;
            linux)
                storage_name="Linux Secret Service"
                ;;
            *)
                storage_name="Environment file"
                ;;
        esac
        
        echo ""
        echo "📦 Auto-detected: $storage_name"
        echo "================================"
        echo ""
        read -p "Enter ${API_KEY_NAME}: " api_key
        
        if [ ! -z "$api_key" ]; then
            local storage_type=$(store_api_key "$API_KEY_NAME" "$api_key")
            
            if [ $? -eq 0 ]; then
                echo ""
                echo "✅ Stored in $storage_type!"
                echo ""
                echo "The key will be automatically loaded when you use gq commands."
                echo ""
            else
                # Fallback to .env file if OS-specific storage fails
                echo ""
                echo "⚠️  Could not store in $storage_name, using .env file fallback"
                echo ""
                
                ENV_FILE="$HOME/.env.api-keys"
                
                # Create or update .env file
                if [ -f "$ENV_FILE" ]; then
                    # Update existing
                    if grep -q "^${API_KEY_NAME}=" "$ENV_FILE"; then
                        if [[ "$os" == "macos" ]]; then
                            sed -i '' "s|^${API_KEY_NAME}=.*|${API_KEY_NAME}='$api_key'|" "$ENV_FILE"
                        else
                            sed -i "s|^${API_KEY_NAME}=.*|${API_KEY_NAME}='$api_key'|" "$ENV_FILE"
                        fi
                    else
                        echo "${API_KEY_NAME}='$api_key'" >> "$ENV_FILE"
                    fi
                else
                    echo "${API_KEY_NAME}='$api_key'" > "$ENV_FILE"
                fi
                
                # Set restrictive permissions
                chmod 600 "$ENV_FILE"
                
                echo ""
                echo "✅ Stored in: $ENV_FILE (permissions: 600)"
                echo ""
            fi
        fi
        ;;
    2)
        echo ""
        echo "🎫 Jira Integration Setup"
        echo "========================="
        echo ""
        echo "This will configure automatic Jira ticket updates after commits."
        echo ""
        echo "Prerequisites:"
        echo "  1. Jira account with API access"
        echo "  2. jq installed (brew install jq) or bundled jq available"
        echo ""
        
        # Check if jq is installed
        if ! command -v jq &> /dev/null; then
            echo "❌ jq is not installed. Install with: brew install jq"
            exit 1
        fi
        
        echo "To get your Jira API token:"
        echo "  1. Go to: https://id.atlassian.com/manage-profile/security/api-tokens"
        echo "  2. Click 'Create API token'"
        echo "  3. Copy the generated token"
        echo ""
        
        read -p "Enter your Jira email: " jira_email
        read -p "Enter your Jira API token: " jira_api_key
        read -p "Enter your Jira base URL (e.g., https://company.atlassian.net): " jira_base_url
        
        # Remove trailing slash from URL if present
        jira_base_url="${jira_base_url%/}"
        
        if [ ! -z "$jira_email" ] && [ ! -z "$jira_api_key" ] && [ ! -z "$jira_base_url" ]; then
            local os=$(detect_os)
            local storage_name=""
            
            case "$os" in
                macos)
                    storage_name="macOS Keychain"
                    ;;
                windows)
                    storage_name="Windows Credential Manager"
                    ;;
                linux)
                    storage_name="Linux Secret Service"
                    ;;
                *)
                    storage_name="Environment file"
                    ;;
            esac
            
            echo ""
            echo "📦 Auto-detected: $storage_name"
            echo "================================"
            echo ""
            
            # Store credentials using OS-specific method
            local storage_type=$(store_api_key "JIRA_API_KEY" "$jira_api_key")
            store_api_key "JIRA_EMAIL" "$jira_email" >/dev/null
            store_api_key "JIRA_BASE_URL" "$jira_base_url" >/dev/null
            
            if [ $? -eq 0 ]; then
                echo ""
                echo "✅ Jira credentials stored in $storage_type!"
                echo ""
                echo "The git-ai script will automatically load these credentials."
                echo ""
                echo "To test, commit with a branch named: feature/PROJ-123-description"
                echo "Or include ticket ID in commit message: feat: PROJ-123 add feature"
                echo ""
            else
                # Fallback to .env file if OS-specific storage fails
                echo ""
                echo "⚠️  Could not store in $storage_name, using .env file fallback"
                echo ""
                
                ENV_FILE="$HOME/.env.api-keys"
                
                # Add or update credentials
                for key_value in "JIRA_API_KEY='$jira_api_key'" "JIRA_EMAIL='$jira_email'" "JIRA_BASE_URL='$jira_base_url'"; do
                    key=$(echo "$key_value" | cut -d'=' -f1)
                    if [ -f "$ENV_FILE" ] && grep -q "^$key=" "$ENV_FILE"; then
                        if [[ "$os" == "macos" ]]; then
                            sed -i '' "s|^$key=.*|$key_value|" "$ENV_FILE"
                        else
                            sed -i "s|^$key=.*|$key_value|" "$ENV_FILE"
                        fi
                    else
                        echo "$key_value" >> "$ENV_FILE"
                    fi
                done
                
                chmod 600 "$ENV_FILE"
                
                echo ""
                echo "✅ Jira credentials stored in: $ENV_FILE"
                echo ""
            fi
            
            echo "📚 For more information, see: automation/JIRA_INTEGRATION.md"
        else
            echo "❌ All fields are required"
            exit 1
        fi
        ;;
    3)
        echo ""
        echo "📋 Current Setup"
        echo "==============="
        echo ""
        echo "Environment variables:"
        env | grep -E "CURSOR_API_KEY|OPENAI_API_KEY|ANTHROPIC_API_KEY|JIRA_" | sed 's/=.*/=***HIDDEN***/'
        echo ""
        echo "Keychain items:"
        echo "  AI Keys:"
        security dump-keychain 2>/dev/null | grep -A 2 "CURSOR_API_KEY\|OPENAI_API_KEY\|ANTHROPIC_API_KEY" || echo "    None found"
        echo ""
        echo "  Jira Keys:"
        if security find-generic-password -a "$USER" -s "JIRA_API_KEY" 2>/dev/null; then
            echo "    ✓ JIRA_API_KEY found"
            echo "    ✓ JIRA_EMAIL: $(security find-generic-password -a "$USER" -s "JIRA_EMAIL" -w 2>/dev/null)"
            echo "    ✓ JIRA_BASE_URL: $(security find-generic-password -a "$USER" -s "JIRA_BASE_URL" -w 2>/dev/null)"
        else
            echo "    None found"
        fi
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
