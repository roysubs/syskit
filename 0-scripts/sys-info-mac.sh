#!/bin/bash
# Author: Roy Wiseman 2025-03
# Cross-platform system information script (macOS & Linux)

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
elif [[ -f /etc/os-release ]]; then
    OS_TYPE="linux"
else
    echo "Unsupported operating system"
    exit 1
fi

# Function to check if running as root (only needed for Linux)
check_root_linux() {
    if [[ $OS_TYPE == "linux" ]] && [[ $EUID -ne 0 ]]; then
        echo "Elevation required; rerunning as sudo..."
        exec sudo bash "$0" "$@"
    fi
}

# Function to install missing tools
install_tools() {
    if [[ $OS_TYPE == "linux" ]]; then
        # Check for dmidecode
        if ! command -v dmidecode &>/dev/null; then
            read -p "'dmidecode' is not available. Install it? [y/N] " yn
            [[ $yn =~ ^[Yy]$ ]] && sudo apt-get update && sudo apt-get install -y dmidecode || exit 1
        fi
        
        # Check for lspci
        if ! command -v lspci &>/dev/null; then
            read -p "'lspci' (pciutils) is not available. Install it? [y/N] " yn
            [[ $yn =~ ^[Yy]$ ]] && sudo apt-get update && sudo apt-get install -y pciutils || exit 1
        fi
    fi
    # macOS uses built-in tools, no installation needed
}

# Capture timestamp
COLLECTED_AT=$(date "+%Y-%m-%d %H:%M:%S")

