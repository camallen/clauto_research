# clauto_research

A Claude Code plugin (`autoresearch`) that runs autonomous experiment loops. Give it a goal and a benchmark command, and it will iteratively try changes, measure results, keep what works, revert what doesn't, and repeat until the goal is met.

Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) concept.

## How it works

1. You define a goal, a benchmark command, and a metric to optimize
2. The plugin sets up session files and a stop hook that drives the loop
3. Each iteration: plan a change → implement → commit → measure → keep or revert
4. Results are logged to `clauto_research.jsonl` and strategies tracked in `clauto_research.md`
5. The loop continues automatically until the goal is met or max iterations reached

The loop is driven by a **stop hook** — when Claude finishes an iteration, the hook intercepts the session end, increments the counter, and re-injects the prompt to start the next iteration. Each iteration gets a fresh context, with `clauto_research.md` serving as memory across resets. This is more reliable than relying on the agent to self-continue.

## Installation

```bash
git clone git@github.com:camallen/clauto_research.git
claude --plugin-dir /path/to/clauto_research
```

## Usage

### Start a research loop

```
/clauto_research:start reduce test runtime --command "npm test" --metric duration_ms --direction lower
```

**Required flags:**
- `--command "<cmd>"` — the benchmark command to run each iteration
- `--metric <name>` — metric name to track (e.g., `duration_ms`, `bundle_kb`, `coverage_pct`)

**Optional flags:**
- `--direction lower|higher` — optimization direction (default: `lower`)
- `--checks "<cmd>"` — validation command run after each experiment (e.g., `"npm test"`). If it fails, the change is reverted even if the metric improved
- `--scope "<glob>"` — restrict which files can be modified (e.g., `"src/**/*.ts"`)
- `--max-iterations <N>` — stop after N iterations (default: unlimited)

If you omit flags, Claude will ask you for the missing info interactively.

#### Examples

```bash
# Optimize test speed
/clauto_research:start reduce test runtime --command "npm test" --metric duration_ms --direction lower

# Improve Lighthouse score
/clauto_research:start improve lighthouse score --command "npx lighthouse http://localhost:3000 --output json" --metric performance --direction higher --max-iterations 30

# Shrink bundle size, only touching TypeScript files
/clauto_research:start shrink bundle size --command "npm run build" --metric bundle_kb --direction lower --scope "src/**/*.ts"
```

### Resume an interrupted session

```
/clauto_research:resume
```

Picks up where the last session left off — updates the session ID so the stop hook works again, shows a summary of progress so far, and continues the experiment loop.

### Check progress

```
/clauto_research:dashboard
```

Shows the current objective, total experiments, best result, recent experiment history, and strategy notes.

### Cancel the loop

```
/clauto_research:cancel
```

Stops the loop, shows a final summary, and cleans up session files.

## Session files

When a loop starts, these files are created in your project root:

| File | Purpose |
|------|---------|
| `clauto_research.md` | Living document — objective, strategies, dead ends (persists across context resets) |
| `clauto_research.sh` | Benchmark script that outputs `METRIC name=value` |
| `clauto_research.jsonl` | JSON Lines log of every experiment result |
| `clauto_research.checks.sh` | Optional validation gate — if this fails, the experiment is reverted regardless of metric |
| `.claude/clauto_research-loop.local.md` | Loop state (iteration count, config, prompt) |

### Validation checks (optional)

Your benchmark command (`clauto_research.sh`) only measures the metric. If you're optimising something like bundle size or latency, an improvement in the metric could still break your tests or types.

Add a `clauto_research.checks.sh` to your project root to catch that. If it exits non-zero, the experiment is reverted regardless of metric improvement.

```bash
#!/bin/bash
set -euo pipefail

npm test
npx tsc --noEmit

echo "CHECKS_PASSED"
```

A template is provided in `templates/clauto_research.checks.sh`.

You don't need this if your benchmark command already fails on broken code (e.g. your test suite is the benchmark).

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Git (the loop commits and reverts experiments)
- `jq` (used by the stop hook to parse transcripts)
