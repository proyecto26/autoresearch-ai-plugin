#!/usr/bin/env bash
# Self-tests for the eval harness (scripts/validate-skills.js + scripts/run-evals.js).
# These validators ARE the CI gate, so a silent break in the block-scalar
# frontmatter parser, the description-length check, the resource-existence check,
# or the routing/collision logic would otherwise pass unnoticed. We exercise them
# against crafted good/bad skill fixtures in a throwaway plugin layout.
#
# Sourced by run-tests.sh (provides pass/fail); also runnable standalone.
set -uo pipefail

if ! declare -F pass >/dev/null 2>&1; then
  PASS=0; FAIL=0
  pass() { echo "PASS"; PASS=$((PASS+1)); }
  fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
  PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  cd "$PLUGIN_DIR"
fi

command -v node >/dev/null 2>&1 || { echo "  (node not found — skipping eval-harness self-tests)"; return 0 2>/dev/null || exit 0; }

HT="$(mktemp -d)"
trap 'rm -rf "$HT"' EXIT
mkdir -p "$HT/scripts" "$HT/evals/cases"
cp scripts/validate-skills.js scripts/run-evals.js "$HT/scripts/"

# Helper: write a SKILL.md with a folded (>-) description block.
mkskill() { # name  desc-line-1  [extra-body]
  local name="$1" desc="$2" body="${3:-}"
  mkdir -p "$HT/skills/$name"
  {
    echo "---"
    echo "name: $name"
    echo "description: >-"
    echo "  $desc"
    echo "version: 0.0.1"
    echo "---"
    echo ""
    echo "# $name"
    echo ""
    echo "$body"
  } > "$HT/skills/$name/SKILL.md"
}

run_validate() { ( cd "$HT" && node scripts/validate-skills.js >/dev/null 2>&1 ); }
run_evals() { ( cd "$HT" && node scripts/run-evals.js >/dev/null 2>&1 ); }
reset_skills() { rm -rf "$HT/skills" "$HT/evals/cases"/*.json 2>/dev/null; mkdir -p "$HT/skills" "$HT/evals/cases"; }

echo ""
echo "--- eval-harness self-test ---"

# HR1 — a valid folded-scalar skill passes Tier 1 (proves block-scalar parsing works)
echo -n "HR1 valid folded-scalar skill passes validate-skills: "
reset_skills
mkskill good "Optimize things autonomously. Use this skill when the user wants to optimize a metric in a loop."
run_validate && pass || fail "valid skill should pass Tier 1"

# HR2 — description over 1024 chars fails (the exact limit v0.3.1 relies on)
echo -n "HR2 over-long description fails validate-skills: "
reset_skills
LONG=$(printf 'word %.0s' $(seq 1 260))   # ~1300 chars
mkskill toolong "Use this skill when you must. $LONG"
run_validate && fail "over-1024 description should fail" || pass

# HR3 — missing 'use when' trigger fails
echo -n "HR3 description without a 'when to use' trigger fails: "
reset_skills
mkskill notrigger "This skill just optimizes metrics and does things."
run_validate && fail "missing trigger should fail" || pass

# HR4 — a referenced resource that does not exist fails
echo -n "HR4 dangling resource reference fails: "
reset_skills
mkskill refskill "Use this skill when optimizing." "See scripts/does-not-exist.sh for details."
run_validate && fail "dangling scripts/ reference should fail" || pass

# HR5 — same reference, resource present, passes
echo -n "HR5 satisfied resource reference passes: "
mkdir -p "$HT/skills/refskill/scripts" && echo '#!/usr/bin/env bash' > "$HT/skills/refskill/scripts/does-not-exist.sh"
run_validate && pass || fail "present resource should pass"

# HR6 — Tier 2 folded-scalar routing: a prompt sharing the description's vocabulary
# ranks the skill. If the parser had read the description as ">-", the score would
# be 0 and the positive trigger would error. So a clean Tier-2 pass proves parsing.
echo -n "HR6 folded description routes (not parsed as '>-'): "
reset_skills
mkskill widgetopt "Use this skill when the user wants to optimize widget throughput in a benchmark loop."
cat > "$HT/evals/cases/widgetopt.json" <<'JSON'
{
  "skill_name": "widgetopt",
  "trigger": {
    "positive": [
      { "prompt": "optimize my widget throughput in a benchmark loop", "top_k": 1 },
      { "prompt": "improve widget throughput automatically", "top_k": 1 },
      { "prompt": "run a loop to make widget throughput faster", "top_k": 1 }
    ],
    "negative": [
      { "prompt": "write me a poem about the ocean" },
      { "prompt": "what is the capital of France" }
    ]
  },
  "evals": [
    { "id": 1, "prompt": "optimize widgets", "expected_output": "does so", "expectations": ["it optimizes"] }
  ]
}
JSON
run_evals && pass || fail "folded-scalar routing should pass Tier 2"

# HR7 — collision gate: two near-identical descriptions error out
echo -n "HR7 near-duplicate descriptions trip the collision gate: "
reset_skills
mkskill dup_a "Use this skill when the user wants to optimize widget throughput in a benchmark loop autonomously."
mkskill dup_b "Use this skill when the user wants to optimize widget throughput in a benchmark loop autonomously."
run_evals && fail "identical descriptions should error the collision gate" || pass
