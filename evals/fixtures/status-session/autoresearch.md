# Autoresearch Session: Optimize unit test runtime

## Goal
Reduce total wall-clock runtime of the unit test suite.

## Primary Metric
- **Name:** total_ms
- **Unit:** ms
- **Direction:** lower is better

## Benchmark
`bash autoresearch.sh` (runs the suite 3 times, reports median as `METRIC total_ms=<value>`)

## Files in Scope
- `tests/conftest.py`
- `pytest.ini`

## Constraints
- All tests must still pass (checked by autoresearch.checks.sh)

## Learnings
- The suite is IO-bound; parallel shards helped immediately.
- Worker oversubscription (16 workers on 8 cores) hurts; 8 is the sweet spot.
- Fixture imports are fragile — lazy-importing conftest fixtures crashed collection.
