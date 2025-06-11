# Guardian Shell - Protected Files

This directory contains critical system recovery files that are marked as read-only in git.
The files in this directory should never be modified without careful consideration.

## Contents

- `shell-guardian.rs` - Rust source code for the shell guardian
- `bash-guardian-fallback.sh` - Pure Bash implementation for systems without Rust
- `shell-guardian.bin` - Pre-compiled binary (when available)

## Usage

Do not modify these files directly. If you need to update them:

1. Make changes in a branch
2. Review changes carefully
3. Force-add the files with `git add -f .guardian-shell/*`
4. Commit with a detailed explanation

The protection exists to prevent accidental modification of these critical safety files.