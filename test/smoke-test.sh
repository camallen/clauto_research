#!/bin/bash

# Smoke test for autoresearch plugin
# Runs in an isolated temp repo, cleans up after itself

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR=$(mktemp -d)
PASSED=0
FAILED=0

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

pass() {
  echo "  PASS: $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  FAIL: $1"
  FAILED=$((FAILED + 1))
}

echo "=== Autoresearch Smoke Test ==="
echo "Plugin root: $PLUGIN_ROOT"
echo "Work dir:    $WORK_DIR"
echo ""

# --- Setup: create a tiny git repo with a file to optimize ---
cd "$WORK_DIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Target file: 10 lines of padding, goal is to reduce line count
for i in $(seq 1 10); do echo "line $i"; done > target.txt
git add -A && git commit -q -m "initial"

# ============================================================
echo "--- Test 1: Setup script creates session files ---"
# ============================================================

export CLAUDE_CODE_SESSION_ID="test-session-123"

"$PLUGIN_ROOT/scripts/setup-autoresearch.sh" \
  reduce line count \
  --command "wc -l < target.txt | tr -d ' '" \
  --metric line_count \
  --direction lower \
  --max-iterations 5 \
  > /dev/null

[[ -f autoresearch.md ]] && pass "autoresearch.md created" || fail "autoresearch.md missing"
[[ -f autoresearch.sh ]] && pass "autoresearch.sh created" || fail "autoresearch.sh missing"
[[ -f autoresearch.jsonl ]] && pass "autoresearch.jsonl created" || fail "autoresearch.jsonl missing"
[[ -f .claude/autoresearch-loop.local.md ]] && pass "loop state file created" || fail "loop state file missing"

# ============================================================
echo "--- Test 2: State file has correct frontmatter ---"
# ============================================================

STATE_FILE=".claude/autoresearch-loop.local.md"
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")

echo "$FRONTMATTER" | grep -q "iteration: 1" && pass "iteration starts at 1" || fail "iteration not 1"
echo "$FRONTMATTER" | grep -q "max_iterations: 5" && pass "max_iterations is 5" || fail "max_iterations wrong"
echo "$FRONTMATTER" | grep -q "session_id: test-session-123" && pass "session_id set" || fail "session_id missing"
echo "$FRONTMATTER" | grep -q 'completion_promise: "GOAL MET"' && pass "completion_promise set" || fail "completion_promise missing"

# ============================================================
echo "--- Test 3: Benchmark script runs and outputs METRIC ---"
# ============================================================

BENCH_OUTPUT=$(bash autoresearch.sh 2>&1)
echo "$BENCH_OUTPUT" | grep -q "^METRIC " && pass "benchmark outputs METRIC line" || fail "no METRIC in benchmark output"

# ============================================================
echo "--- Test 4: autoresearch.md has correct config ---"
# ============================================================

grep -q "reduce line count" autoresearch.md && pass "goal in autoresearch.md" || fail "goal missing from autoresearch.md"
grep -q "line_count" autoresearch.md && pass "metric in autoresearch.md" || fail "metric missing from autoresearch.md"
grep -q "lower" autoresearch.md && pass "direction in autoresearch.md" || fail "direction missing from autoresearch.md"

# ============================================================
echo "--- Test 5: Stop hook continues loop ---"
# ============================================================

# Create a fake transcript file with an assistant message (no promise)
TRANSCRIPT=$(mktemp "$WORK_DIR/transcript-XXXX.json")
cat > "$TRANSCRIPT" <<'TJSON'
{"role":"assistant","message":{"content":[{"type":"text","text":"I ran the experiment and the metric improved."}]}}
TJSON

HOOK_INPUT=$(jq -n \
  --arg sid "test-session-123" \
  --arg tp "$TRANSCRIPT" \
  '{"session_id": $sid, "transcript_path": $tp}')

HOOK_OUTPUT=$(echo "$HOOK_INPUT" | bash "$PLUGIN_ROOT/hooks/stop-hook.sh" 2>&1)

echo "$HOOK_OUTPUT" | jq -e '.decision == "block"' > /dev/null 2>&1 \
  && pass "stop hook returns block decision" || fail "stop hook didn't return block"

# Check iteration was incremented
FRONTMATTER2=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")
echo "$FRONTMATTER2" | grep -q "iteration: 2" && pass "iteration incremented to 2" || fail "iteration not incremented"

