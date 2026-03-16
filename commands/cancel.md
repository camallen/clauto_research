---
description: "Cancel active autoresearch loop and clean up session files"
allowed-tools: ["Read", "Bash"]
---

# Cancel Autoresearch

1. Read `autoresearch.jsonl` (if it exists) and show a final summary of all experiments.
2. Remove the loop state file if it exists: `.claude/autoresearch-loop.local.md`
3. Remove session files if they exist: `autoresearch.md`, `autoresearch.sh`, `autoresearch.jsonl`, `autoresearch.checks.sh`
4. Report how many iterations were completed (from the jsonl), or say no experiments were recorded if the file was empty.
5. If none of the above files exist, say no active autoresearch session was found.
