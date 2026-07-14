---
name: autoresearch
description: >-
  Autonomous experiment loop: edit code, commit, run benchmark, extract metrics,
  keep improvements or revert, repeat forever. Use this skill when the user asks
  to "run autoresearch", "start an experiment loop", "optimize a metric autonomously",
  "autonomous experiments", "benchmark loop",
  "keep/discard experiments", "optimize test speed", "optimize bundle size",
  "optimize build time", "run experiments overnight", "speed up my tests",
  "make my build faster", "reduce compile time",
  "keep trying until it's faster", "run experiments while I sleep",
  "overnight optimization", "edit-measure-keep loop",
  "autoresearch status", or mentions
  "autoresearch", "experiment loop", "autonomous optimization".
  Always use this skill when the user wants to iteratively and autonomously
  improve any measurable metric — even if they don't use the word "autoresearch".
  Also use when the user asks about the status of a running autoresearch session
  or wants to cancel/stop one.
version: 0.3.2
argument-hint: "[optimization goal]"
---

# Autoresearch: Autonomous Experiment Loop

An autonomous optimization loop where Claude edits code, runs a benchmark, measures a metric, and keeps improvements or reverts — repeating forever until stopped.

## Core Concept

The loop is simple: **edit → commit → run → measure → keep or discard → repeat**.

- **Primary metric is king.** Lower (or higher, depending on direction) is better. Improved → keep the commit. Equal or worse → `git revert`.
- **State survives context resets** via `autoresearch.jsonl` (append-only log) and `autoresearch.md` (living session document).
- **Domain-agnostic.** Works for any measurable target: test speed, bundle size, LLM training loss, Lighthouse scores, build times, etc.
- **Be careful not to overfit to the benchmarks and do not cheat on the benchmarks.** Optimize the real workload, not the measurement harness.

## Setup Phase

When the user triggers autoresearch, gather the following (ask if not provided). If `$ARGUMENTS` is provided, use it as the optimization goal:

1. **Goal** — what to optimize (e.g., "reduce unit test runtime") — use `$ARGUMENTS` if provided
2. **Command** — the benchmark to run (e.g., `pnpm test`, `uv run train.py`)
3. **Primary metric** — name, unit, and direction (`lower` or `higher` is better)
4. **Secondary metrics** — optional additional metrics to track for tradeoff monitoring (e.g., memory, compile time)
5. **Files in scope** — which files can be modified
6. **Constraints** — time budget, off-limits files, correctness requirements

Optionally check for `.claude/autoresearch-ai-plugin.local.md` in the project root for persistent configuration:

```markdown
---
enabled: true
max_iterations: 50
working_dir: "/path/to/project"
benchmark_timeout: 600
checks_timeout: 300
---

# Autoresearch Configuration

Additional context or notes for this project's autoresearch setup.
```

- `enabled` — whether autoresearch is active (default: true)
- `max_iterations` — stop after N experiments (default: 0 = unlimited)
- `working_dir` — override directory for experiment files (default: current directory)
- `benchmark_timeout` — benchmark timeout in seconds (default: 600)
- `checks_timeout` — correctness checks timeout in seconds (default: 300)

If the file doesn't exist, use defaults. The file should be added to `.gitignore` (`.claude/*.local.md`).

Then execute these setup steps:

1. Create a branch: `git checkout -b autoresearch/<goal>-<date>`
2. Gitignore the **living session files** — the ones that change every run. This is critical for two reasons: `git revert` will fail if `autoresearch.jsonl` is tracked, and if `autoresearch.md` (which you update mid-loop) is tracked, a broad experiment commit could sweep it in and a later revert would erase your learnings:
   ```bash
   printf '%s\n' autoresearch.jsonl autoresearch.md autoresearch.ideas.md run.log >> .gitignore
   git add .gitignore && git commit -m "autoresearch: add session files to gitignore"
   ```
3. Read all files in scope thoroughly to understand the codebase
4. Write `autoresearch.md` — the session document (see `examples/autoresearch.md`). It is gitignored (living state), so it is never committed or reverted.
5. Write `autoresearch.sh` — the benchmark script (see `examples/autoresearch.sh`)
6. Optionally write `autoresearch.checks.sh` — correctness checks (tests, lint, types)
7. Commit **only** the immutable harness — `autoresearch.sh` and (if present) `autoresearch.checks.sh`. These never change after setup (the file-protection hook enforces it), so keeping them in history is safe and aids reproducibility. Do **not** commit `autoresearch.md`/`.jsonl`/`.ideas.md` (gitignored above).
8. Run baseline: `bash autoresearch.sh`
9. Parse metrics from output (lines matching `METRIC name=value`)
10. Record baseline in `autoresearch.jsonl`: write the `"type":"config"` header, then a `{"type":"status","state":"running",...}` marker, then the baseline result
11. Begin the experiment loop

