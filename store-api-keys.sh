#!/bin/bash

# Secure API Key Storage Helper
# Provides multiple options for storing API keys securely

echo "🔐 Secure API Key Storage Options"
echo "=================================="
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
echo "Choose a storage method:"
echo ""
echo "1. macOS Keychain (Recommended - Most Secure)"
echo "2. SOPS encrypted file (You already use SOPS)"
echo "3. Environment file with restricted permissions"
echo "4. Setup Jira Integration (for automatic ticket updates)"
echo "5. Show current setup"
read -p "Choice (1-5): " choice

case "$choice" in
    1)
        echo ""
        echo "📦 macOS Keychain Storage"
        echo "========================="
        echo ""
        read -p "Enter CURSOR_API_KEY: " api_key
        
        if [ ! -z "$api_key" ]; then
            # Store in macOS Keychain
            security add-generic-password \
                -a "$USER" \
                -s "CURSOR_API_KEY" \
                -w "$api_key" \
                -U \
                -T /usr/bin/security
            
            echo ""
            echo "✅ Stored in macOS Keychain!"
            echo ""
            echo "Add this to your ~/.zshrc to load it automatically:"
            echo ""
            echo "# Load CURSOR_API_KEY from Keychain"
            echo "export CURSOR_API_KEY=\$(security find-generic-password -a \"\$USER\" -s \"CURSOR_API_KEY\" -w 2>/dev/null)"
            echo ""
        fi
        ;;
    2)
        echo ""
        echo "🔒 SOPS Encrypted Storage"
        echo "========================="
        echo ""
        
        # Check if SOPS is available
        if ! command -v sops &> /dev/null; then
            echo "❌ SOPS is not installed"
            echo "Install with: brew install sops"
            exit 1
        fi
        
        # Check for SOPS key
        if [ -z "$SOPS_AGE_KEY_FILE" ]; then
            echo "⚠️  SOPS_AGE_KEY_FILE not set"
            echo "Set it in your ~/.zshrc:"
            echo "  export SOPS_AGE_KEY_FILE=/path/to/age-key.txt"
            exit 1
        fi
        
        read -p "Enter CURSOR_API_KEY: " api_key
        
        if [ ! -z "$api_key" ]; then
            # Create or update encrypted file
            SECRETS_FILE="$HOME/Documents/secrets/api-keys.yaml"
            
            if [ -f "$SECRETS_FILE" ]; then
                # Update existing file
                sops --set "[\"CURSOR_API_KEY\"] \"$api_key\"" "$SECRETS_FILE"
            else
                # Create new file
                echo "CURSOR_API_KEY: \"$api_key\"" | sops --encrypt /dev/stdin > "$SECRETS_FILE"
            fi
            
            echo ""
            echo "✅ Encrypted and stored in: $SECRETS_FILE"
            echo ""
            echo "Add this to your ~/.zshrc to load it:"
            echo ""
            echo "# Load API keys from SOPS"
            echo "if [ -f \"$SECRETS_FILE\" ]; then"
            echo "  export CURSOR_API_KEY=\$(sops --decrypt --extract '[\"CURSOR_API_KEY\"]' \"$SECRETS_FILE\")"
            echo "fi"
            echo ""
        fi
        ;;
    3)
        echo ""
        echo "📄 Environment File Storage"
        echo "==========================="
        echo ""
        
        ENV_FILE="$HOME/.env.api-keys"
        
        read -p "Enter CURSOR_API_KEY: " api_key
        
        if [ ! -z "$api_key" ]; then
            # Create or update .env file
            if [ -f "$ENV_FILE" ]; then
                # Update existing
                if grep -q "^CURSOR_API_KEY=" "$ENV_FILE"; then
                    sed -i '' "s|^CURSOR_API_KEY=.*|CURSOR_API_KEY='$api_key'|" "$ENV_FILE"
                else
                    echo "CURSOR_API_KEY='$api_key'" >> "$ENV_FILE"
                fi
            else
                echo "CURSOR_API_KEY='$api_key'" > "$ENV_FILE"
            fi
            
            # Set restrictive permissions
            chmod 600 "$ENV_FILE"
            
            echo ""
            echo "✅ Stored in: $ENV_FILE (permissions: 600)"
            echo ""
            echo "Add this to your ~/.zshrc to load it:"
            echo ""
            echo "# Load API keys from secure file"
            echo "if [ -f \"$ENV_FILE\" ]; then"
            echo "  source \"$ENV_FILE\""
            echo "fi"
            echo ""
        fi
        ;;
    4)
        echo ""
        echo "🎫 Jira Integration Setup"
        echo "========================="
        echo ""
        echo "This will configure automatic Jira ticket updates after commits."
        echo ""
        echo "Prerequisites:"
        echo "  1. Jira account with API access"
        echo "  2. jq installed (brew install jq)"
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
            echo ""
            echo "Choose storage method:"
            echo "  1. macOS Keychain (Recommended)"
            echo "  2. SOPS encrypted file"
            echo "  3. Environment file"
            read -p "Choice (1-3): " jira_storage_choice
            
            case "$jira_storage_choice" in
                1)
                    # Store in Keychain
                    security add-generic-password -a "$USER" -s "JIRA_API_KEY" -w "$jira_api_key" -U
                    security add-generic-password -a "$USER" -s "JIRA_EMAIL" -w "$jira_email" -U
                    security add-generic-password -a "$USER" -s "JIRA_BASE_URL" -w "$jira_base_url" -U
                    
                    echo ""
                    echo "✅ Jira credentials stored in macOS Keychain!"
                    echo ""
                    echo "The git-ai script will automatically load these credentials."
                    echo ""
                    echo "To test, commit with a branch named: feature/PROJ-123-description"
                    echo "Or include ticket ID in commit message: feat: PROJ-123 add feature"
                    echo ""
                    ;;
                2)
                    # Store in SOPS
                    if ! command -v sops &> /dev/null; then
                        echo "❌ SOPS is not installed. Install with: brew install sops"
                        exit 1
                    fi
                    
                    SECRETS_FILE="$HOME/Documents/secrets/api-keys.yaml"
                    
                    if [ -f "$SECRETS_FILE" ]; then
                        sops --set "[\"JIRA_API_KEY\"] \"$jira_api_key\"" "$SECRETS_FILE"
                        sops --set "[\"JIRA_EMAIL\"] \"$jira_email\"" "$SECRETS_FILE"
                        sops --set "[\"JIRA_BASE_URL\"] \"$jira_base_url\"" "$SECRETS_FILE"
                    else
                        echo -e "JIRA_API_KEY: \"$jira_api_key\"\nJIRA_EMAIL: \"$jira_email\"\nJIRA_BASE_URL: \"$jira_base_url\"" | sops --encrypt /dev/stdin > "$SECRETS_FILE"
                    fi
                    
                    echo ""
                    echo "✅ Jira credentials encrypted and stored in SOPS!"
                    echo ""
                    ;;
                3)
                    # Store in env file
                    ENV_FILE="$HOME/.env.api-keys"
                    
                    # Add or update credentials
                    for key_value in "JIRA_API_KEY='$jira_api_key'" "JIRA_EMAIL='$jira_email'" "JIRA_BASE_URL='$jira_base_url'"; do
                        key=$(echo "$key_value" | cut -d'=' -f1)
                        if [ -f "$ENV_FILE" ] && grep -q "^$key=" "$ENV_FILE"; then
                            sed -i '' "s|^$key=.*|$key_value|" "$ENV_FILE"
                        else
                            echo "$key_value" >> "$ENV_FILE"
                        fi
                    done
                    
                    chmod 600 "$ENV_FILE"
                    
                    echo ""
                    echo "✅ Jira credentials stored in: $ENV_FILE"
                    echo ""
                    ;;
                *)
                    echo "Invalid choice"
                    exit 1
                    ;;
            esac
            
            echo "📚 For more information, see: automation/JIRA_INTEGRATION.md"
        else
            echo "❌ All fields are required"
            exit 1
        fi
        ;;
    5)
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
        echo ""
        echo "SOPS files:"
        ls -lh "$HOME/Documents/secrets/"*.yaml 2>/dev/null || echo "  None found"
        ;;
    *)
        echo "Invalid choice"
        exit 1
        ;;
esac
