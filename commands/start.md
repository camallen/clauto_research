---
description: "Start an autonomous experiment loop to optimize a metric"
argument-hint: "[GOAL] [--command CMD] [--metric NAME] [--direction lower|higher] [--scope GLOB] [--max-iterations N]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-clauto_research.sh:*)", "Read", "Write", "Bash", "Glob", "Grep", "Edit"]
---

# Autoresearch - Autonomous Experiment Loop

## Step 1: Run the setup script (MANDATORY)

You MUST run the setup script below using the Bash tool. Do NOT skip this step. Do NOT create the session files manually. The setup script creates a state file (.claude/clauto_research-loop.local.md) that drives the automatic loop — without it, the loop will not continue between iterations.

If $ARGUMENTS contains natural language instead of CLI flags, first translate it into the correct flags:
- Extract the goal (positional argument)
- Identify the benchmark command → `--command "<cmd>"`
- Identify the metric name → `--metric <name>`
- Identify the optimization direction → `--direction lower` or `--direction higher`
- Identify file scope if mentioned → `--scope "<glob>"`
- Identify iteration limit if mentioned → `--max-iterations <N>`

If you cannot determine --command and --metric from the arguments, DO NOT run the script yet. First ask the user:
1. What command measures the metric? (e.g., "bin/rails test test/models/foo_test.rb", "npm test")
2. What metric name to track? (e.g., "duration_ms", "coverage_pct")
3. Should the metric go lower or higher?
4. Which files are in scope for modification? (optional)

Once you have at least --command and --metric, construct the full flags and run the script.

Run this now:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-clauto_research.sh" $ARGUMENTS
```

After the script runs, verify that `.claude/clauto_research-loop.local.md` exists. If it does not, something went wrong — diagnose and fix before proceeding.

## Step 2: Run the research cycle

You are now in an autonomous research loop. Follow this cycle for EVERY iteration:

1. **Read state**: Read `clauto_research.md` to understand prior results, dead ends, and successful strategies.
2. **Plan**: Based on what's been tried, pick ONE focused modification. Prefer small, isolated changes.
3. **Implement**: Make the code change.
4. **Commit**: `git add -A && git commit -m "experiment: <description>"`
5. **Measure**: Run `bash clauto_research.sh` and parse the `METRIC name=value` output line(s).
6. **Check** (if `clauto_research.checks.sh` exists): Run `bash clauto_research.checks.sh`. If it fails, the experiment fails regardless of metric improvement.
7. **Log**: Append one JSON line to `clauto_research.jsonl`:
   ```
   {"iteration":N,"description":"what you changed","metric_name":"value","baseline":"value","improved":true/false,"kept":true/false,"timestamp":"ISO8601"}
   ```
8. **Decide**:
   - If improved AND checks passed: **keep**. Update `clauto_research.md` with what worked.
   - Otherwise: `git revert HEAD --no-edit`. Update `clauto_research.md` with what didn't work and why.
9. **Report**: Print a summary table:
   ```
   -- Autoresearch: iteration N ----------------------
    Metric:    <name> = <value> (<direction>)
    Baseline:  <original>
    Best:      <best so far>
    This run:  <kept/reverted> - <description>
   ---------------------------------------------------
   ```

## Rules
- ONE change per iteration. Don't combine experiments.
- Always measure BEFORE deciding. No guessing.
- If you've tried 3+ things with no improvement, step back and try a fundamentally different approach.
- Update `clauto_research.md` every iteration — it's your memory across context resets.
- If the metric target is reached, output `<promise>GOAL MET</promise>`.

CRITICAL: Do NOT output `<promise>GOAL MET</promise>` unless the measured metric genuinely meets the target. Do not lie to exit the loop.
