#!/bin/bash
# -------------------------------------------------------------------------
# PRESERVE-CPU-POLICY: CPU Power & Policy Manager
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
    echo -e "${BLUE}[ INFO ] Not running as root — attempting to re-launch with sudo...${NC}"
    if sudo -v 2>/dev/null; then
        exec sudo "$0" "$@"
    else
        echo -e "${RED}Error: This script must be run as root/sudo to access CPU power parameters.${NC}"
        exit 1
    fi
fi

# Ensure dependencies
PKGS="cpufrequtils linux-cpupower powertop"
for p in $PKGS; do
    if ! dpkg -l | grep -q "^ii  $p"; then
        echo "Installing $p..."
        apt-get update -qq && apt-get install -y $p > /dev/null
    fi
done

# --- Functions ---

function get_cpu_info() {
    echo -e "${BLUE}${BOLD}--- CPU Power Audit ---${NC}"
    local model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    local cores=$(nproc)
    echo -e "${BOLD}Model       :${NC} $model ($cores cores)"
    
    # Driver and Governor
    local driver=$(cpupower frequency-info -d | tail -1)
    local gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "N/A")
    echo -e "${BOLD}Driver      :${NC} ${driver:-N/A}"
    echo -e "${BOLD}Governor    :${NC} ${gov:-N/A}"
    
    # Frequencies
    local cur_freq=$(grep "cpu MHz" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    local min_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null)
    local max_freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null)
    
    # Convert kHz to MHz for min/max
    if [[ -n "$min_freq" ]]; then min_freq=$((min_freq / 1000)); fi
    if [[ -n "$max_freq" ]]; then max_freq=$((max_freq / 1000)); fi

    echo -e "${BOLD}Frequency   :${NC} ${cur_freq:-N/A} MHz (Range: ${min_freq:-N/A}-${max_freq:-N/A} MHz)"
    
    # C-States (Power Saving Idle States)
    echo -e "${BOLD}C-States    :${NC}"
    for state in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do
        if [ -f "$state" ]; then
            local sname=$(cat "$state")
            local desc=$(cat "${state/name/desc}")
            echo -e "  - $sname: $desc"
        fi
    done
    echo "------------------------------------------------------------"
}

function set_policy() {
    local mode=$1
    echo -e "${YELLOW}Applying $mode policy...${NC}"
    
    case "$mode" in
        "low")
            # Set governor to powersave (locks to lowest freq)
            cpupower frequency-set -g powersave > /dev/null
            echo -e "${GREEN}Governor set to 'powersave' (Lowest frequency lock).${NC}"
            ;;
        "default")
            # Set governor to ondemand or conservative (balanced)
            if cpupower frequency-info -g | grep -q "ondemand"; then
                cpupower frequency-set -g ondemand > /dev/null
                echo -e "${GREEN}Governor set to 'ondemand' (Balanced/Default).${NC}"
            else
                cpupower frequency-set -g conservative > /dev/null
                echo -e "${GREEN}Governor set to 'conservative' (Balanced/Default).${NC}"
            fi
            ;;
        "healer")
            # HEALER Mode: Best for quiet servers
            echo -e "  [1/2] Setting conservative governor..."
            cpupower frequency-set -g conservative > /dev/null
            
            # Use Powertop auto-tune for other kernel savings
            echo -e "  [2/2] Running Powertop auto-tune (Optimizing pci/usb/controller power)..."
            powertop --auto-tune > /dev/null 2>&1
            
            echo -e "${GREEN}System is now in 'Healthy CPU' mode (Responsive but frugal).${NC}"
            ;;
    esac
}

# --- Main Logic ---

echo -e "============================================================"
echo -e "   CPU Power & Policy Manager"
echo -e "============================================================"

# Handle Switches
if [[ "$1" == "--low" ]]; then
    set_policy "low"
    exit 0
elif [[ "$1" == "--default" ]]; then
    set_policy "default"
    exit 0
elif [[ "$1" == "--healer" ]]; then
    set_policy "healer"
    exit 0
fi

# Audit Mode
get_cpu_info

echo -e "${BOLD}Available Switches:${NC}"
echo -e "  --healer  : Optimal for servers. Balanced frequency + Powertop auto-optimizations."
echo -e "  --low     : Max power savings. Locks CPU to lowest possible frequency."
echo -e "  --default : Standard Linux balanced performance."
echo -e "============================================================"
echo -e "${BLUE}Note: None of these settings will affect network reactivity.${NC}"
echo -e "${BLUE}The server will still wake up instantly to service network calls.${NC}"
echo -e "============================================================"
