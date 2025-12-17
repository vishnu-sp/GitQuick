# git-jira-ai

AI-powered git commit message generator with seamless Jira integration. Generate perfect conventional commits and automatically update Jira tickets - all from your terminal.

## Installation

```bash
npm install -g git-jira-ai
```

That's it! The `gq` command is now available globally.

## Quick Start

### 1. Configure API Keys

```bash
gq update
```

This will guide you through setting up:

- AI provider (OpenAI, Claude, or Cursor)
- Jira credentials

### 2. Setup Jira

```bash
gq jira select
```

Select your Jira instance and default project.

### 3. Start Using

```bash
# Commit with AI
gq

# Commit and push with Jira update
gq cp

# Commit with specific ticket
gq commit DH-1234

# Create branch from ticket
gq branch DH-1234
```

## Features

### 🤖 AI-Powered Commits

Generate perfect conventional commit messages using OpenAI, Claude, or Cursor AI. The AI analyzes your actual code changes - not just file names.

```bash
gq                    # Analyze staged changes and generate commit
gq commit DH-1234     # Commit with ticket ID
```

### 🎫 Seamless Jira Integration

- **Automatic ticket updates** - Push code and update Jira in one command
- **Branch creation from tickets** - `gq branch DH-1234` auto-creates `feature/DH-1234-ticket-summary`
- **Smart ticket extraction** - Automatically detects ticket IDs from branch names
- **Custom field support** - Track time, estimates, story points
- **Multi-instance support** - Switch between production, staging, client Jira instances

### 🌿 Smart Branch Management

```bash
gq branch DH-1234              # Auto-detects type, creates feature/DH-1234-implement-oauth
gq branch feature DH-1234      # Explicit type
gq branch bugfix login-fix     # Without Jira ticket
```

### 📤 One-Command Workflows

```bash
gq          # Commit with AI
gq cp       # Commit + Push + Update Jira
gq push     # Push + Update Jira
gq pr main  # Create PR and update Jira
```

## Commands

### Git Commands

- `gq` - Commit with AI (default)
- `gq commit [TICKET-ID]` - Commit with AI (optional ticket ID)
- `gq push` - Push current branch
- `gq pull` - Pull latest changes
- `gq cp [TICKET-ID]` - Commit and push with AI
- `gq pr [base-branch]` - Create pull request
- `gq status` - Show git status

### Branch Commands

- `gq branch TICKET-ID` - Create branch from ticket
- `gq branch TYPE TICKET` - Create typed branch (feature/bugfix/hotfix)
- `gq branch TYPE NAME` - Create branch without ticket

### Jira Commands

- `gq jira select` - Select instance + project
- `gq jira list [PROJECT]` - List tickets in project
- `gq jira add NAME URL` - Add new Jira instance
- `gq jira instances` - List all instances
- `gq jira remove NAME` - Remove instance
- `gq jira current` - Show current config
- `gq jira find-field "term"` - Find field IDs
- `gq jira set-field NAME ID` - Add/update field
- `gq jira remove-field NAME` - Remove field
- `gq jira list-fields` - Show configured fields

### Configuration

- `gq init` - Initialize and configure gq
- `gq update` - Update API keys and credentials
- `gq config` - Show current configuration
- `gq help` - Show help

## Examples

```bash
# First-time setup
gq init
gq jira select

# Daily workflow
gq branch DH-1234              # Create branch
# ... make changes ...
gq cp DH-1234                  # Commit, push, update Jira

# Browse tickets
gq jira list                   # List tickets in default project
gq jira list PROJECT-KEY       # List tickets in specific project

# Custom fields
gq jira find-field "estimate" # Find field ID
gq jira set-field "Story Points" customfield_12345
```

## Requirements

- Node.js 14+ (for installation)
- Git (obviously!)
- macOS or Linux
- One of: OpenAI API key, Anthropic API key, or Cursor CLI

## Configuration

### AI Providers

Choose one:

- **OpenAI** - Set `OPENAI_API_KEY` environment variable
- **Claude** - Set `ANTHROPIC_API_KEY` environment variable
- **Cursor** - Install Cursor CLI (`cursor-agent login`)

### Jira Setup

1. Get your Jira API token: https://id.atlassian.com/manage-profile/security/api-tokens
2. Run `gq update` to configure credentials
3. Run `gq jira select` to choose instance and project

## Troubleshooting

### jq not found

The package includes bundled jq binaries. If you see this error, try:

```bash
npm uninstall -g git-jira-ai
npm install -g git-jira-ai
```

### Command not found

After installation, make sure npm global bin is in your PATH:

```bash
# Add to ~/.zshrc or ~/.bashrc
export PATH="$HOME/.npm-global/bin:$PATH"
```

Then restart your terminal or run `source ~/.zshrc`.

### Jira updates not working

1. Check credentials: `gq config`
2. Verify Jira instance: `gq jira current`
3. Test API access: `gq jira list`

## License

MIT

## Support

For issues, feature requests, or questions, please open an issue on GitHub.
