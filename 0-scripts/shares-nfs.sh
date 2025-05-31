#!/bin/bash
# Author: Roy Wiseman 2025-03

# share-nfs.sh - Quick Reference and Troubleshooting for NFS Exports

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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"       # Directory where this script is
SCRIPT_FILENAME_WITH_EXT="${0##*/}"               # This script's filename without path
SCRIPT_BASENAME="${SCRIPT_FILENAME_WITH_EXT%.*}"
OUTPUT_DIR="$USER_HOME/reports"
OUTPUT_FILE="$OUTPUT_DIR/$SCRIPT_BASENAME-report.txt"
mkdir -p "$OUTPUT_DIR"

# Add date/time to the output file and display headers
echo -e "${YELLOW}=== NFS Exports Quick Reference & Report ===${RESET}" | tee "$OUTPUT_FILE"
echo "Generated on: $(date)" | tee -a "$OUTPUT_FILE"
echo "Host: $(hostname)" | tee -a "$OUTPUT_FILE"
echo "--------------------------------------------------" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Quick Setup Guide ---
echo -e "${CYAN}--- Quick Setup Guide ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "1.  Install NFS server:" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo apt update && sudo apt install nfs-kernel-server${RESET}   # (Debian/Ubuntu)" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo yum install nfs-utils${RESET}   # (RHEL/CentOS/AlmaLinux/Fedora)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "2.  Backup original config:" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo cp /etc/exports /etc/exports.bak${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "3.  Edit the configuration file:" | tee -a "$OUTPUT_FILE"
echo "    ${RESET}sudo nano /etc/exports${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "4.  Add an export definition (example):" | tee -a "$OUTPUT_FILE"
echo "    /path/to/your/folder    client_ip_or_network(rw,sync,no_subtree_check)" # <-- Server-side path and client access rules
echo "      - /path/to/your/folder: Directory on the server to share" | tee -a "$OUTPUT_FILE"
echo "      - client_ip_or_network: Specific IP, hostname, or network (e.g., 192.168.1.0/24, *, client.example.com)" | tee -a "$OUTPUT_FILE"
echo "      - Options (common):" | tee -a "$OUTPUT_FILE"
echo "        - rw: Read/Write access" | tee -a "$OUTPUT_FILE"
echo "        - ro: Read-Only access" | tee -a "$OUTPUT_FILE"
echo "        - sync: Changes written immediately (safer, slower)" | tee -a "$OUTPUT_FILE"
echo "        - async: Changes buffered (faster, less safe)" | tee -a "$OUTPUT_FILE"
echo "        - no_subtree_check: Disable subtree checking (recommended, prevents issues with renamed files)" | tee -a "$OUTPUT_FILE"
echo "        - no_root_squash: Allow root on client to have root privileges on the share (caution!)" | tee -a "$OUTPUT_FILE"
echo "        - root_squash: Map client root user to anonymous user (default, safer)" | tee -a "$OUTPUT_FILE"
echo "        - all_squash: Map all client users to anonymous user" | tee -a "$OUTPUT_FILE"
echo "        - anonuid=<uid>, anongid=<gid>: Specify UID/GID for squashed users" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "5.  Export the shares (make them available):" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo exportfs -a${RESET}" | tee -a "$OUTPUT_FILE"
echo "    ${RESET}sudo exportfs -v${RESET}   # Verify verbose output" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "6.  Restart NFS services:" | tee -a "$OUTPUT_FILE"
echo "    ${RESET}sudo systemctl restart nfs-kernel-server${RESET}   # (Debian/Ubuntu)" | tee -a "$OUTPUT_FILE"
echo "    ${RESET}sudo systemctl restart nfs-server${RESET}   # (RHEL/CentOS/AlmaLinux/Fedora)" | tee -a "$OUTPUT_FILE"
echo "    ${RESET}sudo systemctl restart rpcbind${RESET}   # Sometimes needed" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "7.  Enable services to start on boot:" | tee -a "$OUTPUT_FILE"
echo "    ${RESET}sudo systemctl enable nfs-kernel-server${RESET}   # (Debian/Ubuntu)" | tee -a "$OUTPUT_FILE"
echo "    ${RESET}sudo systemctl enable nfs-server${RESET}   # (RHEL/CentOS/AlmaLinux/Fedora)" | tee -a "$OUTPUT_FILE"
echo "    ${RESET}sudo systemctl enable rpcbind${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- NFS Management (Server) ---
echo -e "${CYAN}--- NFS Management (Server) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Restart services (apply changes):" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo systemctl restart nfs-kernel-server nfs-server rpcbind${RESET}   # Use relevant service names" | tee -a "$OUTPUT_FILE"
echo "Check service status:" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo systemctl status nfs-kernel-server nfs-server rpcbind${RESET}   # Use relevant service names" | tee -a "$OUTPUT_FILE"
echo "Stop services:" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo systemctl stop nfs-kernel-server nfs-server rpcbind${RESET}   # Use relevant service names" | tee -a "$OUTPUT_FILE"
echo "Start services:" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo systemctl start nfs-kernel-server nfs-server rpcbind${RESET}   # Use relevant service names" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Export all shares defined in /etc/exports:" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo exportfs -a${RESET}" | tee -a "$OUTPUT_FILE"
echo "Re-export all shares (useful after network changes):" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo exportfs -r${RESET}" | tee -a "$OUTPUT_FILE"
echo "Unexport a specific share (e.g., /path/to/share):" | tee -a "$OUTPUT_FILE"
echo -e "    ${RESET}sudo exportfs -u /path/to/share${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Viewing NFS Exports (Server Guide) ---
echo -e "${CYAN}--- Viewing NFS Exports (Server Guide) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "How to view configured and active NFS exports on the server:" | tee -a "$OUTPUT_FILE"
echo "View raw /etc/exports file content:" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}cat /etc/exports${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # Shows definitions from the config file" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "View active exports (what the kernel is currently exporting):" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}exportfs -v${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -v for verbose output (shows options)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "View filesystems mounted on the server that are of type NFS:" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}mount | grep nfs${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # Shows shares this server has mounted from others (NFS client role)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Troubleshooting (Server Side) ---
echo -e "${RED}--- Troubleshooting (Server Side) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Common Issues Checklist:" | tee -a "$OUTPUT_FILE"
echo " - Config error in /etc/exports? --> Check syntax carefully, run '${RESET}sudo exportfs -v${RESET}' after editing." | tee -a "$OUTPUT_FILE"
echo -e " - NFS/RPCBind services running? --> Check '${RESET}sudo systemctl status nfs-kernel-server nfs-server rpcbind${RESET}' (use relevant names)." | tee -a "$OUTPUT_FILE"
echo -e " - Firewall blocking ports 111 (rpcbind) or 2049 (nfs)? --> Check firewall rules (e.g., '${RESET}sudo ufw status${RESET}')." | tee -a "$OUTPUT_FILE"
echo " - Hosts.allow/deny blocking client? --> Check /etc/hosts.allow and /etc/hosts.deny." | tee -a "$OUTPUT_FILE"
echo -e " - Directory permissions correct? --> Check '${RESET}ls -ld /path/to/share${RESET}'. Needs to be readable/writable by the UID/GID client connects as (often 'nobody')." | tee -a "$OUTPUT_FILE"
echo " - SELinux/AppArmor blocking? --> Check system logs if enabled and blocking NFS." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Check NFS/RPCBind service logs for errors:" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}sudo journalctl -u nfs-kernel-server -u nfs-server -u rpcbind --since 'today'${RESET}   # Use relevant service names" | tee -a "$OUTPUT_FILE"
echo "   # View recent logs for NFS and RPCBind daemons" | tee -a "$OUTPUT_FILE"
echo "(Run the above command manually on the server to see detailed logs)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Check Firewall Status (ufw example):" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}sudo ufw status${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # Show ufw firewall rules" | tee -a "$OUTPUT_FILE"
sudo ufw status 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "(ufw command not found)" | tee -a "$OUTPUT_FILE"
echo "Ensure ports 111 (TCP/UDP) and 2049 (TCP/UDP) are ALLOWed." | tee -a "$OUTPUT_FILE"
echo "Note: mountd, statd, lockd use other ports that may need opening or fixing in config." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Connecting from Clients (Linux/Unix-like) ---
echo -e "${CYAN}--- Connecting from Clients (Linux/Unix-like) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "NFS is primarily used by Linux and Unix-like systems." | tee -a "$OUTPUT_FILE"
echo "Windows requires installing 'Client for NFS' feature." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "View available NFS exports on a remote server:" | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}showmount -e server_ip_or_hostname${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # Requires rpcbind/portmapper port 111 to be open on server" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Mount an NFS share to a local directory:" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}sudo mkdir /mnt/remote_nfs${RESET}" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}sudo mount -t nfs server_ip_or_hostname:/remote/path /mnt/remote_nfs -o defaults${RESET}   # Basic mount" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}sudo mount -t nfs server_ip_or_hostname:/remote/path /mnt/remote_nfs -o rw,sync,hard,intr,proto=tcp,vers=4${RESET}   # Example with common options" | tee -a "$OUTPUT_FILE"
echo "   # See 'man nfs' and 'man mount' for options." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Unmount the share:" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}sudo umount /mnt/remote_nfs${RESET}" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Troubleshooting (Client Side) ---
echo -e "${RED}--- Troubleshooting (Client Side) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Common Issues Checklist:" | tee -a "$OUTPUT_FILE"
echo " - Server reachable? --> Ping '${RESET}ping server_ip_or_hostname${RESET}'." | tee -a "$OUTPUT_FILE"
echo -e " - RPCBind (111) port open on server? --> Check '${RESET}nc -zv server_ip 111${RESET}' or '${RESET}telnet server_ip 111${RESET}' from client. showmount will fail if blocked." | tee -a "$OUTPUT_FILE"
echo -e " - NFS (2049) port open on server? --> Check '${RESET}nc -zv server_ip 2049${RESET}' or '${RESET}telnet server_ip 2049${RESET}' from client." | tee -a "$OUTPUT_FILE"
echo " - Correct Export Path? --> Verify path using '${RESET}showmount -e server_ip_or_hostname${RESET}'." | tee -a "$OUTPUT_FILE"
echo " - Permissions? --> Mount might succeed, but file access fails. Check UIDs/GIDs, root_squash/all_squash options, and directory permissions on the server." | tee -a "$OUTPUT_FILE"
echo " - Protocol/Version Mismatch? --> Try specifying options like 'proto=tcp' or 'vers=3/4'." | tee -a "$OUTPUT_FILE"
echo " - Client Firewall blocking outbound? --> Check client firewall rules." | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"
echo "Useful Commands on Client (Linux Terminal):" | tee -a "$OUTPUT_FILE"
echo " - Check if RPCBind (111) and NFS (2049) ports are open on the server:" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}nc -zv server_ip_or_hostname 111 2049${RESET}   # (or telnet)" | tee -a "$OUTPUT_FILE"
echo " - View kernel messages during mount attempts:" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}dmesg | tail -n 20${RESET}   # Look for mount errors" | tee -a "$OUTPUT_FILE"
echo " - Check client NFS service status (if applicable):" | tee -a "$OUTPUT_FILE"
echo -e "   ${RESET}systemctl status nfs-client${RESET}   # (Service name may vary)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# --- Current NFS & Disk State Summary (Server Side) ---
echo -e "${YELLOW}--- Current NFS & Disk State Summary (Server Side) ---${RESET}" | tee -a "$OUTPUT_FILE"

