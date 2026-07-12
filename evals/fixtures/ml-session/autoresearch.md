# Autoresearch ML Session: Optimize val_bpb

## Goal
Lower validation bits-per-byte (val_bpb) for single-GPU LLM pretraining, 5-minute fixed budget per run.

## Primary Metric
- **Name:** val_bpb
- **Unit:** bpb
- **Direction:** lower is better

## Secondary Metrics
- peak_memory_mb, mfu_percent

## Files in Scope
- `train.py` (the ONLY editable file; prepare.py is immutable)

## Constraints
- Fixed 5-minute training budget per experiment
- No new packages
- 12GB VRAM budget

## Learnings
- Matrix LR 0.03 was a clear win over 0.02; 0.05 diverges into noise.
- DEPTH 8 fits in VRAM only with DEVICE_BATCH_SIZE halved to 64.
- Untried so far: warmdown schedule stretch (flagged twice in ASI hints).
