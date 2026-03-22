#!/usr/bin/env bash
set -euo pipefail

# ─── Pre-checks ──────────────────────────────────────────────
# Fast-fail if something is obviously broken
if ! command -v pnpm &>/dev/null; then
  echo "ERROR: pnpm not found"
  exit 1
fi

# ─── Benchmark (median of 3 runs) ────────────────────────────
times=()
for i in {1..3}; do
  start=$(date +%s%N)
  pnpm test --run --silent 2>/dev/null
  end=$(date +%s%N)
  elapsed=$(( (end - start) / 1000000 ))
  times+=("$elapsed")
done

# Sort and pick median
sorted=($(printf '%s\n' "${times[@]}" | sort -n))
median=${sorted[1]}

# ─── Memory measurement (single run) ─────────────────────────
peak_mem=$( /usr/bin/time -v pnpm test --run --silent 2>&1 | grep "Maximum resident" | awk '{print $NF}' )
peak_mem_mb=$(( peak_mem / 1024 ))

# ─── Output METRIC lines ─────────────────────────────────────
echo "METRIC total_ms=$median"
echo "METRIC peak_memory_mb=$peak_mem_mb"
