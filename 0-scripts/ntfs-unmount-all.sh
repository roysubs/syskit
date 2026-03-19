#!/bin/bash
# cleanup_ntfs.sh - Unmount all NTFS drives and remove their mount points

# ── ANSI Colors ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Please run as root: sudo $0${NC}"
    exit 1
fi

function show_usage() {
    echo -e "\n── Current Disk Usage ──"
    if command -v duf &>/dev/null; then
        duf -only-fs ntfs,ntfs3,fuseblk,ext4 2>/dev/null || duf
    else
        df -h -t ntfs -t ntfs3 -t fuseblk -t ext4 2>/dev/null || df -h
    fi
}

echo "========================================"
echo " NTFS Cleanup Script"
echo "========================================"
show_usage
echo ""

# ── Step 1: Unmount all NTFS/fuseblk partitions ──────────────────────────────
echo "── Step 1: Unmounting NTFS partitions ──"

COUNT=0
while IFS= read -r line; do
    DEVICE=$(echo "$line" | awk '{print $1}')
    MOUNT_POINT=$(echo "$line" | awk '{print $2}')

    if [[ -z "$MOUNT_POINT" ]]; then continue; fi

    echo -n "[ UMOUNT ] $DEVICE from $MOUNT_POINT ... "
    if umount "$MOUNT_POINT" 2>/dev/null || umount "$DEVICE" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
        COUNT=$((COUNT + 1))
    else
        echo -e "${YELLOW}FAILED (BUSY)${NC}"
        # Detailed diagnostic:
        if command -v fuser &>/dev/null; then
             note "Processes using $MOUNT_POINT:"
             fuser -m "$MOUNT_POINT" 2>/dev/null | xargs ps -fp 2>/dev/null | sed 's/^/      /'
        fi

        echo -n "           Trying lazy unmount (umount -l) ... "
        if umount -l "$MOUNT_POINT" 2>/dev/null; then
            echo -e "${CYAN}OK (LAZY)${NC}"
            COUNT=$((COUNT + 1))
        else
            echo -e "${RED}FAILED${NC}"
            warn "Try fully closing applications or stopping Samba: sudo systemctl stop smbd"
        fi
    fi
done < <(grep -E '\s(ntfs|fuseblk|ntfs3)\s' /proc/mounts)

if [[ $COUNT -eq 0 ]]; then
    echo "[ INFO ] No active NTFS mounts found to unmount."
fi

echo ""
echo "── Step 2: Removing empty NTFS mount point directories under /mnt ──"

# Remove directories under /mnt that are now empty and aren't system dirs
for dir in /mnt/*/; do
    [[ -d "$dir" ]] || continue
    if mountpoint -q "$dir"; then
        echo "[ SKIP ] $dir is still a mountpoint, leaving it"
    elif [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
        echo -n "[ RMDIR ] $dir ... "
        rmdir "$dir" && echo "OK" || echo "FAILED"
    else
        echo "[ SKIP ] $dir is not empty, leaving it"
    fi
done

echo ""
echo "── Step 3: Current state ──"
show_usage
echo ""
