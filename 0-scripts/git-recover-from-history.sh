#!/bin/bash
# Author: Roy Wiseman 2025-04

# Colors
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Git File History Finder & Recovery Helper${NC}"
echo ""

if [ -z "$1" ]; then
  echo -e "Find any file in Git history and recover a version as a new untracked file"
  echo -e "${YELLOW}Usage:${NC} $(basename "$0") \"<filename_pattern>\""
  echo -e "Example patterns:"
  echo -e "  ${GREEN}\"*important_script*.sh\"${NC} (searches basenames containing 'important_script' ending in .sh)"
  echo -e "  ${GREEN}\"**/config/*.xml\"${NC}       (searches for .xml files in any 'config' directory, or xml files in any subdir of config if config is in root)"
  echo -e "  ${GREEN}\"**/my_exact_file.txt\"${NC} (searches for 'my_exact_file.txt' in any directory)"
  echo -e "${YELLOW}Tip:${NC} Use ${GREEN}**/${NC} to ensure your pattern searches recursively through all directories"
  exit 1
fi

PATTERN="$1"
echo -e "${YELLOW}Searching for files matching pattern:${NC} ${GREEN}$PATTERN${NC}"
echo ""

# Temporary file to store log output for easier parsing
LOG_OUTPUT_FILE=$(mktemp)
# Ensure cleanup of temp file on script exit
trap 'rm -f "$LOG_OUTPUT_FILE"' EXIT

git log --all --full-history \
    --pretty="format:COMMIT_MARKER%n%H%n%ad" \
    --date="format:%Y-%m-%d %H:%M:%S %z" \
    --name-status -- "$PATTERN" > "$LOG_OUTPUT_FILE"

if [ ! -s "$LOG_OUTPUT_FILE" ]; then
    echo -e "No history found for files matching that pattern."
    echo -e "${YELLOW}Consider broadening your pattern or using '${GREEN}**/<your_pattern>${NC}' to search in all directories.${NC}"
    exit 0
fi

echo -e "${YELLOW}Found File Versions (Additions, Modifications, Deletions, Renames):${NC}"
echo -e "=========================================================================="

awk -v green="$GREEN" -v nc="$NC" '
BEGIN {
    current_commit_hash="";
    current_commit_date="";
    printed_commit_header=0;
}

/^COMMIT_MARKER$/ {
    getline;
    current_commit_hash=$0;
    getline;
    current_commit_date=$0;
    printed_commit_header=0;
    next;
}

/^[MADRCT]/ {
    if (!printed_commit_header) {
        printf "%sCommit: %s%s\n", green, current_commit_hash, nc;
        printf "Date:   %s\n", current_commit_date;
        printed_commit_header=1;
    }

    status_code = $1;
    path1 = $2;

    current_filepath_to_display = path1;
    extra_info = "";
    status_char = substr(status_code, 1, 1);

    if (status_char == "R" || status_char == "C") {
        if (NF >= 3) {
            current_filepath_to_display = $3;
            if (status_char == "R") {
                extra_info = sprintf(" (Renamed from %s)", path1);
            } else {
                extra_info = sprintf(" (Copied from %s)", path1);
            }
        } else {
            extra_info = " (Path parsing may be affected by spaces/tabs)";
        }
    }

    printf "  File:   %s%s%s%s (Status: %s)\n", green, current_filepath_to_display, nc, extra_info, status_code;

    commit_for_size_lookup = current_commit_hash;
    path_for_size_lookup = current_filepath_to_display;

    if (status_char == "D") {
      path_for_size_lookup = path1;
      commit_for_size_lookup = current_commit_hash "^";
    }

    size_cmd = "git cat-file -s \"" commit_for_size_lookup ":" path_for_size_lookup "\" 2>/dev/null";
    size_val = "N/A";
    line_content = "";

    if ((size_cmd | getline line_content) > 0) {
        size_val = line_content;
    }
    close(size_cmd);

    printf "  Size:   %s bytes\n", size_val;
    print "  ------------------------------------------------------------------------";
}
END {
    print "==========================================================================";
}
' "$LOG_OUTPUT_FILE"


