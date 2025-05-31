#!/bin/bash
# Author: Roy Wiseman 2025-04

# fstab-reader.sh - Reads, formats, and explains entries in /etc/fstab
# --- Display fstab entries in a table ---
# echo -e "${CYAN}--- fstab Entries ---${NC}"
# echo "Filesystem                                 Mount Point                Type  Options                         Dump    Pass"
# echo "-----------                                -----------                ----  -------                         ----    ----"
# echo "UUID=e88c47aa-2588-41fc-b9c7-eb941ef97a1d  /                          ext4  errors=remount-ro                  0       1"

# fstab-reader.sh - Reads, formats, and explains entries in /etc/fstab

# ANSI color codes for better readability
YELLOW='\e[1;33m' # Section headers
GREEN='\e[1;32m'  # Explanations
CYAN='\e[1;36m'   # Field names
RED='\e[1;31m'    # Errors/Warnings
NC='\e[0m'        # No colour / reset color 

FSTAB_FILE="/etc/fstab"

# --- Header ---
echo -e "${YELLOW}=== /etc/fstab Reader and Explainer ===${NC}"
echo
echo "This script reads your system's ${FSTAB_FILE} file, shows the entries,"
echo "and then provides a detailed explanation of the fields and common options."
echo "Understanding fstab is crucial for managing filesystem mounts at boot."
echo "---------------------------------------------------"
echo ""

# --- Check if /etc/fstab exists ---
if [ ! -f "$FSTAB_FILE" ]; then
    echo -e "${RED}Error: ${FSTAB_FILE} not found! Cannot proceed.${NC}"
    exit 1
fi

# --- Detailed Explanation of Fields and Options ---
echo -e "${YELLOW}=== Detailed Explanation ===${NC}"
echo ""
echo -e "${CYAN}Common Mount Options (Field 4):${NC}"
echo -e "${GREEN}   - defaults: Use default options (rw, suid, dev, exec, auto, nouser, async).${NC}"
echo -e "${GREEN}   - rw: Mount the filesystem read-write.${NC}"
echo -e "${GREEN}   - ro: Mount the filesystem read-only.${NC}"
echo -e "${GREEN}   - auto: Mount automatically at boot or with 'mount -a'.${NC}"
echo -e "${GREEN}   - noauto: Mount only explicitly (e.g., 'mount /mount/point'), NOT at boot.${NC}"
echo -e "${GREEN}   - user: Allows a regular user to mount the filesystem.${NC}"
echo -e "${GREEN}   - nouser: Only root can mount the filesystem (default).${NC}"
echo -e "${GREEN}   - exec: Allows execution of binaries on the filesystem.${NC}"
echo -e "${GREEN}   - noexec: Disallows execution of binaries (good for security on partitions like /tmp).${NC}"
echo -e "${GREEN}   - sync: Write data synchronously to disk (slower, safer).${NC}"
echo -e "${GREEN}   - async: Write data asynchronously (faster, riskier on crash).${NC}"
echo -e "${GREEN}   - suid: Allows set-user-id and set-group-id bits.${NC}"
echo -e "${GREEN}   - nosuid: Disallows set-user-id and set-group-id bits (good for security).${NC}"
echo -e "${GREEN}   - dev: Interpret device files.${NC}"
echo -e "${GREEN}   - nodev: Do not interpret device files (good for security).${NC}"
echo -e "${GREEN}   - relatime: Update access times relative to modify/change time (efficient).${NC}"
echo -e "${GREEN}   - noatime: Do not update access times (performance boost, but may affect some apps).${NC}"
echo -e "${GREEN}   - strictatime: Always update access times (original behavior, high disk traffic).${NC}"
echo -e "${GREEN}   - nofail: Do not report errors if the device does not exist. This prevents the boot process from halting if the device is missing or the mount fails.${NC}"
echo -e "${GREEN}   - _netdev: Requires network access; mount only after network is up (for NFS, cifs, etc.).${NC}"
echo -e "${GREEN}   - comment=...: A field for comments, ignored by mount.${NC}"
echo ""
echo -e "${GREEN}Note: There are many other filesystem-specific and general mount options. Consult 'man mount' and the man page for the specific filesystem type (e.g., 'man mount.cifs', 'man mount.nfs') for a complete list.${NC}"
echo ""

