# Step-by-Step Publishing Guide

## Quick Answer: Git Push?

**You don't need to push to git before publishing to npm**, but it's recommended to:

1. ✅ Commit your changes (for version control)
2. ⚠️ Push to git (optional, but good practice)
3. ✅ Publish to npm

npm publish works independently - it just publishes the package files, not your git repo.

---

## Step-by-Step Publishing Process

### Step 1: Clean Up Test Files

```bash
cd ~/Documents/DH/automation

# Remove test tarball if exists
rm -f git-jira-ai-*.tgz
```

### Step 2: Verify Package is Ready

```bash
# Check what will be published
npm pack --dry-run

# Should show:
# - bin/ directory ✅
# - lib/ directory ✅
# - scripts/postinstall.js ✅
# - README-NPM.md ✅
# - LICENSE ✅
# - package.json ✅
```

### Step 3: (Optional) Commit Changes to Git

```bash
# Check what's changed
git status

# Add npm package files
git add package.json .npmignore README-NPM.md bin/ lib/ scripts/

# Commit
git commit -m "feat: prepare npm package for publishing"
```

### Step 4: (Optional) Push to Git

```bash
# Only if you want to track in git
git push
```

### Step 5: Login to NPM

```bash
npm login

# Enter:
# - Username
# - Password
# - Email
# - OTP (if 2FA enabled)
```

### Step 6: Verify You're Logged In

```bash
npm whoami
# Should show your npm username
```

### Step 7: Check Package Name Availability

```bash
npm search git-jira-ai

# If package name is taken, you'll need to:
# - Choose different name in package.json
# - Or use scoped: @yourusername/git-jira-ai
```

### Step 8: Publish!

```bash
cd ~/Documents/DH/automation

# First publish (requires --access public)
npm publish --access public

# Future updates:
# npm version patch  # or minor/major
# npm publish
```

### Step 9: Verify Publication

```bash
# Check package page
npm view git-jira-ai

# Or visit in browser
open https://www.npmjs.com/package/git-jira-ai
```

---

## Complete Command Sequence

```bash
# 1. Clean up
cd ~/Documents/DH/automation
rm -f git-jira-ai-*.tgz

# 2. Verify package
npm pack --dry-run

# 3. (Optional) Commit to git
git add package.json .npmignore README-NPM.md bin/ lib/ scripts/
git commit -m "feat: prepare npm package for publishing"
git push  # optional

# 4. Login to npm
npm login

# 5. Publish
npm publish --access public

# 6. Verify
npm view git-jira-ai
```

---

## Important Notes

### Git vs NPM

- **Git**: Tracks your source code and changes
- **NPM**: Publishes the distributable package
- **They're independent** - npm doesn't need git push

### Package Name

If `git-jira-ai` is already taken, you'll get an error. Options:

1. Use scoped package: `@yourusername/git-jira-ai`
2. Choose different name: `git-jira-ai-cli`, `gq-cli`, etc.

### First Publish

First publish requires `--access public` flag:

```bash
npm publish --access public
```

Future updates just use:

```bash
npm publish
```

---

## Troubleshooting

### "Package name already exists"

- Choose different name or use scoped package

### "You must verify your email"

- Check email for verification link
- Or run `npm adduser` again

### "Insufficient permissions"

- Make sure you're logged in: `npm whoami`
- Check package ownership

---

## Ready to Publish?

Run these commands:

```bash
cd ~/Documents/DH/automation
npm login
npm publish --access public
```

That's it! 🚀
