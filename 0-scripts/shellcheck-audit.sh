#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2026-10

# shellcheck-audit.sh — run shellcheck across a directory tree and summarise it.
# Complements syntax-check-script.sh, which only catches syntax errors and bad
# characters: shellcheck catches real bugs (unquoted expansions, misused set -e,
# wrong test operators, and more).
#
# Usage:
#   shellcheck-audit.sh [directory]        # default: this repo
#   shellcheck-audit.sh [directory] --full # show every finding, not just the summary

set -uo pipefail

BOLD="\033[1m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
GREEN="\033[1;32m"
NC="\033[0m"

pkg_install() {
    if command -v brew &>/dev/null; then brew install "$@"
    elif command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else
        echo "No supported package manager found (brew/apt/zypper/dnf)." >&2
        exit 1
    fi
}

for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        echo "Usage: $(basename "$0") [directory] [--full]"
        exit 0
    fi
done

if ! command -v shellcheck &>/dev/null; then
    echo -e "${YELLOW}shellcheck not found.${NC}"
    read -r -p "Install it now? [Y/n] " yn
    if [[ -z "$yn" || "$yn" =~ ^[Yy]$ ]]; then
        pkg_install shellcheck
    else
        echo "shellcheck is required. Exiting." >&2
        exit 1
    fi
fi

TARGET_DIR="."
FULL=false
for arg in "$@"; do
    case "$arg" in
        --full) FULL=true ;;
        -h|--help)
            echo "Usage: $(basename "$0") [directory] [--full]"
            exit 0
            ;;
        *) TARGET_DIR="$arg" ;;
    esac
done

if [[ ! -d "$TARGET_DIR" ]]; then
    echo -e "${RED}✖ Not a directory: $TARGET_DIR${NC}" >&2
    exit 1
fi

mapfile -d '' -t FILES < <(find "$TARGET_DIR" -name '*.sh' -not -path '*/.git/*' -print0)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "No .sh files found under $TARGET_DIR."
    exit 0
fi

echo -e "${BOLD}Running shellcheck on ${#FILES[@]} files under $TARGET_DIR ...${NC}"
echo

TMP_RESULTS=$(mktemp)
trap 'rm -f "$TMP_RESULTS"' EXIT

CLEAN=0
ISSUES=0
for f in "${FILES[@]}"; do
    OUT=$(shellcheck -S warning "$f" 2>&1)
    if [[ -z "$OUT" ]]; then
        CLEAN=$((CLEAN + 1))
        continue
    fi
    ISSUES=$((ISSUES + 1))
    COUNT=$(grep -cE '^In .+ line [0-9]+:' <<<"$OUT")
    echo "$COUNT	$f" >> "$TMP_RESULTS"
    if $FULL; then
        echo -e "${BOLD}--- $f ($COUNT finding(s)) ---${NC}"
        echo "$OUT"
        echo
    fi
done

echo -e "${BOLD}Summary${NC}"
echo "  Files checked: ${#FILES[@]}"
echo -e "  Clean:         ${GREEN}$CLEAN${NC}"
echo -e "  With findings: ${YELLOW}$ISSUES${NC}"

if [[ -s "$TMP_RESULTS" ]]; then
    echo
    echo -e "${BOLD}Worst offenders (by finding count):${NC}"
    sort -rn "$TMP_RESULTS" | head -20 | while IFS=$'\t' read -r count file; do
        printf "  %4s  %s\n" "$count" "$file"
    done
    if ! $FULL; then
        echo
        echo "Run with --full to see every finding, or: shellcheck -S warning <file>"
    fi
fi