## The Experiment Loop

**LOOP FOREVER. Never ask "should I continue?" — just keep going.**

The user might be asleep, away from the computer, or expects you to work indefinitely. If each experiment takes ~5 minutes, you can run ~12/hour, ~100 overnight. The loop runs until the user interrupts you, period.

Each iteration:

```
0. Check stopping conditions: run `bash ${CLAUDE_SKILL_DIR}/scripts/session-status.sh --file autoresearch.jsonl [--max-iterations N]` and act on its VERDICT (concluded|max_iterations|wall|backstop|continue). Only continue if VERDICT=continue. (See "Stopping Conditions" for what the script computes and the spec it implements.)
1. Read current git state and autoresearch.md
2. Choose an experimental change (informed by past results and ASI notes)
3. Edit files in scope
4. git add <files-in-scope only> && git commit -m "experiment: <description>"
   (Commit ONLY the files in scope — never autoresearch.md/.jsonl/.ideas.md; they are gitignored so a revert can't erase them.)
5. Run: bash autoresearch.sh > run.log 2>&1
6. Parse METRIC lines from output
7. If autoresearch.checks.sh exists, run it (separate timeout, default 300s)
8. Decide: keep or discard
9. Log result to autoresearch.jsonl (include ASI annotations)
10. If discard/crash: git revert $(git rev-parse HEAD) --no-edit
11. Update autoresearch.md with learnings (every few experiments)
12. Repeat
```

### Decision Rules

- **Metric improved** → `keep` (commit stays, branch advances)
- **Metric equal or worse** → `discard` (run `git revert $(git rev-parse HEAD) --no-edit`)
- **Crash or checks failed** → `discard` (revert, note the failure in ASI)
- **Simpler code for equal perf** → `keep` (removing complexity is a win)
- **Catastrophic secondary metric regression** → consider `discard` even if primary improved (e.g., 1% speed gain but 10x memory usage)
- **If stuck** → think deeper, try a different approach. Consult `autoresearch.ideas.md` if it exists. Re-read source files for new angles. Try combining previous near-misses. Try more radical changes. Read any papers or docs referenced in the code.

### Simplicity Criterion

All else being equal, simpler is better. Weigh complexity cost against improvement magnitude:

- A 0.001 improvement that adds 20 lines of hacky code? Probably not worth it.
- A 0.001 improvement from deleting code? Definitely keep.
- Equal performance with much simpler code? Keep.

### Handling User Messages During Experiments

