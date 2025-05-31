#!/bin/bash
# Author: Roy Wiseman 2025-03

# share-smb.sh - Quick Reference and Troubleshooting for Samba Shares

# ANSI color codes
YELLOW='\e[1;33m'
GREEN='\e[1;32m'
CYAN='\e[1;36m'
RED='\e[1;31m'
RESET='\e[0m'

# Get the real home directory of the user invoking sudo (if run with sudo)
# Otherwise, use the current user's home directory
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(eval echo ~"$SUDO_USER")
else
    USER_HOME="$HOME"
fi

OUTPUT_FILE="$USER_HOME/reports/shares-samba-report.txt"
DIR_PATH="${OUTPUT_FILE%/*}"
mkdir -p "$DIR_PATH"

# Add date/time to the output file and display headers
echo -e "${YELLOW}=== Samba Shares Quick Reference & Report ===${RESET}" | tee "$OUTPUT_FILE"
echo "Generated on: $(date)" | tee -a "$OUTPUT_FILE"
echo "Host: $(hostname)" | tee -a "$OUTPUT_FILE"
echo "---------------------------------------------------" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Quick Setup Guide ---
echo -e "${CYAN}--- Quick Setup Guide ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "1.  Install Samba:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo apt update && sudo apt install samba samba-common-bin samba-vfs-modules${RESET}   # (Debian/Ubuntu)" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo yum install samba samba-common samba-client samba-vfs${RESET}   # (RHEL/CentOS/AlmaLinux/Fedora)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "2.  Backup original config:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "3.  Edit the configuration file:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo nano /etc/samba/smb.conf${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "4.  Add a share definition (example):" | tee -a "$OUTPUT_FILE"
echo "    [MyShareName]             # Choose a short, descriptive name (used by clients)" | tee -a "$OUTPUT_FILE"
echo "        comment = My Shared Folder" | tee -a "$OUTPUT_FILE"
echo "        path = /path/to/your/folder" # <-- Server-side path to the directory being shared
echo "        read only = no            # Set to 'yes' for read-only access" | tee -a "$OUTPUT_FILE"
echo "        guest ok = no             # Set to 'yes' to allow anonymous access (caution!)" | tee -a "$OUTPUT_FILE"
echo "        valid users = your_linux_username # Add Linux usernames allowed to connect (if guest ok = no)" | tee -a "$OUTPUT_FILE"
echo "        create mask = 0664        # Permissions for new files created via share" | tee -a "$OUTPUT_FILE"
echo "        directory mask = 0775     # Permissions for new directories created via share" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "5.  Set a Samba password for users listed in 'valid users' (must be existing Linux users):" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo smbpasswd -a your_linux_username${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "6.  Test the configuration for syntax errors:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}testparm${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "7.  Restart Samba services to apply changes:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo systemctl restart smbd nmbd${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "8.  Enable services to start automatically on boot:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo systemctl enable smbd nmbd${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Samba Management (Server) ---
echo -e "${CYAN}--- Samba Management (Server) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Restart services (apply changes):" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo systemctl restart smbd nmbd${RESET}" | tee -a "$OUTPUT_FILE"
echo "Check service status:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo systemctl status smbd nmbd${RESET}" | tee -a "$OUTPUT_FILE"
echo "Stop services:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo systemctl stop smbd nmbd${RESET}" | tee -a "$OUTPUT_FILE"
echo "Start services:" | tee -a "$OUTPUT_FILE"
echo -e "    ${GREEN}sudo systemctl start smbd nmbd${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Viewing Samba Shares (Server Guide) ---
echo -e "${CYAN}--- Viewing Samba Shares (Server Guide) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "How to view configured and active shares on the server:" | tee -a "$OUTPUT_FILE"
echo "View full Samba configuration (shows share names [sections] and their paths):" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}testparm -s${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -s prints configuration in a concise format" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "List active shares on this server (as seen by a client connecting locally):" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}smbclient -L localhost -N${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -L lists shares, -N means no password prompt (may not show password-protected shares)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Troubleshooting (Server Side) ---
echo -e "${RED}--- Troubleshooting (Server Side) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Common Issues Checklist:" | tee -a "$OUTPUT_FILE"
echo -e " - Configuration syntax errors? --> Run '${RESET}testparm${RESET}' (without -s)." | tee -a "$OUTPUT_FILE"
echo -e " - Samba service running? --> Check '${RESET}sudo systemctl status smbd nmbd${RESET}'." | tee -a "$OUTPUT_FILE"
echo -e " - Firewall blocking ports 445/139? --> Check firewall rules (e.g., '${RESET}sudo ufw status${RESET}')." | tee -a "$OUTPUT_FILE"
echo -e " - Samba user exists & password set? --> Check '${RESET}sudo smbpasswd -a your_user${RESET}' (if user not added yet) or just '${RESET}sudo smbpasswd -L${RESET}' for a list (needs root)." | tee -a "$OUTPUT_FILE"
echo -e " - Directory permissions correct? --> Check '${RESET}ls -ld /path/to/share${RESET}' for the shared directory. Samba user needs read/write." | tee -a "$OUTPUT_FILE"
echo " - SELinux/AppArmor blocking? --> Check system logs if enabled and blocking Samba." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Check Samba service logs for errors:" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}sudo journalctl -u smbd -u nmbd --since 'today'${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # View recent logs for smbd and nmbd daemons" | tee -a "$OUTPUT_FILE"
echo "(Run the above command manually on the server to see detailed logs)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Check Firewall Status (ufw example):" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}sudo ufw status${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # Show ufw firewall rules" | tee -a "$OUTPUT_FILE"
sudo ufw status 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "(ufw command not found)" | tee -a "$OUTPUT_FILE"
echo "Ensure ports 445 (SMB) and possibly 139 (NetBIOS) are ALLOWed." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Connecting from Clients ---
echo -e "${CYAN}--- Connecting from Clients ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Windows (CMD/PowerShell):" | tee -a "$OUTPUT_FILE"
echo " - Map a drive (using server IP or hostname and SHARE_NAME):" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}net use Z: \\\\server_ip_or_hostname\\SHARE_NAME${RESET}" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}net use Z: \\\\server_ip_or_hostname\\SHARE_NAME /persistent:yes${RESET}   # Keep mapping after reboot" | tee -a "$OUTPUT_FILE"
echo "   (You will be prompted for credentials if needed)" | tee -a "$OUTPUT_FILE"
echo " - Connect via File Explorer: \\\\server_ip_or_hostname\\SHARE_NAME" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Linux (Terminal):" | tee -a "$OUTPUT_FILE"
echo " - List shares on a remote server:" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}smbclient -L //server_ip_or_hostname -U username${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # Replace username if not using the current Linux username" | tee -a "$OUTPUT_FILE"
echo " - Connect to a share (like an FTP client):" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}smbclient //server_ip_or_hostname/SHARE_NAME -U username${RESET}" | tee -a "$OUTPUT_FILE"
echo " - Mount the share to a local directory:" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}sudo mkdir /mnt/remote_share${RESET}" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}sudo mount -t cifs //server_ip_or_hostname/SHARE_NAME /mnt/remote_share -o user=your_smb_username,credentials=/path/to/credentials_file,uid=$(id -u),gid=$(id -g)${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # credentials file format: username=your_smb_user,password=your_smb_password" | tee -a "$OUTPUT_FILE"
echo "   # uid/gid help map file ownership to your local user" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Troubleshooting (Client Side) ---
echo -e "${RED}--- Troubleshooting (Client Side) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Common Issues Checklist:" | tee -a "$OUTPUT_FILE"
echo -e " - Server reachable? --> Ping '${RESET}ping server_ip_or_hostname${RESET}'." | tee -a "$OUTPUT_FILE"
echo -e " - Samba port open on server? --> Check '${RESET}nc -zv server_ip 445${RESET}' or '${RESET}telnet server_ip 445${RESET}' from client." | tee -a "$OUTPUT_FILE"
echo -e " - Correct SHARE_NAME? --> 'System error 67' often means share name is wrong." | tee -a "$OUTPUT_FILE"
echo -e "   - Verify SHARE_NAME using '${RESET}smbclient -L //server_ip_or_hostname -N${RESET}' (from Linux client) or examine server's '${RESET}testparm -s${RESET}' output." | tee -a "$OUTPUT_FILE"
echo -e " - Correct Credentials? --> 'System error 5' often means bad username/password." | tee -a "$OUTPUT_FILE"
echo -e "   - Ensure correct Samba username/password. Check server's '${RESET}sudo smbpasswd -L${RESET}' output." | tee -a "$OUTPUT_FILE"
echo -e " - DNS/Hostname resolution? --> Try using the server IP instead of hostname." | tee -a "$OUTPUT_FILE"
echo -e " - Old credentials cached (Windows)? --> Clear Windows Credential Manager entries for the server." | tee -a "$OUTPUT_FILE"
echo -e " - Client firewall blocking outbound connections? --> Check client firewall rules." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Useful Commands on Windows Client (CMD/PowerShell):" | tee -a "$OUTPUT_FILE"
echo " - Check active network connections (look for connections to server_ip:445):" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}netstat -ano | findstr :445${RESET}" | tee -a "$OUTPUT_FILE"
echo " - Flush DNS cache (if using hostname):" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}ipconfig /flushdns${RESET}" | tee -a "$OUTPUT_FILE"
echo " - Disconnect existing network drives (useful for clearing cached credentials/connections):" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}net use * /delete /yes${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Useful Commands on Linux Client (Terminal):" | tee -a "$OUTPUT_FILE"
echo " - Check if port 445 is open on the server:" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}nc -zv server_ip_or_hostname 445${RESET}   # (or telnet server_ip_or_hostname 445)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"


