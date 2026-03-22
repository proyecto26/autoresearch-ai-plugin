#!/usr/bin/env bash
# log-experiment.sh — Append an experiment result to autoresearch.jsonl
#
# Usage:
#   bash ${CLAUDE_SKILL_DIR}/scripts/log-experiment.sh \
#     --run 5 \
#     --commit "abc1234" \
#     --metric 4.23 \
#     --status keep \
#     --description "reduced batch size to 64" \
#     --metrics '{"compile_ms":1200,"memory_mb":512}' \
#     --segment 0 \
#     --confidence 2.3 \
#     --asi '{"hypothesis":"smaller batches converge faster"}'
#
# Options:
#   --run          Experiment number, 1-indexed (required)
#   --commit       Short commit hash (required)
#   --metric       Primary metric value (required)
#   --status       One of: keep, discard, crash, checks_failed (required)
#   --description  Brief description of experiment (required)
#   --metrics      Secondary metrics as JSON object (optional)
#   --segment      Session segment index, 0-based (optional, default: 0)
#   --confidence   MAD-based confidence score (optional)
#   --asi          Actionable Side Information as JSON object (optional)
#   --file         Output file (default: autoresearch.jsonl)
#
# Config header (written once at setup):
#   bash log-experiment.sh --config \
#     --name "Optimize tests" \
#     --metric-name "total_ms" \
#     --metric-unit "ms" \
#     --direction "lower"

set -euo pipefail

# Mode flags
CONFIG_MODE=false

# Config header fields
CFG_NAME=""
CFG_METRIC_NAME=""
CFG_METRIC_UNIT=""
CFG_DIRECTION=""

# Experiment result fields
RUN=""
COMMIT=""
METRIC=""
STATUS=""
DESCRIPTION=""
METRICS=""
SEGMENT="0"
CONFIDENCE=""
ASI=""
FILE="autoresearch.jsonl"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)       CONFIG_MODE=true; shift ;;
    --name)         CFG_NAME="$2"; shift 2 ;;
    --metric-name)  CFG_METRIC_NAME="$2"; shift 2 ;;
    --metric-unit)  CFG_METRIC_UNIT="$2"; shift 2 ;;
    --direction)    CFG_DIRECTION="$2"; shift 2 ;;
    --run)          RUN="$2"; shift 2 ;;
    --commit)       COMMIT="$2"; shift 2 ;;
    --metric)       METRIC="$2"; shift 2 ;;
    --status)       STATUS="$2"; shift 2 ;;
    --description)  DESCRIPTION="$2"; shift 2 ;;
    --metrics)      METRICS="$2"; shift 2 ;;
    --segment)      SEGMENT="$2"; shift 2 ;;
    --confidence)   CONFIDENCE="$2"; shift 2 ;;
    --asi)          ASI="$2"; shift 2 ;;
    --file)         FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Config header mode ---
if $CONFIG_MODE; then
  if [[ -z "$CFG_NAME" || -z "$CFG_METRIC_NAME" || -z "$CFG_METRIC_UNIT" || -z "$CFG_DIRECTION" ]]; then
    echo "Error: --config requires --name, --metric-name, --metric-unit, and --direction" >&2
    exit 1
  fi
  case "$CFG_DIRECTION" in
    lower|higher) ;;
    *) echo "Error: --direction must be 'lower' or 'higher'" >&2; exit 1 ;;
  esac
  # Escape string fields for safe JSON
  json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
  }
  printf '{"type":"config","name":"%s","metricName":"%s","metricUnit":"%s","bestDirection":"%s"}\n' \
    "$(json_escape "$CFG_NAME")" "$(json_escape "$CFG_METRIC_NAME")" "$(json_escape "$CFG_METRIC_UNIT")" "$CFG_DIRECTION" >> "$FILE"
  echo "Config header written: $CFG_NAME ($CFG_METRIC_NAME, $CFG_DIRECTION)"
  exit 0
fi

# --- Experiment result mode ---

# Validate required fields
if [[ -z "$RUN" || -z "$COMMIT" || -z "$METRIC" || -z "$STATUS" || -z "$DESCRIPTION" ]]; then
  echo "Error: --run, --commit, --metric, --status, and --description are all required" >&2
  exit 1
fi

# Validate status
case "$STATUS" in
  keep|discard|crash|checks_failed) ;;
  *) echo "Error: --status must be one of: keep, discard, crash, checks_failed" >&2; exit 1 ;;
esac

TIMESTAMP=$(date +%s)

# Escape double-quotes and backslashes for safe JSON embedding
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# Build JSON line (portable, no jq dependency)
# Start with required fields
SAFE_DESC=$(json_escape "$DESCRIPTION")
JSON=$(printf '{"run":%s,"commit":"%s","metric":%s,"status":"%s","description":"%s","timestamp":%s,"segment":%s' \
  "$RUN" "$COMMIT" "$METRIC" "$STATUS" "$SAFE_DESC" "$TIMESTAMP" "$SEGMENT")

# Add optional secondary metrics
if [[ -n "$METRICS" ]]; then
  JSON="${JSON},\"metrics\":${METRICS}"
fi

# Add optional confidence
if [[ -n "$CONFIDENCE" ]]; then
  JSON="${JSON},\"confidence\":${CONFIDENCE}"
fi

# Add optional ASI
if [[ -n "$ASI" ]]; then
  JSON="${JSON},\"asi\":${ASI}"
fi

# Close JSON object
JSON="${JSON}}"

echo "$JSON" >> "$FILE"

echo "Logged: #$RUN $STATUS | metric=$METRIC | $DESCRIPTION"
