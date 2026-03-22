# Autoresearch: Optimize Unit Test Runtime

## Objective

Reduce the total wall-clock time of the test suite while maintaining 100% test pass rate.

## Metrics

- **Primary:** total_ms (milliseconds, lower is better)
- **Secondary:** peak_memory_mb (MB, informational)

## How to Run

```bash
bash autoresearch.sh
```

Outputs `METRIC total_ms=<value>` and `METRIC peak_memory_mb=<value>`.

## Files in Scope

- `vitest.config.ts` — test runner configuration
- `src/**/*.test.ts` — test files (restructuring allowed)
- `src/test-utils/` — shared test utilities

## Off Limits

- `src/**/*.ts` (non-test source files) — do not modify production code
- `package.json` — do not change dependencies
- `.github/` — do not modify CI configuration

## Constraints

- All tests must pass (enforced by `autoresearch.checks.sh`)
- No flaky tests — if a test intermittently fails, it's a bug to fix, not skip
- Benchmark reports median of 3 runs to reduce timing noise

## What's Been Tried

| # | Description | Metric | Status | Notes |
|---|-------------|--------|--------|-------|
| 0 | Baseline | 12,450ms | keep | Starting point |
