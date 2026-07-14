#!/usr/bin/env bash
# Unit tests for skills/autoresearch/scripts/session-status.sh — the deterministic
# stopping-condition reference implementation. Sourced by run-tests.sh (which
# provides pass/fail and $PY); also runnable standalone.
set -uo pipefail

if ! declare -F pass >/dev/null 2>&1; then
  # Standalone mode: minimal harness.
  PASS=0; FAIL=0
  pass() { echo "PASS"; PASS=$((PASS+1)); }
  fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
  PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  cd "$PLUGIN_DIR"
fi

SS="skills/autoresearch/scripts/session-status.sh"
SSML="skills/autoresearch-ml/scripts/session-status.sh"
TDIR="$(mktemp -d)"
trap 'rm -rf "$TDIR"' EXIT

# field VALUE from a session-status run: `field KEY < output`
field() { grep "^$1=" | head -1 | cut -d= -f2-; }

mklog() { printf '%s\n' "$@" > "$TDIR/log.jsonl"; }

echo ""
echo "--- session-status.sh ---"

# SS1 — both skill copies exist and are byte-identical (matches the shared-script pattern)
echo -n "SS1 helper present in both skills, identical: "
if [[ -f "$SS" && -f "$SSML" ]] && [[ "$("$PY" -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$SS")" == "$("$PY" -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$SSML")" ]]; then pass; else fail "missing or divergent copies"; fi

# SS2 — syntax valid
echo -n "SS2 syntax valid: "
bash -n "$SS" 2>/dev/null && bash -n "$SSML" 2>/dev/null && pass || fail "syntax error"

# SS3 — basic segment-0 run count + continue
echo -n "SS3 basic run count: "
mklog \
  '{"type":"config","name":"A"}' \
  '{"type":"status","state":"running"}' \
  '{"run":1,"status":"keep","segment":0}' \
  '{"run":2,"status":"discard","segment":0}'
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field SEGMENT_RUNS)" == "2" && "$(echo "$OUT" | field VERDICT)" == "continue" ]] && pass || fail "$OUT"

# SS4 — MULTI-SEGMENT regression guard: seg1 has 3 runs at run numbers 51-53.
# The old buggy 'highest run' logic would report 53; correct is 3.
echo -n "SS4 multi-segment counts entries not run number: "
{
  echo '{"type":"config","name":"A"}'
  for i in $(seq 1 50); do echo "{\"run\":$i,\"status\":\"discard\",\"segment\":0}"; done
  echo '{"type":"config","name":"B"}'
  echo '{"run":51,"status":"keep","segment":1}'
  echo '{"run":52,"status":"keep","segment":1}'
  echo '{"run":53,"status":"discard","segment":1}'
} > "$TDIR/log.jsonl"
OUT=$(bash "$SS" --file "$TDIR/log.jsonl" --max-iterations 3)
[[ "$(echo "$OUT" | field SEGMENT)" == "1" && "$(echo "$OUT" | field SEGMENT_RUNS)" == "3" && "$(echo "$OUT" | field VERDICT)" == "max_iterations" ]] && pass || fail "$OUT"

# SS5 — streak resets on keep
echo -n "SS5 streak resets on keep: "
mklog \
  '{"type":"config","name":"A"}' \
  '{"run":1,"status":"crash","segment":0}' \
  '{"run":2,"status":"keep","segment":0}' \
  '{"run":3,"status":"discard","segment":0}' \
  '{"run":4,"status":"crash","segment":0}'
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field STREAK)" == "2" ]] && pass || fail "$OUT"

# SS6 — streak resets on checks_failed
echo -n "SS6 streak resets on checks_failed: "
mklog \
  '{"type":"config","name":"A"}' \
  '{"run":1,"status":"checks_failed","segment":0}' \
  '{"run":2,"status":"discard","segment":0}' \
  '{"run":3,"status":"crash","segment":0}'
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field STREAK)" == "2" ]] && pass || fail "$OUT"

# SS7 — streak ignores an earlier segment's failures
echo -n "SS7 streak scoped to current segment: "
{
  echo '{"type":"config","name":"A"}'
  echo '{"run":1,"status":"crash","segment":0}'
  echo '{"run":2,"status":"crash","segment":0}'
  echo '{"type":"config","name":"B"}'
  echo '{"run":3,"status":"crash","segment":1}'
} > "$TDIR/log.jsonl"
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field STREAK)" == "1" && "$(echo "$OUT" | field SEGMENT_RUNS)" == "1" ]] && pass || fail "$OUT"

# SS8 — terminal wall at streak > 8 (9 trailing failures)
echo -n "SS8 wall at streak>8: "
{
  echo '{"type":"config","name":"A"}'
  echo '{"run":0,"status":"keep","segment":0}'
  for i in $(seq 1 9); do echo "{\"run\":$i,\"status\":\"discard\",\"segment\":0}"; done
} > "$TDIR/log.jsonl"
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field STREAK)" == "9" && "$(echo "$OUT" | field VERDICT)" == "wall" ]] && pass || fail "$OUT"

