#!/bin/bash
# mount_ntfs_fixed.sh - Discover, mount all NTFS partitions, and share via Samba
# - Auto-elevates to sudo if not already root
# - Without sudo: runs in diagnostic/read-only mode
# - With sudo: full mount + share setup + SMART info
# Idempotent: safe to re-run, skips already completed steps.

# ── Auto-sudo elevation ───────────────────────────────────────────────────────
SUDO_MODE=false
if [[ $EUID -eq 0 ]]; then
    SUDO_MODE=true
else
    echo "[ INFO ] Not running as root — attempting to re-launch with sudo..."
    if sudo -v 2>/dev/null; then
        exec sudo "$0" "$@"
    else
        echo "[ INFO ] Could not obtain sudo — running in diagnostic mode only."
        echo ""
    fi
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
section() { echo ""; echo "── $* ──"; }
info()    { echo "[ INFO ] $*"; }
ok()      { echo "[ OK   ] $*"; }
skip()    { echo "[ SKIP ] $*"; }
warn()    { echo "[ WARN ] $*"; }
fail()    { echo "[ FAIL ] $*"; }
note()    { echo "[ NOTE ] $*"; }

SMB_CONF="/etc/samba/smb.conf"

smb_share_exists() {
    grep -qsi "^\[${1}\]" "$SMB_CONF"
}

add_smb_share() {
    local share_name="$1"
    local share_path="$2"
    local smb_user="$3"
    cat >> "$SMB_CONF" << EOF

[$share_name]
   comment = Auto-shared NTFS partition
   path = $share_path
   browseable = yes
   read only = no
   writable = yes
   guest ok = no
   valid users = $smb_user
   create mask = 0664
   directory mask = 0775
EOF
    ok "Added SMB share [$share_name] -> $share_path (user: $smb_user)"
}

# ── SMART summary for a single disk ──────────────────────────────────────────
print_smart_summary() {
    local disk="$1"
    if ! command -v smartctl &>/dev/null; then
        note "smartmontools not installed — skipping SMART info"
        return
    fi

    local smart_out
    smart_out=$(smartctl -A -H "$disk" 2>/dev/null)
    local smart_health
    smart_health=$(echo "$smart_out" | grep -i "overall-health\|test result" | awk -F: '{print $2}' | tr -d ' ')
    local temp
    temp=$(echo "$smart_out" | awk '/Temperature_Celsius|Airflow_Temperature/{print $10; exit}')
    local hours
    hours=$(echo "$smart_out" | awk '/Power_On_Hours/{print $10; exit}')
    local reallocated
    reallocated=$(echo "$smart_out" | awk '/Reallocated_Sector/{print $10; exit}')
    local pending
    pending=$(echo "$smart_out" | awk '/Current_Pending_Sector/{print $10; exit}')

    # Format hours into days
    local hours_display="n/a"
    if [[ -n "$hours" && "$hours" =~ ^[0-9]+$ ]]; then
        hours_display="${hours}h ($(( hours / 24 ))d)"
    fi

    [[ -z "$smart_health" ]] && smart_health="n/a"
    [[ -z "$temp" ]]         && temp="n/a"
    [[ -z "$reallocated" ]]  && reallocated="n/a"
    [[ -z "$pending" ]]      && pending="n/a"

    # Health colouring via symbols
    local health_str="$smart_health"
    if [[ "$smart_health" == "PASSED" ]]; then
        health_str="PASSED ✓"
    elif [[ "$smart_health" == "FAILED"* ]]; then
        health_str="FAILED ✗  <-- ATTENTION: drive may be failing!"
    fi

    echo "    Health      : $health_str"
    echo "    Temperature : ${temp}°C"
    echo "    Power-on    : $hours_display"
    echo "    Reallocated : $reallocated sectors"
    echo "    Pending     : $pending sectors"

    if [[ "$reallocated" =~ ^[0-9]+$ && "$reallocated" -gt 0 ]]; then
        warn "$disk has $reallocated reallocated sectors — monitor this drive closely!"
    fi
    if [[ "$pending" =~ ^[0-9]+$ && "$pending" -gt 0 ]]; then
        warn "$disk has $pending pending sectors — possible read errors!"
    fi
}

echo "========================================"
echo " NTFS Mount + Samba Share Script"
if [[ "$SUDO_MODE" == false ]]; then
echo " *** DIAGNOSTIC MODE (no sudo) ***"
fi
echo "========================================"

