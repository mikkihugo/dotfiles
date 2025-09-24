<!--
Copyright 2024 Mikki Hugo. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-->

# Global Claude Configuration

**Enterprise-Grade AI Development Environment**

**FILE:** `CLAUDE.md`  
**DESCRIPTION:** Comprehensive configuration and guidelines for Claude AI assistant integration with professional development environments. Defines tool preferences, security protocols, and operational standards for AI-assisted development workflows.

**AUTHOR:** Mikki Hugo <mikkihugo@gmail.com>  
**VERSION:** 4.1.0  
**CREATED:** 2024-01-20  
**MODIFIED:** 2024-12-06  

**ENVIRONMENT:** Professional Development Workstation  
**SCOPE:** Global AI Assistant Configuration  
**COMPLIANCE:** Apache 2.0 License, Security Best Practices  

---

## 📋 Table of Contents

1. [Rust Tools Enforcement](#rust-tools-enforcement)
2. [Home Directory Management](#home-directory-management)
3. [Security Protocols](#security-protocols)
4. [Configuration Management](#configuration-management)
5. [Quick Reference](#quick-reference)
6. [Troubleshooting](#troubleshooting)

---

## 🔧 Features

- **✅ Modern Tool Integration:** Rust-based CLI tools for enhanced performance
- **✅ Security-First Approach:** Sensitive data isolation and proper secret management
- **✅ Version Control Excellence:** Git-based configuration management
- **✅ Automation Ready:** Streamlined workflows for AI-assisted development
- **✅ Cross-Platform Compatibility:** Works on Linux, macOS, and WSL
- **✅ Enterprise Standards:** Professional coding practices and documentation

---

## 🛡️ Security Features

- **Token Isolation:** API keys stored in private GitHub Gists
- **Configuration Validation:** Automated checks for sensitive data exposure
- **Access Control:** Proper file permissions and ownership
- **Audit Trail:** Git history for all configuration changes
- **Secure Defaults:** Conservative security settings by default

---

## 📊 Performance Characteristics

- **Tool Startup:** < 100ms for most operations
- **Sync Operations:** Automatic background synchronization
- **Resource Usage:** Optimized for minimal memory footprint
- **Error Recovery:** Graceful degradation with fallback mechanisms

---

## 🚀 Prerequisites

**Required:**
- Git 2.30+
- Bash 4.0+
- GitHub CLI (`gh`)
- Internet connection for synchronization

**Optional (Enhanced Features):**
- Nix (flake-managed toolchain)
- Modern Rust tools (ripgrep, bat, eza, fd)
- Starship prompt
- FZF fuzzy finder

---

## 📖 Usage Examples

```bash
# Initialize new development environment
cd ~/.dotfiles && ./bootstrap.sh

# Sync configuration changes
cd ~/.dotfiles && git add -A && git commit -m "Update config" && git push

# Update sensitive tokens
gh gist edit $GIST_ID ~/.env_tokens
```

---

## 🔍 Monitoring and Logging

All configuration changes are tracked through:
- Git commit history
- System logs in `~/.dotfiles/logs/`
- Automated sync status in `~/.dotfiles/.last_commit`

---

## 🆘 Support

For issues with this configuration:
1. Check the troubleshooting section below
2. Review git history for recent changes
3. Validate tool dependencies
4. Check system logs for errors

---

## RUST TOOLS ENFORCEMENT - WITH SAFETY
**All Rust tools allowed through SafeCLI wrappers for resource management:**
- **grep** → Use `rg` (ripgrep) - fast search
- **ls** → Use `lsd` or `exa` - modern ls 
- **cat** → Use `bat` - syntax highlighting
- **sed** → Use `sd` - intuitive find & replace
- **ps** → Use `procs` - modern ps
- **du** → Use `dust` - intuitive disk usage
- **top** → Use `bottom` - system monitor
- **lint** → Use `oxlint` - fast linter
- **format** → Use `dprint` - fast formatter

## Home Directory Management Rules

### CRITICAL: Always use dotfiles repo
- **Repo**: `~/.dotfiles` → `github.com/mikkihugo/dotfiles`
- **Rule**: Commit ALL home config changes immediately
- **Command**: `cd ~/.dotfiles && git add -A && git commit -m "message" && git push`

### FORBIDDEN: File naming
- **NEVER use**: `enhanced`, `improved`, `better`, `v2`, `new`, `old`
- **NEVER create**: `file_enhanced.ts`, `component_v2.tsx`, `service_better.ts`
- **ALWAYS**: Edit the original file directly
- **ALWAYS**: Use git for version control, not filename suffixes

## Sensitive Data (.env files)
- **Storage**: Private GitHub Gists (NOT in dotfiles repo)
- **Local**: `~/.env_tokens` (downloaded from gist)
- **Update gist**: `gh gist edit $GIST_ID ~/.env_tokens`

## Before editing ANY home config file:
```bash
# Check if it's already managed
ls -la ~/.bashrc  # Look for symlink arrow →

# If not symlinked, add to dotfiles:
cp ~/.bashrc ~/.dotfiles/
ln -sf ~/.dotfiles/.bashrc ~/.bashrc
cd ~/.dotfiles && git add .bashrc && git commit -m "Add .bashrc"
```

## Active configurations:
- **Shell**: bash with Nix dev shell + starship

## Quick reference:
- Commit dotfiles: `cd ~/.dotfiles && git add -A && git commit -m "msg" && git push`
- Update tokens: `gh gist edit $GIST_ID ~/.env_tokens`
