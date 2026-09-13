#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-01
# diff-quick.sh - A beginner-friendly, annotated wrapper around `diff` output
#                 and git conflict markers (<<<<<<< ======= >>>>>>>).
# Usage:
#   diff-quick.sh <file1> <file2>        Explain a classic `diff` between two files
#   diff-quick.sh -u <file1> <file2>     Explain a `diff -u` (unified) instead
#   diff-quick.sh <file-with-conflicts>  Explain the <<<<<<< / ======= / >>>>>>> blocks in one file

# --- ANSI Color Codes (matches diff-files.sh conventions) ---
SCRIPT_HL_GOOD='\033[0;32m'          # Green
SCRIPT_HL_ATTENTION='\033[0;33m'     # Yellow
SCRIPT_HL_SECTION_TITLE='\033[1;33m' # Bright Yellow
SCRIPT_HL_DETAIL='\033[0;36m'        # Cyan
SCRIPT_HL_ERROR_BG='\033[41m'        # Red background
SCRIPT_HL_REMOVED='\033[0;31m'       # Red   - "only in FILE1" / removed
SCRIPT_HL_ADDED='\033[0;32m'         # Green - "only in FILE2" / added
SCRIPT_HL_TOP='\033[0;36m'           # Cyan    - top half of a conflict block
SCRIPT_HL_BOTTOM='\033[0;35m'        # Magenta - bottom half of a conflict block
NC='\033[0m'

# --- Usage ---
show_help() {
    echo -e "\n${SCRIPT_HL_GOOD}diff-quick.sh${NC} — annotated, colourful diff/conflict explainer for people who don't live in git every day.\n"
    echo -e "${SCRIPT_HL_SECTION_TITLE}Compare two files:${NC}"
    echo -e "  ${0##*/} <file1> <file2>        Classic diff format (1,5d0 / < / >), annotated"
    echo -e "  ${0##*/} -u <file1> <file2>     Unified diff format (--- +++ @@), annotated"
    echo -e "\n${SCRIPT_HL_SECTION_TITLE}Explain a conflicted file (after a failed merge/pull/stash pop):${NC}"
    echo -e "  ${0##*/} <file>                 Walks through every <<<<<<< / ======= / >>>>>>> block"
    echo -e "\n${SCRIPT_HL_SECTION_TITLE}Examples:${NC}"
    echo -e "  ${0##*/} old_config.sh new_config.sh"
    echo -e "  ${0##*/} -u old_config.sh new_config.sh"
    echo -e "  ${0##*/} 0-docker/0-media-stack/reset-password.sh   ${SCRIPT_HL_DETAIL}# after a git conflict${NC}\n"
}

# --- Arg parsing ---
UNIFIED=0
POSITIONAL=()
for arg in "$@"; do
    case "$arg" in
        -u|--unified) UNIFIED=1 ;;
        -h|--help) show_help; exit 0 ;;
        *) POSITIONAL+=("$arg") ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [ "$#" -eq 0 ]; then
    show_help
    exit 1
fi

# ============================================================
# Conflict-marker mode (single file argument)
# ============================================================

describe_label() {
    local label="$1" side="$2"
    case "$label" in
        HEAD)
            echo "your current branch (HEAD) — what you had before this operation started"
            ;;
        "Updated upstream")
            echo "the file as it stands right after the most recent checkout/pull (git stash pop)"
            ;;
        "Stashed changes")
            echo "the edits you had stashed away — your own uncommitted work (git stash pop)"
            ;;
        "")
            [[ "$side" == "top" ]] && echo "(no label given)" || echo "(no label given)"
            ;;
        *)
            if [[ "$side" == "top" ]]; then
                echo "usually HEAD / the branch you were already on"
            else
                echo "usually the incoming branch or commit named here"
            fi
            ;;
    esac
}

