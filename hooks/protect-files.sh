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
# Protection only activates AFTER the file has been created (initial setup is allowed).
# The hook reads the tool input from stdin (JSON), extracts the target file_path,
# and blocks the operation with exit code 2 if the file matches a protected pattern.
# The stderr message is fed back to Claude as feedback so it understands why.

set -euo pipefail

# Read JSON payload from stdin
INPUT=$(cat)

# Extract the target file path from tool_input (portable, no jq or grep -P dependency)
# Works with both Write (file_path + content) and Edit (file_path + old_string + new_string)
TARGET_FILE=$(echo "$INPUT" | sed -n 's/.*"file_path"\s*:\s*"\([^"]*\)".*/\1/p' 2>/dev/null || true)

# If no file path found, allow the operation
if [[ -z "$TARGET_FILE" ]]; then
  exit 0
fi

# Normalize: extract just the filename for pattern matching
BASENAME=$(basename "$TARGET_FILE")

# Protection function: blocks modification of existing files only.
# If the file does not exist yet, allow creation (initial setup phase).
block_if_exists() {
  local file="$1"
  local reason="$2"
  if [[ -f "$TARGET_FILE" ]]; then
    echo "Blocked: $reason" >&2
    exit 2
  fi
  # File does not exist yet — allow creation during setup
  exit 0
}

# Protected files — block modification, allow initial creation
case "$BASENAME" in
  prepare.py)
    block_if_exists "$TARGET_FILE" \
      "prepare.py is READ-ONLY. It contains the fixed evaluation harness, tokenizer, and dataloader. Modifying it would invalidate all experiment comparisons. Only train.py may be edited."
    ;;
  autoresearch.sh)
    block_if_exists "$TARGET_FILE" \
      "autoresearch.sh is the benchmark script. Modifying it mid-loop would invalidate past measurements and break metric comparability. If you need to change the benchmark, start a new segment."
    ;;
  autoresearch.checks.sh)
    block_if_exists "$TARGET_FILE" \
      "autoresearch.checks.sh defines correctness checks. Modifying it mid-loop would weaken quality guarantees. Edit only during setup, not during the experiment loop."
    ;;
  parse-metrics.sh)
    block_if_exists "$TARGET_FILE" \
      "parse-metrics.sh is a plugin utility script. It must not be modified during experiments."
    ;;
  log-experiment.sh)
    block_if_exists "$TARGET_FILE" \
      "log-experiment.sh is a plugin utility script. It must not be modified during experiments."
    ;;
esac

# Not a protected file — allow the operation
exit 0
