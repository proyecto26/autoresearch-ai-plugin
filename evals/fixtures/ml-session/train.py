# Eval-fixture stub of the training script — NOT runnable.
# Stands in for skills/autoresearch-ml/assets/train.py so status/advice
# evals have a file to reference without requiring a GPU.

ASPECT_RATIO = 64
DEPTH = 8
DEVICE_BATCH_SIZE = 64
TOTAL_BATCH_SIZE = 524288
MATRIX_LR = 0.03
EMBED_LR = 0.2
WARMUP_FRAC = 0.0
WARMDOWN_FRAC = 0.4

if __name__ == "__main__":
    raise SystemExit("fixture stub — no GPU training in evals")
