#!/bin/bash
# Author: Roy Wiseman 2025-03
# vimdiff-helper.sh - A wrapper for vimdiff with helpful keybindings reference
# Usage: vimdiff-helper.sh <file1> <file2>

# --- ANSI Color Codes ---
SCRIPT_HL_GOOD='\033[0;32m'          # Green
SCRIPT_HL_ATTENTION='\033[0;33m'     # Yellow
SCRIPT_HL_SECTION_TITLE='\033[1;33m' # Bright Yellow
SCRIPT_HL_DETAIL='\033[0;36m'        # Cyan
SCRIPT_HL_ERROR_BG='\033[41m'        # Red background
NC='\033[0m'

# --- Check Vim Installation ---
check_vimdiff_installed() {
    if ! command -v vimdiff &> /dev/null; then
        if command -v vim &> /dev/null; then
            echo -e "${SCRIPT_HL_ATTENTION}Warning: 'vimdiff' not found. Using 'vim -d' instead.${NC}"
            VIM_COMMAND="vim -d"
        else
            echo -e "${SCRIPT_HL_ERROR_BG}Error: vim is not installed.${NC}"
            echo "Install with: sudo apt install vim (Debian/Ubuntu) or sudo dnf install vim-enhanced (Fedora/RHEL)"
            exit 1
        fi
    else
        VIM_COMMAND="vimdiff"
    fi
}

# --- Input Validation ---
if [ "$#" -ne 2 ]; then
    echo -e "\nUsage: ${SCRIPT_HL_GOOD}${0##*/} <file1> <file2>${NC}"
    echo -e "Example: ${SCRIPT_HL_GOOD}${0##*/} document_v1.txt document_v2.txt${NC}\n"
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

check_vimdiff_installed

# --- Display Information ---
get_file_info() {
    local file_path="$1"
    local full_path=$(realpath "$file_path" 2>/dev/null || readlink -f "$file_path")
    local size=$(du -h "$file_path" | awk '{print $1}')
    local lines=$(wc -l < "$file_path" | awk '{print $1}')
    
    if date -r "$file_path" +"%Y-%m-%d %H:%M:%S %Z" >/dev/null 2>&1; then
        local modified_date=$(date -r "$file_path" +"%Y-%m-%d %H:%M:%S %Z")
    elif stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S %Z" "$file_path" >/dev/null 2>&1; then
        local modified_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S %Z" "$file_path")
    else
        local modified_date=$(ls -ld "$file_path" | awk '{print $6, $7, $8}')
    fi

    local file_num="$2"
    local pane_side="$3"
    echo -e "${SCRIPT_HL_SECTION_TITLE}--- File $file_num ($pane_side pane)${NC} Last Modified: ${SCRIPT_HL_DETAIL}$modified_date${NC}"
    echo -e "${SCRIPT_HL_SECTION_TITLE}$full_path${NC}  [${SCRIPT_HL_DETAIL}$size, $lines lines${NC}]"
}

clear
echo -e "${SCRIPT_HL_GOOD}=== Vimdiff Quick Reference ===${NC}\n"

echo -e "${SCRIPT_HL_ATTENTION}Navigation:${NC}"
echo -e "  ]c / [c          Jump to next/previous difference"
echo -e "  Ctrl+w w         Switch between panes"
echo -e "  Ctrl+w h/j/k/l   Focus left/down/up/right pane"

echo -e "\n${SCRIPT_HL_ATTENTION}Applying Changes (on entire hunks):${NC}"
echo -e "  dp   'diff put'    - Send current hunk to other pane"
echo -e "  do   'diff obtain' - Get hunk from other pane"
echo -e "  Note: For single-line edits within hunks, use yy/p manually + :diffupdate"

echo -e "\n${SCRIPT_HL_ATTENTION}Folding:${NC}"
echo -e "  zo / zc   Open/close fold"
echo -e "  zR / zM   Open/close ALL folds"

echo -e "\n${SCRIPT_HL_ATTENTION}General:${NC}"
echo -e "  :wqa          Write all and quit"
echo -e "  :qa!          Quit all without saving"
echo -e "  :diffupdate   Refresh diff highlighting"
echo -e "  Ctrl+Z        Suspend vimdiff (type 'fg' to resume)"

echo -e "\n${SCRIPT_HL_ATTENTION}Color Legend (typical defaults):${NC}"
echo -e "  ${SCRIPT_HL_DETAIL}Red/Pink${NC}      Removed lines"
echo -e "  ${SCRIPT_HL_DETAIL}Green${NC}         Added lines"
echo -e "  ${SCRIPT_HL_DETAIL}Blue/Cyan${NC}     Changed lines (specific differences may be highlighted)"
echo -e "  ${SCRIPT_HL_DETAIL}Grey/Purple${NC}   Filler/folded sections"

echo -e "\n${SCRIPT_HL_GOOD}--------------------------------------------------${NC}"
get_file_info "$file1" "1" "left"
get_file_info "$file2" "2" "right"
echo -e "${SCRIPT_HL_GOOD}--------------------------------------------------${NC}\n"

echo -e "${SCRIPT_HL_DETAIL}Remember:${NC} Move cursor into a hunk, then use ${SCRIPT_HL_ATTENTION}dp${NC} or ${SCRIPT_HL_ATTENTION}do${NC} to apply."
echo -e "${SCRIPT_HL_DETAIL}          Press${NC} ${SCRIPT_HL_ATTENTION}Ctrl+Z${NC} ${SCRIPT_HL_DETAIL}to suspend and review this reference. Type${NC} ${SCRIPT_HL_ATTENTION}fg${NC} ${SCRIPT_HL_DETAIL}to resume.${NC}"
echo -e "${SCRIPT_HL_DETAIL}          (Use${NC} ${SCRIPT_HL_ATTENTION}jobs${NC} ${SCRIPT_HL_DETAIL}to list suspended jobs,${NC} ${SCRIPT_HL_ATTENTION}fg %n${NC} ${SCRIPT_HL_DETAIL}to resume job n)${NC}"
echo -e "${SCRIPT_HL_GOOD}--------------------------------------------------${NC}\n"

read -p "Press Enter to start vimdiff..."

$VIM_COMMAND "$file1" "$file2"

echo -e "\n${SCRIPT_HL_GOOD}Vimdiff session ended.${NC}"
