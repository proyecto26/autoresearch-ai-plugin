# Autoresearch Best Practices

## Writing Good Benchmark Scripts

### Structure of autoresearch.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Pre-checks (fast fail)
# Syntax validation, dependency checks, etc.

# 2. Run the workload
# The actual benchmark

# 3. Output METRIC lines
# METRIC name=value (one per line)
```

### Key Principles

- **Fast is critical.** Every second is multiplied by hundreds of runs. Keep benchmarks
  as short as possible while still being meaningful.
- **Deterministic when possible.** Fixed seeds, pinned configs, controlled environments.
- **Median for noisy metrics.** For timing benchmarks, run 3-5 times and report the median:

```bash
times=()
for i in {1..3}; do
  start=$(date +%s%N)
  pnpm test --silent 2>/dev/null
  end=$(date +%s%N)
  elapsed=$(( (end - start) / 1000000 ))
  times+=("$elapsed")
done
sorted=($(printf '%s\n' "${times[@]}" | sort -n))
median=${sorted[1]}
echo "METRIC total_ms=$median"
```

- **One primary metric.** Track secondary metrics for context, but optimize for one thing.

## Choosing Experiments

### Good Experiment Strategies

- **Low-hanging fruit first.** Start with obvious optimizations before exotic ones.
- **One change at a time.** Isolate variables so results are interpretable.
- **Vary magnitude.** If reducing batch size helps, try several sizes.
- **Simplification wins.** Removing code for equal performance is always a keep.
- **Read the code deeply.** Understanding bottlenecks beats random changes.

### Avoiding Pitfalls

- **Don't thrash.** If 3 consecutive experiments fail, step back and think differently.
- **Don't chase noise.** If confidence is < 1.0×, the "improvement" is likely nothing.
- **Don't break things.** Always verify correctness with `autoresearch.checks.sh`.
- **Don't make irreversible changes.** Git revert must always be clean.
- **Don't increase complexity for marginal gains.** Simpler is better.

## Writing autoresearch.md

The session document is the most important file — it enables context recovery after resets.

### Must Include

- **Objective** — clear, measurable goal
- **Primary metric** — name, unit, direction (lower/higher is better)
- **Secondary metrics** — additional context (memory, compilation time, etc.)
- **How to run** — exact command (`bash autoresearch.sh`)
- **Files in scope** — which files the agent may modify
- **Off limits** — files that must not be changed
- **Constraints** — time budgets, memory limits, correctness requirements
- **What's been tried** — accumulated learnings (update after each experiment)

### Updating Over Time

After every few experiments, update the "What's been tried" section with:
- What worked and why
- What failed and why
- Emerging patterns or insights
- Ideas for future experiments

## Correctness Checks

### When to Use autoresearch.checks.sh

Always create `autoresearch.checks.sh` when:
- The benchmark measures performance (not correctness)
- Tests exist that verify correct behavior
- Type checking or linting is available

### Structure

```bash
#!/usr/bin/env bash
set -euo pipefail

# Run tests
pnpm test --silent

# Run type checking
pnpm tsc --noEmit

# Run linting
pnpm lint
```

### Important Notes

- Checks run **after** a passing benchmark, not before
- Check execution time does NOT affect the primary metric
- If checks fail → status is `checks_failed`, code is reverted
- Checks prevent "improvements" that break correctness

## Managing Ideas

### autoresearch.ideas.md

Keep a backlog of ideas that are too complex for a single experiment:

```markdown
# Experiment Ideas

## High Priority
- [ ] Try flash attention implementation — could reduce memory 40%
- [ ] Pool-based test runner — parallelize test suites

## Medium Priority
- [ ] Tree-shaking unused exports — may reduce bundle size
- [ ] Lazy-load heavy dependencies

## Tried / Stale
- [x] Reduce batch size — worked, kept in commit abc123
- [x] Swap optimizer — no improvement, reverted
```

Update this file as ideas are tried or new ones emerge. On resume after context reset,
prune stale entries and prioritize promising experiments.
