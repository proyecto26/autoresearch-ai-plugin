# GPU Training Guide for Autoresearch ML

## Environment Setup

### Python Environment

Use `uv` for fast, reproducible Python environments:

```bash
# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Create and sync environment
uv sync

# Verify PyTorch + CUDA
uv run python -c "import torch; print(f'CUDA: {torch.cuda.is_available()}, Device: {torch.cuda.get_device_name()}')"
```

### CUDA Verification Checklist

Before starting ML autoresearch:

```bash
# 1. Check NVIDIA driver
nvidia-smi

# 2. Check CUDA version
nvcc --version

# 3. Check PyTorch CUDA support
uv run python -c "
import torch
print(f'PyTorch: {torch.__version__}')
print(f'CUDA available: {torch.cuda.is_available()}')
print(f'CUDA version: {torch.version.cuda}')
print(f'Device: {torch.cuda.get_device_name()}')
print(f'VRAM: {torch.cuda.get_device_properties(0).total_mem / 1e9:.1f} GB')
"

# 4. Check Flash Attention support
uv run python -c "from kernels import flash_attn_func; print('Flash Attention OK')"
```

## Troubleshooting

### Out of Memory (OOM)

**Symptoms:** `torch.cuda.OutOfMemoryError` or `CUDA error: out of memory`

**Solutions (try in order):**

1. **Reduce `DEVICE_BATCH_SIZE`** in train.py (e.g., 128 → 64). Gradient accumulation
   maintains the effective batch size.
2. **Reduce `DEPTH`** — fewer layers = less VRAM
3. **Reduce `ASPECT_RATIO`** — smaller model dimensions
4. **Reduce `MAX_SEQ_LEN`** in prepare.py (if modifiable) — shorter sequences

**Rule of thumb:** VRAM usage ≈ model parameters × 12 bytes (fp32 weights + optimizer states + activations)

### CUDA Version Mismatch

**Symptoms:** `RuntimeError: CUDA error: no kernel image is available`

**Solutions:**

1. Check GPU compute capability: `nvidia-smi --query-gpu=compute_cap --format=csv`
2. Ensure PyTorch was built for your CUDA version
3. For RTX 5090 (Blackwell): ensure CUDA ≥ 12.8 and PyTorch ≥ 2.9

### Slow Training

**Symptoms:** Very few training steps within the 5-minute budget

**Solutions:**

1. Enable Flash Attention (already default in template)
2. Use `torch.compile()` for graph optimization
3. Ensure no CPU bottleneck in data loading (check `prepare.py` runs on GPU)
4. Disable debug mode: `CUDA_LAUNCH_BLOCKING=0`
5. Use `torch.backends.cudnn.benchmark = True` for fixed-size inputs

## Performance Tuning

### Environment Variables

```bash
# Optimal for training
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# For deterministic results (slightly slower)
export CUBLAS_WORKSPACE_CONFIG=:4096:8
```

### Memory Management

The template disables Python GC after the first training step to avoid stalls:

```python
import gc
gc.disable()  # After first step
```

This is intentional — GC pauses can waste significant time in a 5-minute budget.

### Multi-GPU Notes

The template is designed for **single-GPU** training only. For multi-GPU:

- Use `torchrun` or `accelerate` for distributed training
- Modify `train.py` to use `DistributedDataParallel`
- Adjust `DEVICE_BATCH_SIZE` per GPU
- This is an advanced modification outside the default template scope

## Metric: Bits Per Byte (BPB)

### What It Measures

BPB measures how well the model compresses text, normalized by byte count rather than
token count. This makes it **vocabulary-size-independent** — changing the tokenizer or
vocab size doesn't affect the metric, enabling fair comparison across architectures.

### Formula

```
BPB = (cross_entropy_loss × tokens_in_sequence) / bytes_in_sequence × log2(e)
```

Where:
- `cross_entropy_loss` = average negative log-likelihood per token
- `tokens_in_sequence` = number of tokens in the evaluation batch
- `bytes_in_sequence` = number of UTF-8 bytes in the original text
- `log2(e)` ≈ 1.4427 (converts from nats to bits)

### Interpreting BPB

| BPB Range | Quality |
|-----------|---------|
| > 2.0 | Poor — model barely compresses text |
| 1.5–2.0 | Moderate — basic patterns learned |
| 1.0–1.5 | Good — strong language modeling |
| < 1.0 | Excellent — near state-of-the-art compression |

### Why Not Perplexity?

Perplexity depends on vocabulary size — a model with 32K vocab and one with 8K vocab
produce incomparable perplexity values. BPB normalizes by bytes, making all architectures
comparable on a single metric.