# ============================================================
echo "--- Test 6: Stop hook detects completion promise ---"
# ============================================================

# Reset iteration
sed -i '' 's/^iteration: .*/iteration: 2/' "$STATE_FILE"

# Transcript with promise
cat > "$TRANSCRIPT" <<'TJSON'
{"role":"assistant","message":{"content":[{"type":"text","text":"The goal is achieved! <promise>GOAL MET</promise>"}]}}
TJSON

HOOK_INPUT=$(jq -n \
  --arg sid "test-session-123" \
  --arg tp "$TRANSCRIPT" \
  '{"session_id": $sid, "transcript_path": $tp}')

HOOK_OUTPUT=$(echo "$HOOK_INPUT" | bash "$PLUGIN_ROOT/hooks/stop-hook.sh" 2>&1)

# State file should be removed (loop ended)
[[ ! -f "$STATE_FILE" ]] && pass "state file removed on goal met" || fail "state file still exists after goal met"
echo "$HOOK_OUTPUT" | grep -q "Goal met" && pass "stop hook reports goal met" || fail "stop hook didn't report goal met"

# ============================================================
echo "--- Test 7: Stop hook respects max iterations ---"
# ============================================================

# Recreate state file at iteration 5 of 5
mkdir -p .claude
cat > "$STATE_FILE" <<'EOF'
---
active: true
iteration: 5
session_id: test-session-123
max_iterations: 5
completion_promise: "GOAL MET"
started_at: "2026-01-01T00:00:00Z"
---

Loop prompt here.
EOF

cat > "$TRANSCRIPT" <<'TJSON'
{"role":"assistant","message":{"content":[{"type":"text","text":"Did another iteration."}]}}
TJSON

HOOK_INPUT=$(jq -n \
  --arg sid "test-session-123" \
  --arg tp "$TRANSCRIPT" \
  '{"session_id": $sid, "transcript_path": $tp}')

HOOK_OUTPUT=$(echo "$HOOK_INPUT" | bash "$PLUGIN_ROOT/hooks/stop-hook.sh" 2>&1)

[[ ! -f "$STATE_FILE" ]] && pass "state file removed at max iterations" || fail "state file still exists at max iterations"
echo "$HOOK_OUTPUT" | grep -q "max iterations" && pass "stop hook reports max iterations" || fail "stop hook didn't report max iterations"

# ============================================================
echo "--- Test 8: Stop hook ignores wrong session ---"
# ============================================================

mkdir -p .claude
cat > "$STATE_FILE" <<'EOF'
---
active: true
iteration: 1
session_id: other-session-999
max_iterations: 0
completion_promise: "GOAL MET"
started_at: "2026-01-01T00:00:00Z"
---

Loop prompt here.
EOF

HOOK_INPUT=$(jq -n \
  --arg sid "test-session-123" \
  --arg tp "$TRANSCRIPT" \
  '{"session_id": $sid, "transcript_path": $tp}')

HOOK_OUTPUT=$(echo "$HOOK_INPUT" | bash "$PLUGIN_ROOT/hooks/stop-hook.sh" 2>&1)

# State file should still exist (hook ignored it)
[[ -f "$STATE_FILE" ]] && pass "state file untouched for wrong session" || fail "state file removed for wrong session"
# Hook output should be empty (no block, no action)
[[ -z "$HOOK_OUTPUT" ]] && pass "stop hook silent for wrong session" || fail "stop hook produced output for wrong session"

# ============================================================
echo "--- Test 9: Setup script rejects missing args ---"
# ============================================================

# No args at all
OUTPUT=$(bash "$PLUGIN_ROOT/scripts/setup-autoresearch.sh" 2>&1) || true
echo "$OUTPUT" | grep -qi "goal\|gather\|no goal" && pass "no-args prompts for goal" || fail "no-args didn't prompt"

# Goal but no --command/--metric
OUTPUT=$(bash "$PLUGIN_ROOT/scripts/setup-autoresearch.sh" some goal 2>&1) || true
echo "$OUTPUT" | grep -qi "command\|metric\|missing" && pass "missing flags prompts for them" || fail "missing flags didn't prompt"

# ============================================================
echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [[ $FAILED -gt 0 ]]; then
  exit 1
fi
