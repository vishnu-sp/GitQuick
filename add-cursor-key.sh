#!/bin/bash

# Helper script to add CURSOR_API_KEY to Keychain properly

echo "🔐 Add CURSOR_API_KEY to macOS Keychain"
echo "========================================"
echo ""

# Check if already exists
if security find-generic-password -a "$USER" -s "CURSOR_API_KEY" &>/dev/null; then
    echo "⚠️  CURSOR_API_KEY already exists in Keychain"
    read -p "Do you want to update it? (y/N): " update
    if [[ ! "$update" =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
    security delete-generic-password -a "$USER" -s "CURSOR_API_KEY" 2>/dev/null
fi

echo ""
read -sp "Enter your CURSOR_API_KEY (hidden): " api_key
echo ""

if [ -z "$api_key" ]; then
    echo "❌ No key provided"
    exit 1
fi

# Store in Keychain
security add-generic-password \
    -a "$USER" \
    -s "CURSOR_API_KEY" \
    -w "$api_key" \
    -U \
    -T /usr/bin/security \
    -D "Cursor API Key for git-ai automation"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Successfully stored in Keychain!"
    echo ""
    echo "To view in Keychain Access:"
    echo "  1. Open 'Keychain Access' app (Cmd+Space, type 'Keychain')"
    echo "  2. Select 'login' keychain in sidebar"
    echo "  3. Search for: CURSOR_API_KEY"
    echo "  4. Double-click to view"
    echo "  5. Check 'Show password' to see the value"
    echo ""
    echo "The key is now available for git-ai!"
else
    echo "❌ Failed to store key"
    exit 1
fi
