#!/bin/bash
# Author: Roy Wiseman 2025-05

# ANSI color codes
YELLOW='\e[1;33m'
GREEN='\e[1;32m'
CYAN='\e[1;36m'
RED='\e[1;31m'
RESET='\e[0m'

# SAMBA Shares (testparm -s)
echo -e "\n${CYAN}--- SAMBA Shares (testparm -s) ---${RESET}"

testparm -s 2>&1 | awk '
BEGIN {
    # Initialize variables and arrays
    current_share = ""
    share_count = 0
    # Define headers
    headers[0] = "Name"
    headers[1] = "CreateMask"
    headers[2] = "DirMask"
    headers[3] = "Read-Only"
    headers[4] = "ValidUsers"
    headers[5] = "Path"
    headers[6] = "Comment"

    # Initialize max widths with header lengths
    for (i = 0; i <= 6; i++) {
        max_widths[i] = length(headers[i])
    }
}

{ # Main processing block for every line
    # Check if the line is a share header
    if ($0 ~ /^\[.*\]$/) {
        # If we were processing a previous share (and it is not the global section)
        if (current_share != "" && current_share != "global") {
            # Store the order of the previous share
            share_order[share_count++] = current_share
        }

        # Extract the new share name
        first_bracket = index($0, "[")
        last_bracket = index($0, "]")
        current_share = substr($0, first_bracket + 1, last_bracket - first_bracket - 1)

        # Initialize the entry for the new share in the shares array with default values
        shares[current_share, "createmask"] = "default"
        shares[current_share, "dirmask"] = "default"
        shares[current_share, "path"] = "n.a."
        shares[current_share, "readonly"] = "default"
        shares[current_share, "validusers"] = "n.a."
        shares[current_share, "comment"] = "n.a."

    } else if (current_share != "" && current_share != "global") { # Process lines within a share (excluding global)
        # Trim leading and trailing whitespace (spaces and tabs) for processing
        line = $0
        gsub(/^[ \t]+|[ \t]+$/, "", line)

        # Use pattern matching and extraction for parameters, assigning directly to the shares array
        if (match(line, /^create mask *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value) # Trim spaces from the value
            shares[current_share, "createmask"] = value
        } else if (match(line, /^directory mask *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share, "dirmask"] = value
        } else if (match(line, /^path *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share, "path"] = value
        } else if (match(line, /^read only *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            if (value == "Yes") shares[current_share, "readonly"] = "Yes"
            else if (value == "No") shares[current_share, "readonly"] = "No"
            else shares[current_share, "readonly"] = value
        } else if (match(line, /^valid users *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share, "validusers"] = value
        } else if (match(line, /^comment *=/)) { # Extract comment
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share, "comment"] = value
        }
    }
}

END {
    # Process the last share data (if it exists and is not the global section)
     if (current_share != "" && current_share != "global") {
        share_order[share_count++] = current_share # Store the order of the last share
    }

    # Determine the maximum width for each column based on data and headers
    for (i = 0; i < share_count; i++) {
        share_name = share_order[i]
        if (length(share_name) > max_widths[0]) max_widths[0] = length(share_name)
        if (length(shares[share_name, "createmask"]) > max_widths[1]) max_widths[1] = length(shares[share_name, "createmask"])
        if (length(shares[share_name, "dirmask"]) > max_widths[2]) max_widths[2] = length(shares[share_name, "dirmask"])
        if (length(shares[share_name, "readonly"]) > max_widths[3]) max_widths[3] = length(shares[share_name, "readonly"])
        if (length(shares[share_name, "validusers"]) > max_widths[4]) max_widths[4] = length(shares[share_name, "validusers"])
        if (length(shares[share_name, "path"]) > max_widths[5]) max_widths[5] = length(shares[share_name, "path"])
        if (length(shares[share_name, "comment"]) > max_widths[6]) max_widths[6] = length(shares[share_name, "comment"])
    }

    # Print headers with dynamic width
    printf "%-*s  ", max_widths[0], headers[0]
    printf "%-*s  ", max_widths[1], headers[1]
    printf "%-*s  ", max_widths[2], headers[2]
    printf "%-*s  ", max_widths[3], headers[3]
    printf "%-*s  ", max_widths[4], headers[4]
    printf "%-*s  ", max_widths[5], headers[5]
    printf "%-*s\n", max_widths[6], headers[6]

    # Print the separator line made of '=' characters
    for (i = 0; i <= 6; i++) {
        for (j = 0; j < max_widths[i]; j++) {
            printf "="
        }
        if (i < 6) {
            printf "  "
        }
    }
    printf "\n"

    # Print share data with dynamic width
    for (i = 0; i < share_count; i++) {
        share_name = share_order[i]
        printf "%-*s  ", max_widths[0], share_name
        printf "%-*s  ", max_widths[1], shares[share_name, "createmask"]
        printf "%-*s  ", max_widths[2], shares[share_name, "dirmask"]
        printf "%-*s  ", max_widths[3], shares[share_name, "readonly"]
        printf "%-*s  ", max_widths[4], shares[share_name, "validusers"]
        printf "%-*s  ", max_widths[5], shares[share_name, "path"]
        printf "%-*s\n", max_widths[6], shares[share_name, "comment"]
    }
}'

