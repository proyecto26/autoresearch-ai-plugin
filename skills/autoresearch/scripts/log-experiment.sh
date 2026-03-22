#!/usr/bin/env bash
# log-experiment.sh — Append an experiment result to autoresearch.jsonl
#
# Usage:
#   bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-experiment.sh \
#     --commit "abc1234" \
#     --metric 4.23 \
#     --status keep \
#     --description "reduced batch size to 64"
#
# Options:
#   --commit       Short commit hash (required)
#   --metric       Primary metric value (required)
#   --status       One of: keep, discard, crash, checks_failed (required)
#   --description  Brief description of the experiment (required)
#   --file         Output file (default: autoresearch.jsonl)

set -euo pipefail

COMMIT=""
METRIC=""
STATUS=""
DESCRIPTION=""
FILE="autoresearch.jsonl"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)      COMMIT="$2"; shift 2 ;;
    --metric)      METRIC="$2"; shift 2 ;;
    --status)      STATUS="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --file)        FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Validate required fields
if [[ -z "$COMMIT" || -z "$METRIC" || -z "$STATUS" || -z "$DESCRIPTION" ]]; then
  echo "Error: --commit, --metric, --status, and --description are all required" >&2
  exit 1
fi

# Validate status
case "$STATUS" in
  keep|discard|crash|checks_failed) ;;
  *) echo "Error: --status must be one of: keep, discard, crash, checks_failed" >&2; exit 1 ;;
esac

TIMESTAMP=$(date +%s)

# Build JSON line (portable, no jq dependency)
printf '{"commit":"%s","metric":%s,"status":"%s","description":"%s","timestamp":%s}\n' \
  "$COMMIT" "$METRIC" "$STATUS" "$DESCRIPTION" "$TIMESTAMP" >> "$FILE"

echo "Logged: $STATUS | metric=$METRIC | $DESCRIPTION"
