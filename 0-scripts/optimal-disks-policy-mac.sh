#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# -------------------------------------------------------------------------
# OPTIMAL-DISKS-POLICY (macOS): Disk SMART Health Reporting
# -------------------------------------------------------------------------
# macOS has no user-tunable disk power/scheduler policy (unlike Linux's hdparm/
# I/O-scheduler knobs - the OS manages that automatically), so this script covers
# what IS meaningfully portable: SMART health reporting.
#
# Uses `diskutil info` (built-in, no extra install, no sudo needed) rather than
# smartctl/smartmontools: on Apple Silicon, smartctl has known gaps reading the
# proprietary internal NVMe controller, while diskutil's own "SMART Status" field
# talks to it directly through Apple's DiskArbitration framework and just works.

if [[ "$(uname)" != "Darwin" ]]; then
    echo "This is the macOS-specific disk health script. Use optimal-disks-policy.sh on Linux." >&2
    exit 1
fi

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}--- Disk SMART Health Audit (macOS) ---${NC}"
echo

found_any=false
# `diskutil list physical` lists only real physical disks, not synthesized APFS
# containers/volumes layered on top of them (which would otherwise show up as
# separate /dev/diskN entries and get checked redundantly).
while read -r disk; do
    found_any=true

    info=$(diskutil info "$disk" 2>/dev/null)
    model=$(echo "$info" | awk -F': *' '/Device \/ Media Name/{print $2; exit}')
    smart=$(echo "$info" | awk -F': *' '/SMART Status/{print $2; exit}')

    echo -e "${BOLD}$disk${NC}  ${model:-unknown model}"
    if [[ "$smart" == "Verified" ]]; then
        echo -e "  SMART Status: ${GREEN}$smart${NC}"
    elif [[ -n "$smart" ]]; then
        echo -e "  SMART Status: ${RED}$smart${NC}"
    else
        echo -e "  SMART Status: ${YELLOW}Not Available (common for external/USB enclosures)${NC}"
    fi
    echo
done < <(diskutil list physical 2>/dev/null | grep -oE '^/dev/disk[0-9]+')

if [[ "$found_any" == "false" ]]; then
    echo -e "${YELLOW}No physical disks found.${NC}"
fi

echo "Done."
