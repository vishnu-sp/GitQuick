#!/bin/bash

# Install Cursor CLI for automated commit message generation

echo "🎨 Installing Cursor CLI..."
echo ""

# Check if already installed
if command -v cursor-agent &> /dev/null; then
    echo "✓ Cursor CLI is already installed!"
    cursor-agent --version
    exit 0
fi

# Install Cursor CLI
echo "Downloading and installing Cursor CLI..."
curl https://cursor.com/install -fsS | bash

# Check if installation was successful
if command -v cursor-agent &> /dev/null; then
    echo ""
    echo "✅ Cursor CLI installed successfully!"
    echo ""
    echo "You can now use git-ai without API keys - it will automatically use Cursor AI!"
    echo ""
    echo "Try it:"
    echo "  git add -A"
    echo "  git-ai"
else
    echo ""
    echo "⚠️  Installation may have completed, but cursor-agent not found in PATH"
    echo ""
    echo "Please add Cursor CLI to your PATH:"
    echo "  export PATH=\"\$PATH:\$HOME/.local/bin\""
    echo ""
    echo "Or add to your ~/.zshrc:"
    echo "  echo 'export PATH=\"\$PATH:\$HOME/.local/bin\"' >> ~/.zshrc"
    echo "  source ~/.zshrc"
fi
