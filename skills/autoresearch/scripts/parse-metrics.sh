#!/usr/bin/env bash
# parse-metrics.sh — Extract METRIC lines from benchmark output
#
# Usage:
#   bash autoresearch.sh 2>&1 | bash ${CLAUDE_SKILL_DIR}/scripts/parse-metrics.sh
#
# Input:  Benchmark output (stdin) containing lines like "METRIC total_ms=4230"
# Output: Clean metric lines, one per line: "total_ms=4230"
#
# If a metric name is passed as argument, only that metric's value is printed:
#   bash autoresearch.sh 2>&1 | bash ${CLAUDE_SKILL_DIR}/scripts/parse-metrics.sh total_ms
#   → 4230

set -euo pipefail

TARGET="${1:-}"

while IFS= read -r line; do
  if [[ "$line" =~ ^METRIC\ ([a-zA-Z_][a-zA-Z0-9_]*)=(.+)$ ]]; then
    name="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    if [[ -z "$TARGET" ]]; then
      echo "${name}=${value}"
    elif [[ "$name" == "$TARGET" ]]; then
      echo "$value"
    fi
  fi
done