If the user sends a message while the loop is running:
1. Finish the current experiment cycle (don't abandon mid-run)
2. Address the user's feedback or question
3. Resume the loop immediately after — do not wait for permission

### Benchmark Timeout

- Default benchmark timeout: 600 seconds (10 minutes)
- If a run exceeds the timeout, kill it and treat as a crash
- Checks timeout: 300 seconds (5 minutes), separate from benchmark

### Don't Thrash

The **consecutive-failure streak** is the key signal, and it is defined so it can be recomputed from `autoresearch.jsonl` alone (never from memory — you may have been context-reset):

> Starting from the **last line** of `autoresearch.jsonl`, count backward the run entries whose `status` is `discard` or `crash`. Stop counting (streak resets to 0) at the first `keep`, the first `checks_failed`, or the first run belonging to an **earlier `segment`**.

- **Streak ≥ 3 → rethink (soft).** Stop grinding on the current angle:
  1. Think about *why* the last few failed.
  2. Re-read the source files for new angles.
  3. Try a fundamentally different approach.
  4. Consult `autoresearch.ideas.md` for untried ideas.
- **Streak > 8 → wall (terminal).** The current segment is stuck. Stop the session and report it (an orchestrated run returns `Status: WALL`). Starting a genuinely different direction usually means a new segment, which resets the streak.

The `> 8` boundary is deliberately high so a fruitful overnight loop with the occasional rough patch is never aborted — only a truly stuck segment trips it.

## Stopping Conditions

Compute these with `bash ${CLAUDE_SKILL_DIR}/scripts/session-status.sh --file autoresearch.jsonl [--max-iterations N]` at the top of every iteration (loop step 0) — it emits `SEGMENT`, `SEGMENT_RUNS`, `STREAK`, `LAST_STATUS`, `BACKSTOP_ACK`, and a single `VERDICT`, all **recomputed from `autoresearch.jsonl`** and scoped to the **current segment** (delimited by config headers), so they survive context resets. The rules the script implements — and which you follow directly if the script is unavailable:

- **Current-segment run count** = the number of run entries (`status` in `keep|discard|crash|checks_failed`) whose `segment` equals the current segment. Count the matching entries directly — do **not** use the `run` number for this, since `run` is a session-wide sequential counter that keeps climbing across segments (segment 1 might start at `run` 51), so it would over-count a fresh segment.
- **`max_iterations` reached** — if `max_iterations` > 0 (from `.claude/autoresearch-ai-plugin.local.md`) and the current-segment run count ≥ it → stop (`Status: DONE (max_iterations)`). `0` or absent = unlimited.
- **Unbounded-loop backstop (check-in, not a stop)** — when `max_iterations` is 0/unlimited, pause for a human check-in **every 200 current-segment runs** (at counts 200, 400, 600, …). On reaching a boundary `B` (a multiple of 200) for which the log holds no acknowledgement, append a **non-terminal** marker recording it — `{"type":"status","state":"running","backstop_ack":B,...}` — and stop *this dispatch* to ask the user before continuing. Two properties make the continuation coherent: the status stays `running` (so a confirmed relaunch is not blocked by the resume guard), and the `backstop_ack:B` record is durable in the log — so the next dispatch sees `B` is already acknowledged, does **not** re-pause at it, and runs on to the next un-acknowledged boundary. The pause rule is precisely: *pause at boundary `B` only if no status record already carries `backstop_ack` ≥ `B`.* An explicit `max_iterations` replaces this backstop with a hard stop.
- **Consecutive-failure wall** — streak > 8 (see Don't Thrash) → stop (`Status: WALL`).
- **Session already concluded** — if the last `{"type":"status",...}` record in the log is not `running` (e.g. `cancelled`/`done`), the session is over; do not silently resume it.

## Metric Output Format

Benchmark scripts output metrics as structured lines:

```
METRIC total_time=4.23
METRIC memory_mb=512
METRIC val_bpb=1.042
```

Parse these with the helper script at `${CLAUDE_SKILL_DIR}/scripts/parse-metrics.sh`:

```bash
bash autoresearch.sh 2>&1 | bash ${CLAUDE_SKILL_DIR}/scripts/parse-metrics.sh
```

### Secondary Metrics

Beyond the primary metric, output additional `METRIC` lines for tradeoff monitoring:

```
METRIC total_ms=4230        # primary
METRIC compile_ms=1200      # secondary — helps identify bottlenecks
METRIC memory_mb=512        # secondary — monitors resource usage
METRIC cache_hit_rate=0.85  # secondary — instrumentation data
```

Secondary metrics are tracked in the JSONL log and help guide future experiments, but they rarely affect keep/discard decisions (only discard if a catastrophic secondary regression accompanies a marginal primary improvement).

**Output instrumentation data** — phase timings, error counts, cache rates, domain-specific signals. This data guides the next iteration and helps identify where optimization effort should focus.

## Actionable Side Information (ASI)

ASI is structured annotation per experiment that **survives reverts**. When code changes are discarded, only the description and ASI remain — making them the only structured memory of what happened.

Record ASI for every experiment:

```json
{
  "hypothesis": "Reducing loop iterations by breaking early",
  "result": "Marginal speedup but code readability suffered",
  "next_action_hint": "Try vectorization instead of loop unrolling",
  "bottleneck": "Memory bandwidth on L2 cache misses"
}
```

ASI fields are free-form — use whatever keys are useful:
- `hypothesis` — what you expected
- `result` — what actually happened
- `next_action_hint` — guidance for the next experiment
- `bottleneck` — identified performance bottleneck
- `error_details` — crash/failure diagnostics
- Any other domain-specific observations

## Logging to autoresearch.jsonl

### Config Header (written once at setup)

```json
{"type":"config","name":"Optimize unit test runtime","metricName":"total_ms","metricUnit":"ms","bestDirection":"lower"}
```

### Status Marker (session lifecycle)

Immediately after the config header, append a status record, and append a new one whenever the session's lifecycle state changes:

```json
{"type":"status","state":"running","timestamp":1700000000}
```

- `state` — one of: `running` (session active — this also covers a backstop check-in, which pauses for confirmation without concluding), `done` (concluded normally, e.g. `max_iterations` reached or the user ended an unbounded run), `cancelled` (user stopped it), `wall` (consecutive-failure wall), `blocked` (needs user input).
- `backstop_ack` (optional, integer) — on a `running` marker only: records the 200-run backstop boundary the loop paused at for a check-in, so a later dispatch doesn't re-pause at the same boundary. See the backstop rule under Stopping Conditions.
- Write `running` at setup; write `done`/`wall`/`blocked` when the loop stops; write `cancelled` in the Cancel procedure.
- **Resume rule:** a session is resumable only if the **last** `status` record is `running` (or there is no status record — legacy logs). If the last status is `cancelled`/`done`/`wall`, do not silently resume — a concluded session stays concluded until the user explicitly restarts it.
- This marker is a deliberate non-run record; it does not have a `run` number and is skipped by run-counting. It is agent-written, not runtime-enforced, so a hard crash could leave a stale `running` — acceptable, since the alternative (treating any log as active forever) is worse.

### Experiment Results (appended after each run)

Each experiment appends one JSON line:

```json
{"run":5,"commit":"abc1234","metric":4230,"metrics":{"compile_ms":1200,"memory_mb":512},"status":"keep","description":"parallelized test suites","timestamp":1700000000,"segment":0,"confidence":2.3,"asi":{"hypothesis":"parallel tests reduce wall time","next_action_hint":"try worker pool size tuning"}}
```

Fields:
- `run` — experiment number (1-indexed, sequential)
- `commit` — short git commit hash (7 chars)
- `metric` — primary metric value
- `metrics` — secondary metrics dict (optional)
- `status` — one of: `keep`, `discard`, `crash`, `checks_failed`
- `description` — brief description of what was tried
- `timestamp` — Unix timestamp (seconds)
- `segment` — session segment index (0-based, incremented when optimization target changes)
- `confidence` — MAD-based confidence score (null if < 3 experiments)
- `asi` — Actionable Side Information dict (optional, omit if empty)

Use `${CLAUDE_SKILL_DIR}/scripts/log-experiment.sh` to append entries:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/log-experiment.sh \
  --run 5 \
  --commit "$(git rev-parse --short HEAD)" \
  --metric 4230 \
  --status keep \
  --description "parallelized test suites" \
  --metrics '{"compile_ms":1200,"memory_mb":512}' \
  --segment 0 \
  --confidence 2.3 \
  --asi '{"hypothesis":"parallel tests reduce wall time"}'
```

Valid statuses: `keep`, `discard`, `crash`, `checks_failed`

### Logging Invariants

Keep the log analyzable and the run-counts/streaks trustworthy:
- **Never log `keep` when correctness checks failed** — the status is `checks_failed` regardless of how good the metric looks. (This also keeps the failure streak honest: `checks_failed` breaks a discard/crash streak, so mislabeling it as `keep` would hide a stuck segment.)
- **Append-only** — never rewrite or delete past run entries; the log is the reconstructible source of truth. (The `{"type":"status",...}` marker is the one intentional non-run append; it is expected, not a violation.)
- **Secondary-metric consistency** — once a secondary metric name has appeared in `metrics`, include it in every later run; if it is genuinely unavailable for a run, say so in ASI rather than silently dropping it.

## Segments (Multi-Phase Sessions)

When the optimization target changes mid-session (different benchmark, metric, or workload):

1. Write a new config header to `autoresearch.jsonl` with the updated target
2. Increment the segment counter
3. Old results stay in the JSONL but are filtered as previous phase
4. Establish a new baseline for the new segment

This allows a single session to evolve — e.g., first optimize compilation speed, then switch to runtime performance.

## Resuming After Context Reset

If `autoresearch.jsonl` exists in the working directory (the authoritative session state):

1. Read `autoresearch.jsonl` to see all past experiments, current best, ASI annotations, and the **last `{"type":"status",...}` record**. If that last status is `cancelled`/`done`/`wall`, the session is concluded — do not silently resume; confirm with the user first. Only resume when the last status is `running` (or there is no status record — a legacy log).
2. Read `autoresearch.md` for full context (goal, metrics, files, constraints, learnings). If it is missing (it is gitignored, so a fresh clone won't have it), reconstruct it from the JSONL config header and git log.
3. Check `autoresearch.ideas.md` if it exists — prune stale entries, experiment with remaining ideas
4. Check git log to verify current branch state matches expected state
5. Re-check the Stopping Conditions (max_iterations, backstop, failure streak) from the log before continuing
6. Resume the loop from where it left off — no re-setup needed
7. **Resume immediately** if the session is active — do not ask "should I continue?"

## Confidence Scoring

After 3+ experiments, assess whether improvements are real or noise:

- Compute the **Median Absolute Deviation (MAD)** of all metric values in the current segment as a noise floor
- **Confidence = |best improvement| / MAD**
- ≥2.0× → likely real improvement (green)
- 1.0–2.0× → marginal, could be noise (yellow)
- <1.0× → within noise floor (red) — consider re-running to confirm

Record confidence on each experiment result in the JSONL log. When confidence is low, consider:
- Running the benchmark multiple times inside `autoresearch.sh` and reporting the median
- Pinning CPU frequency or reducing system noise
- Making larger changes that produce clearer signal

See `references/confidence-scoring.md` for detailed methodology.

## Session Files

| File | Purpose | Created by |
|------|---------|------------|
| `autoresearch.md` | Living session document — goal, metrics, scope, learnings | Setup phase |
| `autoresearch.sh` | Benchmark script — outputs `METRIC name=value` lines | Setup phase |
| `autoresearch.checks.sh` | Optional correctness checks (tests, lint, types) | Setup phase |
| `autoresearch.jsonl` | Append-only experiment log (survives restarts) | First experiment |
| `autoresearch.ideas.md` | Optional backlog of ideas to try | Anytime |
| `.claude/autoresearch-ai-plugin.local.md` | Optional persistent configuration (max_iterations, working_dir, timeouts) | User-provided |

## Cancel and Status

### Cancelling an Autoresearch Session

When the user asks to cancel or stop autoresearch:

1. Finish the current experiment cycle if one is running
2. Read `autoresearch.jsonl` to count total experiments and results
3. Report a summary: goal, total runs, kept improvements, best metric
4. Append a `{"type":"status","state":"cancelled","timestamp":...}` marker to `autoresearch.jsonl` — this is what makes the session stay stopped instead of being silently resumed later.
5. Do NOT delete `autoresearch.jsonl` or `autoresearch.md` — they contain valuable history
6. Do NOT delete `.claude/autoresearch-ai-plugin.local.md` — it is the user's persistent per-project config; the `cancelled` marker (not config removal) is what ends the session
7. Do NOT revert any kept commits — the improvements are real
8. Inform the user they can resume later with `/run-autoresearch` (which will see the `cancelled` marker and ask before restarting)

### Checking Session Status

When the user asks about autoresearch status or progress:

1. Check if `autoresearch.jsonl` exists — if not, report "No active session"
2. Read `autoresearch.md` for the goal and primary metric
3. Parse `autoresearch.jsonl` to compute: total runs, kept/discarded/crashed counts, baseline vs best, improvement percentage, confidence score, and the **lifecycle state** — the `state` of the last `{"type":"status",...}` record (`running`/`done`/`cancelled`/`wall`/`blocked`)
4. Display a formatted summary, including whether the session is active (last status `running`) or concluded

## Additional Resources

### Reference Files

- **`references/confidence-scoring.md`** — Detailed MAD-based confidence methodology
- **`references/best-practices.md`** — Tips for writing good benchmarks, choosing experiments, ASI patterns, and avoiding pitfalls

### Example Files

- **`examples/autoresearch.md`** — Example session document template
- **`examples/autoresearch.sh`** — Example benchmark script with METRIC output
- **`examples/autoresearch.checks.sh`** — Example correctness checks script

### Utility Scripts

- **`scripts/parse-metrics.sh`** — Extract METRIC lines from benchmark output
- **`scripts/log-experiment.sh`** — Append an experiment result to autoresearch.jsonl
- **`scripts/session-status.sh`** — Compute the stopping-condition state (SEGMENT_RUNS, STREAK, LAST_STATUS, BACKSTOP_ACK, VERDICT) from autoresearch.jsonl
