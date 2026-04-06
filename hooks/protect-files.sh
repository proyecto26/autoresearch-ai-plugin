#!/usr/bin/env bash
# protect-files.sh — Prevent modification of protected autoresearch files
#
# This PreToolUse hook blocks Write and Edit operations on files that must
# not be modified during the autoresearch experiment loop:
#
# - prepare.py: Fixed data infrastructure (evaluation, tokenizer, dataloader)
# - autoresearch.sh: Benchmark script (changing it invalidates past measurements)
# - autoresearch.checks.sh: Correctness checks (changing them weakens guarantees)
# - Plugin utility scripts (parse-metrics.sh, log-experiment.sh)
#
# The hook reads the tool input from stdin (JSON), extracts the target file_path,
# and blocks the operation with exit code 2 if the file matches a protected pattern.
# The stderr message is fed back to Claude as feedback so it understands why.

set -euo pipefail

# Read JSON payload from stdin
INPUT=$(cat)

# Extract the target file path from tool_input
# Both Write and Edit tools include file_path in tool_input
TARGET_FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

# If no file path found, allow the operation
if [[ -z "$TARGET_FILE" ]]; then
  exit 0
fi

# Normalize: extract just the filename for simple pattern matching
BASENAME=$(basename "$TARGET_FILE")

# Protected files — these must never be modified during the experiment loop
case "$BASENAME" in
  prepare.py)
    echo "Blocked: prepare.py is READ-ONLY. It contains the fixed evaluation harness, tokenizer, and dataloader. Modifying it would invalidate all experiment comparisons. Only train.py may be edited." >&2
    exit 2
    ;;
  autoresearch.sh)
    echo "Blocked: autoresearch.sh is the benchmark script. Modifying it mid-loop would invalidate past measurements and break metric comparability. If you need to change the benchmark, start a new segment." >&2
    exit 2
    ;;
  autoresearch.checks.sh)
    echo "Blocked: autoresearch.checks.sh defines correctness checks. Modifying it mid-loop would weaken quality guarantees. Edit only during setup, not during the experiment loop." >&2
    exit 2
    ;;
  parse-metrics.sh)
    echo "Blocked: parse-metrics.sh is a plugin utility script. It must not be modified during experiments." >&2
    exit 2
    ;;
  log-experiment.sh)
    echo "Blocked: log-experiment.sh is a plugin utility script. It must not be modified during experiments." >&2
    exit 2
    ;;
esac

# Not a protected file — allow the operation
exit 0