# --- Current Samba & Disk State Summary (Server Side) ---
echo -e "${YELLOW}--- Current Samba & Disk State Summary (Server Side) ---${RESET}" | tee -a "$OUTPUT_FILE"

# Disk Inventory (Physical/Partition/LVM)
echo -e "\n${CYAN}--- Disk Inventory (Physical/Partition/LVM) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Shows physical disks, partitions, and LVMs." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}lsblk -o NAME,FSTYPE,FSSIZE,FSAVAIL,FSUSED,FSUSE%,UUID,MOUNTPOINT -lp -e 1,7,11,253 | awk 'NR==1 || NF > 1'${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -o custom format, -l list style, -p full path, -e exclude device types (1=ramdisk, 7=loop, 11=sr, 253=device-mapper). awk filters header or lines with data." | tee -a "$OUTPUT_FILE"
lsblk -o NAME,FSTYPE,FSSIZE,FSAVAIL,FSUSED,FSUSE%,UUID,MOUNTPOINT -lp -e 1,7,11,253 2>/dev/null | awk 'NR==1 || NF > 1' | tee -a "$OUTPUT_FILE"

# Disk Usage (Filtered)
echo -e "\n${CYAN}--- Disk Usage Summary (Total, excluding tmpfs/loop/squashfs/docker/run/wsl) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Shows overall disk usage excluding transient/snap, docker overlay, and run filesystems." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}df -hT --total | grep -v -E '^tmpfs|^/dev/loop|squashfs|/docker|/run|/wsl|WSL'${RESET}" | tee -a "$OUTPUT_FILE" # Added docker/run filter here too
echo "   # -h human-readable, -T filesystem type, --total includes a total line, grep excludes specified types" | tee -a "$OUTPUT_FILE"
df -hT --total 2>/dev/null | grep -v -E '^tmpfs|^/dev/loop|squashfs|/docker|/run|/wsl|WSL' | tee -a "$OUTPUT_FILE"

