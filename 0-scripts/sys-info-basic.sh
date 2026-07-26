#!/usr/bin/env bash
# Author: Roy Wiseman 2025-03 (Updated for Multi-Distro / openSUSE Compatibility)
set -euo pipefail

# Ensure we are running as root
if [[ $EUID -ne 0 ]]; then
    echo "Elevation required; rerunning as sudo..."
    exec sudo bash "$0" "$@"
    exit $?
fi

pkg_install() {
    local package_name="$1"
    if command -v zypper &>/dev/null; then
        zypper refresh && zypper install -y "$package_name"
    elif command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y "$package_name"
    elif command -v dnf &>/dev/null; then
        dnf install -y "$package_name"
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm "$package_name"
    elif command -v apk &>/dev/null; then
        apk add "$package_name"
    else
        echo "Error: Could not detect supported package manager." >&2
        return 1
    fi
}

install_if_missing() {
    local cmd="$1"
    local pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        echo "Installing $pkg for $cmd..."
        pkg_install "$pkg" || true
    fi
}

install_if_missing "dmidecode" "dmidecode"
install_if_missing "lspci" "pciutils"
install_if_missing "free" "procps"
install_if_missing "lscpu" "util-linux"

# Capture timestamp
COLLECTED_AT=$(date "+%Y-%m-%d %H:%M:%S")

# Boot time & Uptime helpers
get_last_boot() {
    if uptime -s &>/dev/null; then
        uptime -s
    elif who -b 2>/dev/null | grep -q "boot"; then
        who -b 2>/dev/null | awk '{print $3, $4}'
    elif [[ -f /proc/uptime ]]; then
        date -d "@$(awk -v b="$(date +%s)" -v u="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN{print int(b-u)}')" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'Unknown'
    else
        echo 'Unknown'
    fi
}

get_uptime() {
    if uptime -p &>/dev/null; then
        uptime -p | sed 's/up //g'
    elif [[ -f /proc/uptime ]]; then
        awk '{u=$1; d=int(u/86400); h=int((u%86400)/3600); m=int((u%3600)/60); 
              if (d > 0) printf "%d days, %d hours, %d minutes\n", d, h, m;
              else if (h > 0) printf "%d hours, %d minutes\n", h, m;
              else printf "%d minutes\n", m}' /proc/uptime
    else
        uptime 2>/dev/null | sed -E 's/.*up +([^,]+),.*/\1/' || echo 'Unknown'
    fi
}

BOOT_UP_TIME=$(get_last_boot)
UPTIME=$(get_uptime)

# System info
HOSTNAME=$(hostname 2>/dev/null || uname -n)
DOMAIN=$(hostname -d 2>/dev/null || echo "(none)")
PRIMARY_OWNER=${SUDO_USER:-$(whoami)}
MAKE=$(dmidecode -s system-manufacturer 2>/dev/null | grep -vE "To Be Filled|Not Applicable|Default string" || echo "")
MODEL=$(dmidecode -s system-product-name 2>/dev/null | grep -vE "To Be Filled|Not Applicable|Default string" || echo "")
SERIAL=$(dmidecode -s system-serial-number 2>/dev/null | grep -vE "Not Applicable|None|To Be Filled|Default string" || echo "")
CPU_INFO=$(lscpu 2>/dev/null | awk -F: '/Model name/ {print $2}' | xargs || echo "Unknown")
BIOS_INFO=$(dmidecode -s bios-version 2>/dev/null || echo "Unknown")
CPU_CORES=$(lscpu 2>/dev/null | awk -F: '/Core\(s\) per socket/ {print $2}' | xargs || echo "1")
NUMA=$(lscpu 2>/dev/null | awk -F: '/NUMA node\(s\)/ {print $2}' | xargs || echo "N/A")
LOGICAL_CORES=$(nproc 2>/dev/null || echo "1")

# Memory
TOTAL_MEMORY=$(free -h 2>/dev/null | awk '/Mem:/ {print $2}' || echo "Unknown")

# OS info
if command -v lsb_release &>/dev/null; then
    OS_INFO=$(lsb_release -d 2>/dev/null | cut -f2-)
elif [[ -f /etc/os-release ]]; then
    OS_INFO=$( . /etc/os-release && echo "${PRETTY_NAME:-$NAME}" )
else
    OS_INFO=$(uname -rs)
fi

# Network
IP_ADDRESSES=$(ip -o -4 addr show 2>/dev/null | awk '{print $2 ": " $4}' | sed 's/\/[0-9]*//' || echo "N/A")

# Storage
DISK_SPACE=$(df -h 2>/dev/null | grep -E '^/dev/' | grep -v 'loop' | awk '{printf "    %-15s %-6s %-6s %-6s %-5s %s\n", $1, $2, $3, $4, $5, $6}' || echo "N/A")

# Display
DISPLAY_CARD=$(lspci 2>/dev/null | awk '/VGA|3D/ {print $0}' | head -n1 || echo "Unknown")
DISPLAY_DRIVER=$(lspci -k 2>/dev/null | awk '/VGA|3D/,/Kernel driver in use/ {if (/Kernel driver in use/) print $5}' | head -n1 || echo "not found")
X_SERVER=$(ps -e 2>/dev/null | grep -E 'xfce|mate|gnome|kde|cinnamon|lxde|openbox|fluxbox|i3|WindowServer' | head -n1 || echo "(none)")

# Repositories
if command -v zypper &>/dev/null; then
    REPOS=$(zypper lr -u 2>/dev/null | awk -F'|' 'NR>4 && NF>=6 {gsub(/^[ \t]+|[ \t]+$/, "", $3); gsub(/^[ \t]+|[ \t]+$/, "", $7); printf "%-25s %s\n", $3, $7}' || echo "None")
elif command -v apt-cache &>/dev/null; then
    REPOS=$(apt-cache policy 2>/dev/null | grep "http" | awk '{print $2}' | sort -u || echo "None")
else
    REPOS="Package manager repo listing not configured for this OS"
fi

# Output formatting
OUTPUT=$(cat <<EOF
CollectedAt:     $COLLECTED_AT
Last Boot Time:  $BOOT_UP_TIME
Uptime:          $UPTIME

Hostname:        $HOSTNAME
OS:              $OS_INFO
Domain:          $DOMAIN
Primary Owner:   $PRIMARY_OWNER
Make/Model:      $MAKE $MODEL
Serial Number:   $SERIAL
Total Memory:    $TOTAL_MEMORY
CPU:             $CPU_INFO
BIOS:            $BIOS_INFO
CPU Cores:       $CPU_CORES
NUMA Node(s):    $NUMA
Logical Cores:   $LOGICAL_CORES
Display Card:    $DISPLAY_CARD
Display Driver:  $DISPLAY_DRIVER
X Server:        $X_SERVER

IP Addresses:
$(echo "$IP_ADDRESSES" | sed 's/^/    /')

Disk Space:
$DISK_SPACE

Repositories:
$(echo "$REPOS" | sed 's/^/    /')
EOF
)

# Home directory detection
INVOKER_USER=${SUDO_USER:-$(logname 2>/dev/null || echo "root")}
INVOKER_HOME=$(eval echo "~$INVOKER_USER")

# Output to terminal & file
echo "$OUTPUT"
echo "$OUTPUT" > "$INVOKER_HOME/sys-info.txt"
echo "System information saved to $INVOKER_HOME/sys-info.txt"