# SS9 — exactly 8 failures is NOT a wall (strict > boundary)
echo -n "SS9 streak==8 is not a wall (strict boundary): "
{
  echo '{"type":"config","name":"A"}'
  echo '{"run":0,"status":"keep","segment":0}'
  for i in $(seq 1 8); do echo "{\"run\":$i,\"status\":\"discard\",\"segment\":0}"; done
} > "$TDIR/log.jsonl"
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field STREAK)" == "8" && "$(echo "$OUT" | field VERDICT)" == "continue" ]] && pass || fail "$OUT"

# SS10 — backstop fires at 200 with no ack
echo -n "SS10 backstop at 200 unacked: "
{
  echo '{"type":"config","name":"A"}'
  for i in $(seq 1 200); do echo "{\"run\":$i,\"status\":\"keep\",\"segment\":0}"; done
} > "$TDIR/log.jsonl"
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field SEGMENT_RUNS)" == "200" && "$(echo "$OUT" | field VERDICT)" == "backstop" ]] && pass || fail "$OUT"

# SS11 — backstop suppressed once acked at 200
echo -n "SS11 backstop suppressed by backstop_ack: "
{
  echo '{"type":"config","name":"A"}'
  for i in $(seq 1 200); do echo "{\"run\":$i,\"status\":\"keep\",\"segment\":0}"; done
  echo '{"type":"status","state":"running","backstop_ack":200}'
} > "$TDIR/log.jsonl"
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field BACKSTOP_ACK)" == "200" && "$(echo "$OUT" | field VERDICT)" == "continue" ]] && pass || fail "$OUT"

# SS12 — SEGMENT-SAFE ack: a prior segment's ack must NOT suppress a fresh segment's backstop
echo -n "SS12 backstop ack is segment-scoped: "
{
  echo '{"type":"config","name":"A"}'
  echo '{"type":"status","state":"running","backstop_ack":200}'
  for i in $(seq 1 200); do echo "{\"run\":$i,\"status\":\"keep\",\"segment\":0}"; done
  echo '{"type":"config","name":"B"}'
  for i in $(seq 201 400); do echo "{\"run\":$i,\"status\":\"keep\",\"segment\":1}"; done
} > "$TDIR/log.jsonl"
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field SEGMENT_RUNS)" == "200" && "$(echo "$OUT" | field BACKSTOP_ACK)" == "0" && "$(echo "$OUT" | field VERDICT)" == "backstop" ]] && pass || fail "$OUT"

# SS13 — concluded when last status is cancelled/done
echo -n "SS13 concluded on cancelled status: "
mklog \
  '{"type":"config","name":"A"}' \
  '{"run":1,"status":"keep","segment":0}' \
  '{"type":"status","state":"cancelled"}'
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field LAST_STATUS)" == "cancelled" && "$(echo "$OUT" | field VERDICT)" == "concluded" ]] && pass || fail "$OUT"

# SS14 — LAST_STATUS=none (legacy log) must NOT read as concluded
echo -n "SS14 legacy log (no status) is not concluded: "
mklog \
  '{"type":"config","name":"A"}' \
  '{"run":1,"status":"keep","segment":0}'
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field LAST_STATUS)" == "none" && "$(echo "$OUT" | field VERDICT)" == "continue" ]] && pass || fail "$OUT"

# SS15 — max_iterations boundary: reached at ==, not at max-1
echo -n "SS15 max_iterations boundary: "
mklog \
  '{"type":"config","name":"A"}' \
  '{"run":1,"status":"keep","segment":0}' \
  '{"run":2,"status":"discard","segment":0}'
O2=$(bash "$SS" --file "$TDIR/log.jsonl" --max-iterations 3)   # 2 < 3 -> continue
O3=$(bash "$SS" --file "$TDIR/log.jsonl" --max-iterations 2)   # 2 >= 2 -> max_iterations
[[ "$(echo "$O2" | field VERDICT)" == "continue" && "$(echo "$O3" | field VERDICT)" == "max_iterations" ]] && pass || fail "O2=$O2 O3=$O3"

# SS16 — adversarial: a description containing the literal '"status":"keep"' must not fool counting
echo -n "SS16 adversarial description not miscounted: "
mklog \
  '{"type":"config","name":"A"}' \
  '{"run":1,"status":"crash","segment":0,"description":"tried \"status\":\"keep\" trick"}' \
  '{"run":2,"status":"crash","segment":0}'
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field SEGMENT_RUNS)" == "2" && "$(echo "$OUT" | field STREAK)" == "2" ]] && pass || fail "$OUT"

# SS17 — missing file exits non-zero
echo -n "SS17 missing log errors: "
RC=0; bash "$SS" --file "$TDIR/does-not-exist.jsonl" >/dev/null 2>&1 || RC=$?
[[ $RC -ne 0 ]] && pass || fail "expected non-zero exit"

# SS18 — count is by segment EQUALITY, not merely "after the last config header":
# a stray/legacy run with a different segment in the current region is excluded.
echo -n "SS18 count filters by segment equality (stray record excluded): "
mklog \
  '{"type":"config","name":"B"}' \
  '{"run":99,"status":"keep","segment":0}' \
  '{"run":100,"status":"keep","segment":1}' \
  '{"run":101,"status":"discard","segment":1}'
OUT=$(bash "$SS" --file "$TDIR/log.jsonl")
[[ "$(echo "$OUT" | field SEGMENT)" == "1" && "$(echo "$OUT" | field SEGMENT_RUNS)" == "2" ]] && pass || fail "$OUT"
