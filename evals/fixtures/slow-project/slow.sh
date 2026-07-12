#!/usr/bin/env bash
# Simulated data-processing task. Deliberately inefficient: one subprocess
# per item. The obvious optimization is batching the work in a single awk
# or shell arithmetic pass.
set -euo pipefail

total=0
for i in $(seq 1 100); do
  h=$(printf 'item-%d' "$i" | cksum | cut -d' ' -f1)
  total=$(( total + h % 97 ))
done
echo "checksum-total: $total"
