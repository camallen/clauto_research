# Comparison: autoresearch-plugin vs uditgoenka/autoresearch

Both projects implement autonomous iterative optimization loops for Claude Code, inspired by Karpathy's autoresearch principles. They share the same core concept (goal → measure → modify → verify → keep/revert → repeat) but differ significantly in architecture, scope, and implementation.

---

## Architecture

| Aspect | autoresearch-plugin (this repo) | uditgoenka/autoresearch |
|--------|--------------------------------|-------------------------|
| **Format** | Claude plugin (`.claude-plugin/`) | Claude skill (`SKILL.md` + references) |
| **Implementation** | Bash scripts + Markdown commands | Pure Markdown (no code files) |
| **Loop mechanism** | Stop hook (`stop-hook.sh`) intercepts session end, increments iteration, re-injects prompt | Relies on Claude Code's `/loop N` command or unbounded self-continuation |
| **State management** | YAML frontmatter in `.claude/clauto_research-loop.local.md` + JSON Lines log | TSV log (`autoresearch-results.tsv`) + git history |
| **Setup** | Bash script (`scripts/setup-autoresearch.sh`) generates all session files | Pure prompt-driven setup within SKILL.md |
| **Termination** | `<promise>GOAL MET</promise>` tags detected by hook | Bounded via `/loop N`, unbounded runs until `Ctrl+C` |

## Feature Comparison

| Feature | This repo | uditgoenka/autoresearch |
|---------|-----------|-------------------------|
| Core optimization loop | Yes | Yes |
| Planning wizard | No | Yes (`/autoresearch:plan` — 7-phase interactive wizard) |
| Security audit | No | Yes (`/autoresearch:security` — STRIDE + OWASP + red-team) |
| Guard clause (regression prevention) | No | Yes (optional secondary verification) |
| Dashboard command | Yes (`/dashboard`) | No (inline progress summaries every ~10 iterations) |
| Cancel command | Yes (`/cancel`) | No (`Ctrl+C` or loop bound) |
| Validation gate | Yes (`clauto_research.checks.sh` template) | Yes (guard mechanism, more formalized) |
| Crash recovery protocol | No explicit protocol | Yes (max 3 fix attempts, timeout rules, OOM handling) |
| "When stuck" strategy | No | Yes (>5 consecutive discards triggers re-read + radical experiments) |
| Domain adaptation table | No | Yes (backend, frontend, ML, content, performance, refactoring) |
| CI/CD integration | No | Yes (`--fail-on`, `--diff` delta mode) |
| Bounded iterations | Yes (`max_iterations` in config) | Yes (via `/loop N`) |
| Unbounded iterations | Yes (`max_iterations=0`) | Yes (default mode) |
| Session isolation | Yes (session_id tracking) | No |

## State & Logging

| Aspect | This repo | uditgoenka/autoresearch |
|--------|-----------|-------------------------|
| Results format | JSON Lines (`clauto_research.jsonl`) | TSV (`autoresearch-results.tsv`) |
| Fields tracked | timestamp, iteration, metric_name, metric_value, baseline, best, status, description, commit | iteration, commit, metric, delta, guard, status, description |
| State file | `.claude/clauto_research-loop.local.md` with YAML frontmatter | No separate state file — loop state is implicit in `/loop` counter |
| Living doc | `clauto_research.md` (objective, config, strategies, dead ends) | None — relies on git history + results log |
| Git revert strategy | `git revert HEAD --no-edit` (preserves history) | `git reset --hard HEAD~1` (destructive) |

## Loop Mechanics

**This repo (hook-driven):** The stop hook (`stop-hook.sh`) is the engine. It reads the transcript, checks for completion promises, increments the iteration count in the state file, and injects a system message to trigger the next iteration. This works independently of Claude Code's built-in loop features.

**uditgoenka/autoresearch (prompt-driven):** SKILL.md instructs Claude to "loop until done" or relies on `/loop N` for bounded runs. No external script manages iterations — the agent itself is responsible for continuing. Simpler, but depends on Claude reliably following the "never stop, never ask permission" instruction.

## Strengths

### This repo
- **Mechanical loop control** via hooks — more reliable than agent self-continuation
- **Session isolation** — session_id tracking prevents cross-session state pollution
- **Safer git strategy** — `git revert` preserves full experiment history vs destructive `git reset --hard`
- **Richer state tracking** — living document with strategies and dead ends
- **Dashboard command** for quick status checks mid-run

### uditgoenka/autoresearch
- **Broader feature set** — security audits, planning wizard, guard clauses
- **Pure markdown** — no bash scripts to maintain
- **Crash recovery protocol** with explicit rules for different failure types
- **"When stuck" strategy** for breaking out of plateaus after repeated failures
- **Domain adaptation** with metric/verify suggestions per project type
- **CI/CD integration** for pipeline gating (`--fail-on`, `--diff`)
- **More detailed iteration protocol** (explicit 8-phase cycle)

## Potential Cross-Pollination

**Features this repo could adopt:**
- Guard clause (secondary verification to prevent regressions)
- Crash recovery protocol (explicit rules for syntax errors, runtime errors, OOM, hangs)
- "When stuck" strategy (>5 consecutive discards → re-read everything, try radical changes)
- Planning wizard (interactive setup vs CLI args)
- Domain adaptation table (suggested metrics per project type)

**Features the remote could adopt:**
- Hook-based loop control (more reliable than self-continuation)
- Session isolation (cross-session safety)
- Safe revert strategy (`git revert` over `git reset --hard`)
- Living strategy document (`clauto_research.md`)
- Dashboard command
