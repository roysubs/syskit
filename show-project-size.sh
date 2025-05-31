#!/bin/bash
# Author: Roy Wiseman 2025-01
#
#du -ah --exclude=.git . | sort -rh | head -n 20

# Exit immediately if a command exits with a non-zero status.
# set -e # Optional: uncomment if you want the script to exit on any error

# Ensure that a pipeline command returns a failure status if any command in the pipeline fails.
set -o pipefail

# --- Color Definitions ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m' # Bold Yellow for headers
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Function to print a command in green, execute it, and print its output in cyan ---
run_command() {
    local full_cmd_string="$1"
    # Display the command to be executed in green
    echo -e "# ${GREEN}${full_cmd_string}${NC}"

    local output
    local status

    # Execute the command string.
    # Using 'bash -o pipefail -c' ensures that if any command in the pipe fails,
    # the overall status reflects that failure.
    # stdout is captured; stderr from 'full_cmd_string' will go to this script's stderr.
    output=$(bash -o pipefail -c "$full_cmd_string")
    status=$?

    if [ $status -eq 0 ]; then
        if [ -n "$output" ]; then
            # Display the captured output (the size) in cyan
            echo -e "${CYAN}${output}${NC}"
        else
            # Handle cases where the command succeeded but produced no output
            echo -e "${CYAN}(No output)${NC}"
        fi
    else
        # Announce that the command failed
        echo # Add a newline for readability before error message
        echo -e "Error: Command failed with exit status $status."
        # If the command produced any output to its stdout before failing, display it.
        # Error messages on stderr would have already been printed to the terminal.
        if [ -n "$output" ]; then
            echo "Command's captured stdout (if any):"
            echo "$output"
        fi
    fi
    # Add a blank line for spacing after the command's output block
    echo
    return $status
}

# --- Main Script ---
echo "Show the space used by this project."
echo

# --- Section 1: Apparent Size ---
echo -e "${YELLOW}1. By Apparent Size (Sum of individual file sizes)${NC}"
echo "    Not the used space on disk but counting each file by its byte size."
echo

# Command to calculate sum of individual file sizes in bytes
# Corrected 'du -bch' to 'du -bc' to ensure awk gets raw byte counts.
CMD1="find . -type d -name \".git\" -prune -o -type f -print0 | xargs -0 du -bc | awk 'END{print \$1}'"
run_command "$CMD1"

echo "# Explanation:"
echo "# find .: Starts the search in the current directory (.)."
echo "# -type d -name \".git\" -prune: Finds directories named \".git\" and prevents find from descending into them."
echo "# -o: Logical OR operator."
echo "# -type f -print0: If the entry is not a pruned \".git\" directory, and it's a regular file (-type f),"
echo "#   its name is printed, followed by a null character (-print0) for safe handling of special filenames."
echo "# | xargs -0 du -bc:"
echo "#   xargs -0: Reads the null-terminated file names from find."
echo "#   du -bc: For each file, 'du' (disk usage) is called."
echo "#     -b: Shows apparent size in bytes (sum of file bytes, not disk blocks)."
echo "#     -c: Produces a grand total."
echo "# | awk 'END{print \$1}': Processes the output of 'du -bc'."
echo "#   END{print \$1}: After processing all lines, awk prints the first field of the last line,"
echo "#   which is the grand total in bytes from 'du -c'."
echo

# --- Section 2: Space Used on Disk (Bytes) ---
echo -e "${YELLOW}2. By Space Used on Disk (Actual disk allocation in bytes)${NC}"
echo "    The actual disk space occupied, which can be larger than apparent size due to filesystem block allocation."
echo

# Command to calculate actual disk space used in bytes
CMD2="find . -type d -name \".git\" -prune -o -print0 | xargs -0 du -scb | awk 'END{print \$1}'"
run_command "$CMD2"

echo "# Explanation:"
echo "# find . -type d -name \".git\" -prune -o -print0: Similar to the first command, but -print0 prints all"
echo "#   non-.git items (files and directories). This is because 'du' calculates total disk usage for directories."
echo "# | xargs -0 du -scb:"
echo "#   xargs -0: Reads null-terminated names."
echo "#   du -scb:"
echo "#     -s: Display only a total for each argument."
echo "#     -c: Produce a grand total."
echo "#     -b: Report size in bytes."
echo "# | awk 'END{print \$1}': Prints the grand total figure (in bytes) from 'du -scb' output."
echo

# --- Section 3: Space Used on Disk (Human-Readable) ---
echo -e "${YELLOW}Or, for a more human-readable total at the end (e.g., KB, MB, GB):${NC}"
echo

# Command to calculate actual disk space used, in human-readable format
CMD3="find . -type d -name \".git\" -prune -o -print0 | xargs -0 du -sch | tail -n1 | awk '{print \$1}'"
run_command "$CMD3"

echo "# Explanation:"
echo "# find ... -print0: Same as in section 2."
echo "# | xargs -0 du -sch:"
echo "#   du -sch:"
echo "#     -s: Display a total for each argument."
echo "#     -c: Produce a grand total."
echo "#     -h: Print sizes in human-readable format (e.g., 1K, 234M, 2G)."
echo "# | tail -n1: Gets the last line from 'du -sch' output, which is the grand total line (e.g., \"1.2G total\")."
echo "# | awk '{print \$1}': Prints just the size value (e.g., \"1.2G\") from that total line."
echo

