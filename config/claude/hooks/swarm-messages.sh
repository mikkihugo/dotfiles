#!/usr/bin/env bash
exec node /home/mhugo/.codex/hooks/swarm-messages.mjs claude "${1:-UserPromptSubmit}"
