#!/bin/bash

# View API Keys stored in macOS Keychain

echo "🔍 Searching for API keys in Keychain..."
echo ""

# List all generic passwords for current user
echo "All stored API keys for user '$USER':"
echo "======================================"
security dump-keychain 2>/dev/null | grep -A 3 "keychain: " | grep -B 1 -A 2 "acct\|svce" | grep -E "acct|svce" | sort -u | while read line; do
    if echo "$line" | grep -q "acct"; then
        account=$(echo "$line" | sed 's/.*"acct"<blob>="\(.*\)".*/\1/')
        echo "  Account: $account"
    elif echo "$line" | grep -q "svce"; then
        service=$(echo "$line" | sed 's/.*"svce"<blob>="\(.*\)".*/\1/')
        echo "  Service: $service"
        echo ""
    fi
done

echo ""
echo "Searching for common API key names..."
echo "======================================"

for key_name in "CURSOR_API_KEY" "OPENAI_API_KEY" "ANTHROPIC_API_KEY" "GEMINI_API_KEY"; do
    if security find-generic-password -a "$USER" -s "$key_name" &>/dev/null; then
        echo "✓ Found: $key_name"
        # Try to get the value (will prompt for password if needed)
        value=$(security find-generic-password -a "$USER" -s "$key_name" -w 2>/dev/null)
        if [ ! -z "$value" ]; then
            echo "  Value: ${value:0:10}...${value: -4} (hidden)"
        fi
    else
        echo "✗ Not found: $key_name"
    fi
    echo ""
done

echo ""
echo "💡 To view in Keychain Access UI:"
echo "  1. Open 'Keychain Access' app"
echo "  2. Select 'login' keychain (or 'Local Items')"
echo "  3. Search for: CURSOR_API_KEY"
echo "  4. Double-click to view details"
echo ""
echo "💡 To list all items:"
echo "  security dump-keychain | grep -A 5 'acct'"
