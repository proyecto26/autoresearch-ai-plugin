---
name: autoresearch
description: >-
  This skill should be used when the user asks to "run autoresearch",
  "start an experiment loop", "optimize a metric autonomously",
  "autonomous experiments", "autoresearch setup", "benchmark loop",
  "keep/discard experiments", "optimize test speed", "optimize bundle size",
  "optimize build time", "run experiments overnight", or mentions
  "autoresearch", "experiment loop", "autonomous optimization".
  Provides the core autonomous experiment cycle: edit code, commit, run benchmark,
  extract metrics, keep improvements or revert, repeat forever.
version: 0.1.0
---

# Autoresearch: Autonomous Experiment Loop

An autonomous optimization loop where Claude edits code, runs a benchmark, measures a metric, and keeps improvements or reverts — repeating forever until stopped. Inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch) and [pi-autoresearch](https://github.com/davebcn87/pi-autoresearch).

## Core Concept

The loop is simple: **edit → commit → run → measure → keep or discard → repeat**.

- **Primary metric is king.** Lower (or higher, depending on direction) is better. Improved → keep the commit. Equal or worse → `git revert`.
- **State survives context resets** via `autoresearch.jsonl` (append-only log) and `autoresearch.md` (living session document).
- **Domain-agnostic.** Works for any measurable target: test speed, bundle size, LLM training loss, Lighthouse scores, build times, etc.

## Setup Phase

When the user triggers autoresearch, gather the following (ask if not provided):

1. **Goal** — what to optimize (e.g., "reduce unit test runtime")
2. **Command** — the benchmark to run (e.g., `pnpm test`, `uv run train.py`)
3. **Primary metric** — name, unit, and direction (`lower` or `higher` is better)
4. **Files in scope** — which files can be modified
5. **Constraints** — time budget, off-limits files, correctness requirements

Then execute these setup steps:

1. Create a branch: `git checkout -b autoresearch/<goal>-<date>`
2. Read all files in scope thoroughly to understand the codebase
3. Write `autoresearch.md` — the session document (see `examples/autoresearch.md`)
4. Write `autoresearch.sh` — the benchmark script (see `examples/autoresearch.sh`)
5. Optionally write `autoresearch.checks.sh` — correctness checks (tests, lint, types)
6. Commit both files
7. Run baseline: `bash autoresearch.sh`
8. Parse metrics from output (lines matching `METRIC name=value`)
9. Record baseline in `autoresearch.jsonl`
10. Begin the experiment loop

## The Experiment Loop

**LOOP FOREVER. Never ask "should I continue?" — just keep going.**

Each iteration:

```
1. Read current git state and autoresearch.md
2. Choose an experimental change (informed by past results)
3. Edit files in scope
4. git add <files> && git commit -m "experiment: <description>"
5. Run: bash autoresearch.sh > run.log 2>&1
6. Parse METRIC lines from output
7. If autoresearch.checks.sh exists, run it
8. Decide: keep or discard
9. Log result to autoresearch.jsonl
10. Update autoresearch.md with learnings
11. Repeat
```

### Decision Rules

- **Metric improved** → `keep` (commit stays)
- **Metric equal or worse** → `discard` (run `git revert HEAD --no-edit`)
- **Crash or checks failed** → `discard` (revert, note the failure)
- **Simpler code for equal perf** → `keep` (removing complexity is a win)
- **If stuck** → think deeper, try a different approach. Consult `autoresearch.ideas.md` if it exists.

### Metric Output Format

Benchmark scripts output metrics as structured lines:

```
METRIC total_time=4.23
METRIC memory_mb=512
METRIC val_bpb=1.042
```

Parse these with the helper script at `${CLAUDE_PLUGIN_ROOT}/skills/autoresearch/scripts/parse-metrics.sh`:

```bash
bash autoresearch.sh 2>&1 | bash ${CLAUDE_PLUGIN_ROOT}/skills/autoresearch/scripts/parse-metrics.sh
```

### Logging to autoresearch.jsonl

Each experiment appends one JSON line:

```json
{"commit":"abc123","metric":4.23,"status":"keep","description":"reduced batch size","timestamp":1700000000}
```

Use `${CLAUDE_PLUGIN_ROOT}/skills/autoresearch/scripts/log-experiment.sh` to append entries:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/autoresearch/scripts/log-experiment.sh \
  --commit "$(git rev-parse --short HEAD)" \
  --metric 4.23 \
  --status keep \
  --description "reduced batch size"
```

Valid statuses: `keep`, `discard`, `crash`, `checks_failed`

## Resuming After Context Reset

If `autoresearch.jsonl` and `autoresearch.md` exist in the working directory:

1. Read `autoresearch.md` for full context (goal, metrics, files, constraints)
2. Read `autoresearch.jsonl` to see all past experiments and current best
3. Resume the loop from where it left off — no re-setup needed

## Confidence Scoring

After 3+ experiments, assess whether improvements are real or noise:

- Compute the **Median Absolute Deviation (MAD)** of kept metrics as a noise floor
- **Confidence = |best improvement| / MAD**
- ≥2.0× → likely real improvement (green)
- 1.0–2.0× → marginal, could be noise (yellow)
- <1.0× → within noise floor (red)

For noisy benchmarks (timing-sensitive), run multiple iterations in `autoresearch.sh` and report the **median**.

See `references/confidence-scoring.md` for detailed methodology.

## Session Files

| File | Purpose | Created by |
|------|---------|------------|
| `autoresearch.md` | Living session document — goal, metrics, scope, learnings | Setup phase |
| `autoresearch.sh` | Benchmark script — outputs `METRIC name=value` lines | Setup phase |
| `autoresearch.checks.sh` | Optional correctness checks (tests, lint, types) | Setup phase |
| `autoresearch.jsonl` | Append-only experiment log (survives restarts) | First experiment |
| `autoresearch.ideas.md` | Optional backlog of ideas to try | Anytime |

## Additional Resources

### Reference Files

- **`references/confidence-scoring.md`** — Detailed MAD-based confidence methodology
- **`references/best-practices.md`** — Tips for writing good benchmarks, choosing experiments, and avoiding pitfalls

### Example Files

- **`examples/autoresearch.md`** — Example session document template
- **`examples/autoresearch.sh`** — Example benchmark script with METRIC output
- **`examples/autoresearch.checks.sh`** — Example correctness checks script

### Utility Scripts

- **`scripts/parse-metrics.sh`** — Extract METRIC lines from benchmark output
- **`scripts/log-experiment.sh`** — Append an experiment result to autoresearch.jsonl
