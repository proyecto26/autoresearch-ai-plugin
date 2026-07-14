#!/usr/bin/env bash
# session-status.sh — deterministic stopping-condition state for an autoresearch session.
#
# Reads autoresearch.jsonl and prints the loop's stopping-condition state as
# parseable KEY=value lines, so the agent acts on a computed verdict instead of
# hand-counting the log (which is error-prone and, before this helper, untested).
# The prose rules in SKILL.md remain the human-readable spec this implements.
#
# Usage:
#   bash session-status.sh [--file autoresearch.jsonl] [--max-iterations N]
#
# Output (KEY=value, one per line):
#   SEGMENT        current segment (segment of the last run entry, 0 if none)
#   SEGMENT_RUNS   run entries (keep|discard|crash|checks_failed) in the current segment
#   STREAK         trailing discard/crash count in the current segment
#   LAST_STATUS    state of the last {"type":"status"} record, or "none"
#   BACKSTOP_ACK   max backstop_ack recorded in the current segment, or 0
#   VERDICT        concluded | max_iterations | wall | backstop | continue
#
# Segment scoping: a new segment is delimited by a {"type":"config"} header, so
# the "current segment region" is from the LAST config header to EOF. SEGMENT_RUNS,
# STREAK and BACKSTOP_ACK are computed within that region, which keeps the backstop
# acknowledgement segment-safe (a prior segment's ack can't suppress a new one).

set -euo pipefail

FILE="autoresearch.jsonl"
MAX_ITERATIONS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --max-iterations) MAX_ITERATIONS="$2"; shift 2 ;;
    *) echo "session-status.sh: unknown argument '$1'" >&2; exit 64 ;;
  esac
done

# Resolve a working Python: "python3" is often the Microsoft Store alias stub on
# Windows while "python" is a real CPython. Use the first that can execute.
PY=""
for candidate in python3 python; do
  if "$candidate" -c "import sys" >/dev/null 2>&1; then PY="$candidate"; break; fi
done
if [[ -z "$PY" ]]; then
  echo "session-status.sh: no working python3/python found (needed to parse the JSONL)" >&2
  echo "Compute the stopping conditions from the log per the skill's spec instead." >&2
  exit 69
fi

if [[ ! -f "$FILE" ]]; then
  echo "session-status.sh: log file not found: $FILE" >&2
  exit 66
fi

MAX_ITERATIONS="$MAX_ITERATIONS" "$PY" - "$FILE" <<'PYEOF'
import json, os, sys

path = sys.argv[1]
try:
    max_iterations = int(os.environ.get("MAX_ITERATIONS", "0"))
except ValueError:
    max_iterations = 0

records = []
with open(path, encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            records.append(json.loads(line))
        except ValueError:
            # A malformed line can't be trusted; skip it rather than miscount.
            continue

def is_run(r):
    return r.get("type") not in ("config", "status") and r.get("status") in (
        "keep", "discard", "crash", "checks_failed"
    )

# Current-segment region = from the last config header to EOF.
last_config = -1
for i, r in enumerate(records):
    if r.get("type") == "config":
        last_config = i
region = records[last_config + 1:] if last_config >= 0 else records

# The current segment is the segment of the last run entry. Count runs by
# segment EQUALITY (matching the prose spec), not merely by "after the last
# config header" — so a stray/legacy record in the region with a different or
# missing segment can't inflate the count and trip a stop early.
region_runs_all = [r for r in region if is_run(r)]
segment = region_runs_all[-1].get("segment", 0) if region_runs_all else 0
segment_runs_list = [r for r in region_runs_all if r.get("segment", 0) == segment]
segment_runs = len(segment_runs_list)

# Trailing discard/crash streak within the current segment (a keep or
# checks_failed breaks it; a different segment is already excluded).
streak = 0
for r in reversed(segment_runs_list):
    if r.get("status") in ("discard", "crash"):
        streak += 1
    else:
        break

# Session-global lifecycle status (the last status record anywhere in the log).
last_status = "none"
for r in records:
    if r.get("type") == "status" and isinstance(r.get("state"), str):
        last_status = r["state"]

# Backstop acks are segment-scoped: only those in the current region count.
backstop_ack = 0
for r in region:
    if r.get("type") == "status":
        val = r.get("backstop_ack")
        if isinstance(val, int) and val > backstop_ack:
            backstop_ack = val

if last_status in ("cancelled", "done", "wall", "blocked"):
    verdict = "concluded"
elif max_iterations > 0 and segment_runs >= max_iterations:
    verdict = "max_iterations"
elif streak > 8:
    verdict = "wall"
elif max_iterations <= 0 and segment_runs > 0 and segment_runs % 200 == 0 and backstop_ack < segment_runs:
    verdict = "backstop"
else:
    verdict = "continue"

print(f"SEGMENT={segment}")
print(f"SEGMENT_RUNS={segment_runs}")
print(f"STREAK={streak}")
print(f"LAST_STATUS={last_status}")
print(f"BACKSTOP_ACK={backstop_ack}")
print(f"VERDICT={verdict}")
PYEOF
