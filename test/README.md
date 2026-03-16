# Tests

## Running

```bash
bash test/smoke-test.sh
```

## How it works

The smoke test creates a throwaway git repo in `/tmp`, exercises each plugin component in isolation, then cleans up via a trap on EXIT.

A fake `CLAUDE_CODE_SESSION_ID` is exported so the setup script and stop hook have a session to match on. A trivial benchmark (`wc -l < target.txt`) stands in for a real command.

## What each test covers

| Test | What it does |
|------|-------------|
| 1. Setup script | Runs `setup-autoresearch.sh` with real flags, checks all 4 session files are created |
| 2. State frontmatter | Parses YAML frontmatter from the state file, verifies iteration/max/session_id/promise values |
| 3. Benchmark | Runs the generated `autoresearch.sh`, checks stdout contains a `METRIC` line |
| 4. Config | Greps `autoresearch.md` for goal, metric name, and direction |
| 5. Stop hook continues | Pipes a fake transcript (no promise) into the stop hook, checks it returns `{"decision": "block"}` and increments iteration |
| 6. Completion promise | Transcript contains `<promise>GOAL MET</promise>` — checks the hook removes the state file and reports goal met |
| 7. Max iterations | State file at iteration 5 of 5 — checks the hook stops and cleans up |
| 8. Session isolation | State file has a different session_id — checks the hook does nothing |
| 9. Missing args | Runs setup with no args / partial args — checks it prompts instead of crashing |