echo -e "${CYAN}Importance of UUIDs and LABELs${NC}"
echo -e "${GREEN}   - Using device names like /dev/sda1 is unreliable as they can change if hardware is added or removed.${NC}"
echo -e "${GREEN}   - UUIDs (Universally Unique Identifiers) and LABELs (human-readable names) are persistent identifiers that ensure the correct filesystem is mounted regardless of its device name.${NC}"
echo -e "${GREEN}   - Use 'blkid' or 'lsblk -f' to find UUIDs and LABELs.${NC}"
echo ""

echo -e "${CYAN}Persistence, relationship with the 'mount' command, and the 'auto' option${NC}"
echo -e "${GREEN}   - fstab defines filesystems intended to be mounted persistently across reboots.${NC}"
echo -e "${GREEN}   - Entries with the 'auto' option (or 'defaults' option are automatically mounted during the system boot sequence.${NC}"
echo -e "${GREEN}   - The 'defaults' option is a shorthand that includes all of 'auto', 'rw', 'suid', 'dev', 'exec', 'nouser', 'async'${NC}"
echo -e "${GREEN}   - All of the 'defaults' options are treated as if they explicitly listed (unless overridden by other options).${NC}"
echo -e "${GREEN}   - The 'mount' command uses fstab as a configuration file.${NC}"
echo -e "${GREEN}       'mount /mount/point' looks up the entry in fstab.${NC}"
echo -e "${GREEN}       'mount -a' attempts to mount all 'auto' entries in fstab.${NC}"
echo ""

echo -e "${CYAN}--- fstab Fields ---${NC}"
echo -e "${GREEN}1. Filesystem (or device): Specifies the device or remote filesystem to be mounted (e.g., UUID=..., LABEL=..., /dev/..., //server/share, server:/export).${NC}"
echo -e "${GREEN}2. Mount Point: The directory in the filesystem hierarchy where the Filesystem will be attached (e.g., /, /home, /mnt/data). Must exist.${NC}"
echo -e "${GREEN}3. Type: The filesystem type (e.g., ext4, xfs, swap, nfs, cifs).${NC}"
echo -e "${GREEN}4. Options: Comma-separated list controlling mount behavior (see below).${NC}"
echo -e "${GREEN}5. Dump: Used by 'dump' utility (0=no dump, 1=dump). Largely obsolete.${NC}"
echo -e "${GREEN}6. Pass: Used by 'fsck' utility for check order at boot (0=no check, 1=check root first, 2=check others after root).${NC}"
echo ""

# --- Display fstab entries in a table ---
echo -e "${CYAN}--- fstab Entries ---${NC}"

# Prepare the header lines and the fstab entries for column -t
# We use a subshell { ... } to group the echo commands and the cat/grep/awk pipeline
# The output of the subshell is then piped to column -t
{
    # Echo the header lines
    echo "Filesystem Mount_Point Type Options Dump Pass"
    echo "---------- ----------- ---- ------- ---- ----"
    # Read /etc/fstab, filter comments/empty lines, and format with awk
    # Awk ensures exactly 6 fields are passed, even if optional fields are missing
    # We use printf in awk to ensure a single space delimiter between fields
    cat "$FSTAB_FILE" | grep -vE '^[[:space:]]*#|^[[:space:]]*$' | awk '{ printf "%s %s %s %s %s %s\n", $1, $2, $3, $4, $5, $6 }'
} | column -t -s ' ' # Pipe the combined output (headers + entries) to column -t, using space as delimiter

# --- Footer ---
echo ""
echo -e "${YELLOW}=== End of fstab Explanation ===${NC}"
echo "Remember to be cautious when editing ${FSTAB_FILE}. Errors can prevent your system from booting."
echo "Always back up ${FSTAB_FILE} before making changes."
echo ""

