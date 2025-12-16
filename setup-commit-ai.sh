#!/bin/bash

# Setup script for AI-powered commit message generation
# This helps configure API keys for OpenAI or Anthropic

echo "🤖 AI Commit Message Generator Setup"
echo "======================================"
echo ""
echo "This tool can generate commit messages using:"
echo "1. OpenAI API (GPT models)"
echo "2. Anthropic API (Claude models)"
echo "3. Rule-based fallback (no API key needed)"
echo ""

# Check for existing API keys
if [ ! -z "$OPENAI_API_KEY" ]; then
    echo "✓ OPENAI_API_KEY is already set"
else
    echo "✗ OPENAI_API_KEY is not set"
fi

if [ ! -z "$ANTHROPIC_API_KEY" ]; then
    echo "✓ ANTHROPIC_API_KEY is already set"
else
    echo "✗ ANTHROPIC_API_KEY is not set"
fi

echo ""
read "?Do you want to set up an API key now? (y/N): " setup

if [[ ! "$setup" =~ ^[Yy]$ ]]; then
    echo "Skipping setup. You can set API keys manually:"
    echo "  export OPENAI_API_KEY='your-key-here'"
    echo "  export ANTHROPIC_API_KEY='your-key-here'"
    echo ""
    echo "Add these to your ~/.zshrc to make them permanent."
    exit 0
fi

echo ""
echo "Which API would you like to use?"
echo "1. OpenAI (GPT-4, GPT-3.5)"
echo "2. Anthropic (Claude)"
echo "3. Skip (use rule-based only)"
read "?Choice (1-3): " choice

case "$choice" in
    1)
        echo ""
        read "?Enter your OpenAI API key: " api_key
        if [ ! -z "$api_key" ]; then
            # Add to .zshrc
            if ! grep -q "OPENAI_API_KEY" ~/.zshrc; then
                echo "" >> ~/.zshrc
                echo "# OpenAI API for git commit generation" >> ~/.zshrc
                echo "export OPENAI_API_KEY='$api_key'" >> ~/.zshrc
                echo "✓ Added OPENAI_API_KEY to ~/.zshrc"
            else
                echo "⚠️  OPENAI_API_KEY already exists in ~/.zshrc"
            fi
            export OPENAI_API_KEY="$api_key"
            echo "✓ API key set for this session"
        fi
        ;;
    2)
        echo ""
        read "?Enter your Anthropic API key: " api_key
        if [ ! -z "$api_key" ]; then
            # Add to .zshrc
            if ! grep -q "ANTHROPIC_API_KEY" ~/.zshrc; then
                echo "" >> ~/.zshrc
                echo "# Anthropic API for git commit generation" >> ~/.zshrc
                echo "export ANTHROPIC_API_KEY='$api_key'" >> ~/.zshrc
                echo "✓ Added ANTHROPIC_API_KEY to ~/.zshrc"
            else
                echo "⚠️  ANTHROPIC_API_KEY already exists in ~/.zshrc"
            fi
            export ANTHROPIC_API_KEY="$api_key"
            echo "✓ API key set for this session"
        fi
        ;;
    *)
        echo "Skipping API setup. Using rule-based generation only."
        ;;
esac

echo ""
echo "✅ Setup complete!"
echo ""
echo "Usage:"
echo "  git-ai      - Generate commit message with AI"
echo "  git-aip     - Generate commit message and push"
echo ""
echo "Note: Run 'source ~/.zshrc' or restart your terminal to load API keys."