# ════════════════════════════════════════════════════════════════════════════
# SECTION A — DRIVE DISCOVERY (no sudo needed)
# ════════════════════════════════════════════════════════════════════════════
section "Drive Discovery"

echo ""
echo "  All block devices:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT | grep -v "^loop" | sed 's/^/    /'
echo ""

while IFS= read -r disk; do
    DISK_NAME=$(basename "$disk")
    PARTITIONS=$(lsblk -lno NAME,TYPE "$disk" 2>/dev/null | awk '$2=="part"{print "/dev/"$1}')
    PART_COUNT=$(echo "$PARTITIONS" | grep -c '/dev/' 2>/dev/null || echo 0)

    echo "  /dev/$DISK_NAME:"

    if [[ $PART_COUNT -eq 0 ]]; then
        RAW_FS=$(blkid -s TYPE -o value "$disk" 2>/dev/null)
        if [[ -n "$RAW_FS" ]]; then
            note "/dev/$DISK_NAME has no partition table but has filesystem: $RAW_FS"
            info "This drive can be mounted directly as /dev/$DISK_NAME"
        else
            warn "/dev/$DISK_NAME has no partitions and no filesystem detected!"
            echo ""
            echo "    This drive appears unformatted. To use it:"
            echo ""
            echo "    1. Create a partition table:"
            echo "       sudo fdisk /dev/$DISK_NAME"
            echo "       (press g for GPT, n for new partition, w to write)"
            echo ""
            echo "    2a. Format as NTFS (for Windows compatibility):"
            echo "        sudo mkfs.ntfs -f -L MyDrive /dev/${DISK_NAME}1"
            echo ""
            echo "    2b. Format as ext4 (Linux only, better performance):"
            echo "        sudo mkfs.ext4 -L MyDrive /dev/${DISK_NAME}1"
            echo ""
            echo "    Then re-run this script."
        fi
    elif [[ $PART_COUNT -gt 1 ]]; then
        note "/dev/$DISK_NAME has $PART_COUNT partitions — only NTFS ones will be auto-mounted"
        echo "    Partitions:"
        while IFS= read -r part; do
            [[ -z "$part" ]] && continue
            PTYPE=$(blkid -s TYPE -o value "$part" 2>/dev/null)
            PLABEL=$(blkid -s LABEL -o value "$part" 2>/dev/null)
            PSIZE=$(lsblk -lno SIZE "$part" 2>/dev/null)
            PMOUNT=$(grep "^$part " /proc/mounts | awk '{print $2}' | head -1)
            STATUS=""
            [[ -n "$PMOUNT" ]] && STATUS=" (mounted at $PMOUNT)"
            [[ -z "$PTYPE" ]] && PTYPE="unknown"
            echo "      $part  size=$PSIZE  type=$PTYPE  label=${PLABEL:-(none)}$STATUS"
            if [[ -z "$PTYPE" || "$PTYPE" == "unknown" ]]; then
                warn "$part appears unformatted"
            fi
        done <<< "$PARTITIONS"
    else
        part=$(echo "$PARTITIONS" | head -1)
        PTYPE=$(blkid -s TYPE -o value "$part" 2>/dev/null)
        PLABEL=$(blkid -s LABEL -o value "$part" 2>/dev/null)
        PSIZE=$(lsblk -lno SIZE "$part" 2>/dev/null)
        PMOUNT=$(grep "^$part " /proc/mounts | awk '{print $2}' | head -1)
        echo "    $part  size=$PSIZE  type=${PTYPE:-(unknown)}  label=${PLABEL:-(none)}  mount=${PMOUNT:-(not mounted)}"
    fi
    echo ""

done < <(lsblk -lno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | grep -v "sda")

# ════════════════════════════════════════════════════════════════════════════
# SECTION B — CURRENT MOUNTS SUMMARY (no sudo needed)
# ════════════════════════════════════════════════════════════════════════════
section "Current NTFS Mounts"

NTFS_MOUNTS=$(grep -E '\s(ntfs|fuseblk)\s' /proc/mounts 2>/dev/null)
if [[ -n "$NTFS_MOUNTS" ]]; then
    echo "$NTFS_MOUNTS" | awk '{printf "  %-15s -> %-25s (%s)\n", $1, $2, $3}'
else
    info "No NTFS partitions currently mounted"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION C — CURRENT SMB SHARES SUMMARY (no sudo needed)
# ════════════════════════════════════════════════════════════════════════════
section "Current SMB Shares"

