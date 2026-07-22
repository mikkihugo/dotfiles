#!/usr/bin/env bash
# shell/bash/noninteractive-path.sh — BASH_ENV hook for NON-interactive bash.
#
# Why: HM's ~/.bashrc early-returns on `[[ $- == *i* ]] || return`, so
# non-interactive/agent shells (Claude Code, Cursor agent, CI, `bash -c`) never
# source shell/bash/bashrc and never get its wrapper-precedence restore. mise's
# `activate` hook-env prepends tool INSTALL dirs (…/mise/installs/<tool>/latest)
# ahead of ~/.local/bin, so bare `vtcode`/`goose`/`kimi` hit the raw upstream
# binary (no llm-gateway routing, no OTEL) instead of the HM gateway wrapper.
#
# This is the non-interactive twin of the `export PATH="$HOME/.local/bin:$PATH"`
# line in shell/bash/bashrc. Kept deliberately minimal + fast: PATH only, no
# mise activate, no direnv, no SOPS — those stay in the interactive path.
#
# Idempotent: a sentinel stops re-prepend in inherited grandchild shells.

if [ -z "${__CC_LOCALBIN_FIRST:-}" ]; then
	# Force the HM wrapper dir ahead of any mise install dirs inherited from a
	# parent that ran `mise activate`. A duplicate later in PATH is harmless.
	export PATH="$HOME/.local/bin:$PATH"
	export __CC_LOCALBIN_FIRST=1
fi
