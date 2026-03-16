#!/bin/bash

# Autoresearch Setup Script
# Creates session files and loop state for autonomous experiment optimization

set -euo pipefail

# Parse arguments
GOAL_PARTS=()
COMMAND=""
METRIC=""
DIRECTION="lower"
SCOPE=""
MAX_ITERATIONS=0
COMPLETION_PROMISE="GOAL MET"

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Autoresearch - Autonomous Experiment Loop

USAGE:
  /autoresearch [GOAL...] [OPTIONS]

ARGUMENTS:
  GOAL...    What you want to optimize (e.g. "reduce test suite runtime")

OPTIONS:
  --command <cmd>              Benchmark command (default: interactive setup)
  --metric <name>              Metric name to track
  --direction lower|higher     Optimize direction (default: lower)
  --scope <glob>               Files in scope for modification
  --max-iterations <n>         Max iterations (default: unlimited)
  --completion-promise <text>  Custom promise phrase (default: "GOAL MET")
  -h, --help                   Show this help

EXAMPLES:
  /autoresearch reduce test runtime --command "npm test" --metric duration_ms --direction lower
  /autoresearch improve lighthouse score --command "npx lighthouse http://localhost:3000 --output json" --metric performance --direction higher --max-iterations 30
  /autoresearch shrink bundle size --command "npm run build" --metric bundle_kb --direction lower --scope "src/**/*.ts"
HELP_EOF
      exit 0
      ;;
    --command) COMMAND="$2"; shift 2 ;;
    --metric) METRIC="$2"; shift 2 ;;
    --direction) DIRECTION="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --max-iterations)
      if ! [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations must be a number" >&2; exit 1
      fi
      MAX_ITERATIONS="$2"; shift 2 ;;
    --completion-promise) COMPLETION_PROMISE="$2"; shift 2 ;;
    *) GOAL_PARTS+=("$1"); shift ;;
  esac
done

GOAL="${GOAL_PARTS[*]:-}"

# If no goal provided, prompt Claude to gather info interactively
if [[ -z "$GOAL" ]]; then
  cat <<'EOF'
No goal specified. Please gather the following from the user:

1. **Goal**: What metric are you optimizing? (e.g., "reduce test suite runtime")
2. **Command**: What command measures the metric? (e.g., "npm test", "make build")
3. **Metric name**: What to call the metric (e.g., "duration_ms", "bundle_kb")
4. **Direction**: lower or higher?
5. **Scope** (optional): Which files can be modified? (glob pattern)

Then run this command again with the gathered parameters:
  /autoresearch <goal> --command "<cmd>" --metric <name> --direction <lower|higher>
EOF
  exit 0
fi

# Check required parameters
if [[ -z "$COMMAND" ]] || [[ -z "$METRIC" ]]; then
  cat <<'EOF'
Missing required parameters. Please provide:

  --command "<cmd>"    Benchmark command that produces a measurable result
  --metric <name>      Metric name to track (e.g., duration_ms, coverage_pct)

Example:
  /autoresearch reduce test runtime --command "bin/rails test test/models/foo_test.rb" --metric duration_ms --direction lower
EOF
  exit 0
fi

# Check we're in a git repo
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: autoresearch requires a git repository (for commit/revert)." >&2
  echo "Run: git init" >&2
  exit 1
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

# Create session files
# 1. autoresearch.md — living document
cat > autoresearch.md <<SESSIONEOF
# Autoresearch Session

## Objective
${GOAL}

## Configuration
- **Benchmark command**: \`${COMMAND}\`
- **Metric**: ${METRIC} (${DIRECTION} is better)
- **File scope**: ${SCOPE:-all files}
- **Branch**: ${BRANCH}

## Baseline
_Not yet measured. Run the benchmark first to establish baseline._

## Successful Strategies
_None yet._

## Dead Ends
_None yet._

## Current Thinking
_Starting fresh. Will establish baseline first, then begin experiments._
SESSIONEOF

# 2. autoresearch.sh — benchmark script
if [[ -n "$COMMAND" ]]; then
  cat > autoresearch.sh <<BENCHEOF
#!/bin/bash
# Autoresearch benchmark script
# Outputs: METRIC name=value

set -euo pipefail

START_S=\$(date +%s)

# Run the benchmark command
${COMMAND}
EXIT_CODE=\$?

END_S=\$(date +%s)
DURATION_MS=\$(( (END_S - START_S) * 1000 ))

if [[ \$EXIT_CODE -ne 0 ]]; then
  echo "BENCHMARK_FAILED exit_code=\$EXIT_CODE"
  exit 1
fi

echo "METRIC duration_ms=\$DURATION_MS"
BENCHEOF
  chmod +x autoresearch.sh
else
  cat > autoresearch.sh <<'BENCHEOF'
#!/bin/bash
# Autoresearch benchmark script
# TODO: Replace this with your actual benchmark command
# Must output: METRIC name=value
#
# Example:
#   npm test 2>&1
#   echo "METRIC duration_ms=$SECONDS"

set -euo pipefail

echo "ERROR: benchmark command not configured. Edit autoresearch.sh or re-run /autoresearch with --command"
exit 1
BENCHEOF
  chmod +x autoresearch.sh
fi

# 3. autoresearch.jsonl — experiment log (empty to start)
touch autoresearch.jsonl

# 4. Set up Ralph-compatible loop state file
mkdir -p .claude

# Quote completion promise for YAML
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  COMPLETION_PROMISE_YAML="\"$COMPLETION_PROMISE\""
else
  COMPLETION_PROMISE_YAML="null"
fi

# Build the research loop prompt
LOOP_PROMPT="You are in an autoresearch loop. Read autoresearch.md for context, then run ONE experiment cycle:

1. Read autoresearch.md and autoresearch.jsonl to understand what's been tried
2. Plan one focused change based on prior results
3. Implement the change and commit it
4. Run: bash autoresearch.sh — parse METRIC lines from output
5. If autoresearch.checks.sh exists, run it — failure means revert regardless of metric
6. Append result to autoresearch.jsonl as JSON
7. If improved and checks passed: keep. Otherwise: git revert HEAD --no-edit
8. Update autoresearch.md with learnings
9. Print summary table showing iteration, metric value, baseline, best, and decision

Goal: ${GOAL}
Metric: ${METRIC:-duration_ms} (${DIRECTION} is better)
Scope: ${SCOPE:-all files}

If the target is met, output <promise>${COMPLETION_PROMISE}</promise>"

cat > .claude/autoresearch-loop.local.md <<STATEEOF
---
active: true
iteration: 1
session_id: ${CLAUDE_CODE_SESSION_ID:-}
max_iterations: ${MAX_ITERATIONS}
completion_promise: ${COMPLETION_PROMISE_YAML}
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

${LOOP_PROMPT}
STATEEOF

# Output setup message
cat <<EOF
🔬 Autoresearch loop activated!

Goal:       ${GOAL}
Metric:     ${METRIC:-duration_ms} (${DIRECTION} is better)
Command:    ${COMMAND:-"(edit autoresearch.sh)"}
Scope:      ${SCOPE:-all files}
Iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)
Branch:     ${BRANCH}

Session files created:
  autoresearch.md      — living document (your memory across resets)
  autoresearch.sh      — benchmark script
  autoresearch.jsonl   — experiment log

Starting research loop. First step: establish baseline by running the benchmark.
EOF