# Mounted non-zero size filesystems (Filtered)
echo -e "\n${CYAN}--- Mounted Filesystems with Non-Zero Size (excluding tmpfs/loop/squashfs/docker/run/wsl) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Shows active mounts, filtered to exclude zero-size, transient, snap, docker overlay, and run filesystems." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}findmnt -o SIZE,USE%,TARGET,SOURCE,FSTYPE,OPTIONS | grep -v \"^[[:space:]]*0\" | grep -v -E 'tmpfs|loop|squashfs|/docker|/run|/wsl|WSL'${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -o custom format. Filters zero size and common non-persistent/container mounts." | tee -a "$OUTPUT_FILE"
# findmnt -o SIZE,USE%,TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | grep -v "^[[:space:]]*0" | grep -v -E 'tmpfs|loop|squashfs|/docker|/run|/wsl|WSL' | column -t | tee -a "$OUTPUT_FILE"
findmnt -o SIZE,USE%,TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | \
grep -v "^[[:space:]]*0" | \
grep -v -E 'tmpfs|loop|squashfs|/docker|/run|/wsl|WSL' | \
sed 's/^[[:space:]]*├─/.    .    ├─/' | \
sed 's/^[[:space:]]*$/.    .    .    .    .    ./' | \
column -t | \
sed 's/\.    /     /g'

