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
# Only files in the project root are matched — nested files like src/data/prepare.py
# are NOT blocked (they are unrelated to autoresearch).

set -euo pipefail

# Read JSON payload from stdin
INPUT=$(cat)

# Extract the target file path and working directory from tool input
# Uses portable sed (no jq or grep -P dependency — works on Git Bash/Windows)
TARGET_FILE=$(echo "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null || true)

# If no file path found, allow the operation
if [[ -z "$TARGET_FILE" ]]; then
  exit 0
fi

# Extract filename and parent directory
BASENAME=$(basename "$TARGET_FILE")
DIRNAME=$(dirname "$TARGET_FILE")

# Only protect files in the project root (or one level deep for scripts).
# Files like src/data/prepare.py or lib/utils/parse-metrics.sh are NOT blocked.
# We check by looking at the directory depth relative to the project.
# Protected patterns: */prepare.py at root, */autoresearch.sh at root,
# */scripts/parse-metrics.sh, */scripts/log-experiment.sh
is_protected_location() {
  local dir_basename
  dir_basename=$(basename "$DIRNAME")
  case "$BASENAME" in
    # These are only protected at project root level (not in subdirectories)
    prepare.py|autoresearch.sh|autoresearch.checks.sh)
      # Check the parent is NOT a nested source directory
      # Allow if parent contains typical source dirs (src, lib, pkg, etc.)
      case "$dir_basename" in
        src|lib|pkg|packages|components|modules|internal|cmd|app|data|utils)
          return 1  # Not protected — it's in a source subdirectory
          ;;
      esac
      return 0  # Protected — likely project root
      ;;
    # Plugin utility scripts are protected wherever they are
    parse-metrics.sh|log-experiment.sh)
      return 0
      ;;
  esac
  return 1  # Not a protected filename
}

# Check if this file should be protected
if ! is_protected_location; then
  exit 0
fi

# Protection: blocks modification of existing files only.
# If the file does not exist yet, allow creation (initial setup phase).
if [[ ! -f "$TARGET_FILE" ]]; then
  exit 0
fi

# File exists and is protected — block the modification
case "$BASENAME" in
  prepare.py)
    echo "Blocked: prepare.py is READ-ONLY. It contains the fixed evaluation harness, tokenizer, and dataloader. Modifying it would invalidate all experiment comparisons. Only train.py may be edited." >&2
    ;;
  autoresearch.sh)
    echo "Blocked: autoresearch.sh is the benchmark script. Modifying it mid-loop would invalidate past measurements and break metric comparability. If you need to change the benchmark, start a new segment." >&2
    ;;
  autoresearch.checks.sh)
    echo "Blocked: autoresearch.checks.sh defines correctness checks. Modifying it mid-loop would weaken quality guarantees. Edit only during setup, not during the experiment loop." >&2
    ;;
  parse-metrics.sh)
    echo "Blocked: parse-metrics.sh is a plugin utility script. It must not be modified during experiments." >&2
    ;;
  log-experiment.sh)
    echo "Blocked: log-experiment.sh is a plugin utility script. It must not be modified during experiments." >&2
    ;;
esac
exit 2
