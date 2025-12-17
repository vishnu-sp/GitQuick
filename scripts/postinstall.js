#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');

const platform = os.platform();
const arch = os.arch();

// Map platform/arch to jq binary name
let jqBinaryName = '';
if (platform === 'darwin') {
  jqBinaryName = arch === 'arm64' ? 'jq-macos-arm64' : 'jq-macos-amd64';
} else if (platform === 'linux') {
  jqBinaryName = arch === 'arm64' ? 'jq-linux-arm64' : 'jq-linux-amd64';
} else {
  console.error('⚠️  Unsupported platform:', platform, arch);
  console.error('   jq will need to be installed manually');
  process.exit(0);
}

const jqSourcePath = path.join(__dirname, '..', 'bin', 'jq', jqBinaryName);
const jqTargetPath = path.join(__dirname, '..', 'bin', 'jq-binary');

// Check if source binary exists
if (!fs.existsSync(jqSourcePath)) {
  console.error('⚠️  jq binary not found:', jqBinaryName);
  console.error('   Please ensure jq binaries are included in the package');
  process.exit(0);
}

try {
  // Copy binary to bin/jq (executable)
  fs.copyFileSync(jqSourcePath, jqTargetPath);
  
  // Set executable permissions
  fs.chmodSync(jqTargetPath, 0o755);
  
  console.log('✅ git-jira-ai installed successfully!');
  console.log('');
  console.log('📝 Next steps:');
  console.log('   1. Configure API keys: gq update');
  console.log('   2. Setup Jira: gq jira select');
  console.log('   3. Start using: gq');
  console.log('');
} catch (error) {
  console.error('❌ Error setting up jq binary:', error.message);
  console.error('   You may need to install jq manually: brew install jq');
  process.exit(0);
}
