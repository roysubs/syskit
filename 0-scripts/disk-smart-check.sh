#!/usr/bin/env bash

# ==============================================================================
# UNIVERSAL DISK HEALTH SCOUT
# Optimized for: macOS (M1/M2/M3/M4), openSUSE, Debian/Mint, Arch
# ==============================================================================

set -e
DATE=$(date +%Y%m%d)
OUT_DIR="/tmp/disks"
mkdir -p "$OUT_DIR"

# --- Style ---
GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3); RED=$(tput setaf 1); BLUE=$(tput setaf 4); NC=$(tput sgr0)
info() { printf "${BLUE}ℹ %s${NC}\n" "$1"; }
success() { printf "${GREEN}✓ %s${NC}\n" "$1"; }
warn() { printf "${YELLOW}⚠ %s${NC}\n" "$1"; }

# ==============================================================================
# STEP 1: ENVIRONMENT DETECTION
# ==============================================================================

detect_env() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        PLATFORM="macos"
        DISTRO="macOS"
    elif [ -f /etc/os-release ]; then
        PLATFORM="linux"
        # Source the file to get the ID variable (e.g., opensuse-tumbleweed, debian, etc.)
        DISTRO=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    else
        PLATFORM="linux"
        DISTRO="generic"
    fi
    info "Environment: $PLATFORM ($DISTRO)"
}

# ==============================================================================
# STEP 2: IDEMPOTENT DEPENDENCY CHECK
# ==============================================================================

install_deps() {
    if command -v smartctl &> /dev/null; then
        success "smartmontools is present."
        return
    fi

    warn "smartmontools missing. Attempting install..."
    if [[ "$PLATFORM" == "macos" ]]; then
        brew install smartmontools
    elif [[ "$PLATFORM" == "linux" ]]; then
        case "$DISTRO" in
            opensuse*|suse*) sudo zypper install -y smartmontools ;;
            debian|ubuntu|mint) sudo apt-get update && sudo apt-get install -y smartmontools ;;
            arch|manjaro) sudo pacman -S --noconfirm smartmontools ;;
            *) info "Please install 'smartmontools' manually via your package manager." ;;
        esac
    fi
}

# ==============================================================================
# STEP 3: SMART SCANNER
# ==============================================================================

scan_disks() {
    # 1. Get List of External Disks
    if [[ "$PLATFORM" == "macos" ]]; then
        DISKS=$(diskutil list external physical | grep "/dev/disk" | awk '{print $1}')
    else
        # Linux: Find USB storage devices specifically
        DISKS=$(lsblk -dno NAME,TRAN | grep "usb" | awk '{print "/dev/"$1}')
    fi

    if [ -z "$DISKS" ]; then
        warn "No external disks detected."
        return
    fi

    for DISK in $DISKS; do
        # Target the RAW node for macOS performance/bypass
        if [[ "$PLATFORM" == "macos" ]]; then
            TARGET_NODE="/dev/r${DISK#*/dev/}"
        else
            TARGET_NODE="$DISK"
        fi

        info "Scanning $DISK..."

        # Shotgun approach for bridge chips
        RAW_INFO=""
        for driver in "auto" "sat" "usbjmicron"; do
            set +e
            TMP=$(sudo smartctl -a -d "$driver" "$TARGET_NODE" 2>/dev/null)
            set -e
            if echo "$TMP" | grep -q "Serial Number:"; then
                RAW_INFO="$TMP"
                success "Data captured via $driver driver."
                break
            fi
        done

        # --- Report Generation ---
        if [ -n "$RAW_INFO" ]; then
            # Extract Vitals
            MODEL=$(echo "$RAW_INFO" | grep -iE "Device Model:|Model Family:" | head -n1 | awk -F': ' '{print $2}' | xargs | tr ' ' '_')
            CAP=$(echo "$RAW_INFO" | grep "User Capacity:" | awk -F'[' '{print $2}' | awk -F']' '{print $1}' | awk '{print $1$2}' | tr ' ' '_')
            HOURS=$(echo "$RAW_INFO" | awk '$1 == 9 {print $10}')
            REALLOC=$(echo "$RAW_INFO" | awk '$1 == 5 {print $10}')
            PENDING=$(echo "$RAW_INFO" | awk '$1 == 197 {print $10}')

            # Grade Health
            STATUS="GOOD"
            if [[ ${REALLOC:-0} -gt 0 ]] || [[ ${PENDING:-0} -gt 0 ]]; then STATUS="BAD"; fi
            if [[ ${HOURS:-0} -gt 40000 ]]; then [[ "$STATUS" == "GOOD" ]] && STATUS="OK"; fi
            
            REPORT_NAME="${CAP}-${MODEL}-${STATUS}-${DATE}.txt"
        else
            REPORT_NAME="UNKNOWN-$(basename "$DISK")-${DATE}.txt"
            STATUS="UNKNOWN"
        fi

        # Write result to file
        {
            echo "PLATFORM: $PLATFORM ($DISTRO)"
            echo "DATE:     $DATE"
            echo "DISK:     $DISK"
            echo "STATUS:   $STATUS"
            echo "--------------------------------"
            if [ "$STATUS" != "UNKNOWN" ]; then
                echo "Hours: $HOURS | Realloc: $REALLOC | Pending: $PENDING"
                echo "$RAW_INFO" | grep -E "ID#|5 Reallocated|9 Power_On|197 Current_Pending"
            else
                echo "SMART Access Blocked. Check Sharkoon power or cables."
                [[ "$PLATFORM" == "macos" ]] && diskutil info "$DISK" | grep "Media Name" || lsblk -no MODEL "$DISK"
            fi
        } > "$OUT_DIR/$REPORT_NAME"
        
        info "Report: $OUT_DIR/$REPORT_NAME"
    done
}

# --- Execution ---
detect_env
install_deps
scan_disks

print_header() { printf "\n${BLUE}=== %s ===${NC}\n" "$1"; }
print_header "COMPLETE"
ls -lh "$OUT_DIR" | grep "$DATE"
