#!/usr/bin/env bash

# ==============================================================================
# UNIVERSAL DISK HEALTH SCOUT
# Optimized for: macOS (M1/M2/M3/M4), openSUSE, Debian/Mint, Arch, RHEL
# ==============================================================================

set -uo pipefail
DATE=$(date +%Y%m%d)
OUT_DIR="/tmp/disks"
mkdir -p "$OUT_DIR"

# --- Style ---
GREEN=$(tput setaf 2 2>/dev/null || echo ""); YELLOW=$(tput setaf 3 2>/dev/null || echo ""); RED=$(tput setaf 1 2>/dev/null || echo ""); BLUE=$(tput setaf 4 2>/dev/null || echo ""); NC=$(tput sgr0 2>/dev/null || echo "")
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
        brew install smartmontools 2>/dev/null || true
    elif [[ "$PLATFORM" == "linux" ]]; then
        if command -v zypper &>/dev/null; then
            sudo zypper --non-interactive install --auto-agree-with-licenses -y smartmontools
        elif command -v apt-get &>/dev/null; then
            sudo apt-get update && sudo apt-get install -y smartmontools
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y smartmontools
        elif command -v pacman &>/dev/null; then
            sudo pacman -Sy --noconfirm smartmontools
        else
            info "Please install 'smartmontools' manually via your package manager."
        fi
    fi
}

# ==============================================================================
# STEP 3: SMART SCANNER
# ==============================================================================

scan_disks() {
    if [[ "$PLATFORM" == "macos" ]]; then
        DISKS=$(diskutil list physical | grep "/dev/disk" | awk '{print $1}')
    else
        # Linux: Scan all physical disk block devices (SATA, NVMe, USB)
        DISKS=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk" {print "/dev/"$1}')
    fi

    if [ -z "$DISKS" ]; then
        warn "No physical disks detected."
        return
    fi

    for DISK in $DISKS; do
        if [[ "$PLATFORM" == "macos" ]]; then
            TARGET_NODE="/dev/r${DISK#*/dev/}"
        else
            TARGET_NODE="$DISK"
        fi

        info "Scanning $DISK..."

        RAW_INFO=""
        for driver in "auto" "sat" "nvme" "usbjmicron"; do
            TMP=$(sudo smartctl -a -d "$driver" "$TARGET_NODE" 2>/dev/null || true)
            if echo "$TMP" | grep -qE "Serial Number:|Device Model:|Model Number:"; then
                RAW_INFO="$TMP"
                success "Data captured for $DISK via $driver driver."
                break
            fi
        done

        if [ -n "$RAW_INFO" ]; then
            MODEL=$(echo "$RAW_INFO" | grep -iE "Device Model:|Model Number:|Model Family:" | head -n1 | awk -F': ' '{print $2}' | xargs | tr ' ' '_')
            CAP=$(echo "$RAW_INFO" | grep -iE "User Capacity:|Total Capacity:" | head -n1 | awk -F'[' '{print $2}' | awk -F']' '{print $1}' | awk '{print $1$2}' | tr ' ' '_' || echo "UnknownCap")
            HOURS=$(echo "$RAW_INFO" | awk '$1 == 9 {print $10}' | head -n1)
            REALLOC=$(echo "$RAW_INFO" | awk '$1 == 5 {print $10}' | head -n1)
            PENDING=$(echo "$RAW_INFO" | awk '$1 == 197 {print $10}' | head -n1)

            STATUS="GOOD"
            if [[ -n "$REALLOC" && ${REALLOC:-0} -gt 0 ]] || [[ -n "$PENDING" && ${PENDING:-0} -gt 0 ]]; then 
                STATUS="BAD"
            fi
            if echo "$RAW_INFO" | grep -iq "SMART overall-health self-assessment test result: FAILED"; then
                STATUS="FAILED"
            fi

            REPORT_NAME="${CAP:-UnknownCap}-${MODEL:-UnknownModel}-${STATUS}-${DATE}.txt"
        else
            REPORT_NAME="UNKNOWN-$(basename "$DISK")-${DATE}.txt"
            STATUS="UNKNOWN"
        fi

        {
            echo "PLATFORM: $PLATFORM ($DISTRO)"
            echo "DATE:     $DATE"
            echo "DISK:     $DISK"
            echo "STATUS:   $STATUS"
            echo "--------------------------------"
            if [ "$STATUS" != "UNKNOWN" ]; then
                echo "Hours: ${HOURS:-N/A} | Realloc: ${REALLOC:-0} | Pending: ${PENDING:-0}"
                echo "$RAW_INFO" | grep -E "ID#|5 Reallocated|9 Power_On|197 Current_Pending|SMART overall-health|Percentage Used" || true
                echo "--------------------------------"
                echo "$RAW_INFO"
            else
                echo "SMART Access Blocked or Unsupported for $DISK."
                [[ "$PLATFORM" == "macos" ]] && diskutil info "$DISK" 2>/dev/null | grep "Media Name" || lsblk -no MODEL "$DISK" 2>/dev/null || true
            fi
        } > "$OUT_DIR/$REPORT_NAME"

        info "Report generated: $OUT_DIR/$REPORT_NAME"
    done
}

# --- Execution ---
detect_env
install_deps
scan_disks

printf "\n${BLUE}=== COMPLETE ===${NC}\n"
ls -lh "$OUT_DIR" 2>/dev/null | grep "$DATE" || true
