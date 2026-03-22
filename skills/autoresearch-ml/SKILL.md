---
name: autoresearch-ml
description: >-
  This skill should be used when the user asks to "train a model autonomously",
  "optimize LLM training", "run ML experiments", "autoresearch with GPU",
  "optimize val_bpb", "autonomous ML training", "LLM pretraining loop",
  "setup ML autoresearch", "GPU training experiments", or mentions
  "train.py", "prepare.py", "bits per byte", "val_bpb", "NVIDIA GPU training",
  "RTX training", "H100 training", "autonomous model training".
  Specialized ML/LLM training skill that extends the core autoresearch loop
  with GPU-specific workflows, data preparation, and a ready-to-use training template.
version: 0.1.0
---

# Autoresearch ML: Autonomous LLM Training Optimization

Extends the core `autoresearch` skill with specialized ML/LLM training workflows.
Provides a ready-to-use training template based on [Karpathy's autoresearch](https://github.com/karpathy/autoresearch)
for single-GPU LLM pretraining experiments.

**Prerequisites:** This skill builds on the core `autoresearch` skill. The experiment loop,
metric parsing, logging, and keep/discard logic are all handled by the core skill.
This skill adds ML-specific setup, GPU guidance, and the training template.

## Quick Start with Template

To set up ML autoresearch from the bundled template:

1. Copy asset files to the project directory:
   ```bash
   cp ${CLAUDE_PLUGIN_ROOT}/skills/autoresearch-ml/assets/prepare.py .
   cp ${CLAUDE_PLUGIN_ROOT}/skills/autoresearch-ml/assets/train.py .
   cp ${CLAUDE_PLUGIN_ROOT}/skills/autoresearch-ml/assets/pyproject.toml .
   cp ${CLAUDE_PLUGIN_ROOT}/skills/autoresearch-ml/assets/program.md .
   ```

2. Install dependencies:
   ```bash
   uv sync
   ```

3. Prepare data (downloads shards, trains tokenizer — ~2 min):
   ```bash
   uv run prepare.py
   ```

4. Run baseline training (~5 min):
   ```bash
   uv run train.py
   ```

5. Follow the core `autoresearch` skill to set up the experiment loop with:
   - **Command:** `uv run train.py`
   - **Primary metric:** `val_bpb` (bits per byte, lower is better)
   - **Files in scope:** `train.py` only (prepare.py is fixed)

## Template Architecture

### prepare.py (FIXED — never modify)

Handles all data infrastructure:

- **Data download:** Fetches parquet shards from HuggingFace (climbmix-400b-shuffle)
- **Tokenizer training:** Trains BPE tokenizer (8192 vocab) using rustbpe/tiktoken
- **Dataloader:** Best-fit document packing with 100% token utilization
- **Evaluation:** `evaluate_bpb()` computes bits-per-byte (vocab-size-independent metric)

Key constants:
- `MAX_SEQ_LEN = 2048` — context length
- `TIME_BUDGET = 300` — 5-minute training window (wall clock)
- `EVAL_TOKENS = 40 * 524288` — validation tokens
- `VOCAB_SIZE = 8192` — BPE vocabulary size

### train.py (MODIFIED BY AGENT — the only editable file)

Contains the full model and training loop:

- **Model:** GPT with RoPE, sliding window attention, value embeddings, Flash Attention 3
- **Optimizer:** Hybrid MuonAdamW (Muon for matrices, AdamW for everything else)
- **Training:** Gradient accumulation, LR schedules (warmup/flat/warmdown), fixed time budget
- **Output:** Prints `val_bpb` and other metrics after training completes

Editable hyperparameters include: `ASPECT_RATIO`, `DEPTH`, `WINDOW_PATTERN`,
`TOTAL_BATCH_SIZE`, learning rates, LR schedule phases, and the full model architecture.

### program.md (Agent instructions)

Self-contained instructions for the autonomous loop. Can be used directly with any
Claude-compatible agent. Follows the same edit → commit → run → measure → keep/discard pattern.

## GPU Requirements

### Minimum Requirements

- **NVIDIA GPU** with CUDA support (compute capability ≥ 7.0)
- **VRAM:** 16GB+ recommended (24GB+ for larger experiments)
- **CUDA:** 12.0+ (template targets CUDA 12.8)
- **Driver:** 535+ (check with `nvidia-smi`)

### Supported GPUs

| GPU | VRAM | Notes |
|-----|------|-------|
| RTX 4090 | 24GB | Great for experiments |
| RTX 5090 | 32GB | Excellent — more VRAM enables larger models |
| H100 | 80GB | Original development target |
| A100 | 40/80GB | Production-grade |

### GPU Verification

Before starting, verify GPU setup:

```bash
nvidia-smi                          # Check driver and GPU
python -c "import torch; print(torch.cuda.is_available())"  # Check PyTorch CUDA
python -c "import torch; print(torch.cuda.get_device_name())"  # Check device name
```

## ML-Specific Experiment Strategies

### What to Try

1. **Architecture changes:** Layer count, attention patterns, embedding dimensions
2. **Optimizer tuning:** Learning rates (per-parameter), schedule phases, momentum
3. **Attention patterns:** Window sizes, sliding window configurations
4. **Normalization:** RMS norm parameters, placement
5. **Regularization:** Dropout, weight decay, gradient clipping
6. **Batch size:** Trade-off between gradient quality and steps-per-budget

### Key Constraints

- **Fixed 5-minute time budget.** All experiments are directly comparable regardless of
  model size or architecture — the wall clock is the equalizer.
- **Single file modification.** Only `train.py` changes; `prepare.py` is immutable.
  This ensures fair comparison (same data, same evaluation).
- **VRAM is a soft constraint.** Using more VRAM is acceptable but note the trade-off
  (larger model = fewer training steps in 5 minutes).

### Decision Rule

- Lower `val_bpb` = improvement → keep
- Equal or higher `val_bpb` = regression → discard
- Crash (OOM, CUDA error) → discard, note the failure, try a smaller change

## Benchmark Script for ML

When setting up the autoresearch loop, use this as `autoresearch.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Run training (5 minutes, outputs metrics to stderr)
uv run train.py > run.log 2>&1

# Extract val_bpb from output
val_bpb=$(grep "^val_bpb:" run.log | tail -1 | awk '{print $2}')
memory=$(grep "^peak_memory:" run.log | tail -1 | awk '{print $2}' || echo "0")

echo "METRIC val_bpb=$val_bpb"
echo "METRIC peak_memory_gb=$memory"
```

## Additional Resources

### Reference Files

- **`references/gpu-training-guide.md`** — Detailed GPU setup, CUDA configuration, troubleshooting OOM errors, and performance tuning tips

### Asset Files

All files in `assets/` are ready to copy into a project:

- **`assets/prepare.py`** — Data preparation (download, tokenizer, dataloader, evaluation)
- **`assets/train.py`** — Model architecture and training loop
- **`assets/program.md`** — Self-contained agent instructions for the ML loop
- **`assets/pyproject.toml`** — Python dependencies (PyTorch, Flash Attention, etc.)