print_conflict_legend() {
    echo -e "${SCRIPT_HL_ATTENTION}How to read conflict markers:${NC}"
    echo -e "  ${SCRIPT_HL_TOP}<<<<<<< LABEL${NC}          starts the ${SCRIPT_HL_TOP}TOP${NC} side of the conflict"
    echo -e "  ${SCRIPT_HL_TOP}   ...top side lines...${NC}"
    echo -e "  ${SCRIPT_HL_ATTENTION}=======${NC}                the dividing line between the two sides"
    echo -e "  ${SCRIPT_HL_BOTTOM}   ...bottom side lines...${NC}"
    echo -e "  ${SCRIPT_HL_BOTTOM}>>>>>>> LABEL${NC}          ends the ${SCRIPT_HL_BOTTOM}BOTTOM${NC} side"
    echo
    echo -e "${SCRIPT_HL_DETAIL}What TOP/BOTTOM usually mean, depending on how you got here:${NC}"
    echo -e "  ${SCRIPT_HL_DETAIL}git merge / git pull:${NC}  TOP=HEAD (your branch)          BOTTOM=<branch being merged in>"
    echo -e "  ${SCRIPT_HL_DETAIL}git stash pop:${NC}         TOP=Updated upstream (pulled)   BOTTOM=Stashed changes (your edits)"
    echo -e "  ${SCRIPT_HL_DETAIL}git rebase:${NC}            ${SCRIPT_HL_ERROR_BG} flipped! ${NC} TOP=branch you're rebasing ONTO, BOTTOM=the commit being replayed"
    echo
}

print_resolution_steps() {
    echo -e "\n${SCRIPT_HL_SECTION_TITLE}To resolve each block:${NC}"
    echo -e "  1. Decide: keep TOP, keep BOTTOM, or hand-write a combination of both."
    echo -e "  2. Delete the three marker lines themselves (${SCRIPT_HL_ATTENTION}<<<<<<<${NC}, ${SCRIPT_HL_ATTENTION}=======${NC}, ${SCRIPT_HL_ATTENTION}>>>>>>>${NC}) — git never removes these for you."
    echo -e "  3. Save the file, then: ${SCRIPT_HL_GOOD}git add <file>${NC}"
    echo -e "  4. Once every conflicted file is added, continue the operation, e.g. ${SCRIPT_HL_GOOD}git commit${NC}, ${SCRIPT_HL_GOOD}git rebase --continue${NC}, or ${SCRIPT_HL_GOOD}git stash drop${NC}."
    echo
    echo -e "${SCRIPT_HL_DETAIL}Want an interactive 2-pane view instead of reading markers by eye?${NC}  ${SCRIPT_HL_GOOD}diff-files.sh <file1> <file2>${NC}  (vimdiff)"
    echo -e "${SCRIPT_HL_DETAIL}Want a real 3-way merge tool (base/ours/theirs)?${NC}                  ${SCRIPT_HL_GOOD}git mergetool${NC}"
}

run_conflict_explain() {
    local f="$1"

    if [ ! -f "$f" ]; then
        echo -e "${SCRIPT_HL_ERROR_BG}Error: File '$f' not found.${NC}"
        exit 1
    fi

    if ! grep -q '^<<<<<<< ' "$f"; then
        echo -e "${SCRIPT_HL_ATTENTION}No conflict markers ('<<<<<<< ') found in $f.${NC}"
        echo -e "${SCRIPT_HL_DETAIL}Tip: pass TWO files instead to compare them: ${0##*/} file1 file2${NC}"
        exit 1
    fi

    clear
    echo -e "${SCRIPT_HL_GOOD}=== Conflict markers in: $f ===${NC}\n"
    print_conflict_legend

    local in_top=0 in_bottom=0 top_label="" bottom_label="" lineno=0 block=0
    while IFS= read -r line || [ -n "$line" ]; do
        lineno=$((lineno + 1))
        if [[ $line == "<<<<<<< "* || $line == "<<<<<<<" ]]; then
            block=$((block + 1))
            top_label="${line#<<<<<<< }"
            [[ "$top_label" == "<<<<<<<" ]] && top_label=""
            echo -e "\n${SCRIPT_HL_SECTION_TITLE}── Conflict block #$block — starts at line $lineno ──${NC}"
            echo -e "${SCRIPT_HL_TOP}<<<<<<< $top_label${NC}   ${SCRIPT_HL_DETAIL}= $(describe_label "$top_label" top)${NC}"
            in_top=1
        elif [[ $line == "=======" && $in_top -eq 1 ]]; then
            echo -e "${SCRIPT_HL_ATTENTION}=======${NC}"
            in_top=0
            in_bottom=1
        elif [[ $line == ">>>>>>> "* || $line == ">>>>>>>" ]] && [ $in_bottom -eq 1 ]; then
            bottom_label="${line#>>>>>>> }"
            [[ "$bottom_label" == ">>>>>>>" ]] && bottom_label=""
            echo -e "${SCRIPT_HL_BOTTOM}>>>>>>> $bottom_label${NC}   ${SCRIPT_HL_DETAIL}= $(describe_label "$bottom_label" bottom)${NC}"
            echo -e "${SCRIPT_HL_SECTION_TITLE}── Conflict block #$block — ends at line $lineno ──${NC}"
            in_bottom=0
        elif [ $in_top -eq 1 ]; then
            echo -e "${SCRIPT_HL_TOP}TOP  |${NC} $line"
        elif [ $in_bottom -eq 1 ]; then
            echo -e "${SCRIPT_HL_BOTTOM}BOT  |${NC} $line"
        fi
    done < "$f"

    echo -e "\n${SCRIPT_HL_GOOD}Found $block conflict block(s) in $f.${NC}"
    print_resolution_steps
}

