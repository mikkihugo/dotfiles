#!/usr/bin/env bash
# remind-skills.sh — Copilot CLI userPromptSubmitted hook.
#
# Reads the user prompt from stdin (JSON payload), checks if it's a non-trivial
# task, and if so emits a one-line reminder to consult the skill catalog before
# guessing at commands or APIs.
#
# Payload shape (Copilot CLI userPromptSubmitted):
#   {"sessionId":"...","cwd":"...","hookEventName":"userPromptSubmitted","prompt":"..."}
#
# Behavior:
# - Trivial prompts (greetings, single-word, system commands) → no reminder
# - Task prompts (have verb, mention files/commands, or are multi-sentence) → reminder
# - If reminder was already shown in the last N prompts (counted in /tmp) → skip
# - Reminder printed to stderr (Copilot CLI surfaces stderr to the model)
set -eu

PAYLOAD="$(cat)"
PROMPT="$(printf '%s' "$PAYLOAD" | jq -r '.prompt // ""')"

# Skip empty prompts
if [ -z "$PROMPT" ] || [ "$PROMPT" = "null" ]; then
  exit 0
fi

PROMPT_LEN=${#PROMPT}

# Trivial-prompt heuristics: short, no imperative verb, no file/command reference
SKIP=0

# Very short prompts (< 20 chars) are conversational
if [ "$PROMPT_LEN" -lt 20 ]; then
  SKIP=1
fi

# Pure greetings
if printf '%s' "$PROMPT" | grep -qiE '^(hi|hello|hey|thanks|ty|ok|yes|no|sure)\b'; then
  SKIP=1
fi

# Slash commands (Copilot built-in)
if printf '%s' "$PROMPT" | grep -qE '^/'; then
  SKIP=1
fi

# Shell-bang commands (user wants to execute directly)
if printf '%s' "$PROMPT" | grep -qE '^!'; then
  SKIP=1
fi

if [ "$SKIP" -eq 1 ]; then
  exit 0
fi

# Throttle: show on prompts 1 and 6, skip the rest (show reminder twice per 10 prompts)
THROTTLE_FILE="/tmp/copilot-skill-remind-count"
COUNT=0
if [ -f "$THROTTLE_FILE" ]; then
  COUNT=$(cat "$THROTTLE_FILE" 2>/dev/null || echo 0)
fi
COUNT=$((COUNT + 1))
echo "$COUNT" > "$THROTTLE_FILE"
# Fire on first prompt and every 5th prompt thereafter (count 1, 6, 11, ...)
if [ $((COUNT % 5)) -ne 1 ]; then
  exit 0
fi

# Emit reminder to stderr — Copilot CLI surfaces this to the model
cat <<'EOF' >&2
[skills-reminder] Non-trivial task detected. Before guessing at commands or APIs, load the relevant skill via the `skill` tool. Skills own the canonical procedure (e.g., sf-debug-scan for SF runtime anomalies, systematic-debugging before changing behavior, existing-capability-first before adding surface). Common triggers: "diag sf", "fix the bug", "add a feature", "research X", "make a plan". If no skill matches, proceed directly but state the action.
EOF

exit 0
