#!/bin/bash
# Author: Roy Wiseman 2025-04

# git-vimdiff.sh (formerly gitdiff.sh)
# Compares the current version of a file with a historical version using vimdiff.
# Includes logic to follow file renames in history.
# Usage: git-vimdiff.sh <filename> <HEAD-ref_number>
# Example: git-vimdiff.sh myscript.sh 3  (Compares myscript.sh with HEAD~3 version)

# --- ANSI Color Codes ---
GREEN='\033[0;32m'                   # For general script output & "good" things in help
YELLOW='\033[0;33m'                  # For "attention" items like keys in help
SCRIPT_HL_SECTION_TITLE='\033[1;33m' # Bright Yellow text for section titles in help
SCRIPT_HL_DETAIL='\033[0;36m'        # Cyan text for details/paths in help
BG_RED='\033[41m'                    # Red Background (for script errors or specific highlights)
# BG_GREEN='\033[42m' # Green Background - Not actively used in new help
# BG_CYAN='\033[46m'  # Cyan Background - Not actively used in new help
NC='\033[0m'                         # No Color

# --- Vim/Vimdiff Installation Check ---
check_vimdiff_installed() {
    if ! command -v vimdiff &> /dev/null; then
        if command -v vim &> /dev/null; then
            echo -e "${YELLOW}Warning: 'vimdiff' command not found directly. Will try 'vim -d'.${NC}"
            echo -e "${YELLOW}If this fails, ensure vim is installed and 'vimdiff' is in your PATH${NC}"
            echo -e "${YELLOW}(often a symlink to 'vim -d').${NC}"
            VIM_COMMAND="vim -d"
        else
            echo -e "${BG_RED}Error: 'vim' (and thus 'vimdiff') does not seem to be installed.${NC}"
            echo "Please install vim. For example:"
            echo "  Debian/Ubuntu: sudo apt update && sudo apt install vim"
            echo "  Fedora/RHEL:   sudo dnf install vim-enhanced"
            echo "  macOS (Homebrew): brew install vim"
            exit 1
        fi
    else
        VIM_COMMAND="vimdiff" # Default to vimdiff if found
    fi
}

# --- Input Validation ---
if [ "$#" -ne 2 ]; then
    echo
    echo "Compare a current file with a previous version from its git history. In git syntax,"
    echo "HEAD~1 is the last committed version of the script (not just the last commit in general"
    echo "but the last time that this file was committed). HEAD~3 is 3rd commit ago, etc."
    echo
    echo -e "Usage: ${GREEN}${0##*/} <filename> <HEAD-ref_number>${NC}"
    echo
    echo -e "Example: ${GREEN}${0##*/} myscript.sh 3${NC}  # Compare the latest with the 3rd most recent commit"
    echo
    echo "The following is used to get a list of all commit hashes in the history that"
    echo "affected the given \$filename, following renames with a 40% similarity threshold:"
    echo -e "${GREEN}git log --follow --find-renames=40% --pretty=format:\"%H\" -- \"\$filename\"${NC}"
    echo "By taking the Nth commit hash from this list (where N is your head_ref_num), we get the"
    echo "precise commit hash where the file was in its HEAD~N state relative to its own history."
    echo
    exit 1
fi

# --- Check Vimdiff Installation Early ---
check_vimdiff_installed # Sets $VIM_COMMAND

filename="$1"
head_ref_num="$2"
git_ref="HEAD~$head_ref_num"

# --- Git Repository Check ---
git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${BG_RED}Error: Not in a Git repository.${NC}"
    exit 1
fi

# --- File Information (Current) ---
git_file_path_current=$(git ls-files --full-name --error-unmatch "$filename" 2>/dev/null)
if [ $? -ne 0 ]; then
    echo -e "${BG_RED}Error: File '$filename' is not tracked by Git or does not exist at current path.${NC}"
    exit 1
fi
if [ ! -f "$filename" ]; then
    echo -e "${BG_RED}Error: File '$filename' does not exist in the working directory.${NC}"
    echo "       (It might be tracked by Git but deleted or moved locally)."
    exit 1
fi


if git diff --quiet "$filename"; then
    file_status="unmodified"
else
    file_status="modified"
fi
file_size_current=$(du -h "$filename" | awk '{print $1}')

# --- File Information (Historical) ---
historical_commit_hashes=($(git log --follow --find-renames=40% --pretty=format:"%H" -- "$filename" 2>/dev/null))

if [ "${#historical_commit_hashes[@]}" -le "$head_ref_num" ]; then
    echo -e "${BG_RED}Error: The file '$filename' does not have $head_ref_num ancestor commits in its history.${NC}"
    echo "It might not have existed or been tracked that far back."
    exit 1
fi

historical_commit_hash="${historical_commit_hashes[$head_ref_num]}"
git_file_path_historical=$(git show --name-only --pretty="" "$historical_commit_hash" -- "$filename" 2>/dev/null | head -n 1)

