#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-09
# find-missing-headers.sh - Recursively find scripts whose bash header doesn't match the
#                            project standard:
#                              line 1: #!/usr/bin/env bash
#                              line 2: a bash-4+ version guard (checks for BASH_VERSINFO)
#
# A file only counts as a "bash script" here if its first line is ANY bash shebang
# (#!/bin/bash, #!/usr/bin/env bash, #!/usr/local/bin/bash, etc) - non-bash files
# (python, zsh, awk, expect, plain text...) are silently skipped.
#
# Companion to add-bash-version-guard.sh, which fixes exactly what this finds.
#
# Usage:
#   find-missing-headers.sh [path]        List failing file paths, one per line (default path: .)
#   find-missing-headers.sh -v [path]     Same, but explain what's wrong with each one
#
# Output: matching paths go to stdout (so you can pipe them, e.g. into xargs); the
# scan summary always goes to stderr so it never pollutes piped output.

SCRIPT_HL_GOOD='\033[0;32m'
SCRIPT_HL_ATTENTION='\033[0;33m'
SCRIPT_HL_ERROR='\033[0;31m'
SCRIPT_HL_DETAIL='\033[0;36m'
NC='\033[0m'

VERBOSE=0
if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    VERBOSE=1
    shift
fi
ROOT="${1:-.}"

if [ ! -d "$ROOT" ]; then
    echo -e "${SCRIPT_HL_ERROR}Error: '$ROOT' is not a directory.${NC}" >&2
    exit 1
fi

total=0
bad_shebang=0
missing_guard=0

while IFS= read -r -d '' f; do
    grep -qI '' "$f" 2>/dev/null || continue   # skip binary files (avoids null-byte warnings below)
    first_line=$(head -n1 "$f" 2>/dev/null)
    [[ "$first_line" == "#!"*bash* ]] || continue
    total=$((total + 1))

    second_line=$(sed -n '2p' "$f" 2>/dev/null)
    bad=0
    miss=0
    [[ "$first_line" != "#!/usr/bin/env bash" ]] && bad=1
    [[ "$second_line" != *BASH_VERSINFO* ]] && miss=1

    [ "$bad" -eq 0 ] && [ "$miss" -eq 0 ] && continue

    bad_shebang=$((bad_shebang + bad))
    missing_guard=$((missing_guard + miss))

    if [ "$VERBOSE" -eq 1 ]; then
        echo -e "${SCRIPT_HL_ATTENTION}${f}${NC}"
        [ "$bad" -eq 1 ] && echo -e "    ${SCRIPT_HL_ERROR}✗ shebang:${NC} ${SCRIPT_HL_DETAIL}${first_line}${NC}  (expected: #!/usr/bin/env bash)"
        [ "$miss" -eq 1 ] && echo -e "    ${SCRIPT_HL_ERROR}✗ line 2: ${NC} ${SCRIPT_HL_DETAIL}missing the bash-4+ version guard${NC}"
    else
        echo "$f"
    fi
done < <(find "$ROOT" -type f -not -path '*/.git/*' -print0 2>/dev/null)

{
    echo
    echo -e "${SCRIPT_HL_GOOD}Scanned $total bash script(s) under '$ROOT'.${NC}"
    if [ "$bad_shebang" -eq 0 ] && [ "$missing_guard" -eq 0 ]; then
        echo -e "${SCRIPT_HL_GOOD}✅ All good — every one has the standard header.${NC}"
    else
        echo -e "${SCRIPT_HL_ATTENTION}$bad_shebang with a non-standard shebang, $missing_guard missing the version guard.${NC}"
        echo -e "${SCRIPT_HL_DETAIL}Fix them all with: 0-scripts/add-bash-version-guard.sh${NC}"
    fi
} >&2
