#!/bin/bash
# -------------------------------------------------------------------------
# PRESERVE-DISKS-POLICY: Disk Health & Power Manager
# -------------------------------------------------------------------------

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# ── Auto-sudo elevation ───────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[0;34m[ INFO ] Not running as root — attempting to re-launch with sudo...\033[0m"
    if sudo -v 2>/dev/null; then
        exec sudo "$0" "$@"
    else
        echo -e "\033[0;31mError: This script must be run as root/sudo to access disk parameters.\033[0m"
        exit 1
    fi
fi

# Ensure dependencies
for cmd in hdparm smartctl lsblk; do
    if ! command -v $cmd &>/dev/null; then
        echo "Installing $cmd..."
        apt-get update -qq && apt-get install -y smartmontools hdparm > /dev/null
    fi
done

# --- Functions ---

function print_legend() {
    echo -e "${BLUE}${BOLD}--- SMART Metric Guide ---${NC}"
    echo -e " ${BOLD}Reallocated Sectors${NC} : Bad sectors moved to spare area.        ${GREEN}Healthy: 0${NC}"
    echo -e " ${BOLD}Pending Sectors${NC}     : Weak sectors awaiting remap.            ${GREEN}Healthy: 0${NC}"
    echo -e " ${BOLD}Start/Stop Count${NC}    : Total times drive spun up/down.         ${NC}"
    echo -e " ${BOLD}Load Cycle Count${NC}    : Times heads moved to park area.         ${YELLOW}Limit: 300k+${NC}"
    echo -e " ${BOLD}Temperature${NC}         : Heat.                                   ${GREEN}Range: 20-45°C${NC}"
    echo -e "------------------------------------------------------------"
}

function get_smart_val() {
    local disk=$1
    local attr=$2
    # Search for attribute ID at start of line, grab the 10th column (RAW_VALUE), strip extra Seagate formatting
    local val=$(smartctl -A "$disk" 2>/dev/null | awk -v id="$attr" '$1 == id {print $10}')
    echo "$val" | sed 's/h+.*$//' | sed 's/[^0-9]//g'
}

function check_disk() {
    local d=$1
    local type_label="Unknown"
    
    # Improved rotation detection: lsblk ROTA is often wrong behind SATA controllers
    if smartctl -i "$d" 2>/dev/null | grep -qi "Solid State"; then
        type_label="SSD (Flash)"
    elif smartctl -i "$d" 2>/dev/null | grep -qi "Rotation Rate"; then
        type_label="HDD (Mechanical)"
    else
        # Fallback to lsblk
        local rota=$(lsblk -dno ROTA "$d" 2>/dev/null)
        if [[ "$rota" == "1" ]]; then type_label="HDD (Mechanical)"; else type_label="SSD (Flash)"; fi
    fi
    
    local model=$(lsblk -dno MODEL "$d" 2>/dev/null)
    local state=$(hdparm -C "$d" 2>/dev/null | grep "state" | cut -d: -f2 | xargs || echo "Unknown")
    local apm=$(hdparm -B "$d" 2>/dev/null | grep "APM_level" | cut -d= -f2 | xargs || echo "N/A")

    echo -e "${BOLD}Drive:${NC} $d (${BLUE}$type_label${NC})"
    echo -e "  Model       : $model"
    echo -e "  Power State : $state"
    echo -e "  APM Level   : $apm (254/255=Max Perf, 1-127=Spin-down allowed)"
    
    # SMART Metrics
    local realloc=$(get_smart_val "$d" 5)
    local pending=$(get_smart_val "$d" 197)
    local uncorr=$(get_smart_val "$d" 198)
    local load=$(get_smart_val "$d" 193)
    local startstop=$(get_smart_val "$d" 4)
    local temp=$(get_smart_val "$d" 194)
    [[ -z "$temp" ]] && temp=$(get_smart_val "$d" 190)
    local hours=$(get_smart_val "$d" 9)

    echo -n "  Reallocated : "
    if [[ -z "$realloc" ]]; then echo "N/A"; elif [[ "$realloc" -eq 0 ]]; then echo -e "${GREEN}0 (OK)${NC}"; else echo -e "${RED}$realloc (WARNING)${NC}"; fi
    
    echo -n "  Pending     : "
    if [[ -z "$pending" ]]; then echo "N/A"; elif [[ "$pending" -eq 0 ]]; then echo -e "${GREEN}0 (OK)${NC}"; else echo -e "${RED}$pending (CRITICAL)${NC}"; fi

    echo -n "  Uncorrect   : "
    if [[ -z "$uncorr" || "$uncorr" -eq 0 ]]; then echo -e "${GREEN}0 (OK)${NC}"; else echo -e "${RED}$uncorr (CRITICAL)${NC}"; fi

    echo -e "  Spin cycles : ${startstop:-N/A} (Start/Stop Count)"
    echo -e "  Load Cycles : ${load:-N/A}"
    echo -e "  Temp / Hrs  : ${temp:-N/A}°C / ${hours:-N/A}h"
    echo ""
}

