---
name: autoresearch-ml
description: >-
  Autonomous LLM training optimization with GPU support. Runs 5-minute training
  experiments, measures val_bpb, keeps improvements or reverts — repeat forever.
  Use this skill when the user asks to "train a model autonomously",
  "optimize LLM training", "run ML experiments", "autoresearch with GPU",
  "optimize val_bpb", "autonomous ML training", "LLM pretraining loop",
  "setup ML autoresearch", "set up ML autoresearch on my GPU",
  "GPU training experiments",
  "pretrain from scratch", "speed up training", "lower my loss",
  "GPU optimization", "CUDA training", or mentions "train.py", "prepare.py",
  "bits per byte", "val_bpb", "NVIDIA GPU training", "RTX 3090/4090/5090 training",
  "H100 training", "autonomous model training", "consumer GPU training",
  "low VRAM training". Always use this skill when the user wants to autonomously
  optimize any ML training metric.
version: 0.3.1
argument-hint: "[run tag or GPU description]"
---

# Autoresearch ML: Autonomous LLM Training Optimization

An autonomous experiment loop for single-GPU LLM pretraining. Edit `train.py` → commit → run 5-minute training → measure `val_bpb` → keep improvement or revert → **repeat forever**.

This skill is self-contained — it includes everything needed to set up and run the loop.

## Setup Phase

### 1. Copy Template Assets

Copy the bundled training template to the project directory:

```bash
cp ${CLAUDE_SKILL_DIR}/assets/prepare.py .
cp ${CLAUDE_SKILL_DIR}/assets/train.py .
cp ${CLAUDE_SKILL_DIR}/assets/pyproject.toml .
cp ${CLAUDE_SKILL_DIR}/assets/program.md .
```

### 2. Install and Prepare

```bash
uv sync                    # Install dependencies
uv run prepare.py          # Download data shards, train tokenizer (~2 min)
```

### 3. Verify GPU

```bash
nvidia-smi
python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}, Device: {torch.cuda.get_device_name()}, VRAM: {torch.cuda.get_device_properties(0).total_mem / 1e9:.1f} GB')"
```

### 4. Initialize the Experiment Session

1. Create a branch: `git checkout -b autoresearch/<tag>-<date>` — use `$ARGUMENTS` as the run tag if provided, otherwise propose one based on today's date
2. Gitignore the **living session files** — critical: `git revert` fails if `autoresearch.jsonl` is tracked, and if `autoresearch.md` (which you update mid-loop) is tracked, a revert can erase your learnings:
   ```bash
   printf '%s\n' autoresearch.jsonl autoresearch.md autoresearch.ideas.md run.log >> .gitignore
   git add .gitignore && git commit -m "autoresearch: add session files to gitignore"
   ```
3. Read `prepare.py` and `train.py` thoroughly to understand the codebase
4. Write `autoresearch.md` — a living session document recording goal, metrics, files in scope, constraints, and learnings. It is gitignored (living state), never committed or reverted.
5. Write `autoresearch.sh` — the benchmark script (see Benchmark Script section below)
6. Commit **only** `autoresearch.sh` (the immutable benchmark harness) — not `autoresearch.md`/`.jsonl` (gitignored above). `train.py` stays in history as normal.
7. Run baseline: `bash autoresearch.sh`
8. Parse metrics from output (lines matching `METRIC name=value`)
9. Record baseline in `autoresearch.jsonl`:
   - First write a config header: `{"type":"config","name":"Optimize val_bpb","metricName":"val_bpb","metricUnit":"bpb","bestDirection":"lower"}`
   - Then a status marker: `{"type":"status","state":"running","timestamp":...}`
   - Then record the baseline result
10. Begin the experiment loop

## The Experiment Loop

**LOOP FOREVER. Never ask "should I continue?" — just keep going.**

The user might be asleep, away from the computer, or expects you to work indefinitely. Each experiment takes ~5 minutes, so you can run ~12/hour, ~100 overnight. The loop runs until the user interrupts you, period. If you run out of ideas, think harder — re-read `train.py` for new angles, try combining previous near-misses, try more radical architectural changes.

Each iteration:

```
0. Check stopping conditions (see "Stopping Conditions" below). If any is met, stop and report — do not start another experiment.
1. Read current git state and autoresearch.md
2. Choose an experimental change to train.py (informed by past results and ASI notes)
3. Edit train.py (the ONLY editable file)
4. git add train.py && git commit -m "experiment: <description>"
   (Commit ONLY train.py — never autoresearch.md/.jsonl/.ideas.md; they are gitignored so a revert can't erase them.)
5. Run: bash autoresearch.sh > run.log 2>&1
6. Parse METRIC lines from output
7. If output is empty (crash): tail -n 50 run.log to read the stack trace
8. Decide: keep or discard
9. Log result to autoresearch.jsonl (include ASI annotations)
10. If discard/crash: git revert $(git rev-parse HEAD) --no-edit
11. Update autoresearch.md with learnings (every few experiments)
12. Repeat
```