# # Mounted non-zero size filesystems (Filtered)
# echo -e "\n${CYAN}--- Mounted Filesystems with Non-Zero Size (excluding tmpfs/loop/squashfs/docker/run/wsl) ---${RESET}" | tee -a "$OUTPUT_FILE"
# echo "Shows active mounts, filtered to exclude zero-size, transient, snap, docker overlay, and run file systems." | tee -a "$OUTPUT_FILE"
# # Use findmnt and pipe to awk for filtering zero-size and exclusion patterns.
# # awk 'NR==1 { print; next }' prints the header and skips processing for it.
# # '! /^[[:space:]]*0/' filters out lines where the first field (SIZE) starts with 0 or spaces then 0.
# # '! /tmpfs|loop|squashfs|\/docker|\/run|\/wsl|WSL/' filters out lines containing the exclusion patterns anywhere.
# # { print } prints the lines that pass the filters.
# echo -e "${GREEN}findmnt -o SIZE,USE%,TARGET,SOURCE,FSTYPE,OPTIONS | awk 'NR==1 { print; next } ! /^[[:space:]]*0/ && ! /tmpfs|loop|squashfs|\\/docker|\\/run|\\/wsl|WSL/ { print }'${RESET}" | tee -a "$OUTPUT_FILE"
# echo "   # -o custom format. awk filters header, zero size, and common non-persistent/container mounts." | tee -a "$OUTPUT_FILE"
# # Execute findmnt and pipe its output through awk for filtering, then to tee
# findmnt -o SIZE,USE%,TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | awk 'NR==1 { print; next } ! /^[[:space:]]*0/ && ! /tmpfs|loop|squashfs|\/docker|\/run|\/wsl|WSL/ { print }' | tee -a "$OUTPUT_FILE"
# echo "" | tee -a "$OUTPUT_FILE"

# # Detailed Samba Shares (Configured via testparm -s)
# echo -e "\n${CYAN}--- Samba Shares (Configured - via testparm -s) ---${RESET}" | tee -a "$OUTPUT_FILE"
# echo "This shows share names [in brackets] and their corresponding paths on the server as defined in smb.conf." | tee -a "$OUTPUT_FILE"
# echo -e "${GREEN}testparm -s${RESET}" | tee -a "$OUTPUT_FILE"
# echo "   # -s prints configuration in a concise format" | tee -a "$OUTPUT_FILE"
# testparm -s 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "(Command not found or config error - run 'testparm' alone for details)" | tee -a "$OUTPUT_FILE"

# Detailed Samba Shares (Configured via testparm -s or custom script)
echo -e "\n${CYAN}--- Samba Shares (Configured) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Share names as defined in smb.conf." | tee -a "$OUTPUT_FILE"
# Define the path to the custom table script (assumes it's in the same directory)
# $BASH_SOURCE[0] is the path to the current script
# SCRIPT_DIR="$(dirname "$BASH_SOURCE[0]")"
# TABLE_SCRIPT_PATH="$SCRIPT_DIR/shares-smb-table.sh"
# Check if the custom table script exists and is executable
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
        shares[current_share]["createmask"] = "default"
        shares[current_share]["dirmask"] = "default"
        shares[current_share]["path"] = "n.a." # Use n.a. as in your example for path if not set
        shares[current_share]["readonly"] = "default"
        shares[current_share]["validusers"] = "n.a." # Use n.a. as in your example for users if not set
        shares[current_share]["comment"] = "n.a." # Use n.a. as in your example for comment if not set

    } else if (current_share != "" && current_share != "global") { # Process lines within a share (excluding global)
        # Trim leading and trailing whitespace (spaces and tabs) for processing
        line = $0
        gsub(/^[ \t]+|[ \t]+$/, "", line)

        # Use pattern matching and extraction for parameters, assigning directly to the shares array
        if (match(line, /^create mask *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value) # Trim spaces from the value
            shares[current_share]["createmask"] = value
        } else if (match(line, /^directory mask *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share]["dirmask"] = value
        } else if (match(line, /^path *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share]["path"] = value
        } else if (match(line, /^read only *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
             # Represent "Yes" as "Yes" and "No" as "No" as in your example
            if (value == "Yes") shares[current_share]["readonly"] = "Yes"
            else if (value == "No") shares[current_share]["readonly"] = "No"
            else shares[current_share]["readonly"] = value # Handle other potential values
        } else if (match(line, /^valid users *=/)) {
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share]["validusers"] = value
        } else if (match(line, /^comment *=/)) { # Extract comment
            value = substr(line, RSTART + RLENGTH)
            gsub(/^ *| *$/, "", value)
            shares[current_share]["comment"] = value
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
        if (length(shares[share_name]["createmask"]) > max_widths[1]) max_widths[1] = length(shares[share_name]["createmask"])
        if (length(shares[share_name]["dirmask"]) > max_widths[2]) max_widths[2] = length(shares[share_name]["dirmask"])
        if (length(shares[share_name]["readonly"]) > max_widths[3]) max_widths[3] = length(shares[share_name]["readonly"])
        if (length(shares[share_name]["validusers"]) > max_widths[4]) max_widths[4] = length(shares[share_name]["validusers"])
        if (length(shares[share_name]["path"]) > max_widths[5]) max_widths[5] = length(shares[share_name]["path"])
        if (length(shares[share_name]["comment"]) > max_widths[6]) max_widths[6] = length(shares[share_name]["comment"])
    }

    # Print headers with dynamic width
    printf "%-*s  ", max_widths[0], headers[0] # Left-align Name
    printf "%-*s  ", max_widths[1], headers[1] # Left-align CreateMask
    printf "%-*s  ", max_widths[2], headers[2] # Left-align DirMask
    printf "%-*s  ", max_widths[3], headers[3] # Left-align Read-Only
    printf "%-*s  ", max_widths[4], headers[4] # Left-align ValidUsers
    printf "%-*s  ", max_widths[5], headers[5] # Left-align Path
    printf "%-*s\n", max_widths[6], headers[6] # Left-align Comment (no trailing spaces)

    # Print the separator line made of '=' characters
    for (i = 0; i <= 6; i++) {
        # Print '=' characters for the width of the column
        for (j = 0; j < max_widths[i]; j++) {
            printf "="
        }
        # Print the spacing after the column (except for the last column)
        if (i < 6) {
            printf "  "
        }
    }
    printf "\n" # Newline after the separator line

    # Print share data with dynamic width
    for (i = 0; i < share_count; i++) {
        share_name = share_order[i]
        printf "%-*s  ", max_widths[0], share_name # Left-align Name
        printf "%-*s  ", max_widths[1], shares[share_name]["createmask"] # Left-align CreateMask
        printf "%-*s  ", max_widths[2], shares[share_name]["dirmask"] # Left-align DirMask
        printf "%-*s  ", max_widths[3], shares[share_name]["readonly"] # Left-align Read-Only
        printf "%-*s  ", max_widths[4], shares[share_name]["validusers"] # Left-align ValidUsers
        printf "%-*s  ", max_widths[5], shares[share_name]["path"] # Left-align Path
        printf "%-*s\n", max_widths[6], shares[share_name]["comment"] # Left-align Comment (no trailing spaces)
    }
}'

