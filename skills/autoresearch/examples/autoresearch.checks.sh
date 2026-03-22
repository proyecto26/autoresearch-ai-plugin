#!/usr/bin/env bash
set -euo pipefail

# ─── Correctness checks ──────────────────────────────────────
# These run AFTER the benchmark passes.
# Execution time does NOT affect the primary metric.
# If any check fails → status = checks_failed, code is reverted.

echo "Running tests..."
pnpm test --run

echo "Running type checks..."
pnpm tsc --noEmit

echo "Running linter..."
pnpm lint

echo "All checks passed."