### Stopping Conditions

Check these at the top of every iteration (loop step 0). All counts are **recomputed from `autoresearch.jsonl`** each time, scoped to the **current segment** (see Segments below), so they survive context resets:

- **Current-segment run count** = number of run entries (`status` in `keep|discard|crash|checks_failed`) whose `segment` equals the current segment. Count the matching entries directly — do **not** use the `run` number, which is a session-wide sequential counter that keeps climbing across segments and would over-count a fresh segment.
- **`max_iterations` reached** — if `max_iterations` > 0 (from `.claude/autoresearch-ai-plugin.local.md`, see the generic `autoresearch` skill's config section) and the current-segment run count ≥ it → stop (`Status: DONE (max_iterations)`). `0` or absent = unlimited.
- **Unbounded-loop backstop (check-in, not a stop)** — when `max_iterations` is 0/unlimited, pause for a human check-in **every 200 current-segment runs** (at 200, 400, 600, …). On reaching a boundary `B` (a multiple of 200) with no acknowledgement in the log, append a non-terminal marker `{"type":"status","state":"running","backstop_ack":B,...}` and stop this dispatch to ask the user. The status stays `running` (a confirmed relaunch isn't blocked) and the `backstop_ack:B` record is durable, so the next dispatch does not re-pause at `B`. Pause rule: *pause at boundary `B` only if no status record already carries `backstop_ack` ≥ `B`.* An explicit `max_iterations` replaces this with a hard stop.
- **Consecutive-failure wall** — streak > 8 (see Don't Thrash) → stop (`Status: WALL`).
- **Session already concluded** — if the last `{"type":"status",...}` record is not `running`, do not silently resume.

### Decision Rules

- **val_bpb improved (lower)** → `keep` (commit stays, branch advances)
- **val_bpb equal or worse** → `discard` (run `git revert $(git rev-parse HEAD) --no-edit`)
- **Crash (OOM, CUDA error, NaN loss)** → `discard` (revert). If it's a simple fix (typo, import), fix and re-run. If the idea is fundamentally broken, log as crash and move on.
- **Simpler code for equal val_bpb** → `keep` (removing complexity is a win)
- **Catastrophic VRAM increase** → consider `discard` even if val_bpb improved slightly

### Simplicity Criterion

All else being equal, simpler is better. A 0.001 val_bpb improvement that adds 20 lines of hacky code? Probably not worth it. A 0.001 improvement from deleting code? Definitely keep. Equal val_bpb with much simpler code? Keep.

### Constraints

- **Fixed 5-minute time budget.** All experiments are directly comparable — the wall clock is the equalizer.
- **Single file modification.** Only `train.py` changes; `prepare.py` is immutable. This ensures fair comparison (same data, same evaluation).
- **VRAM is a soft constraint.** Using more VRAM is acceptable but note the trade-off (larger model = fewer training steps in 5 minutes).
- **No new packages.** You can only use what's already in `pyproject.toml`.
- **Timeout:** If a run exceeds 10 minutes, kill it and treat as a crash.

### Don't Thrash

The **consecutive-failure streak** is recomputed from `autoresearch.jsonl` (never from memory): starting from the last line, count backward the runs whose `status` is `discard` or `crash`; stop (reset to 0) at the first `keep`, the first `checks_failed`, or the first run in an **earlier `segment`**.

- **Streak ≥ 3 → rethink (soft):** stop, think about *why* the last few failed, re-read `train.py` for new angles, try a fundamentally different approach.
- **Streak > 8 → wall (terminal):** the segment is stuck; stop and report (`Status: WALL`). A genuinely different direction usually means a new segment, which resets the streak.

The `> 8` boundary is deliberately high so a fruitful overnight run with the occasional crash isn't aborted — only a truly stuck segment trips it.

### Handling User Messages

If the user sends a message while the loop is running: finish the current cycle, address the feedback, then resume immediately — do not wait for permission.

## Logging to autoresearch.jsonl

Each experiment appends one JSON line:

```json
{"run":2,"commit":"def5678","metric":0.993,"metrics":{"peak_memory_mb":44200,"mfu_percent":39.8},"status":"keep","description":"increase LR to 0.04","timestamp":1700000000,"segment":0,"confidence":null,"asi":{"hypothesis":"higher LR converges faster","arch_change":"MATRIX_LR 0.03→0.04"}}
```

Use the shared logging script:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/log-experiment.sh \
  --run 2 \
  --commit "$(git rev-parse --short HEAD)" \
  --metric 0.993 \
  --status keep \
  --description "increase LR to 0.04" \
  --metrics '{"peak_memory_mb":44200,"mfu_percent":39.8}' \
  --segment 0 \
  --asi '{"hypothesis":"higher LR converges faster"}'
```

Parse metrics from benchmark output:

```bash
bash autoresearch.sh 2>&1 | bash ${CLAUDE_SKILL_DIR}/scripts/parse-metrics.sh
```

Valid statuses: `keep`, `discard`, `crash`, `checks_failed`

### Status Marker & Logging Invariants

Alongside run entries, the log carries a session-lifecycle marker (identical semantics to the generic `autoresearch` skill):

```json
{"type":"status","state":"running","timestamp":1700000000}
```

Write `running` at setup, `done`/`wall`/`blocked` when the loop stops, `cancelled` on user cancel. A session resumes only if the **last** `status` record is `running` (or there is none — legacy log). The marker has no `run` number and is skipped by run-counting.

Invariants: never log `keep` when correctness checks failed (it is `checks_failed`); the log is append-only (the status marker is the one intentional non-run append); once a secondary metric appears, include it every run.

## Segments (Multi-Phase Sessions)

A **segment** groups runs under one optimization target. When the target changes materially — a different architecture family, a different eval, or a changed time budget — start a new segment so old runs are filtered as a previous phase without being lost:

1. Write a new config header to `autoresearch.jsonl` with the updated target.
2. Increment `segment` on all subsequent runs.
3. Establish a fresh baseline for the new segment.

Everything scoped "to the current segment" resets at a segment boundary: the baseline, the confidence (MAD) noise floor, the consecutive-failure streak, and the `max_iterations`/backstop run count. This is why the Stopping Conditions and Don't Thrash rules all say "current segment" — a new research direction gets a clean slate rather than inheriting the previous phase's failures or run budget.

## ASI (Actionable Side Information)

ASI is structured annotation per experiment that **survives reverts**. When code changes are discarded, only the description and ASI remain — the only structured memory of what happened.

Record ASI for every experiment:

```json
{
  "hypothesis": "Deeper model with fewer steps should compress better",
  "arch_change": "DEPTH 8→12, DEVICE_BATCH_SIZE 128→64",
  "result": "val_bpb improved 0.998→0.992, but 2x VRAM",
  "next_action_hint": "Try intermediate DEPTH=10 for better VRAM tradeoff"
}
```

## Resuming After Context Reset

If `autoresearch.jsonl` exists in the working directory (the authoritative session state):

1. Read `autoresearch.jsonl` for all past experiments, current best, ASI, and the **last `{"type":"status",...}` record**. Resume only if that last status is `running` (or none — legacy log); if it is `cancelled`/`done`/`wall`, confirm with the user before restarting.
2. Read `autoresearch.md` for full context; if missing (it is gitignored), reconstruct it from the JSONL config header and git log.
3. Check git log to verify current branch state matches expected state.
4. If git state is dirty (unclean shutdown), revert **only known experiment leftovers** — an uncommitted `train.py` edit from an interrupted experiment. Do not blindly discard changes you cannot attribute to the loop; if unsure what a dirty change is, stop and ask.
5. Re-check the Stopping Conditions from the log before continuing.
6. Resume the loop from where it left off — no re-setup needed.
7. **Resume immediately** if the session is active — do not ask "should I continue?"

## Confidence Scoring

After 3+ experiments, assess whether improvements are real or noise:

- Compute the **Median Absolute Deviation (MAD)** of all metric values as a noise floor
- **Confidence = |best improvement| / MAD**
- ≥2.0× → likely real improvement
- 1.0–2.0× → marginal, could be noise
- <1.0× → within noise floor

ML training with fixed seeds is mostly deterministic, so the noise floor is typically very low.

## Template Architecture

### prepare.py (FIXED — never modify)

- **Data download:** Fetches parquet shards from HuggingFace (climbmix-400b-shuffle)
- **Tokenizer training:** BPE tokenizer (8192 vocab) using rustbpe/tiktoken
- **Dataloader:** Best-fit document packing with 100% token utilization, BOS-aligned
- **Evaluation:** `evaluate_bpb()` computes bits-per-byte (vocab-size-independent metric)

Key constants: `MAX_SEQ_LEN = 2048`, `TIME_BUDGET = 300`, `EVAL_TOKENS = 40 * 524288`, `VOCAB_SIZE = 8192`

### train.py (MODIFIED BY AGENT — the only editable file)

- **Model:** GPT with RoPE, sliding window attention, value embeddings, Flash Attention 3
- **Optimizer:** Hybrid MuonAdamW (Muon for matrices, AdamW for everything else)
- **Training:** Gradient accumulation, LR schedules (warmup/flat/warmdown), fixed time budget

Editable: `ASPECT_RATIO`, `DEPTH`, `WINDOW_PATTERN`, `TOTAL_BATCH_SIZE`, learning rates, LR schedule phases, and the full model architecture.

## GPU Requirements

### Supported GPU Tiers

| Tier | GPUs | VRAM | Notes |
|------|------|------|-------|
| **Consumer** | GTX 1080 Ti, RTX 2080 Ti | 11GB | fp32 fallback, gradient checkpointing required |
| **Consumer+** | RTX 3090, RTX 4090 | 24GB | Great for experiments |
| **Enthusiast** | RTX 5090 | 32GB | Excellent — larger models possible |
| **Datacenter** | A100, H100 | 40-80GB | Original development target |

### Consumer GPU Adaptations

For GPUs with limited VRAM (< 16GB), apply these changes to `train.py` during the first experiment:

1. **Remove Flash Attention 3 import and dependency** — the top-level `from kernels import get_kernel` block (lines 20-24) runs unconditionally at startup and will fail on non-Hopper GPUs. Replace the entire block and the `fa3.flash_attn_func()` call in `CausalSelfAttention.forward()` with `torch.nn.functional.scaled_dot_product_attention`. Also remove `kernels` from `pyproject.toml` and run `uv sync` again.
2. **Enable gradient checkpointing** — use `torch.utils.checkpoint.checkpoint()` with `use_reentrant=False` to trade ~30% compute for ~50% VRAM savings
3. **Auto-scale model size** — reduce `DEPTH` and `DEVICE_BATCH_SIZE` to fit VRAM budget (see table below)
4. **Cap evaluation steps** — scale eval batch count by available VRAM (30-100 steps)
5. **fp32 fallback** — use fp32 instead of bf16 for Pascal GPUs (compute capability < 7.5). Change the autocast dtype and disable bf16-specific optimizations.

### VRAM Auto-Scaling Guide

| VRAM Budget | DEPTH | n_embd | Batch Size | Seq Length | ~Params |
|-------------|-------|--------|------------|------------|---------|
| 4GB | 2 | 128 | 4 | 512 | ~1M |
| 8GB | 4 | 256 | 8 | 1024 | ~5M |
| 12GB | 6 | 384 | 16 | 1024 | ~14M |
| 16GB | 8 | 512 | 32 | 2048 | ~25M |
| 24GB | 8 | 512 | 128 | 2048 | ~50M |
| 32GB | 12 | 768 | 128 | 2048 | ~85M |
| 80GB | 16 | 1024 | 128 | 2048 | ~200M |

**Note:** `n_embd` must be a multiple of `HEAD_DIM` (default 128). Config search: start with the largest depth that fits, reduce `DEVICE_BATCH_SIZE` then `MAX_SEQ_LEN` if OOM.

## Experiment Strategies

1. **Architecture:** Layer count, attention patterns, embedding dimensions, activation functions
2. **Optimizer:** Learning rates (per-parameter), schedule phases, momentum, weight decay
3. **Attention:** Window sizes, sliding window configs, full vs. local attention
4. **Batch size:** Trade-off between gradient quality and steps-per-budget
5. **Initialization:** Weight init schemes, residual scaling parameters
6. **Advanced:** Value embeddings, softcapped logits, GQA

## Metric: Bits Per Byte (BPB)

How well the model compresses text, normalized by byte count. Vocabulary-size-independent — all architectures are directly comparable. Lower is better. See `references/gpu-training-guide.md` for the formula and interpretation table.

## Benchmark Script

Use this as `autoresearch.sh`:

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

## Session Files

| File | Purpose |
|------|---------|
| `autoresearch.md` | Living session document — goal, metrics, scope, learnings |
| `autoresearch.sh` | Benchmark script — outputs `METRIC name=value` lines |
| `autoresearch.jsonl` | Append-only experiment log with ASI (survives restarts) |

## Additional Resources

- **`references/gpu-training-guide.md`** — Detailed GPU setup, CUDA configuration, OOM troubleshooting, BPB formula, and performance tuning
- **`scripts/parse-metrics.sh`** — Extract METRIC lines from benchmark output
- **`scripts/log-experiment.sh`** — Append experiment results to autoresearch.jsonl
- **`assets/prepare.py`** — Data preparation (download, tokenizer, dataloader, evaluation)
- **`assets/train.py`** — Model architecture and training loop
- **`assets/program.md`** — Self-contained agent instructions for the ML loop
- **`assets/pyproject.toml`** — Python dependencies (PyTorch, Flash Attention, etc.)