# Disk Inventory (Physical/Partition/LVM)
echo -e "\n${CYAN}--- Disk Inventory (Physical/Partition/LVM) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Shows physical disks, partitions, and LVMs." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}lsblk -o NAME,FSTYPE,FSSIZE,FSAVAIL,FSUSED,FSUSE%,UUID,MOUNTPOINT -lp -e 1,7,11,253 | awk 'NR==1 || NF > 1'${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -o custom format, -l list style, -p full path, -e exclude device types (1=ramdisk, 7=loop, 11=sr, 253=device-mapper). awk filters header or lines with data." | tee -a "$OUTPUT_FILE"
lsblk -o NAME,FSTYPE,FSSIZE,FSAVAIL,FSUSED,FSUSE%,UUID,MOUNTPOINT -lp -e 1,7,11,253 2>/dev/null | awk 'NR==1 || NF > 1' | tee -a "$OUTPUT_FILE"

# Disk Usage (Filtered)
echo -e "\n${CYAN}--- Disk Usage Summary (Total, excluding tmpfs/loop/squashfs/docker/run) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Shows overall disk usage excluding transient/snap, docker overlay, and run filesystems." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}df -hT --total | grep -v -E '^tmpfs|^/dev/loop|squashfs|/docker|/run|/wsl|WSL'${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -h human-readable, -T filesystem type, --total includes a total line, grep excludes specified types" | tee -a "$OUTPUT_FILE"
df -hT --total 2>/dev/null | grep -v -E '^tmpfs|^/dev/loop|squashfs|/docker|/run|/wsl|WSL' | tee -a "$OUTPUT_FILE"

# Mounted non-zero size filesystems (Filtered)
echo -e "\n${CYAN}--- Mounted Filesystems with Non-Zero Size (excluding tmpfs/loop/squashfs/docker/run) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Shows active mounts, filtered to exclude zero-size, transient, snap, docker overlay, and run filesystems." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}findmnt -o SIZE,USE%,TARGET,SOURCE,FSTYPE,OPTIONS | grep -v \"^[[:space:]]*0\" | grep -v -E 'tmpfs|loop|squashfs|/docker|/run|/wsl|WSL' | column -t${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -o custom format. Filters zero size and common non-persistent/container mounts." | tee -a "$OUTPUT_FILE"
findmnt -o SIZE,USE%,TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null | grep -v "^[[:space:]]*0" | grep -v -E 'tmpfs|loop|squashfs|/docker|/run|/wsl|WSL' | column -t | tee -a "$OUTPUT_FILE"

