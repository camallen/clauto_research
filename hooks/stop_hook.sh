#!/bin/bash

# Autoresearch Stop Hook
# Reimplements the same stop-hook pattern (state file, iterations, completion promise)
# as Ralph Loop; does not use the Claude Ralph Loop plugin.

set -euo pipefail

HOOK_INPUT=$(cat)

# Check for autoresearch loop state
STATE_FILE=".claude/clauto_research-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Parse frontmatter
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

# Session isolation
STATE_SESSION=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

# Validate
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Autoresearch: state file corrupted, stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Max iterations check
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "🔬 Autoresearch: max iterations ($MAX_ITERATIONS) reached."
  rm "$STATE_FILE"
  exit 0
fi

# Get transcript and check for completion promise
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "Autoresearch: transcript not found, stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "Autoresearch: no assistant messages found, stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

LAST_LINES=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -n 100)
if [[ -z "$LAST_LINES" ]]; then
  rm "$STATE_FILE"
  exit 0
fi

set +e
LAST_OUTPUT=$(echo "$LAST_LINES" | jq -rs '
  map(.message.content[]? | select(.type == "text") | .text) | last // ""
' 2>&1)
JQ_EXIT=$?
set -e

if [[ $JQ_EXIT -ne 0 ]]; then
  echo "Autoresearch: failed to parse transcript, stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Check completion promise
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "🔬 Autoresearch: Goal met! (<promise>$COMPLETION_PROMISE</promise>)"
    rm "$STATE_FILE"
    exit 0
  fi
fi

# Continue loop
NEXT_ITERATION=$((ITERATION + 1))

PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "Autoresearch: no prompt in state file, stopping." >&2
  rm "$STATE_FILE"
  exit 0
fi

# Update iteration
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

SYSTEM_MSG="🔬 Autoresearch iteration $NEXT_ITERATION | To complete: output <promise>$COMPLETION_PROMISE</promise> when goal is genuinely met"

jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
