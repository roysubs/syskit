#!/bin/bash
# Author: Roy Wiseman 2025-03

# vimdiff-helper.sh
# A wrapper for vimdiff to display helpful information and keybindings
# before launching the comparison.
# Usage: vimdiff-helper.sh <file1> <file2>

# --- ANSI Color Codes for this script's output ---
SCRIPT_HL_GOOD='\033[0;32m'          # Green text for good/command examples
SCRIPT_HL_ATTENTION='\033[0;33m'     # Yellow text for attention/keys
SCRIPT_HL_SECTION_TITLE='\033[1;33m' # Bright Yellow text for section titles
SCRIPT_HL_DETAIL='\033[0;36m'        # Cyan text for details/paths
SCRIPT_HL_ERROR_BG='\033[41m'        # Red background for errors
NC='\033[0m' # No Color

# --- Vim/Vimdiff Installation Check ---
check_vimdiff_installed() {
    if ! command -v vimdiff &> /dev/null; then
        if command -v vim &> /dev/null; then
            echo -e "${SCRIPT_HL_ATTENTION}Warning: 'vimdiff' command not found directly. Will try 'vim -d'.${NC}"
            echo -e "${SCRIPT_HL_ATTENTION}If this fails, ensure vim is installed and 'vimdiff' is in your PATH${NC}"
            echo -e "${SCRIPT_HL_ATTENTION}(often a symlink to 'vim -d').${NC}"
            VIM_COMMAND="vim -d"
        else
            echo -e "${SCRIPT_HL_ERROR_BG}Error: 'vim' (and thus 'vimdiff') does not seem to be installed.${NC}"
            echo "Please install vim. For example:"
            echo "  Debian/Ubuntu: sudo apt update && sudo apt install vim"
            echo "  Fedora/RHEL:   sudo dnf install vim-enhanced"
            echo "  macOS (Homebrew): brew install vim"
            exit 1
        fi
    else
        VIM_COMMAND="vimdiff"
    fi
}

# --- Input Validation ---
if [ "$#" -ne 2 ]; then
    echo
    echo "Compares two files using vimdiff, showing useful info and keybindings beforehand."
    echo
    echo -e "Usage: ${SCRIPT_HL_GOOD}${0##*/} <file1> <file2>${NC}"
    echo
    echo -e "Example: ${SCRIPT_HL_GOOD}${0##*/} document_v1.txt document_v2.txt${NC}"
    echo
    exit 1
fi

file1="$1"
file2="$2"

if [ ! -f "$file1" ]; then
    echo -e "${SCRIPT_HL_ERROR_BG}Error: File '$file1' not found or is not a regular file.${NC}"
    exit 1
fi

if [ ! -f "$file2" ]; then
    echo -e "${SCRIPT_HL_ERROR_BG}Error: File '$file2' not found or is not a regular file.${NC}"
    exit 1
fi

check_vimdiff_installed

# --- Gather File Information ---
get_file_info() {
    local file_path="$1"
    local full_path
    local size
    local lines
    local modified_date

    full_path=$(realpath "$file_path" 2>/dev/null || readlink -f "$file_path")
    size=$(du -h "$file_path" | awk '{print $1}')
    lines=$(wc -l < "$file_path" | awk '{print $1}')
    if date -r "$file_path" +"%Y-%m-%d %H:%M:%S %Z" >/dev/null 2>&1; then
        modified_date=$(date -r "$file_path" +"%Y-%m-%d %H:%M:%S %Z")
    elif stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S %Z" "$file_path" >/dev/null 2>&1; then
        modified_date=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S %Z" "$file_path")
    else
        modified_date=$(ls -ld "$file_path" | awk '{print $6, $7, $8}')
    fi

    echo -e "  ${SCRIPT_HL_DETAIL}Full Path:${NC}    $full_path"
    echo -e "  ${SCRIPT_HL_DETAIL}Size:${NC}         $size"
    echo -e "  ${SCRIPT_HL_DETAIL}Lines:${NC}        $lines"
    echo -e "  ${SCRIPT_HL_DETAIL}Last Modified:${NC} $modified_date"
}