# NFS Exports (Configured via /etc/exports)
echo -e "\n${CYAN}--- NFS Exports (Configured - via /etc/exports) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "This shows the raw content of the /etc/exports file." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}cat /etc/exports${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # Main configuration file for NFS exports" | tee -a "$OUTPUT_FILE"
cat /etc/exports 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "(/etc/exports not found or readable)" | tee -a "$OUTPUT_FILE"

# NFS Exports (Active via exportfs -v)
echo -e "\n${CYAN}--- NFS Exports (Active - via exportfs -v) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "This shows the directories currently being exported by the NFS server." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}sudo exportfs -v${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -v for verbose output (shows export options). Requires root." | tee -a "$OUTPUT_FILE"
sudo exportfs -v 2>/dev/null | tee -a "$OUTPUT_FILE" || echo "(Command not found or requires sudo)" | tee -a "$OUTPUT_FILE"
echo "" | tee -a "$OUTPUT_FILE"

# Active NFS Connections (ss -tuna | grep 2049)
echo -e "\n${CYAN}--- Active NFS Connections (ss) ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Shows active network connections on ports 111 (rpcbind) and 2049 (NFS, main nfsd daemon runs here)." | tee -a "$OUTPUT_FILE"
echo -e "${GREEN}ss -tuna | grep -E '111|2049|Address' | column -t${RESET}" | tee -a "$OUTPUT_FILE"
echo "   # -t tcp, -u udp, -n numeric ports, -a all sockets. Filters for ports 111 and 2049." | tee -a "$OUTPUT_FILE"
ss -tuna 2>/dev/null | grep -E '111|2049|Address' | column -t | tee -a "$OUTPUT_FILE"

# Permissions of common share locations
echo -e "\n${CYAN}--- Potential Share Location Permissions ---${RESET}" | tee -a "$OUTPUT_FILE"
echo "Checking permissions for common share parent directories. Shared directories must allow access for the client's effective UID/GID." | tee -a "$OUTPUT_FILE"
for dir in /srv/nfs /export /mnt /media /home /var/nfs; do # Added /srv/nfs and /export
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
