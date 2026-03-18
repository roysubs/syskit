#!/bin/bash
# cleanup_ntfs.sh - Unmount all NTFS drives and remove their mount points

if [[ $EUID -ne 0 ]]; then
    echo "Please run as root: sudo $0"
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
        echo "OK"
        COUNT=$((COUNT + 1))
    else
        echo "FAILED (busy? try: sudo lsof $MOUNT_POINT)"
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
