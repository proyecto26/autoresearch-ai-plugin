#!/usr/bin/env bash
set -euo pipefail

# ─── Pre-checks (fast fail, <1s) ─────────────────────────────
if ! command -v pnpm &>/dev/null; then
  echo "ERROR: pnpm not found"
  exit 1
fi

# ─── Portable millisecond timer ──────────────────────────────
# date +%s%N is GNU-only; fall back to python3 on macOS/BSD
if date +%s%N 2>/dev/null | grep -qv '%N'; then
  now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
else
  now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }
fi

# ─── Benchmark (median of 3 runs) ────────────────────────────
times=()
for i in {1..3}; do
  start=$(now_ms)
  pnpm test --run --silent 2>/dev/null
  end=$(now_ms)
  elapsed=$(( end - start ))
  times+=("$elapsed")
done

# Sort and pick median
sorted=($(printf '%s\n' "${times[@]}" | sort -n))
median=${sorted[1]}

# ─── Memory measurement (single run, best-effort) ────────────
# GNU time uses -v, BSD time (macOS) uses -l
peak_mem=0
if /usr/bin/time -v true 2>/dev/null; then
  peak_mem=$( /usr/bin/time -v pnpm test --run --silent 2>&1 | grep "Maximum resident" | awk '{print $NF}' || echo "0" )
  peak_mem_mb=$(( ${peak_mem:-0} / 1024 ))
elif /usr/bin/time -l true 2>/dev/null; then
  peak_mem=$( /usr/bin/time -l pnpm test --run --silent 2>&1 | grep "maximum resident" | awk '{print $1}' || echo "0" )
  peak_mem_mb=$(( ${peak_mem:-0} / 1024 / 1024 ))  # BSD reports bytes
else
  peak_mem_mb=0
fi

# ─── Instrumentation (optional, helps guide next experiment) ──
# Run once more with JSON reporter for detailed breakdown
pnpm test --run --reporter=json > /tmp/test-results.json 2>/dev/null || true
setup_ms=$(jq '.testResults | map(.perfStats.setupTime // 0) | add // 0' /tmp/test-results.json 2>/dev/null || echo "0")
slow_tests=$(jq '[.testResults[] | select(.perfStats.runtime > 1000)] | length' /tmp/test-results.json 2>/dev/null || echo "0")

# ─── Output METRIC lines ─────────────────────────────────────
echo "METRIC total_ms=$median"
echo "METRIC peak_memory_mb=$peak_mem_mb"
echo "METRIC setup_ms=$setup_ms"
echo "METRIC slow_tests=$slow_tests"
