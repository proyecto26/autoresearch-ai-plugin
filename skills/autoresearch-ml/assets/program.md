# autoresearch

Autonomous LLM pretraining research — edit `train.py`, run 5-minute training, measure `val_bpb`, keep improvement or revert, repeat forever.

## Setup

To set up a new experiment, work with the user to:

1. **Agree on a run tag**: propose a tag based on today's date (e.g. `mar5`). The branch `autoresearch/<tag>-<date>` must not already exist.
2. **Create the branch**: `git checkout -b autoresearch/<tag>-<date>` from current main.
3. **Read the in-scope files** for full context:
   - `prepare.py` — fixed constants, data prep, tokenizer, dataloader, evaluation. Do not modify.
   - `train.py` — the file you modify. Model architecture, optimizer, training loop.
4. **Verify data exists**: Check that `~/.cache/autoresearch/` contains data shards and a tokenizer. If not, tell the human to run `uv run prepare.py`.
5. **Ensure session files are gitignored** (critical — `git revert` will fail if tracked):
   ```bash
   echo -e "autoresearch.jsonl\nrun.log" >> .gitignore
   git add .gitignore && git commit -m "autoresearch: add session files to gitignore"
   ```
6. **Write `autoresearch.md`** — a living session document recording goal, metrics, files in scope, constraints, and learnings. Update after every few experiments.
7. **Write `autoresearch.sh`** — the benchmark script:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   uv run train.py > run.log 2>&1
   val_bpb=$(grep "^val_bpb:" run.log | tail -1 | awk '{print $2}' || echo "0")
   memory=$(grep "^peak_vram_mb:" run.log | tail -1 | awk '{print $2}' || echo "0")
   mfu=$(grep "^mfu_percent:" run.log | tail -1 | awk '{print $2}' || echo "0")
   echo "METRIC val_bpb=$val_bpb"
   echo "METRIC peak_memory_mb=$memory"
   echo "METRIC mfu_percent=$mfu"
   ```
8. **Commit session files**, run baseline (`bash autoresearch.sh`), and record in `autoresearch.jsonl`.
9. **Initialize autoresearch.jsonl**: Write a config header, then the baseline result:
   ```json
   {"type":"config","name":"Optimize val_bpb","metricName":"val_bpb","metricUnit":"bpb","bestDirection":"lower"}
   ```
10. **Confirm and go**: Confirm setup looks good, then kick off the experimentation.

## Experimentation

Each experiment runs on a single GPU. The training script runs for a **fixed time budget of 5 minutes** (wall clock training time, excluding startup/compilation).

**What you CAN do:**
- Modify `train.py` — this is the only file you edit. Everything is fair game: model architecture, optimizer, hyperparameters, training loop, batch size, model size, etc.

**What you CANNOT do:**
- Modify `prepare.py`. It is read-only.
- Install new packages or add dependencies.
- Modify the evaluation harness.

**The goal is simple: get the lowest val_bpb.** The time budget is fixed at 5 minutes. Everything is fair game.

**VRAM** is a soft constraint. Some increase is acceptable for meaningful val_bpb gains, but it should not blow up dramatically.

**Simplicity criterion**: All else being equal, simpler is better. A 0.001 val_bpb improvement that adds 20 lines of hacky code? Probably not worth it. A 0.001 val_bpb improvement from deleting code? Definitely keep. Equal val_bpb with simpler code? Keep.

**The first run**: Always establish the baseline by running the training script as is.

## The experiment loop

The experiment runs on a dedicated branch (e.g. `autoresearch/mar5-<date>`).

LOOP FOREVER:

1. Read current git state and `autoresearch.md`
2. Choose an experimental change to `train.py` (informed by past results and ASI notes)
3. Edit `train.py` (the ONLY editable file)
4. `git add train.py && git commit -m "experiment: <description>"`
5. Run: `bash autoresearch.sh > run.log 2>&1`
6. Parse METRIC lines from output
7. If output is empty (crash): `tail -n 50 run.log` to read the stack trace
8. Decide: keep or discard
9. Record results in `autoresearch.jsonl` with ASI annotations
10. If discard/crash: `git revert $(git rev-parse HEAD) --no-edit`
11. Update `autoresearch.md` with learnings (every few experiments)
12. Repeat

**Timeout**: If a run exceeds 10 minutes, kill it and treat as a crash.

**Crashes**: If it's a simple fix (typo, import), fix and re-run. If fundamentally broken, log as crash and move on.

**NEVER STOP**: Once the experiment loop has begun, do NOT pause to ask the human if you should continue. Do NOT ask "should I keep going?" or "is this a good stopping point?". The human might be asleep, or gone from a computer and expects you to continue working *indefinitely* until you are manually stopped. You are autonomous. If you run out of ideas, think harder — re-read the in-scope files for new angles, try combining previous near-misses, try more radical architectural changes. The loop runs until the human interrupts you, period.

## Logging results

When an experiment is done, log it to `autoresearch.jsonl` (one JSON object per line). Do NOT commit the log file — leave it untracked by git.

Each experiment appends one JSON line:

```json
{"run":1,"commit":"a1b2c3d","metric":0.9979,"metrics":{"peak_memory_mb":45060,"mfu_percent":39.8},"status":"keep","description":"baseline","timestamp":1700000000,"segment":0,"confidence":null,"asi":{"hypothesis":"establish baseline"}}
```

Fields:
- `run` — experiment number (1-indexed, sequential)
- `commit` — git commit hash (short, 7 chars)
- `metric` — val_bpb achieved — use 0 for crashes
- `metrics` — secondary metrics: `peak_memory_mb`, `mfu_percent`
- `status` — one of: `keep`, `discard`, `crash`, `checks_failed`
- `description` — short text describing what was tried
- `timestamp` — Unix timestamp (seconds)
- `segment` — session segment index (0-based)
- `confidence` — MAD-based confidence score (null if < 3 experiments)
- `asi` — Actionable Side Information: structured annotations that survive reverts

### ASI (Actionable Side Information)

Record ASI for every experiment — especially discards and crashes. When code changes are reverted, ASI is the only structured memory of what happened.

```json
{"hypothesis":"deeper model compresses better","arch_change":"DEPTH 8→12","result":"val_bpb 0.998→0.992 but 2x VRAM","next_action_hint":"try DEPTH=10 for balance"}
```

## Resuming after context reset

If `autoresearch.jsonl` and `autoresearch.md` exist in the working directory:

1. Read `autoresearch.md` for full context
2. Read `autoresearch.jsonl` to see all past experiments, current best, and ASI annotations
3. Check git log to verify current branch state
4. Resume the loop immediately — do not ask "should I continue?"
