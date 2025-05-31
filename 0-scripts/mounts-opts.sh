#!/bin/bash
# Author: Roy Wiseman 2025-05

# --- Configuration ---

# ANSI Color Codes
COLOR_LOCAL_HEADER="\033[1;32m"      # Green bold for Local header
COLOR_REMOTE_SAMBA_HEADER="\033[1;32m" # Green bold for SAMBA/CIFS header
COLOR_NFS_HEADER="\033[1;35m"       # Magenta bold for NFS header
COLOR_FIELD="\033[1;34m"             # Blue bold for fields (Source and Mount Point) as requested
COLOR_RESET="\033[0m"         # Reset color to default

echo -e "${COLOR_LOCAL_HEADER}\nDisplay all current mount options:${COLOR_RESET}"

# Regex to exclude common system/virtual mounts and the root mount
# This pattern looks for filesystem types or mount points to exclude.
# Add or remove patterns here if you see other unwanted entries.
EXCLUDE_REGEX=' type (sysfs|proc|devtmpfs|devpts|tmpfs|securityfs|cgroup|pstore|bpf|autofs|mqueue|hugetlbfs|debugfs|tracefs|configfs|ramfs|fusectl|nsfs|portal|overlay|squashfs|binfmt_misc|rpc_pipefs|fuse.*|nfsd)| on / type | on /snap/| on /var/lib/docker/| on /run/| on /sys/| on /dev/| on /proc/'

# --- Processing ---

# Get raw mount output and filter out the unwanted entries
# We pipe the mount output directly into grep for initial filtering.
filtered_mounts=$(mount | grep -vE "$EXCLUDE_REGEX")

# Initialize variables to store categorized mounts. We'll append lines to these.
local_mounts=""
samba_mounts="" # For CIFS mounts
nfs_mounts=""   # For NFS mounts

# Read the filtered mounts line by line
# IFS= prevents leading/trailing whitespace from being trimmed
# -r prevents backslash escapes from being interpreted
# The '<<< "$filtered_mounts"' syntax feeds the multi-line string into the while loop
while IFS= read -r line; do
    # Extract the source (1st field) and filesystem type (5th field) from the current line
    # We use awk here for reliable field extraction based on the 'mount' output format
    read -r current_source current_fstype <<< $(echo "$line" | awk '{print $1, $5}')

    # --- Categorization Logic ---

    # 1. Remote SAMBA (cifs) mounts - identified by filesystem type
    if [[ "$current_fstype" == "cifs" ]]; then
        # Append the full line and a *real* newline character
        samba_mounts+="$line"$'\n'
        continue # Go to the next line
    fi

    # 2. NFS mounts - identified by filesystem type
    if [[ "$current_fstype" == "nfs" ]] || [[ "$current_fstype" == "nfs4" ]]; then
        # Append the full line and a *real* newline character
        nfs_mounts+="$line"$'\n'
        continue # Go to the next line
    fi

    # 3. Local Disk Mounts - identified by source starting with /dev/sd
    #    (We implicitly exclude NFS and CIFS here as they were checked first)
    if [[ "$current_source" =~ ^\/dev\/sd ]]; then
        # Append the full line and a *real* newline character
        local_mounts+="$line"$'\n'
        continue # Go to the next line
    fi

    # Lines that are not categorized above are ignored (e.g., other types that
    # passed the initial filter but don't fit our desired categories).

done <<< "$filtered_mounts"

# --- Output ---

# Function to print a colored mount line with Source and Mount Point highlighted
# Takes one line of mount output as input
print_colored_line() {
    local line="$1"
    # Use awk to split the line and apply colors to specific fields (1st and 3rd)
    # Pass color variables to awk using -v
    echo "$line" | awk -v field_color="$COLOR_FIELD" -v reset_color="$COLOR_RESET" '
    {
        # Print field 1 (Source) in color, followed by a space
        printf "%s%s%s ", field_color, $1, reset_color
        # Print field 2 ("on"), followed by a space
        printf "%s ", $2
        # Print field 3 (Mount Point) in color, followed by a space
        printf "%s%s%s ", field_color, $3, reset_color
        # Print field 4 ("type"), followed by a space
        printf "%s ", $4
        # Print the rest of the line from field 5 onwards,
        # separating fields with a space, but no space after the last field.
        for (i = 5; i <= NF; i++) {
            printf "%s%s", $i, (i == NF ? "" : " ")
        }
        # Print a newline at the end of the processed line
        printf "\n"
    }
    '
}


# Print Local Mounts section if any were found
if [[ -n "$local_mounts" ]]; then
    # echo -e interprets the color codes and the header newline
    echo -e "${COLOR_LOCAL_HEADER}\n--- Local Disk Mounts ---${COLOR_RESET}"
    # Read the collected mounts line by line from the variable
    # The <<< operator feeds the variable content as standard input to the while loop
    while IFS= read -r mount_line; do
        # Pass each individual line to the coloring function
        print_colored_line "$mount_line"
    done <<< "$local_mounts"
fi

# Print Remote SAMBA Mounts section if any were found
if [[ -n "$samba_mounts" ]]; then
    # echo -e interprets the color codes and the header newline
    echo -e "${COLOR_REMOTE_SAMBA_HEADER}--- Remote SAMBA/CIFS Mounts ---${COLOR_RESET}"
     while IFS= read -r mount_line; do
        # Pass each individual line to the coloring function
        print_colored_line "$mount_line"
    done <<< "$samba_mounts"
fi

# Print NFS Mounts section if any were found
if [[ -n "$nfs_mounts" ]]; then
    # echo -e interprets the color codes and the header newline
    echo -e "${COLOR_NFS_HEADER}--- NFS Mounts ---${COLOR_RESET}"
     while IFS= read -r mount_line; do
        # Pass each individual line to the coloring function
        # The coloring function will highlight the 1st (server:/share) and 3rd (mount point) fields
        print_colored_line "$mount_line"
    done <<< "$nfs_mounts"
fi

# Add a final newline for cleaner output separation if any sections were printed
# if [[ -n "$local_mounts" ]] || [[ -n "$samba_mounts" ]] || [[ -n "$nfs_mounts" ]]; then
#     echo ""
# fi

exit 0
