# Autoresearch Best Practices

## Writing Good Benchmark Scripts

### Structure of autoresearch.sh

```bash
#!/usr/bin/env bash
set -euo pipefail

# 1. Pre-checks (fast fail, <1 second)
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
- **Output instrumentation data.** Phase timings, error counts, cache rates, domain-specific
  signals. This data guides the next iteration and helps identify where to focus.
- **Can be updated during the loop.** As you discover what matters, update the benchmark
  script to capture more useful data.

### Output Instrumentation

Beyond the primary metric, output whatever data helps the next iteration:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Run the workload
pnpm test --run --reporter=json > /tmp/test-results.json 2>&1

# Primary metric
total_ms=$(jq '.testResults | map(.perfStats.runtime) | add' /tmp/test-results.json)
echo "METRIC total_ms=$total_ms"

# Instrumentation — helps identify bottlenecks
setup_ms=$(jq '.testResults | map(.perfStats.setupTime) | add' /tmp/test-results.json)
echo "METRIC setup_ms=$setup_ms"
slow_tests=$(jq '[.testResults[] | select(.perfStats.runtime > 1000)] | length' /tmp/test-results.json)
echo "METRIC slow_tests=$slow_tests"
```

## Benchmark Guardrails

**Be careful not to overfit to the benchmarks and do not cheat on the benchmarks.**

Common traps to avoid:
- **Don't optimize the harness.** If you speed up the benchmark script itself (e.g., skipping
  pre-checks, reducing measurement iterations), you're not improving the real workload.
- **Don't hardcode outputs.** Returning cached/precomputed results defeats the purpose.
- **Don't reduce workload size.** Processing fewer items to appear faster isn't optimization.
- **Don't disable correctness checks.** Removing validation to gain speed is regression.
- **Don't game the metric.** If the metric measures "test runtime," don't delete tests.

The goal is to optimize the **real workload**, not the measurement apparatus.

## Choosing Experiments

### Good Experiment Strategies

- **Low-hanging fruit first.** Start with obvious optimizations before exotic ones.
- **One change at a time.** Isolate variables so results are interpretable.
- **Vary magnitude.** If reducing batch size helps, try several sizes.
- **Simplification wins.** Removing code for equal performance is always a keep.
- **Read the code deeply.** Understanding bottlenecks beats random changes.
- **Combine near-misses.** Two ideas that each gave marginal improvement may compound.
- **Try radical changes.** When incremental changes plateau, make larger architectural shifts.

### Avoiding Pitfalls

- **Don't thrash.** If 3 consecutive experiments fail, step back and think differently.
- **Don't chase noise.** If confidence is < 1.0×, the "improvement" is likely nothing.
- **Don't break things.** Always verify correctness with `autoresearch.checks.sh`.
- **Don't make irreversible changes.** Git revert must always be clean.
- **Don't increase complexity for marginal gains.** Simpler is better.

### When Stuck

If you run out of obvious ideas:

1. Re-read source files for new angles (look at what you haven't touched yet)
2. Read papers, docs, or comments referenced in the code
3. Combine previous near-misses (two marginal improvements may compound)
4. Try more radical architectural changes
5. Check `autoresearch.ideas.md` for deferred experiments
6. Profile or instrument the workload to find new bottlenecks
7. Think about the problem from first principles

## Actionable Side Information (ASI)

### Why ASI Matters

When an experiment is discarded (git revert), the code changes disappear. Only the description
and ASI survive in `autoresearch.jsonl`. ASI is the **only structured memory** of what happened
in failed experiments.

### What to Record

Record ASI for every experiment — especially discards and crashes:

```json
{
  "hypothesis": "Reducing loop iterations by breaking early should save 20%",
  "result": "Only 3% speedup, but code became harder to read",
  "next_action_hint": "Try vectorization instead of loop optimization",
  "bottleneck": "Memory bandwidth on L2 cache misses, not CPU cycles"
}
```

### ASI Patterns by Domain

**Performance optimization:**
```json
{"bottleneck": "I/O bound", "profile_data": "90% time in disk reads", "next_action_hint": "try memory-mapped files"}
```

**ML training:**
```json
{"arch_change": "DEPTH 8→12", "vram_delta_mb": "+2000", "steps_delta": "-200", "next_action_hint": "try DEPTH=10 for balance"}
```

**Bundle/build size:**
```json
{"removed_dep": "lodash", "size_delta_kb": "-45", "next_action_hint": "check for other tree-shakeable imports"}
```

### Using ASI for Future Experiments

When choosing the next experiment, review ASI from recent runs:
- `next_action_hint` from the last few experiments
- `bottleneck` fields to avoid optimizing the wrong thing
- Error patterns from `error_details` in crashes

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
- Key ASI observations (bottlenecks, near-misses)

A fresh agent resuming after context reset should be able to read `autoresearch.md` alone
and have full context to continue productively.

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

# Run tests — suppress success output, let errors through
pnpm test --run --reporter=dot 2>&1 | tail -50

# Run type checking
pnpm tsc --noEmit 2>&1 | grep -i error || true

# Run linting
pnpm lint
```

### Important Notes

- Checks run **after** a passing benchmark, not before
- Check execution time does NOT affect the primary metric
- If checks fail → status is `checks_failed`, code is reverted
- Checks prevent "improvements" that break correctness
- **Separate timeout:** Default 300 seconds (configurable independently from benchmark)
- **Keep output minimal:** Suppress success output, let errors through

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
prune stale entries and prioritize promising experiments. When all ideas are exhausted,
write a final summary and delete the file.
