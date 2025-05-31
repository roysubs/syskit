#!/usr/bin/env bash
# Author: Roy Wiseman 2025-05
#
# fix-corrupt-script.sh — clean hidden Unicode/control characters from a script
# Usage: ./fix-corrupt-script.sh script.sh        → creates script.sh.cleaned
#        ./fix-corrupt-script.sh --in-place file  → cleans file in-place
#

set -euo pipefail

# Functions for color output
red()   { printf "\033[0;31m%s\033[0m\n" "$*"; }
green() { printf "\033[0;32m%s\033[0m\n" "$*"; }

# Check args
if [[ $# -lt 1 ]]; then
    red "Usage: $0 <script> [--in-place]"
    exit 1
fi

INPLACE=false
if [[ "$1" == "--in-place" ]]; then
    if [[ -z "${2:-}" ]]; then
        red "Error: --in-place requires a filename"
        exit 1
    fi
    INPLACE=true
    INPUT="$2"
else
    INPUT="$1"
fi

if [[ ! -f "$INPUT" ]]; then
    red "Error: File not found: $INPUT"
    exit 1
fi

# Set output path
if $INPLACE; then
    TMP_CLEANED="$(mktemp)"
else
    TMP_CLEANED="${INPUT}.cleaned"
fi

# Clean using iconv and sed
iconv -c -f utf-8 -t ascii "$INPUT" | sed 's/[^[:print:]\t]//g' > "$TMP_CLEANED"

# Restore permissions
chmod --reference="$INPUT" "$TMP_CLEANED"

# Replace original or keep cleaned copy
if $INPLACE; then
    mv "$TMP_CLEANED" "$INPUT"
    green "✔ Cleaned in place: $INPUT"
else
    green "✔ Cleaned copy written to: $TMP_CLEANED"
fi

# Old / Alternative method
# #!/bin/bash
# # Usage: ./fix-corrupt-script.sh bad_script.sh > clean_script.sh
# 
# input="$1"
# if [[ ! -f "$input" ]]; then
#   echo "Usage: $0 <script-to-clean>" >&2
#   exit 1
# fi
# 
# # Read file line-by-line and remove suspicious characters
# while IFS= read -r line || [[ -n "$line" ]]; do
#   # Remove all non-printable characters except TAB (09), LF (0A), CR (0D)
#   cleaned=$(echo -n "$line" | tr -cd '\11\12\15\40-\176')
#   echo "$cleaned"
# done < "$input"

# Fix line-ending problems in scripts:
# 
# dos2unix ~/syskit/0-scripts/shares-smb.sh
# 
# Method 2: Using sed
# 
# If you prefer not to install dos2unix:
# sed -i 's/\r$//' ~/syskit/0-scripts/shares-smb.sh
