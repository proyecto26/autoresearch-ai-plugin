#!/usr/bin/env bash
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PLUGIN_DIR"

# Python resolution: on Windows, "python3" is often the Microsoft Store alias
# stub (or absent) while "python" is a real CPython. Use the first name that
# can actually execute code.
PY=""
for candidate in python3 python; do
  if "$candidate" -c "import sys" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
if [[ -z "$PY" ]]; then
  echo "ERROR: no working python3/python found (needed for JSON validation tests)" >&2
  exit 1
fi

echo "========================================="
echo "  E2E TEST SUITE: autoresearch-ai-plugin"
echo "========================================="
PASS=0; FAIL=0

pass() { echo "PASS"; PASS=$((PASS+1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# --- parse-metrics.sh ---
echo ""
echo "--- parse-metrics.sh ---"

echo -n "T1 all metrics: "
OUT=$(printf "noise\nMETRIC val_bpb=0.997\nmore\nMETRIC mem=512\n" | bash skills/autoresearch/scripts/parse-metrics.sh)
EXPECTED=$(printf "val_bpb=0.997\nmem=512")
[[ "$OUT" == "$EXPECTED" ]] && pass || fail "$OUT"

echo -n "T2 single metric: "
OUT=$(printf "METRIC a=1\nMETRIC b=2\n" | bash skills/autoresearch/scripts/parse-metrics.sh b)
[[ "$OUT" == "2" ]] && pass || fail "$OUT"

echo -n "T3 no metrics: "
OUT=$(printf "no metrics\n" | bash skills/autoresearch/scripts/parse-metrics.sh)
[[ -z "$OUT" ]] && pass || fail "$OUT"

echo -n "T4 malformed METRIC line: "
OUT=$(printf "METRIC =noval\nMETRIC 123=bad\nMETRIC good=1\n" | bash skills/autoresearch/scripts/parse-metrics.sh)
[[ "$OUT" == "good=1" ]] && pass || fail "$OUT"

# --- log-experiment.sh ---
echo ""
echo "--- log-experiment.sh ---"
TESTFILE="/tmp/test-autoresearch-$$.jsonl"
rm -f "$TESTFILE"

echo -n "T5 config header: "
bash skills/autoresearch/scripts/log-experiment.sh --config --name "Test" --metric-name "ms" --metric-unit "ms" --direction lower --file "$TESTFILE" >/dev/null
LINE=$(head -1 "$TESTFILE")
echo "$LINE" | "$PY" -c "import json,sys; d=json.load(sys.stdin); assert d['type']=='config' and d['metricName']=='ms'" 2>/dev/null && pass || fail "$LINE"

echo -n "T6 basic experiment: "
bash skills/autoresearch/scripts/log-experiment.sh --run 1 --commit abc1234 --metric 4.23 --status keep --description "baseline" --file "$TESTFILE" >/dev/null
LINE=$(tail -1 "$TESTFILE")
echo "$LINE" | "$PY" -c "import json,sys; d=json.load(sys.stdin); assert d['run']==1 and d['status']=='keep' and d['metric']==4.23" 2>/dev/null && pass || fail "$LINE"

echo -n "T7 full fields (metrics, ASI, confidence): "
bash skills/autoresearch/scripts/log-experiment.sh --run 2 --commit def5678 --metric 3.8 --status discard --description "tried something" --metrics '{"mem":512}' --segment 0 --confidence 2.1 --asi '{"hypothesis":"test"}' --file "$TESTFILE" >/dev/null
LINE=$(tail -1 "$TESTFILE")
echo "$LINE" | "$PY" -c "import json,sys; d=json.load(sys.stdin); assert d['confidence']==2.1 and d['asi']['hypothesis']=='test' and d['metrics']['mem']==512" 2>/dev/null && pass || fail "$LINE"

echo -n "T8 JSON escaping (quotes in description): "
bash skills/autoresearch/scripts/log-experiment.sh --run 3 --commit ghi9012 --metric 5.0 --status crash --description "tried \"lazy eval\"" --file "$TESTFILE" >/dev/null
LINE=$(tail -1 "$TESTFILE")
echo "$LINE" | "$PY" -c 'import json,sys; d=json.load(sys.stdin); assert "lazy eval" in d["description"]' 2>/dev/null && pass || fail "$LINE"

echo -n "T9 invalid status rejected: "
if bash skills/autoresearch/scripts/log-experiment.sh --run 4 --commit xxx --metric 1 --status invalid --description "test" --file /dev/null 2>/dev/null; then
  fail "should reject invalid status"
else
  pass
fi

echo -n "T10 missing required field: "
if bash skills/autoresearch/scripts/log-experiment.sh --run 1 --commit abc --metric 1 --file /dev/null 2>/dev/null; then
  fail "should reject missing fields"
else
  pass
fi

echo -n "T11 all JSONL lines valid JSON: "
ALL_VALID=true
while IFS= read -r line; do
  echo "$line" | "$PY" -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || { ALL_VALID=false; break; }
done < "$TESTFILE"
$ALL_VALID && pass || fail "invalid JSON line"
rm -f "$TESTFILE"

# --- protect-files.sh ---
echo ""
echo "--- protect-files.sh ---"

echo -n "T12 block existing prepare.py: "
touch /tmp/prepare.py
RC=0; echo '{"tool_input":{"file_path":"/tmp/prepare.py"}}' | bash hooks/protect-files.sh 2>/dev/null || RC=$?
[[ $RC -eq 2 ]] && pass || fail "exit=$RC"
rm -f /tmp/prepare.py

echo -n "T13 allow new prepare.py (setup): "
RC=0; echo '{"tool_input":{"file_path":"/tmp/new/prepare.py"}}' | bash hooks/protect-files.sh 2>/dev/null || RC=$?
[[ $RC -eq 0 ]] && pass || fail "exit=$RC"

echo -n "T14 allow src/data/prepare.py (subdirectory): "
mkdir -p /tmp/src/data && touch /tmp/src/data/prepare.py
RC=0; echo '{"tool_input":{"file_path":"/tmp/src/data/prepare.py"}}' | bash hooks/protect-files.sh 2>/dev/null || RC=$?
[[ $RC -eq 0 ]] && pass || fail "exit=$RC"
rm -rf /tmp/src

echo -n "T15 block existing autoresearch.sh: "
touch /tmp/autoresearch.sh
RC=0; echo '{"tool_input":{"file_path":"/tmp/autoresearch.sh"}}' | bash hooks/protect-files.sh 2>/dev/null || RC=$?
[[ $RC -eq 2 ]] && pass || fail "exit=$RC"
rm -f /tmp/autoresearch.sh

echo -n "T16 allow train.py (always editable): "
touch /tmp/train.py
RC=0; echo '{"tool_input":{"file_path":"/tmp/train.py"}}' | bash hooks/protect-files.sh 2>/dev/null || RC=$?
[[ $RC -eq 0 ]] && pass || fail "exit=$RC"
rm -f /tmp/train.py

echo -n "T17 allow no file_path: "
RC=0; echo '{"tool_input":{"command":"ls"}}' | bash hooks/protect-files.sh 2>/dev/null || RC=$?
[[ $RC -eq 0 ]] && pass || fail "exit=$RC"

echo -n "T18 block existing log-experiment.sh: "
touch /tmp/log-experiment.sh
RC=0; echo '{"tool_input":{"file_path":"/tmp/log-experiment.sh"}}' | bash hooks/protect-files.sh 2>/dev/null || RC=$?
[[ $RC -eq 2 ]] && pass || fail "exit=$RC"
rm -f /tmp/log-experiment.sh

echo -n "T19 stderr feedback on block: "
touch /tmp/prepare.py
ERR=$(echo '{"tool_input":{"file_path":"/tmp/prepare.py"}}' | bash hooks/protect-files.sh 2>&1 >/dev/null || true)
[[ "$ERR" == *"READ-ONLY"* ]] && pass || fail "$ERR"
rm -f /tmp/prepare.py

echo -n "T20 JSON with spaces (POSIX sed): "
touch /tmp/prepare.py
RC=0; echo '{"tool_input": { "file_path" : "/tmp/prepare.py" }}' | bash hooks/protect-files.sh 2>/dev/null || RC=$?
[[ $RC -eq 2 ]] && pass || fail "exit=$RC"
rm -f /tmp/prepare.py

# --- Python assets ---
echo ""
echo "--- Python assets ---"

echo -n "T21 prepare.py compiles: "
"$PY" -m py_compile skills/autoresearch-ml/assets/prepare.py 2>/dev/null && pass || fail "compile error"

echo -n "T22 train.py compiles: "
"$PY" -m py_compile skills/autoresearch-ml/assets/train.py 2>/dev/null && pass || fail "compile error"

# --- Shell syntax ---
echo ""
echo "--- Shell syntax ---"

echo -n "T23 autoresearch.sh syntax: "
bash -n skills/autoresearch/examples/autoresearch.sh 2>/dev/null && pass || fail "syntax error"

echo -n "T24 autoresearch.checks.sh syntax: "
bash -n skills/autoresearch/examples/autoresearch.checks.sh 2>/dev/null && pass || fail "syntax error"

echo -n "T25 log-experiment.sh syntax: "
bash -n skills/autoresearch/scripts/log-experiment.sh 2>/dev/null && pass || fail "syntax error"

echo -n "T26 parse-metrics.sh syntax: "
bash -n skills/autoresearch/scripts/parse-metrics.sh 2>/dev/null && pass || fail "syntax error"

echo -n "T27 protect-files.sh syntax: "
bash -n hooks/protect-files.sh 2>/dev/null && pass || fail "syntax error"

echo ""
echo "========================================="
echo "  RESULTS: $PASS passed, $FAIL failed"
echo "========================================="
exit $FAIL