if [[ -r "$SMB_CONF" ]]; then
    SHARES=$(grep -i '^\[' "$SMB_CONF" | grep -iv '^\[global\]\|^\[homes\]\|^\[printers\]\|^\[print\$\]')
    if [[ -n "$SHARES" ]]; then
        echo "$SHARES" | sed 's/^/  /'
    else
        info "No custom SMB shares found in $SMB_CONF"
    fi
else
    note "Cannot read $SMB_CONF without sudo"
fi

# ════════════════════════════════════════════════════════════════════════════
# Exit here if not sudo
# ════════════════════════════════════════════════════════════════════════════
if [[ "$SUDO_MODE" == false ]]; then
    echo ""
    echo "========================================"
    echo " End of diagnostic mode."
    echo " Run with sudo (or just re-run, it will"
    echo " prompt) to mount and share drives."
    echo "========================================"
    exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION D — FULL SETUP (sudo required)
# ════════════════════════════════════════════════════════════════════════════

REAL_USER="${SUDO_USER:-$USER}"
USER_ID=$(id -u "$REAL_USER")
GROUP_ID=$(id -g "$REAL_USER")
MOUNT_BASE="/mnt"
MOUNTED=0
SHARED=0

MOUNT_ERR=$(mktemp /tmp/ntfs_mount_err.XXXXXX)
trap 'rm -f "$MOUNT_ERR"' EXIT

# ── Dependencies ──────────────────────────────────────────────────────────────
section "Checking Dependencies"

for pkg_check in "ntfs-3g:ntfs-3g" "smbd:samba" "smartctl:smartmontools"; do
    cmd="${pkg_check%%:*}"
    pkg="${pkg_check##*:}"
    if ! command -v "$cmd" &>/dev/null; then
        info "$pkg not found. Installing..."
        apt-get install -y "$pkg"
    else
        ok "$pkg is installed"
    fi
done

# ── Samba user check ──────────────────────────────────────────────────────────
section "Checking Samba User"

SMB_USER="$REAL_USER"
if pdbedit -L 2>/dev/null | grep -qi "^${SMB_USER}:"; then
    ok "Samba user '$SMB_USER' exists"
else
    echo ""
    fail "Samba user '$SMB_USER' does not exist in the Samba database."
    echo ""
    echo "  To create it, run:"
    echo ""
    echo "    sudo smbpasswd -a $SMB_USER"
    echo ""
    echo "  Then re-run this script."
    exit 1
fi

# ── SMART health check ────────────────────────────────────────────────────────
section "SMART Drive Health"

while IFS= read -r disk; do
    DISK_NAME=$(basename "$disk")
    echo "  /dev/$DISK_NAME:"
    print_smart_summary "$disk"
    echo ""
done < <(lsblk -lno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | grep -v "sda")

# ── Mount NTFS partitions ─────────────────────────────────────────────────────
section "Mounting NTFS Partitions"

while IFS= read -r partition; do
    [[ -z "$partition" ]] && continue

    UUID=$(blkid -s UUID -o value "$partition" 2>/dev/null)
    LABEL=$(blkid -s LABEL -o value "$partition" 2>/dev/null)
    DEV_BASE=$(basename "$partition")

    if grep -qs "^$partition " /proc/mounts; then
        MOUNT_POINT=$(grep "^$partition " /proc/mounts | awk '{print $2}' | head -1)
        skip "$partition already mounted at $MOUNT_POINT"
        continue
    fi
    if [[ -n "$UUID" ]] && grep -qs "UUID=$UUID" /proc/mounts; then
        skip "$partition (UUID=$UUID) already mounted"
        continue
    fi

    if [[ -n "$LABEL" ]]; then
        LABEL_CLEAN=$(echo "$LABEL" | tr ' ' '_' | tr -cd '[:alnum:]_-')
        DIR_NAME="${DEV_BASE}-${LABEL_CLEAN}"
    elif [[ -n "$UUID" ]]; then
        DIR_NAME="${DEV_BASE}-${UUID}"
    else
        DIR_NAME="${DEV_BASE}"
    fi

    if [[ "$DIR_NAME" == *"/"* || "$DIR_NAME" == *".."* ]]; then
        warn "$partition: unsafe mount point name '$DIR_NAME', skipping"
        continue
    fi

    MOUNT_POINT="${MOUNT_BASE}/${DIR_NAME}"
    mkdir -p "$MOUNT_POINT"

    echo -n "[ MOUNT ] $partition -> $MOUNT_POINT ... "
    if mount -t ntfs-3g \
        -o uid="$USER_ID",gid="$GROUP_ID",umask=022,noatime \
        "$partition" "$MOUNT_POINT" 2>"$MOUNT_ERR"; then
        echo "OK"
        MOUNTED=$((MOUNTED + 1))
    else
        ERR=$(cat "$MOUNT_ERR")
        if echo "$ERR" | grep -qi "hibernat\|dirty"; then
            echo ""
            info "$partition appears dirty/hibernated, attempting recovery..."
            ntfsfix "$partition" &>/dev/null
            if mount -t ntfs-3g \
                -o uid="$USER_ID",gid="$GROUP_ID",umask=022,noatime,remove_hiberfile \
                "$partition" "$MOUNT_POINT" 2>/dev/null; then
                ok "Mounted after recovery: $MOUNT_POINT"
                MOUNTED=$((MOUNTED + 1))
            else
                fail "Could not recover $partition"
                rmdir "$MOUNT_POINT" 2>/dev/null
            fi
        else
            fail "$partition: $ERR"
            rmdir "$MOUNT_POINT" 2>/dev/null
        fi
    fi