echo -e "${SCRIPT_HL_SECTION_TITLE}--- File 1 Information ---${NC}"
get_file_info "$file1"
echo
echo -e "${SCRIPT_HL_SECTION_TITLE}--- File 2 Information ---${NC}"
get_file_info "$file2"
echo "--------------------------------------------------"

echo -e "${SCRIPT_HL_GOOD}Vimdiff Navigation & Action Tips:${NC}"
echo -e "  ${SCRIPT_HL_ATTENTION}Ctrl+w Ctrl+w${NC} (or ${SCRIPT_HL_ATTENTION}Ctrl+w w${NC}): Switch focus between panes."
echo -e "  ${SCRIPT_HL_ATTENTION}Ctrl+w h/j/k/l${NC}: Focus pane left/down/up/right."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}Navigating Differences (Hunks):${NC}"
echo -e "  A 'hunk' is a block of differing lines, often with some surrounding"
echo -e "  identical lines for context."
echo -e "  By default, vimdiff shows ${SCRIPT_HL_ATTENTION}6 lines of context${NC} around changes."
echo -e "    (Controllable via Vim's ':set diffopt=...' command, e.g., ':set diffopt+=context:3')."
echo -e "  ${SCRIPT_HL_ATTENTION}]c${NC}: Jump to the start of the ${SCRIPT_HL_GOOD}next${NC} difference hunk."
echo -e "  ${SCRIPT_HL_ATTENTION}[c${NC}: Jump to the start of the ${SCRIPT_HL_GOOD}previous${NC} difference hunk."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}Applying Entire Hunks (Propagating Changes):${NC}"
echo -e "  ${SCRIPT_HL_ATTENTION}dp${NC} ('diff put') and ${SCRIPT_HL_ATTENTION}do${NC} ('diff obtain') operate on the ${SCRIPT_HL_GOOD}entire current hunk${NC}."
echo -e "  To use:"
echo -e "    1. Move your cursor into the highlighted hunk you want to affect."
echo -e "    2. In the ${SCRIPT_HL_GOOD}source${NC} pane (pane with changes you want to send):"
echo -e "       ${SCRIPT_HL_ATTENTION}dp${NC} => ${SCRIPT_HL_GOOD}Puts (sends)${NC} the hunk from active pane"
echo -e "                 ${SCRIPT_HL_GOOD}to${NC} the other pane."
echo -e "    3. In the ${SCRIPT_HL_GOOD}destination${NC} pane (pane where you want to receive changes):"
echo -e "       ${SCRIPT_HL_ATTENTION}do${NC} => ${SCRIPT_HL_GOOD}Gets (obtains)${NC} the hunk from other pane"
echo -e "                 ${SCRIPT_HL_GOOD}into${NC} the active pane."
echo -e "  ${SCRIPT_HL_ATTENTION}Note:${NC} You ${SCRIPT_HL_GOOD}cannot${NC} use 'dp'/'do' for a single line within a multi-line hunk."
echo -e "  For ${SCRIPT_HL_DETAIL}line-specific changes within a hunk (or any arbitrary copy/paste):${NC}"
echo -e "    1. Use standard Vim commands: e.g., ${SCRIPT_HL_ATTENTION}yy${NC} (yank line),"
echo -e "       ${SCRIPT_HL_ATTENTION}V${NC} (visual line mode) then ${SCRIPT_HL_ATTENTION}y${NC} (yank selection)."
echo -e "    2. Switch panes (${SCRIPT_HL_ATTENTION}Ctrl+w Ctrl+w${NC})."
echo -e "    3. Move to desired location and ${SCRIPT_HL_ATTENTION}p${NC} (paste)."
echo -e "    4. Run ${SCRIPT_HL_ATTENTION}:diffupdate${NC} to re-calculate differences if needed."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}Folding (Hiding/Showing Identical Text):${NC}"
echo -e "  ${SCRIPT_HL_ATTENTION}zo${NC}: Open fold. ${SCRIPT_HL_ATTENTION}zc${NC}: Close fold."
echo -e "  ${SCRIPT_HL_ATTENTION}zr${NC}: Reduce folding. ${SCRIPT_HL_ATTENTION}zm${NC}: More folding."
echo -e "  ${SCRIPT_HL_ATTENTION}zR${NC}: Open ALL folds. ${SCRIPT_HL_ATTENTION}zM${NC}: Close ALL folds."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}General Vim:${NC}"
echo -e "  ${SCRIPT_HL_ATTENTION}:q${NC} (in one pane): Closes pane. ${SCRIPT_HL_ATTENTION}:qa${NC} or ${SCRIPT_HL_ATTENTION}:qall${NC}: Quit all."
echo -e "  ${SCRIPT_HL_ATTENTION}:wqa${NC} or ${SCRIPT_HL_ATTENTION}:wqall${NC}: Write all & quit. ${SCRIPT_HL_ATTENTION}:qa!${NC}: Quit all w/o saving."
echo -e "  ${SCRIPT_HL_ATTENTION}:diffupdate${NC}: Refresh diff (if auto-refresh seems off after edits)."
echo ""
echo -e "${SCRIPT_HL_GOOD}Vimdiff Color Explanation (Typical Defaults - can vary with your colorscheme):${NC}"
echo -e "  ${SCRIPT_HL_ATTENTION}- Default Background (e.g., white/grey/terminal's default):${NC}"
echo -e "    Lines that are identical in both files and not part of a diff"
echo -e "    hunk's immediate context."
echo -e "  ${SCRIPT_HL_ATTENTION}- Removed Lines (Highlight Group: DiffDelete):${NC}"
echo -e "    Often a ${SCRIPT_HL_DETAIL}Red/Reddish background${NC}. These lines exist in one file but"
echo -e "    not the other (seen as 'removed' from the perspective of the file"
echo -e "    that lacks them)."
echo -e "  ${SCRIPT_HL_ATTENTION}- Added Lines (Highlight Group: DiffAdd):${NC}"
echo -e "    Often ${SCRIPT_HL_DETAIL}Green/Greenish text or background${NC}. These lines exist in one file"
echo -e "    but not the other (seen as 'added' to the file that has them)."
echo -e "  ${SCRIPT_HL_ATTENTION}- Changed Lines (Highlight Group: DiffChange):${NC}"
echo -e "    Often a ${SCRIPT_HL_DETAIL}Blue/Cyan/Light Blue background${NC}. Lines are present in both"
echo -e "    versions but content has been modified."
echo -e "    Within these lines, the ${SCRIPT_HL_DETAIL}specific differing text${NC} itself might have"
echo -e "    another highlight (Highlight Group: DiffText, often standout like bold"
echo -e "    or a different shade)."
echo -e "  ${SCRIPT_HL_ATTENTION}- Filler Lines (Highlight Group: Folded,${NC}"
echo -e "    ${SCRIPT_HL_ATTENTION}or sometimes part of DiffChange/Delete appearance):${NC}"
echo -e "    Often ${SCRIPT_HL_DETAIL}Grey/Pinkish/Purple-ish background${NC} (like the 'pink' you observed)."
echo -e "    These lines are sometimes inserted by vimdiff when there are many changes,"
echo -e "    to help visually align corresponding blocks that are far apart,"
echo -e "    or indicate folded identical lines."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}Suspending Vimdiff to See This Again:${NC}"
echo -e "  If you want to re-read these instructions while vimdiff is running:"
echo -e "    1. In vimdiff, press ${SCRIPT_HL_ATTENTION}Ctrl+Z${NC}. This suspends vimdiff and returns you to your shell."
echo -e "    2. You can now scroll up in your terminal to see this help text."
echo -e "    3. To return to your vimdiff session exactly where you left off,"
echo -e "       type ${SCRIPT_HL_ATTENTION}fg${NC} (foreground) in your shell and press Enter."
echo "--------------------------------------------------"

vimdiff_command="$VIM_COMMAND \"$file1\" \"$file2\""

echo "Running command:"
echo -e "${SCRIPT_HL_GOOD}$vimdiff_command${NC}"
echo "--------------------------------------------------"

read -p "Press Enter to start vimdiff..."

$VIM_COMMAND "$file1" "$file2"

echo "--------------------------------------------------"
echo "Vimdiff session ended."
