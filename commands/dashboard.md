---
description: "Show autoresearch experiment results dashboard"
allowed-tools: ["Read", "Bash", "Glob"]
---

# Autoresearch Dashboard

Read and display the current autoresearch session state.

1. Read `autoresearch.md` for the current objective and strategy notes.
2. Read `autoresearch.jsonl` for all experiment results.
3. Display a summary:
   - Objective and metric direction
   - Total experiments run
   - Best result achieved (and which iteration)
   - Last 5 experiments in a table
   - Current strategy notes / dead ends from autoresearch.md
4. If no session files exist, say so.