if [ "$#" -eq 1 ]; then
    run_conflict_explain "$1"
    exit 0
fi

if [ "$#" -ne 2 ]; then
    show_help
    exit 1
fi

file1="$1"
file2="$2"

if [ ! -f "$file1" ]; then
    echo -e "${SCRIPT_HL_ERROR_BG}Error: File '$file1' not found.${NC}"
    exit 1
fi
if [ ! -f "$file2" ]; then
    echo -e "${SCRIPT_HL_ERROR_BG}Error: File '$file2' not found.${NC}"
    exit 1
fi

# ============================================================
# Two-file diff mode
# ============================================================

print_switches_reference() {
    echo -e "\n${SCRIPT_HL_SECTION_TITLE}Useful diff switches:${NC}"
    echo -e "  ${SCRIPT_HL_GOOD}-u${NC}              Unified format (context + +/- prefixes) — usually easier to read than the default"
    echo -e "  ${SCRIPT_HL_GOOD}-y${NC}              Side-by-side columns"
    echo -e "  ${SCRIPT_HL_GOOD}-q${NC}              Just say whether files differ, no details"
    echo -e "  ${SCRIPT_HL_GOOD}-r${NC}              Recurse into directories"
    echo -e "  ${SCRIPT_HL_GOOD}-w${NC}              Ignore whitespace differences"
    echo -e "  ${SCRIPT_HL_GOOD}-i${NC}              Ignore case"
    echo -e "  ${SCRIPT_HL_GOOD}--color=always${NC}  Force diff's own (basic) colour output"
    echo -e "  ${SCRIPT_HL_DETAIL}git equivalents:${NC} ${SCRIPT_HL_GOOD}git diff --stat${NC} (summary only), ${SCRIPT_HL_GOOD}git diff --word-diff${NC} (highlight changed words, not whole lines)"
}

print_classic_legend() {
    echo -e "${SCRIPT_HL_GOOD}=== Classic diff: $(basename "$file1")  vs  $(basename "$file2") ===${NC}\n"
    echo -e "${SCRIPT_HL_DETAIL}FILE1 (LEFT)  = $file1${NC}"
    echo -e "${SCRIPT_HL_DETAIL}FILE2 (RIGHT) = $file2${NC}\n"
    echo -e "${SCRIPT_HL_ATTENTION}How to read it:${NC}"
    echo -e "  Each change block starts with a header like ${SCRIPT_HL_SECTION_TITLE}3,5c2${NC} or ${SCRIPT_HL_SECTION_TITLE}7a8,9${NC} or ${SCRIPT_HL_SECTION_TITLE}10,12d9${NC}."
    echo -e "  The letter in the middle tells you what happened going from FILE1 → FILE2:"
    echo -e "    ${SCRIPT_HL_SECTION_TITLE}a${NC}dd     = FILE2 has extra lines FILE1 doesn't"
    echo -e "    ${SCRIPT_HL_SECTION_TITLE}c${NC}hange  = the lines differ between the two files"
    echo -e "    ${SCRIPT_HL_SECTION_TITLE}d${NC}elete  = FILE1 has lines FILE2 doesn't"
    echo -e "  Below the header:"
    echo -e "    ${SCRIPT_HL_REMOVED}< line${NC}   = this line is only in FILE1 (the FIRST file you named)"
    echo -e "    ${SCRIPT_HL_ADDED}> line${NC}   = this line is only in FILE2 (the SECOND file you named)"
    echo -e "    ${SCRIPT_HL_DETAIL}---${NC}       = separator between the '<' block and the '>' block, only shown for 'change' blocks"
}

