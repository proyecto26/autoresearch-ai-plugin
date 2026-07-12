# Skill Evals

How this plugin measures whether its skills actually work: that they **trigger** when they should, **stay distinct** from each other, and **change agent behavior** the way each skill promises.

The framework is adapted from [agent-skills' eval system](https://github.com/addyosmani/agent-skills/tree/main/evals), which adopts [Anthropic skill-creator's `evals.json` schema](https://github.com/anthropics/skills/tree/main/skills/skill-creator) for the behavioral tier.

## The three tiers

| Tier | What it checks | Runs | Cost |
|---|---|---|---|
| 1. Structural | Frontmatter, naming, description limits, referenced resources exist | CI (`scripts/validate-skills.js`) | Free |
| 2. Trigger & routing | Positive prompts rank their skill; negatives route to the sibling; descriptions don't collide | CI (`scripts/run-evals.js`) | Free |
| 3. Behavioral | An agent following the skill satisfies its `expectations[]`, judged from the execution trace | On demand (`scripts/run-evals.js --behavioral <skill>`) | Tokens |

Tier 2 is a lexical approximation of routing (stemmed TF-IDF over descriptions). It cannot judge semantics — that's Tier 3's job — but it catches the failure modes that dominate real trigger bugs: a description missing the vocabulary users say, and an over-broad description that outranks the right skill.

## Running

```bash
# Tier 1 — structural, deterministic
node scripts/validate-skills.js

# Tier 2 — trigger/routing, deterministic
node scripts/run-evals.js

# Tier 3 — behavioral, runs each eval through headless claude, then grades the trace
node scripts/run-evals.js --behavioral autoresearch              # spends tokens
node scripts/run-evals.js --behavioral autoresearch --dry-run    # prints the plan only
```

Tier 3 runs each eval in a throwaway workspace (fixtures from `files[]` materialized out of `evals/fixtures/`), captures the full `--output-format stream-json --verbose` execution trace, and grades the **trace** (tool calls included) rather than the model's final prose. The executor runs with `--permission-mode acceptEdits` plus a pre-approved tool list so the agent can genuinely edit files and run commands instead of narrating. Grading output lands in `evals/results/` (gitignored).

## Two-skill catalog semantics

This plugin has exactly two skills, and they are a deliberate generic/specialization pair. That changes how to read Tier 2:

- **`top_k: 1` on every positive prompt.** With n=2 documents, "top 3" is vacuously true; rank-1 is the only meaningful bar.
- **Negatives carry `owner`.** The real routing risk is between the siblings ("optimize test speed" vs "speed up training"), so every negative declares the sibling as owner and the runner asserts the owner outranks the skill under test.
- **Expect the ≥50% description-overlap warning.** The two descriptions intentionally share loop vocabulary; the ≥75% collision *error* is the gate that must stay green.

## Eval case format

One file per skill: `evals/cases/<skill-name>.json`. `trigger` is the routing extension; `evals[]` is skill-creator's schema (`id`, `prompt`, `expected_output`, optional `files[]`, `expectations[]`).

Unlike the upstream repo (whose behavioral evals are fixtureless and marked `trust_level: "provisional"`), the behavioral evals here ship **real fixtures** (`evals/fixtures/slow-project`, `status-session`, `ml-session`), so their pass/fail is evidence, not a sanity check. Known limit: the `autoresearch-ml` eval covers the status/advice protocol only — the GPU training loop itself cannot run in an eval harness and stays validated by `tests/run-tests.sh` (asset compilation) plus real sessions.

**Writing good trigger prompts:** paraphrase how users actually talk; don't copy the description (that's gaming the eval). If a realistic prompt can't rank because the description lacks its vocabulary, that's a real finding — improve the description.

## Adding a skill

Every skill ships with an eval file: at least 3 positive triggers, 2 negative triggers (with `owner`), and 1 behavioral eval with fixtures. The runner warns below these minimums.