echo ""
echo -e "${YELLOW}Understanding Search Patterns & Filepaths:${NC}"
echo -e "  - ${YELLOW}Recursive Search (Globstar ${GREEN}**/${NC}):${NC} To ensure your pattern searches through all subdirectories,"
echo -e "    prefix it with ${GREEN}**/${NC}. For example, ${GREEN}\"**/my_file.txt\"${NC} will find ${GREEN}my_file.txt${NC} anywhere in the repository."
echo ""
echo -e "  - ${YELLOW}Patterns Without Slashes (Basename Matching):${NC}"
echo -e "    Git generally matches patterns ${YELLOW}without${NC} a slash (${GREEN}/${NC}) in them against the filename itself (the 'basename')."
echo -e "    This means a pattern like ${GREEN}\"*report*.pdf\"${NC} can find a file (e.g., ${GREEN}annual_report.pdf${NC}) in any directory"
echo -e "    because it's matching the filename part. Your working pattern ${GREEN}\"*dw*\"${NC} used this behavior."
echo -e "    If a simple prefix pattern (e.g., ${GREEN}\"prefix*\"${NC}) doesn't behave as expected for subdirectories,"
echo -e "    using ${GREEN}\"**/prefix*\"${NC} is more explicit for forcing a recursive search from the repository root."
echo ""
echo -e "  - ${YELLOW}Filepaths in Output:${NC} All filepaths listed by this script are relative to your repository root."
echo ""
echo -e "  - ${YELLOW}Spaces/Tabs in Filenames:${NC} If actual filenames contain spaces or tabs, their parsing in the list"
echo -e "    (especially for renamed/copied files) might be imperfect. Always ${YELLOW}quote your input pattern${NC} to the script."
echo ""
echo -e "${YELLOW}Note on Commit Hashes:${NC}"
echo -e "  The script displays full commit hashes (e.g., ${GREEN}a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2${NC})."
echo -e "  For most Git commands, including ${GREEN}git checkout${NC}, you can usually use a shorter, unique prefix of the hash."
echo -e "  Typically, the first 7-10 characters (e.g., ${GREEN}a1b2c3d${NC}) are enough. Git will warn you if it's ambiguous."
echo ""
echo -e "${YELLOW}How to Recover a Specific File Version:${NC}"
echo -e "1. From the list above, identify the ${GREEN}Commit Hash${NC} and the exact ${GREEN}Filepath/to/your/file.ext${NC} of the version you want."
echo -e "   The ${GREEN}Filepath/to/your/file.ext${NC} is the path the file had ${YELLOW}in that specific historical commit${NC}."
echo ""
echo -e "2. Determine the correct commit reference:"
echo -e "   - If the file status is 'D' (e.g., D in commit ${GREEN}abc1234${NC}), it means the file was deleted IN that commit."
echo -e "     To get the version ${YELLOW}just before it was deleted${NC}, you need to checkout from its ${YELLOW}parent commit${NC}."
echo -e "     The caret symbol (${GREEN}^${NC}) after a commit hash (e.g., ${GREEN}\"abc1234^\"${NC}) is used to refer to this parent commit."
echo -e "     It represents the state of the repository one step before the changes in ${GREEN}abc1234${NC} were applied."
echo ""
echo -e "   - If the file status is 'M', 'A', 'R', or 'C' (e.g., in commit ${GREEN}def5678${NC}), that commit contains the specified version."
echo -e "     Use that commit hash directly (quoting it is also safe): ${GREEN}\"def5678\"${NC}"
echo -e "     The filepath to use in the checkout command will be the one shown for that commit version (for R/C, this is usually the ${YELLOW}new${NC} path)."
echo ""
echo -e "3. Use the following git command. This will restore the file to that ${GREEN}Filepath/to/your/file.ext${NC} in your"
echo -e "   working directory (relative to the repository root) and also ${YELLOW}stage the change for commit${NC}:"
echo -e "   ${GREEN}git checkout \"<COMMIT_HASH_OR_COMMIT_HASH^>\" -- \"Filepath/to/your/file.ext\"${NC}"
echo ""
echo -e "${YELLOW}After Running Checkout:${NC}"
echo -e "1. The file is now in your working directory at the specified path and ${YELLOW}staged for commit${NC}."
echo -e "2. Confirm this by running: ${GREEN}git status${NC}"
echo -e "   You should see the file listed under 'Changes to be committed:' (e.g., as 'new file' or 'modified')."
echo -e "3. Review the recovered file to ensure it's the version you want."
echo -e "4. To make the recovery permanent in your history, commit the staged change:"
echo -e "   ${GREEN}git commit -m \"Recovered [your file name] from history\"${NC} (customize your commit message)"
echo ""
echo -e "${YELLOW}Examples:${NC}"
echo -e "  Scenario 1: File ${GREEN}src/old_feature.sh${NC} was DELETED in commit ${GREEN}a1b2c3d4e5${NC}."
echo -e "  To restore it as it was just BEFORE deletion:"
echo -e "    ${GREEN}git checkout \"a1b2c3d4e5^\" -- \"src/old_feature.sh\"${NC}"
echo ""
echo -e "  Scenario 2: File ${GREEN}docs/instructions.md${NC} was MODIFIED in commit ${GREEN}f6g7h8i9j0${NC} and you want that version."
echo -e "    ${GREEN}git checkout \"f6g7h8i9j0\" -- \"docs/instructions.md\"${NC}"
echo ""
echo -e "  Scenario 3: File ${GREEN}scripts/old_name.py${NC} was RENAMED to ${GREEN}scripts/new_name.py${NC} in commit ${GREEN}k1l2m3n4o5${NC}."
echo -e "  To get the content as ${GREEN}scripts/new_name.py${NC} from that commit:"
echo -e "    ${GREEN}git checkout \"k1l2m3n4o5\" -- \"scripts/new_name.py\"${NC}"