# --- Main Logic ---

echo -e "============================================================"
echo -e "   Disk Spin-Down Policy & Health Monitor"
echo -e "============================================================"

# Handle Switches
if [[ "$1" == "--low" ]]; then
    echo -e "${YELLOW}Applying LOW POWER policy... (30 min spin-down)${NC}"
    HDD_LIST=$(lsblk -dno NAME,ROTA | grep " 1$" | awk '{print "/dev/"$1}' | xargs)
    if [[ -n "$HDD_LIST" ]]; then
        hdparm -S 241 $HDD_LIST
        hdparm -B 127 $HDD_LIST
        echo -e "${GREEN}Applied to: $HDD_LIST${NC}"
    else
        echo "No mechanical HDDs found."
    fi
    exit 0
elif [[ "$1" == "--healer" ]]; then
    echo -e "${BLUE}${BOLD}Applying HEALER policy... (Optimal Health & Minimal Thrashing)${NC}"
    
    # 1. Kernel Writeback Optimization (Batch writes in RAM to let disks sleep)
    echo -e "  [1/3] Optimizing Kernel Write Caches..."
    sysctl -w vm.dirty_writeback_centisecs=6000 > /dev/null  # Check every 60s
    sysctl -w vm.dirty_expire_centisecs=12000 > /dev/null    # Keep data in RAM up to 120s
    
    # 2. I/O Scheduler Optimization
    echo -e "  [2/3] Tuning I/O Schedulers for latency..."
    for d in $(lsblk -dno NAME,ROTA | grep " 1$" | awk '{print $1}'); do
        if [ -e "/sys/block/$d/queue/scheduler" ]; then
            echo bfq > /sys/block/$d/queue/scheduler 2>/dev/null || echo mq-deadline > /sys/block/$d/queue/scheduler
        fi
    done

    # 3. Spin-down (Gentle 1 hour)
    echo -e "  [3/3] Setting 1-hour gentle spin-down..."
    HDD_LIST=$(lsblk -dno NAME,ROTA | grep " 1$" | awk '{print "/dev/"$1}' | xargs)
    if [[ -n "$HDD_LIST" ]]; then
        hdparm -S 242 $HDD_LIST  # 242 = 1 hour
        hdparm -B 128 $HDD_LIST  # 128 = No spin-down via APM (let hdparm -S handle it)
    fi

    echo -e "${GREEN}System is now in 'Healthy Storage' mode.${NC}"
    exit 0
elif [[ "$1" == "--default" ]]; then
    echo -e "${YELLOW}Applying DEFAULT Linux policy... (Spindown disabled/OS default)${NC}"
    HDD_LIST=$(lsblk -dno NAME,ROTA | grep " 1$" | awk '{print "/dev/"$1}' | xargs)
    if [[ -n "$HDD_LIST" ]]; then
        hdparm -S 0 $HDD_LIST
        hdparm -B 254 $HDD_LIST
        echo -e "${GREEN}Applied to: $HDD_LIST${NC}"
    else
        echo "No mechanical HDDs found."
    fi
    exit 0
fi

# Default View (Audit Only)
print_legend

for d in $(lsblk -dno NAME | grep -E '^sd|^nvme' | awk '{print "/dev/"$1}'); do
    [[ -e "$d" ]] && check_disk "$d"
done
echo -e "============================================================"
echo -e "${BOLD}Notes:${NC}"
echo -e "Note: If an HDD says 'standby', it is currently saving you money."
echo -e "If it stays 'active/idle' forever, an app is likely poking it."
echo -e "============================================================"
echo -e ""
echo -e "============================================================"
echo -e "${BOLD}Available Switches:${NC}"
echo -e "  --healer  : (Recommended) Max health. Optimal Caching + I/O Scheduling + 1hr spin-down."
echo -e "  --low     : Spin down mechanical disks after 30 mins inactivity."
echo -e "  --default : Disable auto spin-down (Max performance/availability)."
echo -e "============================================================"

