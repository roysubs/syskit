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

# ── Auto-sudo elevation ───────────────────────────────────────────────────────
SUDO_MODE=false
if [[ $EUID -eq 0 ]]; then
    SUDO_MODE=true
else
    echo "[ INFO ] Not running as root — attempting to re-launch with sudo..."
    if sudo -v 2>/dev/null; then
        exec sudo "$0" "$@"
    else
        echo -e "${RED}[ FAIL ] Could not obtain sudo — cannot unmount drives.${NC}"
        exit 1
    fi
fi

# ── Step 0: Confirmation ─────────────────────────────────────────────────────
echo -e "${YELLOW}${BOLD}⚠️  WARNING: This will unmount all NTFS drives and may disconnect Samba clients!${NC}"
echo -e "Currently mounted drives:"
if command -v duf &>/dev/null; then
    duf -only-fs ntfs,ntfs3,fuseblk 2>/dev/null
else
    df -h -t ntfs -t ntfs3 -t fuseblk 2>/dev/null
fi
echo ""
echo -n "Do you want to continue? [y/N] "
read -r choice
if [[ ! "$choice" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
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
