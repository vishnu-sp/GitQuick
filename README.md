# GitQuick (gq) - AI-Powered Git Automation CLI

<div align="center">

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![macOS](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos)
[![GitHub stars](https://img.shields.io/github/stars/yourusername/gitquick?style=social)](https://github.com/yourusername/gitquick)

[Quick Start](#installation) • [Features](#features) • [Documentation](#quick-start) • [Contributing](.github/CONTRIBUTING.md)

<img src="docs/demo.gif" alt="GitQuick Demo" width="600">

</div>

---

## Why GitQuick Exists

I love coding, but I HATE:

- Context switching between terminal and browser
- Writing the same information twice (commit message + Jira updates)
- Remembering to update tickets
- Writing commit messages when I'm in flow state

---

## What GitQuick Does

⚡ **faster** - One command replaces 5 manual steps  
🤖 **Smarter commits** - AI analyzes your changes, not generic templates  
🎯 **Zero context switching** - Update Jira without leaving your terminal  
🔒 **Actually secure** - macOS Keychain, not plaintext files

### Before GitQuick

```bash
# Traditional workflow (5+ steps, 3+ minutes)
git add .
git commit -m "feat: implement oauth"  # manually written, often poorly worded
git push
# Switch to browser → Find Jira ticket → Write update → Click submit , add assigne , update time , tag testers
# Switch back to terminal...
```

### After GitQuick

```bash
# GitQuick workflow (1 command, 15 seconds)
gq cp  # Done. AI writes commit, pushes, updates Jira automatically
```

**The Difference:**

- ✅ AI-generated conventional commits from actual code changes
- ✅ Automatic Jira ticket updates with detailed summaries
- ✅ Branch creation with automatic naming from Jira tickets
- ✅ Complete workflow in a single command

---

## Features

### 🤖 AI-Powered Commit Messages

Generate perfect conventional commit messages using OpenAI, Claude, or Cursor AI. The AI analyzes your actual code changes - not just file names.

```bash
# AI analyzes your staged changes and generates:
# "feat(auth): implement OAuth 2.0 authentication with JWT tokens
#
# - Add OAuth2 provider configuration
# - Implement token refresh mechanism
# - Add secure session management"
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
```

### 🔐 Secure Credential Storage

- macOS Keychain integration (primary - automatically loads credentials)
- Environment file fallback (~/.env.api-keys with restricted permissions)
- Automatic credential loading - no manual export needed
- Never commits credentials to git

---

## Installation

### Prerequisites

- macOS (for Keychain support, optional)
- Git installed
- Bash or Zsh
- `jq` - JSON processor: `brew install jq` (required for Jira integration and AI features)
- Python 3 (for Jira integration)
- One AI provider: OpenAI, Anthropic (Claude), or Cursor (required for AI commit messages)
  - **For Cursor:** Also requires `cursor-agent` CLI - install with `./install-cursor-cli.sh`

### Quick Install

```bash
# 1. Clone the repository
git clone https://github.com/yourusername/gitquick.git
cd gitquick

# 2. Initialize gq (sets up shell configuration)
./git-cli.sh init
# This will:
# - Ask you to select shell config file (.zshrc or .bashrc)
# - Add gq function to your shell config
# - Automatically reload shell config (or show instructions)
# - Prompt to install cursor-agent if you prefer Cursor AI
# - Guide you through credential setup
```

**Important:**

- `./git-cli.sh init` is **required** to make the `gq` command available
- Shell config is automatically reloaded after setup (no manual `source` needed)
- You can choose which shell config file to use (.zshrc or .bashrc)
- Cursor CLI installation is offered automatically during init

---

## Quick Start

### First-Time Setup

**1. Initialize GitQuick**

```bash
./git-cli.sh init
# This will:
# 1. Ask you to select shell config file (.zshrc or .bashrc)
# 2. Add gq function to your shell config
# 3. Automatically reload shell config
# 4. Prompt to install cursor-agent (if you want Cursor AI)
# 5. Guide you through credential setup
```

**2. Configure AI Provider** (choose one)

During `gq init` or later with `gq update`:

```bash
gq update
# What would you like to configure?
# 1. Store AI Provider API Key
#    → Select provider: Cursor AI / OpenAI / Anthropic Claude
#    → Choose storage: macOS Keychain or Environment file
#    → Enter your API key
# 2. Setup Jira Integration
# 3. Show current setup
```

**AI Provider Options:**

- **Cursor AI**: Uses `cursor-agent` CLI (installed automatically during init if you choose)
- **OpenAI**: Requires API key (stored securely in Keychain or env file)
- **Anthropic Claude**: Requires API key (stored securely in Keychain or env file)

**Note:** API keys are automatically loaded from Keychain when you run `gq` commands - no need to export them manually!

**3. Configure Jira** (optional but recommended)

```bash
gq update
# Select option 2: Setup Jira Integration
# Enter:
# - Jira email
# - Jira API token (get from https://id.atlassian.com/manage-profile/security/api-tokens)
# - Jira base URL (e.g., https://company.atlassian.net)
# Choose storage: macOS Keychain (recommended) or Environment file

# Then select default project
gq jira select
```

### Complete Development Workflow

**Scenario:** Working on Jira ticket DH-1234

```bash
# 1. Browse available tickets
gq jira list
# Shows: DH-1234 [To Do] Story: Implement OAuth authentication

# 2. Create feature branch from ticket
gq branch DH-1234
# ✅ Fetches ticket details from Jira
# ✅ Auto-detects type (feature/bugfix/hotfix)
# ✅ Creates: feature/DH-1234-implement-oauth-authentication
# ✅ Ticket ID now in branch name!

# 3. Make your changes...
# (edit files, write code)

# 4. Stage and commit with AI
gq
# ✅ Auto-extracts DH-1234 from branch name
# ✅ AI analyzes your actual code changes
# ✅ Generates: "feat(auth): DH-1234 implement OAuth 2.0 authentication"
# ✅ Uses Jira ticket context for better message

# 5. Push and update Jira
gq push
# ✅ Auto-extracts DH-1234 from branch
# ✅ Pushes to remote
# ✅ Prompts: "Update Jira ticket DH-1234? (Y/n)"
# ✅ AI generates detailed comment with changes
# ✅ Optionally update time tracking, status, assignee

# 6. Create pull request
gq pr main
# ✅ Creates PR linked to Jira ticket
```

**Or do it all in one command:**

```bash
gq cp
# ✅ Commit with AI (using ticket context)
# ✅ Push to remote
# ✅ Update Jira ticket
# All in 15 seconds!
```

---

## Command Reference

### Git Commands

| Command                         | Description                 | Ticket ID                              |
| ------------------------------- | --------------------------- | -------------------------------------- |
| `gq` or `gq commit [TICKET-ID]` | Commit with AI              | Auto-extracted from branch or explicit |
| `gq cp [TICKET-ID]`             | Commit + Push + Update Jira | Auto-extracted or explicit             |
| `gq push`                       | Push + Update Jira          | Auto-extracted from branch             |
| `gq pull`                       | Pull latest changes         | N/A                                    |
| `gq pr [base-branch]`           | Create pull request         | Auto-linked if ticket in branch        |
| `gq status`                     | Show git status             | N/A                                    |

### Branch Commands

| Command                    | Description                                  |
| -------------------------- | -------------------------------------------- |
| `gq branch TICKET-ID`      | Create branch from Jira ticket (interactive) |
| `gq branch TYPE TICKET-ID` | Create typed branch from ticket              |
| `gq branch TYPE NAME`      | Create branch without ticket                 |

**Branch Types:** `feature`, `bugfix`, `hotfix`

### Jira Commands

| Command                  | Description                                    |
| ------------------------ | ---------------------------------------------- |
| `gq jira select`         | Select Jira instance and default project       |
| `gq jira list [PROJECT]` | List tickets (uses default project if omitted) |
| `gq jira current`        | Show current Jira configuration                |
| `gq jira add NAME URL`   | Add new Jira instance                          |
| `gq jira instances`      | List all configured instances                  |

### Configuration Commands

| Command     | Description                                                                                                       |
| ----------- | ----------------------------------------------------------------------------------------------------------------- |
| `gq init`   | Initial setup (selects shell config, installs cursor-agent if needed, configures credentials, auto-reloads shell) |
| `gq update` | Update API keys and credentials (auto-reloads shell config)                                                       |
| `gq config` | Show current configuration                                                                                        |
| `gq help`   | Show command reference                                                                                            |

---

## Smart Features

### Automatic Ticket ID Extraction

GitQuick automatically extracts ticket IDs from your branch names, so you rarely need to specify them explicitly.

**Supported formats:**

- `feature/DH-1234-description` → extracts `DH-1234`
- `bugfix/PROJ-456-fix` → extracts `PROJ-456`
- `DH-1234-simple` → extracts `DH-1234`
- `hotfix/TEAM-789` → extracts `TEAM-789`

**When it happens:**

| Command     | Auto-Extracts? | Can Override?                |
| ----------- | -------------- | ---------------------------- |
| `gq commit` | ✅ Yes         | ✅ Yes (`gq commit DH-1234`) |
| `gq cp`     | ✅ Yes         | ✅ Yes (`gq cp DH-1234`)     |
| `gq push`   | ✅ Yes         | ❌ No (always uses branch)   |

**Example:**

```bash
# You're in branch: feature/DH-1234-implement-auth

gq          # ✅ Uses DH-1234 automatically
gq cp       # ✅ Uses DH-1234 automatically
gq push     # ✅ Uses DH-1234 automatically

# Override if needed
gq commit DH-5678  # ✅ Uses DH-5678 instead
```

---

## Advanced Usage

### Multiple Jira Instances

Work across different Jira environments seamlessly:

```bash
# Add multiple instances
gq jira add production https://company.atlassian.net
gq jira add staging https://staging.atlassian.net
gq jira add client https://client.atlassian.net

# Switch between them
gq jira select
# Interactive menu to choose instance and project

# Browse without switching default
gq jira list CLIENT
```

### Time Tracking with Custom Fields

```bash
# 1. Configure custom fields
gq jira find-field "actual dev"
gq jira set-field "Actual Dev Efforts (hrs)" customfield_10634
gq jira set-field "Original Estimate (hrs)" customfield_10633

# 2. Set estimate when starting work
gq branch feature DH-1234
gq commit
gq push
# Prompted: "Update Original Estimate? Enter 8"

# 3. Update actual time when done
gq commit
gq push
# Prompted: "Update Actual Dev Efforts? Enter 6"
```

### Working Without Jira

GitQuick works perfectly even without Jira integration:

```bash
# Create branch without ticket
gq branch feature my-feature

# Commit with AI (no Jira context)
gq commit
# ✅ AI still analyzes your code changes
# ✅ Generates conventional commit messages
# ❌ No Jira integration (no ticket ID in branch)

# Push normally
gq push
# ✅ Simple push, no Jira prompts
```

---

## AI Providers

### Supported Providers

**OpenAI (GPT-4)**

- Best for: General purpose, balanced speed and quality
- Get API key: https://platform.openai.com/api-keys
- Cost: Pay-per-use (~$0.01-0.03 per commit)

**Anthropic (Claude)**

- Best for: Detailed analysis, comprehensive documentation
- Get API key: https://console.anthropic.com/
- Cost: Pay-per-use (~$0.01-0.03 per commit)

**Cursor AI**

- Best for: If you already use Cursor IDE
- Seamless integration with existing Cursor subscription
- **Prerequisites:** Requires `cursor-agent` CLI tool
  - **Automatically installed** during `gq init` if you choose Cursor AI
  - Or install manually: `./install-cursor-cli.sh` or `curl https://cursor.com/install -fsS | bash`
  - Authenticate: `cursor-agent login` OR set `CURSOR_API_KEY` in Keychain/env file
- Cost: Uses Cursor subscription credits (Free tier: limited)
- **Note:** API keys are automatically loaded from Keychain - no manual export needed!

### How AI is Used

**Commit Messages:**

- Analyzes `git diff` (staged changes)
- Considers file types, changes, additions, deletions
- Generates conventional commit format
- Includes Jira ticket context when available

**Jira Comments:**

- Analyzes commit history and code changes
- Generates detailed summaries with:
  - What was done
  - Technical implementation details
  - Business impact
  - Testing instructions

### Fallback Behavior

If AI is unavailable:

- Falls back to rule-based commit generation
- Analyzes file changes and patterns
- Still generates conventional commits
- Reduced quality but fully functional

---

## Security

### Credential Storage

**macOS Keychain** (Primary - Recommended)

- System-level encryption
- Requires macOS password to access
- Automatic security updates from Apple
- Credentials automatically loaded when running `gq` commands
- Best for: Individual developers on macOS

**Environment Files** (Fallback)

- Stored in `~/.env.api-keys` with restricted permissions (600)
- Local machine only
- Requires manual sourcing in shell config
- Best for: Development environments or when Keychain is not available

**Note:** SOPS is still supported as a fallback if you have existing SOPS setup, but it's no longer available in the interactive menu.

### What's Stored

- Jira API token, email, and base URL
- AI provider API keys (OpenAI/Claude/Cursor)
- All credentials automatically loaded when running `gq` commands

### Security Best Practices

✅ Rotate API tokens every 90 days  
✅ Use different tokens for different environments  
✅ Never share API tokens  
✅ Use Keychain on macOS  
✅ Review API token access regularly

---

## Troubleshooting

### Common Issues

**"Command not found: gq"**

```bash
# Solution: Reinitialize shell configuration
cd gitquick/automation
./git-cli.sh init
# Shell config is automatically reloaded, but if it doesn't work:
source ~/.zshrc  # or ~/.bashrc
```

**"Jira credentials not configured"**

```bash
# Solution: Configure Jira
gq update
# Select option 2: Setup Jira Integration, enter credentials
```

**"jq command not found"**

```bash
# Solution: Install jq
brew install jq
```

**AI commit generation fails**

```bash
# Check AI provider configuration
gq config

# Fallback still works with rule-based generation
```

### Getting Help

1. Check `gq help` for command reference
2. Run `gq config` to verify configuration
3. Visit our [Issues page](https://github.com/yourusername/gitquick/issues)
4. Join our [Discussions](https://github.com/yourusername/gitquick/discussions)

---

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](.github/CONTRIBUTING.md) for guidelines.

**Ways to contribute:**

- 🐛 Report bugs
- 💡 Suggest features
- 📖 Improve documentation
- 🔧 Submit pull requests
- ⭐ Star the repository

---

## Roadmap

- [ ] Linux support (using pass/gpg for credentials)
- [ ] Windows support (using Windows Credential Manager)
- [ ] GitLab/Bitbucket issue tracking integration
- [ ] VS Code extension
- [ ] Brew formula for easier installation
- [ ] Docker support for cross-platform usage
- [ ] Team collaboration features
- [ ] Analytics dashboard for team insights

---

## License

MIT License - see [LICENSE](LICENSE) file for details.

---

## Acknowledgments

Built with:

- OpenAI GPT-4 / Anthropic Claude / Cursor AI
- Jira REST API
- macOS Keychain Services
- Automatic credential loading and management

---

<div align="center">

**Made with ❤️ for developers who want to focus on code, not paperwork.**

[⭐ Star us on GitHub](https://github.com/yourusername/gitquick) • [📖 Documentation](https://github.com/yourusername/gitquick/wiki) • [💬 Discussions](https://github.com/yourusername/gitquick/discussions)

</div>
