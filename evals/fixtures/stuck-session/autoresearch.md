# Autoresearch Session: Optimize bundle size

## Goal
Reduce production bundle size.

## Primary Metric
- **Name:** bytes
- **Unit:** B
- **Direction:** lower is better

## Benchmark
`bash autoresearch.sh`

## Files in Scope
- build config, `package.json`

## Constraints
- `max_iterations: 0` (unlimited)

## Learnings
- Nothing has stuck: runs 2–10 all discarded or crashed. The current segment is stuck (9 consecutive failures).
