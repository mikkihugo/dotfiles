#!/bin/bash
#
# Copyright 2024 Mikki Hugo. All rights reserved.
# Licensed under the Apache License, Version 2.0 (the "License")
#
# Comprehensive linting for dotfiles repository
# Purpose: Run all linters and code quality checks
# Version: 1.0.0

set -euo pipefail

echo "🔍 Running dotfiles linting suite..."

# Shell script linting with shellcheck
if command -v shellcheck >/dev/null 2>&1; then
    echo "📝 Linting shell scripts..."
    find . -name "*.sh" -type f -exec shellcheck {} \; || echo "⚠️ Shellcheck found issues"
else
    echo "⚠️ shellcheck not found, install with: mise install shellcheck"
fi

# Markdown linting
if command -v markdownlint >/dev/null 2>&1; then
    echo "📝 Linting markdown files..."
    markdownlint "*.md" || echo "⚠️ Markdown linting found issues"
else
    echo "⚠️ markdownlint not found, install with: npm install -g markdownlint-cli"
fi

# YAML linting
if command -v yamllint >/dev/null 2>&1; then
    echo "📝 Linting YAML files..."
    find . -name "*.yml" -o -name "*.yaml" -type f -exec yamllint {} \; || echo "⚠️ YAML linting found issues"
else
    echo "⚠️ yamllint not found, install with: pip install yamllint"
fi

# TOML linting (if available)
if command -v taplo >/dev/null 2>&1; then
    echo "📝 Linting TOML files..."
    find . -name "*.toml" -type f -exec taplo fmt --check {} \; || echo "⚠️ TOML formatting issues found"
fi

# Git hooks check
echo "🪝 Checking git hooks..."
if [ -d ".git/hooks" ]; then
    echo "✅ Git hooks directory exists"
else
    echo "⚠️ No git hooks found"
fi

echo "✅ Linting complete!"