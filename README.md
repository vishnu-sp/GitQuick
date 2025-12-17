# git-jira-ai

> AI-powered git commit message generator with seamless Jira integration

[![npm version](https://img.shields.io/npm/v/git-jira-ai.svg)](https://www.npmjs.com/package/git-jira-ai)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Node.js Version](https://img.shields.io/badge/node-%3E%3D14.0.0-brightgreen.svg)](https://nodejs.org/)

Generate perfect conventional commit messages using AI and automatically update Jira tickets - all from your terminal.

## Features

- 🤖 **AI-Powered Commits** - Analyzes your code changes and generates conventional commit messages
- 🎫 **Advanced Jira Integration** - Comprehensive ticket management with field updates, assignee changes, and user tagging
- 📝 **AI-Generated Technical Summaries** - Automatically creates detailed, conversational comments explaining your changes
- 🔧 **Custom Field Configuration** - Update any Jira custom field (story points, estimates, time tracking, etc.)
- 👥 **User Tagging & Assignment** - Tag team members in comments and update ticket assignees
- 🌿 **Smart Branch Management** - Create branches from Jira tickets with intelligent naming
- ⚡ **One-Command Workflows** - Commit, push, and update Jira in a single command
- 🔐 **Secure Storage** - Uses platform-native secure storage (macOS Keychain, Windows Credential Manager, Linux Secret Service)

## Installation

```bash
npm install -g git-jira-ai
```

## Quick Start

### 1. Initialize

```bash
gq init
```

This will guide you through:

- Setting up AI provider (OpenAI, Claude, or Cursor)
- Configuring Jira credentials
- Selecting your Jira instance and project

### 2. Start Using

```bash
# Commit with AI
gq commit

# Commit and push with Jira update
gq cp

# Create branch from ticket
gq branch DH-1234
```

## Usage

### Git Commands

```bash
gq                    # Show help (default)
gq commit [TICKET]    # Commit with AI (optional ticket ID)
gq cp [TICKET]        # Commit, push & update Jira
gq push               # Push current branch
gq pull               # Pull latest changes
gq pr [base]          # Create pull request
gq status             # Show git status
```

### Branch Commands

```bash
gq branch TICKET-ID           # Create branch from ticket (auto-detects type)
gq branch TYPE TICKET-ID       # Create typed branch (feature/bugfix/hotfix)
gq branch TYPE NAME            # Create branch without ticket
```

### Jira Commands

```bash
gq jira select                 # Select instance + project
gq jira list [PROJECT]         # List tickets in project
gq jira current                 # Show current configuration
gq jira add NAME URL           # Add new Jira instance
gq jira instances              # List all instances
gq jira find-field "term"      # Find custom field IDs
gq jira set-field NAME ID      # Configure custom field mapping
gq jira list-fields            # Show configured custom fields
gq jira help                   # Show Jira help
```

### Configuration

```bash
gq init                        # First-time setup
gq update                      # Update API keys and credentials
gq config                      # Show current configuration
gq help                        # Show detailed help
```

## Examples

### Daily Workflow

```bash
# Create branch from ticket
gq branch DH-1234

# Make your changes...
git add .

# Commit, push, and update Jira in one command
gq cp DH-1234
```

### Browse Tickets

```bash
# List tickets in default project
gq jira list

# List tickets in specific project
gq jira list PROJECT-KEY
```

### Advanced Jira Features

**Custom Field Updates**

```bash
# Find any custom field ID
gq jira find-field "estimate"
gq jira find-field "story points"

# Configure field mapping
gq jira set-field "Story Points" customfield_12345
gq jira set-field "Time Tracking" customfield_10633

# When committing, custom fields are automatically updated
gq cp DH-1234  # Updates configured fields automatically
```

**User Tagging & Assignment**

```bash
# When committing with --will-push, you'll be prompted to:
# - Tag users in comments (@username mentions)
# - Update ticket assignee
# - Add detailed technical summary

gq cp DH-1234
# Interactive prompts for:
# ✓ Tag team members in comment
# ✓ Change assignee
# ✓ Add technical summary
```

**AI-Generated Technical Summaries**

```bash
# Automatically generates detailed, conversational comments:
# - Explains what was changed and why
# - Includes commit links
# - Provides testing instructions
# - Mentions edge cases and considerations

gq cp DH-1234
# Creates comment like:
# "Hey team, just finished up the authentication task.
#  The issue was that users were getting logged out randomly..."
```

## Requirements

- **Node.js** 14.0.0 or higher
- **Git** (obviously!)
- **macOS, Linux, or Windows**
- **One of the following AI providers:**
  - OpenAI API key
  - Anthropic (Claude) API key
  - Cursor CLI (installed via `cursor-agent login`)

## Configuration

### AI Provider

Choose one AI provider:

**OpenAI**

```bash
gq update
# Select OpenAI and enter your API key
```

**Claude (Anthropic)**

```bash
gq update
# Select Claude and enter your API key
```

**Cursor**

```bash
# Install Cursor CLI first
cursor-agent login
# Then use gq - it will automatically detect Cursor
```

### Jira Setup

1. Get your Jira API token: https://id.atlassian.com/manage-profile/security/api-tokens
2. Run `gq update` to configure credentials
3. Run `gq jira select` to choose instance and project

### Secure Storage

GitQuick automatically uses platform-native secure storage:

- **macOS**: Keychain
- **Windows**: Credential Manager
- **Linux**: Secret Service (libsecret)

API keys are stored securely and never exposed in plain text.

## Troubleshooting

### Command not found

After installation, ensure npm global bin is in your PATH:

```bash
# Add to ~/.zshrc or ~/.bashrc
export PATH="$HOME/.npm-global/bin:$PATH"
```

Then restart your terminal or run `source ~/.zshrc`.

### jq not found

The package includes bundled jq binaries. If you see this error:

```bash
npm uninstall -g git-jira-ai
npm install -g git-jira-ai
```

### Jira updates not working

1. Check credentials: `gq config`
2. Verify Jira instance: `gq jira current`
3. Test API access: `gq jira list`

### AI not generating commits

1. Verify API keys: `gq config`
2. Check API key is set: `gq update`
3. Ensure you have staged changes: `git status`

## How It Works

1. **AI Analysis**: Analyzes your `git diff` to understand actual code changes
2. **Commit Generation**: Creates conventional commit messages following best practices
3. **Jira Sync**: Automatically updates tickets with:
   - Commit links and commit details
   - AI-generated technical summaries (conversational, detailed comments)
   - Custom field updates (story points, estimates, time tracking, etc.)
   - User tagging (@mentions in comments)
   - Assignee updates
   - Status transitions
4. **Smart Detection**: Extracts ticket IDs from branch names and commit messages
5. **Interactive Workflow**: Prompts for field updates, assignee changes, and user tagging during commit

## License

MIT

## Support

For issues, feature requests, or questions:

- Open an issue on [GitHub](https://github.com/vishnu-sp/GitQuick/issues)
- Check the [documentation](https://github.com/vishnu-sp/GitQuick#readme)

---

**Made with ❤️ for developers who want to focus on code, not paper works**
