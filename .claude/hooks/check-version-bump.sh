#!/bin/bash
# PreToolUse hook for DOSBTS.
# Advises (does NOT block) when an Edit/Write touches CURRENT_PROJECT_VERSION
# in project.pbxproj while CHANGELOG.md still has unreleased entries that
# haven't been promoted to a fresh [Build N] — YYYY-MM-DD block today.
#
# Spec: https://docs.claude.com/en/docs/claude-code/hooks
# stdin is JSON: { tool_name, tool_input: { file_path, old_string, new_string, ... } }

set -e

REPO="/Users/doke/extracode/DOSBTS"
INPUT="$(cat)"

# Extract fields with python3 (always present on macOS). Silent on parse errors.
file_path=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('file_path',''))" 2>/dev/null || true)
new_string=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('new_string',''))" 2>/dev/null || true)
content=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('content',''))" 2>/dev/null || true)
command=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" 2>/dev/null || true)

# Detect a version-bump edit. Two signals:
#   1. Edit/Write to project.pbxproj where the payload contains CURRENT_PROJECT_VERSION
#   2. Bash command that sed-rewrites CURRENT_PROJECT_VERSION
is_bump=0
case "$file_path" in
  *project.pbxproj)
    case "$new_string$content" in
      *CURRENT_PROJECT_VERSION*) is_bump=1 ;;
    esac
    ;;
esac
case "$command" in
  *CURRENT_PROJECT_VERSION*) is_bump=1 ;;
esac

[ "$is_bump" -eq 1 ] || exit 0

# Inspect CHANGELOG.md state.
changelog="$REPO/CHANGELOG.md"
[ -f "$changelog" ] || exit 0

today=$(date +%Y-%m-%d)

# Lines between [Unreleased] and the first [Build N] header.
unreleased_body=$(awk '
  /^## \[Unreleased\]/ { in_block=1; next }
  in_block && /^## \[Build [0-9]+\]/ { exit }
  in_block { print }
' "$changelog" | grep -vE '^\s*$' || true)

# First [Build N] line.
first_build_line=$(grep -m1 -E '^## \[Build [0-9]+\]' "$changelog" || true)

has_unreleased=0
[ -n "$unreleased_body" ] && has_unreleased=1

has_fresh_promotion=0
case "$first_build_line" in
  *"— $today"*|*"- $today"*) has_fresh_promotion=1 ;;
esac

# Warn if there are pending [Unreleased] entries AND no [Build N] header dated today.
if [ "$has_unreleased" -eq 1 ] && [ "$has_fresh_promotion" -eq 0 ]; then
  cat >&2 <<EOF
⚠️  CHANGELOG promotion reminder

You appear to be bumping CURRENT_PROJECT_VERSION, but CHANGELOG.md still has
entries under [Unreleased] and no '## [Build N] — $today' header yet.

CLAUDE.md rule: promote [Unreleased] → [Build N] — YYYY-MM-DD BEFORE bumping.
Use the 'bump-build' skill to do both in one step, or promote manually first.

(Hook is advisory — proceeding.)
EOF
fi

exit 0
