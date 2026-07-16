#!/usr/bin/env bash
exec node /home/mhugo/.codex/hooks/swarm-messages.mjs kimi-code "${1:-UserPromptSubmit}"