# List active shares (as seen by client connecting to localhost)
echo -e "\n${CYAN}--- Samba Shares (Active - via smbclient -L localhost) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "This shows shares the server is actively advertising and available to clients." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}smbclient -L localhost -N${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -L lists shares, -N means no password (may not show password-protected shares depending on config)" | tee -a "$OUTPUT_FILE"
smbclient -L localhost -N 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "(Command not found - install samba-client)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Active Samba Connections (smbstatus)
echo -e "\n${CYAN}--- Active Samba Connections (smbstatus) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Lists current active connections to Samba shares on this server. Requires root privileges." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}sudo smbstatus -b${RESET}" | tee -a "$OUTPUT_FILE" # Added sudo
echo "   # -b brief output" | tee -a "$OUTPUT_FILE"
sudo smbstatus -b 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "(Command not found or requires sudo)" | tee -a "$OUTPUT_FILE" # Added check note

# Active SMB Connections via ss (Port 445)
echo -e "\n${CYAN}--- Active SMB/CIFS Connections (ss) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Shows active network connections on port 445 (SMB/CIFS) on this server." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}ss -tuna | grep -E ':445|Address' | column -t${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -t tcp, -u udp, -n numeric ports, -a all sockets. Filters for port 445." | tee -a "$OUTPUT_FILE"
ss -tuna 2>/dev/null | grep -E ':445|Address' | column -t | tee -a "$OUTPUT_FILE"

# Permissions of common share locations
echo -e "\n${CYAN}--- Potential Share Location Permissions ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Checking permissions for common share parent directories. Shared directories must allow access for the Samba user." | tee -a "$OUTPUT_FILE"
for dir in /srv/samba /mnt /media /home /var/nfs /export; do
    if [ -d "$dir" ]; then
        echo -e "\nPermissions for $dir:" | tee -a "$OUTPUT_FILE"
        ls -ld "$dir" | tee -a "$OUTPUT_FILE"
    fi
done

# System Uptime
echo -e "\n${CYAN}--- System Uptime ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Uptime: $(uptime -p)" | tee -a "$OUTPUT_FILE"


# Final message
echo -e "${GREEN}\nReport sections complete.${RESET}" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}Full report saved to: ${OUTPUT_FILE}${RESET}"

exit 0