done < <(blkid -t TYPE=ntfs -o device | sort)

# ── Samba shares ──────────────────────────────────────────────────────────────
section "Setting Up Samba Shares"

SMB_CHANGED=0
while IFS= read -r line; do
    DEVICE=$(echo "$line" | awk '{print $1}')
    MOUNT_POINT=$(echo "$line" | awk '{print $2}')

    FS_TYPE=$(blkid -s TYPE -o value "$DEVICE" 2>/dev/null)
    if [[ "$FS_TYPE" != "ntfs" && "$FS_TYPE" != "ntfs-3g" ]]; then
        continue
    fi

    MNT_BASE=$(basename "$MOUNT_POINT")
    DEV_BASE=$(basename "$DEVICE")
    [[ -z "$MNT_BASE" || "$MNT_BASE" == "/" ]] && MNT_BASE="$DEV_BASE"
    SHARE_NAME=$(echo "${MNT_BASE}" | tr -cd '[:alnum:]_-')

    if smb_share_exists "$SHARE_NAME"; then
        skip "SMB share [$SHARE_NAME] already exists"
    else
        add_smb_share "$SHARE_NAME" "$MOUNT_POINT" "$SMB_USER"
        SMB_CHANGED=1
        SHARED=$((SHARED + 1))
    fi

done < <(grep -E '\s(ntfs|fuseblk)\s' /proc/mounts)

# ── Restart Samba ─────────────────────────────────────────────────────────────
if [[ "$SMB_CHANGED" -eq 1 ]]; then
    section "Samba Restart"

    echo -n "[ SMB  ] Testing config ... "
    if testparm -s "$SMB_CONF" &>/dev/null; then
        echo "OK"
        echo -n "[ SMB  ] Restarting smbd ... "
        if systemctl restart smbd 2>/dev/null || service smbd restart 2>/dev/null; then
            echo "OK"
        else
            fail "Could not restart smbd (try: sudo systemctl restart smbd)"
        fi
    else
        fail "smb.conf has errors — not restarting. Check with: testparm"
    fi
else
    note "Samba config unchanged — skipping restart"
fi

# ── Final Summary ─────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo " Final Summary"
echo "========================================"
if [[ "$MOUNTED" -eq 0 && "$SHARED" -eq 0 ]]; then
    ok "Everything is already up-to-date and configured."
fi
echo "  Samba user                    : $SMB_USER"
echo "  Newly mounted NTFS partitions : $MOUNTED"
echo "  Newly added SMB shares        : $SHARED"

echo ""
echo "  Disk Usage:"
grep -E '\s(ntfs|fuseblk)\s' /proc/mounts | awk '{print $2}' | while read -r mp; do
    df -h "$mp" 2>/dev/null | tail -1 | awk -v path="$mp" '{
        printf "  %-25s  size=%-8s used=%-8s avail=%-8s use%%=%s\n", path, $2, $3, $4, $5
    }'
done

echo ""
echo "  Mounted NTFS partitions:"
grep -E '\s(ntfs|fuseblk)\s' /proc/mounts | awk '{printf "  %-15s -> %s\n", $1, $2}' || echo "  (none)"

echo ""
echo "  SMB shares:"
grep -i '^\[' "$SMB_CONF" | grep -iv '^\[global\]\|^\[homes\]\|^\[printers\]\|^\[print\$\]' | sed 's/^/  /' || echo "  (none)"
