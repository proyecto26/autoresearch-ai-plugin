# Confidence Scoring for Autoresearch

## Purpose

When optimizing a metric through repeated experiments, noise is unavoidable. A benchmark
that reports 4.2s one run might report 4.1s the next — without any code change. Confidence
scoring separates real improvements from measurement noise.

## Methodology: Median Absolute Deviation (MAD)

MAD is a robust estimator of variability, less sensitive to outliers than standard deviation.

### Computing the Noise Floor

Given a set of "kept" metric values `[m1, m2, ..., mn]`:

1. Compute the median: `M = median(m1, m2, ..., mn)`
2. Compute absolute deviations: `d_i = |m_i - M|`
3. Compute MAD: `MAD = median(d1, d2, ..., dn)`

The MAD represents the typical run-to-run variation (noise floor).

### Computing Confidence

For the best improvement observed:

```
confidence = |best_metric - baseline_metric| / MAD
```

### Interpreting Confidence

| Confidence | Color  | Interpretation |
|------------|--------|----------------|
| ≥ 2.0×     | Green  | Likely a real improvement — signal is 2× the noise |
| 1.0–2.0×   | Yellow | Marginal — could be real, could be noise |
| < 1.0×     | Red    | Within the noise floor — probably not real |

### Minimum Experiments

Confidence scoring requires at least 3 experiments to be meaningful. With fewer data
points, MAD is unreliable.

## Practical Tips

### For Noisy Benchmarks (Timing)

Wall-clock benchmarks are inherently noisy. To reduce noise:

- Run the benchmark **3-5 times** inside `autoresearch.sh` and report the **median**
- Pin CPU frequency if possible (`cpupower frequency-set -g performance`)
- Close competing workloads
- Use `taskset` to pin to specific CPU cores

### For Deterministic Benchmarks (ML Training)

ML training with fixed seeds is mostly deterministic. The noise floor will be very low,
making small improvements detectable. With GPU training:

- Use `torch.backends.cudnn.deterministic = True` for reproducibility
- Fixed random seeds across runs
- Note that different GPU architectures may produce slightly different results

### For Build/Bundle Size Benchmarks

These are typically deterministic (same input → same output). Confidence scoring may
show infinite confidence (MAD ≈ 0). This is expected — any measured change is real.

## Example Calculation

Given 5 kept experiments with metric values: `[4.23, 4.15, 4.18, 4.20, 4.12]`

1. Baseline: `4.23`
2. Best: `4.12`
3. Median of kept: `4.18`
4. Absolute deviations: `[0.05, 0.03, 0.00, 0.02, 0.06]`
5. MAD: `0.03`
6. Confidence: `|4.12 - 4.23| / 0.03 = 3.67×` → Green (likely real)
