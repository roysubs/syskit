#!/bin/bash
# Author: Roy Wiseman 2025-02

# --- Configuration ---

# ANSI Color Codes
COLOR_HEADER="\033[1;32m"  # Green bold for all headers (Local, SAMBA, NFS)
COLOR_FIELD="\033[1;34m"   # Blue bold for fields (Target and Source) as requested
COLOR_RESET="\033[0m"      # Reset color to default

# Regex to exclude common system/virtual mounts based on findmnt --df -n output format.
# It matches lines where:
# 1. The TARGET (7th field) is exactly /
# 2. The TARGET (7th field) starts with common system paths like /sys/, /proc/, etc.
# 3. The FSTYPE (2nd field) is one of the common virtual/pseudo types.
# This regex seems correct based on the previous debugging output.
EXCLUDE_REGEX='^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +/$|^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +/(sys|proc|dev|run|snap|var/lib/docker)/|^(sysfs|proc|devtmpfs|devpts|tmpfs|securityfs|cgroup|pstore|bpf|autofs|mqueue|hugetlbfs|debugfs|tracefs|configfs|ramfs|fusectl|nsfs|portal|overlay|squashfs|binfmt_misc|rpc_pipefs|fuse.*|nfsd) '


# --- Processing ---

# Get mount output with disk space info using findmnt --df -n
# -n omits the header
# --df includes disk space usage columns
# Pipe the output to grep for initial filtering using the defined regex
# Ensure grep doesn't interpret escape sequences in EXCLUDE_REGEX; quoting is important.
filtered_mounts=$(findmnt --df -n | grep -vE "$EXCLUDE_REGEX")


# Initialize arrays to store categorized mounts.
local_mount_lines=()
samba_mount_lines=() # For CIFS mounts
nfs_mount_lines=()   # For NFS mounts

# Read the filtered mounts line by line
# IFS= prevents leading/trailing whitespace from being trimmed
# -r prevents backslash escapes from being interpreted
# The '<<< "$filtered_mounts"' syntax feeds the multi-line string into the while loop
while IFS= read -r line; do
    # Extract the filesystem type (2nd field) and source (1st field) from the current line
    # In findmnt --df -n output: $1=SOURCE, $2=FSTYPE, ..., $7=TARGET
    # Use awk for reliable field extraction
    # Need to be careful with awk when fields might contain spaces,
    # but findmnt --df -n usually quotes or escapes sources/targets with spaces.
    read -r current_source current_fstype <<< $(echo "$line" | awk '{print $1, $2}')

    # --- Categorization Logic ---

    # 1. Remote SAMBA (cifs) mounts - identified by filesystem type (2nd field)
    if [[ "$current_fstype" == "cifs" ]]; then
        samba_mount_lines+=("$line") # Append the full line to the array
        continue # Go to the next line
    fi

    # 2. NFS mounts - identified by filesystem type (2nd field)
    if [[ "$current_fstype" == "nfs" ]] || [[ "$current_fstype" == "nfs4" ]]; then
        nfs_mount_lines+=("$line") # Append the full line to the array
        continue # Go to the next line
    fi

    # 3. Local Disk Mounts - identified by source (1st field) starting with /dev/sd
    #    (We implicitly exclude NFS and CIFS here as they are checked first)
    # Check if source (1st field) starts with /dev/sd
    if [[ "$current_source" =~ ^\/dev\/sd ]]; then
        local_mount_lines+=("$line") # Append the full line to the array
        continue # Go to the next line
    fi

    # Lines that are not categorized above are ignored

done <<< "$filtered_mounts"

# --- Output ---

# Print header row for the columns
# Based on findmnt --df -n columns: SOURCE, FSTYPE, SIZE, USED, AVAIL, USE%, TARGET, OPTIONS
# Adjusted order to match coloring request (Target, Source, ...) and increased width
print_header_row() {
    printf "%-35s %-35s %-10s %-8s %-8s %-8s %-5s %s\n" \
        "TARGET" "SOURCE" "FSTYPE" "SIZE" "USED" "AVAIL" "USE%" "OPTIONS"
    printf -- "-%.0s" {1..120} # Print a line of hyphens (increased length)
    printf "\n"
}


# Function to print a colored mount line with Target (7th field) and Source (1st field) highlighted
# Takes one line of findmnt --df -n output as input
print_colored_line() {
    local line="$1"
    # Use awk to split the line and apply colors to specific fields (7th=TARGET, 1st=SOURCE)
    # Pass color variables to awk using -v
    # Adjusted printf formatting to match increased header widths
    echo "$line" | awk -v field_color="$COLOR_FIELD" -v reset_color="$COLOR_RESET" '
    {
        # Print field 7 (TARGET) in color, formatted to 35 chars wide
        printf "%s%-35s%s ", field_color, $7, reset_color
        # Print field 1 (SOURCE) in color, formatted to 35 chars wide
        printf "%s%-35s%s ", field_color, $1, reset_color
        # Print field 2 (FSTYPE), formatted to 10 chars wide
        printf "%-10s ", $2
        # Print field 3 (SIZE), formatted to 8 chars wide
        printf "%-8s ", $3
        # Print field 4 (USED), formatted to 8 chars wide
        printf "%-8s ", $4
        # Print field 5 (AVAIL), formatted to 8 chars wide
        printf "%-8s ", $5
        # Print field 6 (USE%), formatted to 5 chars wide
        printf "%-5s ", $6
        # Print the rest of the line from field 8 onwards (OPTIONS)
        for (i = 8; i <= NF; i++) {
            printf "%s%s", $i, (i == NF ? "" : " ")
        }
        printf "\n"
    }
    '
}


# Print Local Mounts section
if [ ${#local_mount_lines[@]} -gt 0 ]; then
    # echo -e interprets the color codes and the header newline
    echo -e "${COLOR_HEADER}\n--- Local Disk Mounts ---${COLOR_RESET}"
    print_header_row # Print the header row for columns

    # Sort local mounts by the 7th field (TARGET/Mount Point) before printing
    # Convert array to newline string, sort, then read sorted lines
    printf "%s\n" "${local_mount_lines[@]}" | sort -k 7 | while IFS= read -r sorted_mount_line; do
        # Pass each individual sorted line to the coloring function
        print_colored_line "$sorted_mount_line"
    done
fi

# Print Remote SAMBA Mounts section
if [ ${#samba_mount_lines[@]} -gt 0 ]; then
    # echo -e interprets the color codes and the header newline
    echo -e "${COLOR_HEADER}\n--- Remote SAMBA/CIFS Mounts ---${COLOR_RESET}"
    print_header_row # Print the header row for columns
     for mount_line in "${samba_mount_lines[@]}"; do
        # Pass each individual line to the coloring function
        print_colored_line "$mount_line"
    done
fi

# Print NFS Mounts section
if [ ${#nfs_mount_lines[@]} -gt 0 ]; then
    # echo -e interprets the color codes and the header newline
    echo -e "${COLOR_HEADER}\n--- NFS Mounts ---${COLOR_RESET}"
    print_header_row # Print the header row for columns
     for mount_line in "${nfs_mount_lines[@]}"; do
        # Pass each individual line to the coloring function
        # The coloring function will highlight the 7th (Target) and 1st (Source) fields
        print_colored_line "$mount_line"
    done
fi

# Add a final newline for cleaner output separation if any sections were printed
if [ ${#local_mount_lines[@]} -gt 0 ] || [ ${#samba_mount_lines[@]} -gt 0 ] || [ ${#nfs_mount_lines[@]} -gt 0 ]; then
    echo ""
fi

exit 0
