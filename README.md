# clauto_research

A Claude Code plugin (`autoresearch`) that runs autonomous experiment loops. Give it a goal and a benchmark command, and it will iteratively try changes, measure results, keep what works, revert what doesn't, and repeat until the goal is met.

Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) concept.

## How it works

1. You define a goal, a benchmark command, and a metric to optimize
2. The plugin sets up session files and a stop hook that drives the loop
3. Each iteration: plan a change → implement → commit → measure → keep or revert
4. Results are logged to `autoresearch.jsonl` and strategies tracked in `autoresearch.md`
5. The loop continues automatically until the goal is met or max iterations reached

The loop is driven by a **stop hook** — when Claude finishes an iteration, the hook intercepts the session end, increments the counter, and re-injects the prompt to start the next iteration. This is more reliable than relying on the agent to self-continue.

## Installation

Clone this repo, then register it as a Claude Code plugin:

```bash
git clone git@github.com:camallen/clauto_research.git

# Add the plugin to your project (from your target project directory)
claude plugins add /path/to/clauto_research
```

Or add it directly to your project's `.claude/plugins.json`:

```json
["/path/to/clauto_research"]
```

## Usage

### Start a research loop

```
/autoresearch reduce test runtime --command "npm test" --metric duration_ms --direction lower
```

**Required flags:**
- `--command "<cmd>"` — the benchmark command to run each iteration
- `--metric <name>` — metric name to track (e.g., `duration_ms`, `bundle_kb`, `coverage_pct`)

**Optional flags:**
- `--direction lower|higher` — optimization direction (default: `lower`)
- `--scope "<glob>"` — restrict which files can be modified (e.g., `"src/**/*.ts"`)
- `--max-iterations <N>` — stop after N iterations (default: unlimited)

If you omit flags, Claude will ask you for the missing info interactively.

#### Examples

```bash
# Optimize test speed
/autoresearch reduce test runtime --command "npm test" --metric duration_ms --direction lower

# Improve Lighthouse score
/autoresearch improve lighthouse score --command "npx lighthouse http://localhost:3000 --output json" --metric performance --direction higher --max-iterations 30

# Shrink bundle size, only touching TypeScript files
/autoresearch shrink bundle size --command "npm run build" --metric bundle_kb --direction lower --scope "src/**/*.ts"
```

### Resume an interrupted session

```
/resume
```

Picks up where the last session left off — updates the session ID so the stop hook works again, shows a summary of progress so far, and continues the experiment loop.

### Check progress

```
/dashboard
```

Shows the current objective, total experiments, best result, recent experiment history, and strategy notes.

### Cancel the loop

```
/cancel
```

Stops the loop, shows a final summary, and cleans up session files.

## Session files

When a loop starts, these files are created in your project root:

| File | Purpose |
|------|---------|
| `autoresearch.md` | Living document — objective, strategies, dead ends (persists across context resets) |
| `autoresearch.sh` | Benchmark script that outputs `METRIC name=value` |
| `autoresearch.jsonl` | JSON Lines log of every experiment result |
| `autoresearch.checks.sh` | Optional validation gate — if this fails, the experiment is reverted regardless of metric |
| `.claude/autoresearch-loop.local.md` | Loop state (iteration count, config, prompt) |

### Adding validation checks

Copy `templates/autoresearch.checks.sh` to your project root and add commands:

```bash
#!/bin/bash
set -euo pipefail

npm test
npx tsc --noEmit

echo "CHECKS_PASSED"
```

If this script exits non-zero, the experiment is reverted even if the metric improved. This prevents regressions.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Git (the loop commits and reverts experiments)
- `jq` (used by the stop hook to parse transcripts)