# NFS Exports (sudo exportfs -v)
echo -e "\n${CYAN}--- NFS Exports (Active - via exportfs -v) ---${RESET}"
echo "This section attempts to display active NFS exports using 'sudo exportfs -v'."
echo "Attempting to run 'sudo exportfs -v'..."

# Initialize variables for capturing command output and exit status
EXPORTFS_OUTPUT=""
SUDO_EXPORTFS_EXIT_CODE=0

# Attempt to run sudo exportfs -v, capturing both stdout and stderr.
# The exit code of the sudo command itself is captured.
EXPORTFS_OUTPUT=$(sudo exportfs -v 2>&1)
SUDO_EXPORTFS_EXIT_CODE=$?

if [[ $SUDO_EXPORTFS_EXIT_CODE -eq 0 ]]; then
    # 'sudo exportfs -v' command executed successfully (exportfs itself exited with 0)
    if [[ -n "$EXPORTFS_OUTPUT" ]]; then
        echo -e "${GREEN}Current NFS Exports:${RESET}"
        echo "$EXPORTFS_OUTPUT"
    else
        # Command was successful but produced no output (e.g., no NFS shares configured)
        echo -e "${YELLOW}No active NFS exports found or 'exportfs -v' produced no output.${RESET}"
        echo "(The command 'sudo exportfs -v' executed successfully but returned no data.)"
    fi
else
    # 'sudo exportfs -v' failed (non-zero exit code)
    echo -e "${RED}Execution of 'sudo exportfs -v' failed (exit code: $SUDO_EXPORTFS_EXIT_CODE).${RESET}"

    # Check if the error message indicates that 'exportfs' command was not found by sudo
    if [[ "$EXPORTFS_OUTPUT" == *"exportfs: command not found"* || "$EXPORTFS_OUTPUT" == *"sudo: exportfs: command not found"* ]]; then
        echo -e "${RED}'exportfs' command not found by sudo or not installed.${RESET}"
        echo "Please ensure NFS server utilities (e.g., 'nfs-kernel-server' on Debian/Ubuntu, or 'nfs-utils' on RHEL/CentOS/Fedora) are installed."
    # Check for common sudo password failure messages (these can be locale-dependent)
    elif [[ "$EXPORTFS_OUTPUT" == *"try again"* || "$EXPORTFS_OUTPUT" == *"incorrect password attempt"* || "$EXPORTFS_OUTPUT" == *"Sorry, user "*is\ not\ allowed\ to\ execute* ]]; then
        echo -e "${RED}Sudo authentication or permission error encountered:${RESET}"
        echo -e "${RED}$EXPORTFS_OUTPUT${RESET}" # Show the specific sudo error
    else
        # Other errors: Could be an error from exportfs itself, or a less common sudo issue.
        echo "Error details from 'sudo exportfs -v':"
        echo -e "${RED}$EXPORTFS_OUTPUT${RESET}"
        echo "This could be an issue with NFS configuration, a runtime error from 'exportfs',"
        echo "or specific sudo permissions for the command for user '$(whoami)'."
    fi
fi
echo ""
