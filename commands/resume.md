---
description: "Resume an interrupted autoresearch loop"
allowed-tools: ["Read", "Edit", "Bash", "Glob", "Grep", "Write"]
---

# Resume Autoresearch

## Step 1: Validate session files exist

Check that the required session files are present:
- `clauto_research.md` — living document
- `clauto_research.sh` — benchmark script
- `clauto_research.jsonl` — experiment log

If any of these are missing, tell the user there's no autoresearch session to resume and suggest running `/autoresearch` to start a new one.

## Step 2: Restore or create loop state

Check if `.claude/clauto_research-loop.local.md` exists.

**If it exists:** Update the `session_id` field to the current session so the stop hook recognizes this session:

```bash
sed -i '' "s/^session_id: .*/session_id: ${CLAUDE_CODE_SESSION_ID}/" .claude/clauto_research-loop.local.md
```

**If it doesn't exist:** Reconstruct it from `clauto_research.md`. Read `clauto_research.md` to extract the configuration (goal, metric, direction, scope), and count the lines in `clauto_research.jsonl` to determine the current iteration number. Then create `.claude/clauto_research-loop.local.md` with the correct state — use the same format as the setup script would produce.

## Step 3: Show current state

Read `clauto_research.md` and `clauto_research.jsonl`. Print a brief summary:
- Goal and metric
- Iterations completed so far
- Best result achieved
- Last experiment result

## Step 4: Continue the loop

You are now back in the autoresearch loop. Follow the same cycle as `/autoresearch` Step 2:

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
