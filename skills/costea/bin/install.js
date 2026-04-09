#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const os = require('os');

const home = os.homedir();
const src = path.join(__dirname, '..');
const version = require('../package.json').version;

const targets = [
  { name: 'Claude Code', dir: path.join(home, '.claude', 'skills', 'costea') },
  { name: 'Codex',       dir: path.join(home, '.codex', 'skills', 'costea') },
];

/** Recursively copy a directory */
function copyDir(srcDir, destDir) {
  fs.mkdirSync(destDir, { recursive: true });
  for (const entry of fs.readdirSync(srcDir, { withFileTypes: true })) {
    const srcPath = path.join(srcDir, entry.name);
    const destPath = path.join(destDir, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
      // Preserve executable permission for shell scripts
      if (entry.name.endsWith('.sh')) {
        fs.chmodSync(destPath, 0o755);
      }
    }
  }
}

const installed = [];

for (const t of targets) {
  const parent = path.dirname(t.dir);
  if (fs.existsSync(path.dirname(parent))) {
    // Copy SKILL.md
    fs.mkdirSync(t.dir, { recursive: true });
    fs.copyFileSync(path.join(src, 'SKILL.md'), path.join(t.dir, 'SKILL.md'));

    // Copy scripts/ directory (all parsers, receipt, lib, etc.)
    const scriptsDir = path.join(src, 'scripts');
    if (fs.existsSync(scriptsDir)) {
      copyDir(scriptsDir, path.join(t.dir, 'scripts'));
    }

    fs.writeFileSync(path.join(t.dir, 'VERSION'), version);
    installed.push(t.name);
  }
}

// Fallback: install to Claude Code even if ~/.claude doesn't exist yet
if (installed.length === 0) {
  const fallback = targets[0];
  fs.mkdirSync(fallback.dir, { recursive: true });
  fs.copyFileSync(path.join(src, 'SKILL.md'), path.join(fallback.dir, 'SKILL.md'));

  const scriptsDir = path.join(src, 'scripts');
  if (fs.existsSync(scriptsDir)) {
    copyDir(scriptsDir, path.join(fallback.dir, 'scripts'));
  }

  fs.writeFileSync(path.join(fallback.dir, 'VERSION'), version);
  installed.push(fallback.name);
}

// Also install /costeamigo if present
const amigoSrc = path.join(src, '..', 'costeamigo');
if (fs.existsSync(path.join(amigoSrc, 'SKILL.md'))) {
  for (const t of targets) {
    const amigoDir = t.dir.replace(/costea$/, 'costeamigo');
    const parent = path.dirname(amigoDir);
    if (fs.existsSync(path.dirname(parent))) {
      fs.mkdirSync(amigoDir, { recursive: true });
      fs.copyFileSync(path.join(amigoSrc, 'SKILL.md'), path.join(amigoDir, 'SKILL.md'));
      const amigoScripts = path.join(amigoSrc, 'scripts');
      if (fs.existsSync(amigoScripts)) {
        copyDir(amigoScripts, path.join(amigoDir, 'scripts'));
      }
    }
  }
}

console.log('');
console.log('  @costea/costea installed!');
console.log('');
for (const name of installed) {
  console.log(`   + ${name}`);
}
console.log('');
console.log('   /costea     - Estimate cost before running a task');
console.log('   /costeamigo - Historical token consumption report');
console.log('');
console.log('   Requires: jq (brew install jq)');
console.log('   https://github.com/memovai/costea');
console.log('');