if [ -z "$git_file_path_historical" ]; then
    echo -e "${BG_RED}Error: Could not determine the historical path for '$filename' at $git_ref.${NC}"
    echo "       This can happen if the file was introduced and then renamed/moved in complex ways"
    echo "       not fully traced by 'git log --follow' for the specified commit."
    exit 1
fi

historical_file_info=$(git ls-tree -l "$historical_commit_hash" -- "$git_file_path_historical" 2>/dev/null)
if [ -n "$historical_file_info" ]; then
    file_size_historical_bytes=$(echo "$historical_file_info" | awk '{print $4}')
    if [[ "$file_size_historical_bytes" =~ ^[0-9]+$ ]]; then
        if command -v numfmt >/dev/null 2>&1; then
            file_size_historical=$(numfmt --to=iec-i --format="%8.1f" "$file_size_historical_bytes" | xargs)
        else
            file_size_historical="${file_size_historical_bytes} bytes"
        fi
    else
        file_size_historical="N/A (invalid size data)"
    fi
else
    file_size_historical="N/A (could not retrieve size)"
fi

commit_date=$(git show -s --format=%cd "$historical_commit_hash" 2>/dev/null)
if [ -z "$commit_date" ]; then
    commit_date=$(git log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M:%S' "$historical_commit_hash" -- "$git_file_path_historical" 2>/dev/null)
    if [ -z "$commit_date" ]; then
        commit_date="N/A (could not retrieve date)"
    fi
fi

# --- Display Information ---
echo -e "${SCRIPT_HL_SECTION_TITLE}--- Comparing Files ---${NC}"
echo -e "${SCRIPT_HL_DETAIL}Current Version:${NC}"
echo -e "  Path:   $filename (Status: $file_status)"
echo -e "  Size:   $file_size_current"
echo -e "${SCRIPT_HL_DETAIL}Historical Version ($git_ref):${NC}"
echo -e "  Path:   $git_file_path_historical (Commit: ${historical_commit_hash:0:12})" # Show short hash
echo -e "  Size:   $file_size_historical"
echo -e "  Date:   $commit_date"
echo "--------------------------------------------------"

# --- Prepare Diff Command ---
# $VIM_COMMAND is set by check_vimdiff_installed
vimdiff_command="$VIM_COMMAND \"$filename\" <(git show $historical_commit_hash:\"$git_file_path_historical\")"

echo "Running command:"
echo -e "${GREEN}$vimdiff_command${NC}"
echo "--------------------------------------------------"

# --- Vimdiff Navigation Tips and Color Explanation (New Expanded Version) ---
echo -e "${GREEN}Vimdiff Navigation & Action Tips:${NC}" # Using GREEN for main title
echo -e "  ${YELLOW}Ctrl+w Ctrl+w${NC} (or ${YELLOW}Ctrl+w w${NC}): Switch focus between panes."
echo -e "  ${YELLOW}Ctrl+w h/j/k/l${NC}: Focus pane left/down/up/right."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}Navigating Differences (Hunks):${NC}"
echo -e "  A 'hunk' is a block of differing lines, often with some surrounding"
echo -e "  identical lines for context."
echo -e "  By default, vimdiff shows ${YELLOW}6 lines of context${NC} around changes."
echo -e "    (Controllable via Vim's ':set diffopt=...' command, e.g., ':set diffopt+=context:3')."
echo -e "  ${YELLOW}]c${NC}: Jump to the start of the ${GREEN}next${NC} difference hunk."
echo -e "  ${YELLOW}[c${NC}: Jump to the start of the ${GREEN}previous${NC} difference hunk."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}Applying Entire Hunks (Propagating Changes):${NC}"
echo -e "  ${YELLOW}dp${NC} ('diff put') and ${YELLOW}do${NC} ('diff obtain') operate on the ${GREEN}entire current hunk${NC}."
echo -e "  To use:"
echo -e "    1. Move your cursor into the highlighted hunk you want to affect."
echo -e "    2. In the ${GREEN}source${NC} pane (pane with changes you want to send):"
echo -e "       ${YELLOW}dp${NC} => ${GREEN}Puts (sends)${NC} the hunk from active pane"
echo -e "                 ${GREEN}to${NC} the other pane."
echo -e "    3. In the ${GREEN}destination${NC} pane (pane where you want to receive changes):"
echo -e "       ${YELLOW}do${NC} => ${GREEN}Gets (obtains)${NC} the hunk from other pane"
echo -e "                 ${GREEN}into${NC} the active pane."
echo -e "  ${YELLOW}Note:${NC} You ${GREEN}cannot${NC} use 'dp'/'do' for a single line within a multi-line hunk."
echo -e "  For ${SCRIPT_HL_DETAIL}line-specific changes within a hunk (or any arbitrary copy/paste):${NC}"
echo -e "    1. Use standard Vim commands: e.g., ${YELLOW}yy${NC} (yank line),"
echo -e "       ${YELLOW}V${NC} (visual line mode) then ${YELLOW}y${NC} (yank selection)."
echo -e "    2. Switch panes (${YELLOW}Ctrl+w Ctrl+w${NC})."
echo -e "    3. Move to desired location and ${YELLOW}p${NC} (paste)."
echo -e "    4. Run ${YELLOW}:diffupdate${NC} to re-calculate differences if needed."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}Folding (Hiding/Showing Identical Text):${NC}"
echo -e "  ${YELLOW}zo${NC}: Open fold. ${YELLOW}zc${NC}: Close fold."
echo -e "  ${YELLOW}zr${NC}: Reduce folding. ${YELLOW}zm${NC}: More folding."
echo -e "  ${YELLOW}zR${NC}: Open ALL folds. ${YELLOW}zM${NC}: Close ALL folds."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}General Vim:${NC}"
echo -e "  ${YELLOW}:q${NC} (in one pane): Closes pane. ${YELLOW}:qa${NC} or ${YELLOW}:qall${NC}: Quit all."
echo -e "  ${YELLOW}:wqa${NC} or ${YELLOW}:wqall${NC}: Write all & quit. ${YELLOW}:qa!${NC}: Quit all w/o saving."
echo -e "  ${YELLOW}:diffupdate${NC}: Refresh diff (if auto-refresh seems off after edits)."
echo ""
echo -e "${GREEN}Vimdiff Color Explanation (Typical Defaults - can vary with your colorscheme):${NC}"
echo -e "  ${YELLOW}- Default Background (e.g., white/grey/terminal's default):${NC}"
echo -e "    Lines that are identical in both files and not part of a diff"
echo -e "    hunk's immediate context."
echo -e "  ${YELLOW}- Removed Lines (Highlight Group: DiffDelete):${NC}"
echo -e "    Often a ${SCRIPT_HL_DETAIL}Red/Reddish background${NC}. These lines exist in one file but"
echo -e "    not the other (seen as 'removed' from the perspective of the file"
echo -e "    that lacks them)."
echo -e "  ${YELLOW}- Added Lines (Highlight Group: DiffAdd):${NC}"
echo -e "    Often ${SCRIPT_HL_DETAIL}Green/Greenish text or background${NC}. These lines exist in one file"
echo -e "    but not the other (seen as 'added' to the file that has them)."
echo -e "  ${YELLOW}- Changed Lines (Highlight Group: DiffChange):${NC}"
echo -e "    Often a ${SCRIPT_HL_DETAIL}Blue/Cyan/Light Blue background${NC}. Lines are present in both"
echo -e "    versions but content has been modified."
echo -e "    Within these lines, the ${SCRIPT_HL_DETAIL}specific differing text${NC} itself might have"
echo -e "    another highlight (Highlight Group: DiffText, often standout like bold"
echo -e "    or a different shade)."
echo -e "  ${YELLOW}- Filler Lines (Highlight Group: Folded,${NC}"
echo -e "    ${YELLOW}or sometimes part of DiffChange/Delete appearance):${NC}"
echo -e "    Often ${SCRIPT_HL_DETAIL}Grey/Pinkish/Purple-ish background${NC}."
echo -e "    These lines are sometimes inserted by vimdiff when there are many changes,"
echo -e "    to help visually align corresponding blocks that are far apart,"
echo -e "    or indicate folded identical lines."
echo ""
echo -e "  ${SCRIPT_HL_DETAIL}Suspending Vimdiff to See This Again:${NC}"
echo -e "  If you want to re-read these instructions while vimdiff is running:"
echo -e "    1. In vimdiff, press ${YELLOW}Ctrl+Z${NC}. This suspends vimdiff and returns you to your shell."
echo -e "    2. You can now scroll up in your terminal to see this help text."
echo -e "    3. To return to your vimdiff session exactly where you left off,"
echo -e "       type ${YELLOW}fg${NC} (foreground) in your shell and press Enter."
echo ""
echo -e "${SCRIPT_HL_SECTION_TITLE}Git-Specific Advanced Tip:${NC}" # Using Bright Yellow for this section
echo -e "  Compare with a different historical version ${YELLOW}*without*${NC} leaving Vim:"
echo -e "  1. Focus the historical version's pane (usually the ${SCRIPT_HL_DETAIL}left one${NC}, showing content from \`git show\`)."
echo -e "  2. Type the command: ${YELLOW}\`:e <new_git_ref>:%#\`" # %# refers to current file in alternate buffer
echo -e "     Example for HEAD~4: ${YELLOW}\`:e HEAD~4:%#\`"
echo -e "     Or, if the filename might have changed significantly across history and \`%#\` isn't working as expected:"
echo -e "     ${YELLOW}\`:e <new_git_ref>:$git_file_path_current\`"
echo -e "     (Using the current file path often works as Git intelligently resolves it for \`show\`.)"
echo -e "  3. In ${YELLOW}*both*${NC} windows, run ${YELLOW}\`:diffupdate\`${NC} to refresh the diff comparison."
echo "--------------------------------------------------"

# --- Run Diff ---
read -p "Press Enter to view the diff..."

# Execute the constructed vimdiff command
# 'eval' is used here to correctly interpret the process substitution <(...)
eval "$vimdiff_command"

echo "--------------------------------------------------"
echo "Vimdiff session ended."
