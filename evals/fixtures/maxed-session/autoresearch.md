# Autoresearch Session: Optimize unit test runtime

## Goal
Reduce total wall-clock runtime of the unit test suite.

## Primary Metric
- **Name:** total_ms
- **Unit:** ms
- **Direction:** lower is better

## Benchmark
`bash autoresearch.sh`

## Files in Scope
- `tests/conftest.py`, `pytest.ini`

## Constraints
- Capped at `max_iterations: 3` (see `.claude/autoresearch-ai-plugin.local.md`)

## Learnings
- Parallel shards and cached fixtures both helped; 3 experiments logged.