run_classic_diff() {
    print_classic_legend
    local diff_output
    diff_output=$(diff "$file1" "$file2")
    if [ -z "$diff_output" ]; then
        echo -e "\n${SCRIPT_HL_GOOD}✅ Files are identical.${NC}"
        return
    fi

    while IFS= read -r line; do
        if [[ $line =~ ^([0-9]+)(,([0-9]+))?([acd])([0-9]+)(,([0-9]+))?$ ]]; then
            local l1="${BASH_REMATCH[1]}" l2="${BASH_REMATCH[3]:-${BASH_REMATCH[1]}}"
            local act="${BASH_REMATCH[4]}"
            local r1="${BASH_REMATCH[5]}" r2="${BASH_REMATCH[7]:-${BASH_REMATCH[5]}}"
            local left_range right_range
            [ "$l1" = "$l2" ] && left_range="line $l1" || left_range="lines $l1-$l2"
            [ "$r1" = "$r2" ] && right_range="line $r1" || right_range="lines $r1-$r2"
            echo
            case "$act" in
                a) echo -e "${SCRIPT_HL_SECTION_TITLE}»» After FILE1 $left_range: FILE2 ADDS $right_range (new — not in FILE1)${NC}" ;;
                d) echo -e "${SCRIPT_HL_SECTION_TITLE}»» FILE1 $left_range is DELETED — FILE2 has nothing there (gap sits before FILE2 line $r1)${NC}" ;;
                c) echo -e "${SCRIPT_HL_SECTION_TITLE}»» FILE1 $left_range CHANGED into FILE2 $right_range${NC}" ;;
            esac
        elif [ "$line" = "---" ]; then
            echo -e "${SCRIPT_HL_DETAIL}   ·········· (FILE1 above / FILE2 below) ··········${NC}"
        elif [[ $line == "<"* ]]; then
            echo -e "${SCRIPT_HL_REMOVED}   ${line}${NC}"
        elif [[ $line == ">"* ]]; then
            echo -e "${SCRIPT_HL_ADDED}   ${line}${NC}"
        else
            echo "   $line"
        fi
    done <<< "$diff_output"

    print_switches_reference
}

print_unified_legend() {
    echo -e "${SCRIPT_HL_GOOD}=== Unified diff: $(basename "$file1")  vs  $(basename "$file2") ===${NC}\n"
    echo -e "${SCRIPT_HL_ATTENTION}How to read it:${NC}"
    echo -e "  ${SCRIPT_HL_SECTION_TITLE}--- file1${NC}   labels FILE1 (OLD / LEFT)"
    echo -e "  ${SCRIPT_HL_SECTION_TITLE}+++ file2${NC}   labels FILE2 (NEW / RIGHT)"
    echo -e "  ${SCRIPT_HL_ATTENTION}@@ -a,b +c,d @@${NC}  a hunk header: FILE1 lines a..a+b-1 correspond to FILE2 lines c..c+d-1"
    echo -e "  ${SCRIPT_HL_REMOVED}-line${NC}       = only in FILE1 (removed)"
    echo -e "  ${SCRIPT_HL_ADDED}+line${NC}       = only in FILE2 (added)"
    echo -e "   line        = unchanged context, shown for orientation"
}

run_unified_diff() {
    print_unified_legend
    local diff_output
    diff_output=$(diff -u "$file1" "$file2")
    if [ -z "$diff_output" ]; then
        echo -e "\n${SCRIPT_HL_GOOD}✅ Files are identical.${NC}"
        return
    fi

    echo
    while IFS= read -r line; do
        if [[ $line == "--- "* ]]; then
            echo -e "${SCRIPT_HL_SECTION_TITLE}${line}${NC}   ${SCRIPT_HL_DETAIL}(FILE1 / OLD / LEFT)${NC}"
        elif [[ $line == "+++ "* ]]; then
            echo -e "${SCRIPT_HL_SECTION_TITLE}${line}${NC}   ${SCRIPT_HL_DETAIL}(FILE2 / NEW / RIGHT)${NC}"
        elif [[ $line =~ ^@@\ -([0-9]+)(,([0-9]+))?\ \+([0-9]+)(,([0-9]+))?\ @@ ]]; then
            local a="${BASH_REMATCH[1]}" b="${BASH_REMATCH[3]:-1}" c="${BASH_REMATCH[4]}" d="${BASH_REMATCH[6]:-1}"
            echo -e "${SCRIPT_HL_ATTENTION}»» Hunk: FILE1 lines $a-$((a + b - 1))  ↔  FILE2 lines $c-$((c + d - 1))${NC}"
        elif [[ $line == "-"* ]]; then
            echo -e "${SCRIPT_HL_REMOVED}${line}${NC}"
        elif [[ $line == "+"* ]]; then
            echo -e "${SCRIPT_HL_ADDED}${line}${NC}"
        else
            echo "   $line"
        fi
    done <<< "$diff_output"

    print_switches_reference
}

if [ "$UNIFIED" -eq 1 ]; then
    run_unified_diff
else
    run_classic_diff
fi