# Get system information based on OS
get_system_info() {
    if [[ $OS_TYPE == "macos" ]]; then
        HOSTNAME=$(hostname)
        DOMAIN=$(hostname | cut -d. -f2- 2>/dev/null)
        PRIMARY_OWNER=$(whoami)
        
        # Use system_profiler for hardware info
        MAKE="Apple"
        MODEL=$(system_profiler SPHardwareDataType | awk '/Model Name/ {$1=$2=""; print $0}' | xargs)
        SERIAL=$(system_profiler SPHardwareDataType | awk '/Serial Number/ {print $4}')
        CPU_INFO=$(sysctl -n machdep.cpu.brand_string)
        CPU_CORES=$(sysctl -n hw.physicalcpu)
        LOGICAL_CORES=$(sysctl -n hw.logicalcpu)
        NUMA="N/A (macOS)"
        
        # Memory in GB
        TOTAL_MEMORY=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
        
        # Boot time
        BOOT_UP_TIME=$(sysctl -n kern.boottime | awk '{print $4}' | sed 's/,//' | xargs -I {} date -r {} "+%Y-%m-%d %H:%M:%S")
        UPTIME=$(uptime | sed 's/.*up //' | sed 's/, [0-9]* user.*//')
        
        # Network info
        IP_ADDRESSES=$(ifconfig | awk '/inet / && !/127.0.0.1/ {print $2}' | while read ip; do echo "    $(route get "$ip" 2>/dev/null | awk '/interface:/ {print $2}'): $ip"; done)
        
        # Disk space
        DISK_SPACE=$(df -h | grep -E '^/dev/disk' | awk '{printf "    %-20s %-8s %-8s %-8s %-5s\n", $1, $2, $3, $4, $5}')
        
        # OS info
        OS_INFO="macOS $(sw_vers -productVersion) ($(sw_vers -productName))"
        
        # Display info
        DISPLAY_CARD=$(system_profiler SPDisplaysDataType | awk '/Chipset Model/ {$1=$2=""; print $0}' | xargs)
        DISPLAY_DRIVER="N/A (macOS uses built-in drivers)"
        
        # Window manager/DE
        X_SERVER=$(ps -e | grep -E 'WindowServer|Dock' | head -1)
        
        # Package manager info
        if command -v brew &>/dev/null; then
            REPOS="Homebrew installed at: $(brew --prefix)"
        else
            REPOS="No Homebrew installation found"
        fi
        
        BIOS_INFO="N/A (macOS uses EFI)"
        
    else  # Linux
        HOSTNAME=$(hostname)
        DOMAIN=$(hostname -d 2>/dev/null)
        PRIMARY_OWNER=$(whoami)
        MAKE=$(dmidecode -s system-manufacturer 2>/dev/null)
        MODEL=$(dmidecode -s system-product-name 2>/dev/null | grep -v "To Be Filled By O.E.M")
        SERIAL=$(dmidecode -s system-serial-number 2>/dev/null)
        CPU_INFO=$(lscpu | grep "Model name" | sed 's/Model name:\s*//')
        BIOS_INFO=$(dmidecode -s bios-version 2>/dev/null)
        CPU_CORES=$(lscpu | awk '/^CPU\(s\):/ {print $2}')
        NUMA=$(lscpu | awk -F: '/NUMA node0 CPU\(s\)/ {print $2}' | xargs)
        LOGICAL_CORES=$(lscpu | awk -F: '/Thread\(s\) per core/ {print $2}' | xargs)
        
        # Memory
        TOTAL_MEMORY=$(free -g | awk '/Mem:/ {print $2}')
        
        # Boot and uptime
        BOOT_UP_TIME=$(uptime -s 2>/dev/null || who -b | awk '{print $3, $4}')
        UPTIME=$(uptime -p 2>/dev/null || uptime | sed 's/.*up //' | sed 's/, [0-9]* user.*//')
        
        # Network
        IP_ADDRESSES=$(ip -o -4 addr show 2>/dev/null | awk '{print $2 ": " $4}' | sed 's/\/[0-9]*//')
        
        # Disk space
        DISK_SPACE=$(df -h | grep -E '^/dev/' | grep -v 'loop' | awk '{printf "    %-20s %-8s %-8s %-8s %-5s\n", $1, $2, $3, $4, $5}')
        
        # OS info
        OS_INFO=$(lsb_release -d 2>/dev/null | cut -f2- || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
        
        # Display
        DISPLAY_CARD=$(lspci 2>/dev/null | awk '/VGA|3D/ { found=1; print; next } /^[[:space:]]/ && found { print; next } found { exit }')
        DISPLAY_DRIVER=$(lspci -k 2>/dev/null | awk '/VGA|3D/ { found=1; next } /^[[:space:]]/ && found { print; next } found { exit }' | awk -F': ' '/Kernel driver in use/ {print $2}')
        
        # Desktop environment
        X_SERVER=$(ps -e | grep -E 'xfce|mate|gnome|kde|cinnamon|lxde|openbox|fluxbox|i3|wayland')
        
        # Repositories
        REPOS=$(apt-cache policy 2>/dev/null | grep "http" | awk '{print $2}' | sort -u || echo "apt not available")
    fi
}

# Main execution
check_root_linux
install_tools
get_system_info

# Build output
OUTPUT=$(cat <<EOF
CollectedAt:     $COLLECTED_AT
Last Boot Time:  $BOOT_UP_TIME
Uptime:          $UPTIME

Hostname:        $HOSTNAME
OS:              $OS_INFO
Domain:          ${DOMAIN:-(none)}
Primary Owner:   $PRIMARY_OWNER
Make/Model:      $MAKE $MODEL
Serial Number:   $SERIAL
Total Memory:    $TOTAL_MEMORY GB
CPU:             $CPU_INFO
BIOS/Firmware:   $BIOS_INFO
CPU Cores:       $CPU_CORES
NUMA node0:      $NUMA
Logical Cores:   $LOGICAL_CORES
Display Card:    $DISPLAY_CARD
Display Driver:  ${DISPLAY_DRIVER:-(not found)}
Window Manager:  $X_SERVER

IP Addresses:
$(echo "$IP_ADDRESSES" | sed 's/^/    /')

Disk Space:
$DISK_SPACE

Package Repos:
$(echo "$REPOS" | sed 's/^/    /')
EOF
)

# Determine output location
if [[ $OS_TYPE == "macos" ]]; then
    OUTPUT_FILE="$HOME/sys-info.txt"
else
    INVOKER_HOME=$(eval echo ~$(logname))
    OUTPUT_FILE="$INVOKER_HOME/sys-info.txt"
fi

# Print to screen and save
echo "$OUTPUT"
echo "$OUTPUT" > "$OUTPUT_FILE"
echo ""
echo "System information saved to $OUTPUT_FILE"
