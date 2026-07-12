---
description: Run an autonomous experiment loop via the Autoresearch Orchestrator agent
argument-hint: "[optimization goal | status | cancel]"
allowed-tools: ["Read", "Grep", "Glob", "Bash", "Task"]
---

# /run-autoresearch — managed experiment loop

Manage an autoresearch session for this project. Arguments: "$ARGUMENTS"

## Route the request

**If the argument is `status`** (or asks how the session is going): follow the *Checking Session Status* procedure from the `autoresearch` skill — read `autoresearch.jsonl` and `autoresearch.md`, compute totals/baseline/best/confidence, and display the summary. Do not launch the agent.

**If the argument is `cancel` or `stop`:** follow the *Cancelling an Autoresearch Session* procedure from the `autoresearch` skill — summarize results, preserve `autoresearch.jsonl`/`autoresearch.md` and kept commits. Do not launch the agent.

**Otherwise, run a session:**

1. **Detect session type.**
   - Existing session: `autoresearch.jsonl` present (the authoritative state file) → resume; no questions needed. If only `autoresearch.md` exists (interrupted setup), treat it as a new session — setup reuses the doc's parameters.
   - ML training session: the goal mentions LLM/GPU training, `val_bpb`, pretraining — or the project contains the `train.py`/`prepare.py` template → use the `autoresearch-ml` skill protocol.
   - Anything else → the generic `autoresearch` skill protocol.

2. **Gather setup parameters** (new sessions only). Required before dispatch: goal, benchmark command, primary metric (name, unit, direction), files in scope, constraints. Take them from "$ARGUMENTS" and the project; ask the user only for what cannot be inferred. Check `.claude/autoresearch-ai-plugin.local.md` for `max_iterations`, `working_dir`, and timeouts.

3. **Dispatch the `autoresearch-orchestrator` agent** (Task tool) with a complete brief:
   - session type (generic | ml) and the corresponding skill to follow
   - goal, benchmark command, metric name/unit/direction, files in scope, constraints
   - config values from the local settings file
   - batch size for this dispatch (default 10 experiments per checkpoint)

4. **Handle the checkpoint** the agent returns:
   - Relay the checkpoint report to the user verbatim.
   - `CONTINUE` → relaunch the orchestrator immediately for the next batch (do not ask permission; the user started an autonomous loop and can interrupt anytime).
   - `DONE` / `WALL` → report final summary: total runs, kept improvements, baseline → best with percentage, and the top untried ASI hints.
   - `BLOCKED` → surface the blocker and ask the user how to proceed.

## Guardrails

- State persists in `autoresearch.jsonl` + `autoresearch.md`; the loop survives context resets and can be resumed later with `/run-autoresearch` alone.
- Never let the orchestrator (or yourself) modify `autoresearch.sh`, `autoresearch.checks.sh`, or `prepare.py` after creation. The plugin's file-protection hook blocks Write/Edit changes; shell writes are not intercepted, so the prohibition applies to Bash commands as well.
- Respect `max_iterations` from `.claude/autoresearch-ai-plugin.local.md`; stop relaunching once reached. `max_iterations: 0` or absent means unlimited.
