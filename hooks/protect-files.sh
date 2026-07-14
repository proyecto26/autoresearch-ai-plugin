#!/usr/bin/env bash
# protect-files.sh — Prevent modification of protected autoresearch files.
#
# This PreToolUse hook blocks Write and Edit operations on files that must not
# change during the experiment loop:
#
# - prepare.py / autoresearch.sh / autoresearch.checks.sh: the immutable session
#   harness, protected ONLY when they sit at the session root (the payload's cwd).
#   Editing them mid-loop invalidates metric comparability.
# - Plugin utility scripts (parse-metrics.sh, log-experiment.sh, session-status.sh):
#   protected ONLY when they resolve under this plugin's own directory. A user
#   project never has its own copy, so we never block an unrelated same-named file.
#
# Protection activates only AFTER a file exists (initial setup can create it).
#
# Location is decided by the *canonical* session root (cwd), not by a
# parent-directory-name whitelist. Canonicalizing with `cd … && pwd` resolves
# `..` traversal and symlinks and normalizes the path separator, so it works on
# Linux, macOS (including bash 3.2) and Git Bash/Windows, and is not fooled by
# paths like `src/../prepare.py` or Windows-style `C:\proj\prepare.py`.

set -euo pipefail

# Where this plugin lives (…/hooks/protect-files.sh -> plugin root, canonical).
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || echo "")"

INPUT=$(cat)

# Extract the target file path and the session cwd from the payload (portable
# POSIX sed — the top-level "cwd" is provided by Claude Code's hook input).
extract() { echo "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" 2>/dev/null | head -1 || true; }
TARGET_FILE=$(extract file_path)
CWD=$(extract cwd)

# No file path → nothing to protect.
if [[ -z "$TARGET_FILE" ]]; then
  exit 0
fi

# Normalize Windows backslashes to forward slashes so basename/dirname and the
# comparisons below behave identically on a `C:\proj\prepare.py` payload.
TARGET_FILE=${TARGET_FILE//\\//}
CWD=${CWD//\\//}
[[ -z "$CWD" ]] && CWD="$PWD"

BASENAME=$(basename "$TARGET_FILE")

# Fast path: if the basename is not even a candidate, allow immediately.
case "$BASENAME" in
  prepare.py|autoresearch.sh|autoresearch.checks.sh|parse-metrics.sh|log-experiment.sh|session-status.sh) ;;
  *) exit 0 ;;
esac

# Resolve the target to an absolute path (relative → against cwd).
case "$TARGET_FILE" in
  /*|[A-Za-z]:/*) TARGET_ABS="$TARGET_FILE" ;;
  *) TARGET_ABS="${CWD%/}/$TARGET_FILE" ;;
esac

# Block modification of an existing file only; allow first-time creation (setup).
# -f resolves any `..` in the path via the filesystem, so traversal can't dodge it.
if [[ ! -f "$TARGET_ABS" ]]; then
  exit 0
fi

# Canonicalize the target's directory and the session root. `cd … && pwd`
# resolves `..`, symlinks, and separator quirks; the file is known to exist here.
TARGET_DIR_CANON="$(cd "$(dirname "$TARGET_ABS")" 2>/dev/null && pwd || echo "")"
CWD_CANON="$(cd "$CWD" 2>/dev/null && pwd || echo "")"
TARGET_CANON="${TARGET_DIR_CANON}/${BASENAME}"

is_protected() {
  case "$BASENAME" in
    prepare.py|autoresearch.sh|autoresearch.checks.sh)
      # Protected only when the (canonical) file sits directly in the session root.
      [[ -n "$TARGET_DIR_CANON" && -n "$CWD_CANON" && "$TARGET_DIR_CANON" == "$CWD_CANON" ]] && return 0 ;;
    parse-metrics.sh|log-experiment.sh|session-status.sh)
      # Protected only when the (canonical) file is under this plugin's own dir.
      [[ -n "$PLUGIN_ROOT" && "$TARGET_CANON" == "$PLUGIN_ROOT"/* ]] && return 0 ;;
  esac
  return 1
}

if ! is_protected; then
  exit 0
fi

case "$BASENAME" in
  prepare.py)
    echo "Blocked: prepare.py is READ-ONLY. It contains the fixed evaluation harness, tokenizer, and dataloader. Modifying it would invalidate all experiment comparisons. Only train.py may be edited." >&2 ;;
  autoresearch.sh)
    echo "Blocked: autoresearch.sh is the benchmark script. Modifying it mid-loop would invalidate past measurements and break metric comparability. If you need to change the benchmark, start a new segment." >&2 ;;
  autoresearch.checks.sh)
    echo "Blocked: autoresearch.checks.sh defines correctness checks. Modifying it mid-loop would weaken quality guarantees. Edit only during setup, not during the experiment loop." >&2 ;;
  parse-metrics.sh|log-experiment.sh|session-status.sh)
    echo "Blocked: $BASENAME is a plugin utility script. It must not be modified during experiments." >&2 ;;
esac
exit 2
