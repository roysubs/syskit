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

# ── ANSI Colors ──────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Helpers ───────────────────────────────────────────────────────────────────
section() { echo ""; echo -e "${BOLD}── $* ──${NC}"; }
info()    { echo -e "${BLUE}[ INFO ] $*${NC}"; }
ok()      { echo -e "${GREEN}[ OK   ] $*${NC}"; }
skip()    { echo -e "${CYAN}[ SKIP ] $*${NC}"; }
warn()    { echo -e "${YELLOW}[ WARN ] $*${NC}"; }
fail()    { echo -e "${RED}[ FAIL ] $*${NC}"; }
note()    { echo -e "${BOLD}[ NOTE ] $*${NC}"; }

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

    local temp hours realloc pending
    temp=$(echo "$smart_out" | awk '/Temperature_Celsius|Airflow_Temperature/{print $10; exit}')
    # Improved Power_On_Hours parsing from preserve-disks-policy.sh
    hours=$(echo "$smart_out" | awk '/Power_On_Hours/{print $10; exit}' | sed 's/h+.*$//' | sed 's/[^0-9]//g')
    realloc=$(echo "$smart_out" | awk '/Reallocated_Sector/{print $10; exit}')
    pending=$(echo "$smart_out" | awk '/Current_Pending_Sector/{print $10; exit}')

    # Format hours into days
    local hours_display="n/a"
    if [[ -n "$hours" && "$hours" =~ ^[0-9]+$ ]]; then
        hours_display="${hours}h ($(( hours / 24 ))d)"
    fi

    # Health symbols
    local health_str="n/a"
    [[ "$smart_health" == "PASSED" ]] && health_str="PASSED ✓"
    [[ "$smart_health" == "FAILED"* ]] && health_str="FAILED ✗  <-- ATTENTION!"

    echo "    Health      : $health_str"
    echo "    Temperature : ${temp:-n/a}°C"
    echo "    Power-on    : $hours_display"
    echo "    Reallocated : ${realloc:-0} sectors"
    echo "    Pending     : ${pending:-0} sectors"
}

function show_usage() {
    echo -e "\n── Current Disk Usage ──"
    if command -v duf &>/dev/null; then
        # Removed the '/' to show all matched devices, and included fuseblk for ntfs-3g
        duf -only-fs ntfs,ntfs3,fuseblk,ext4 2>/dev/null || duf
    else
        df -h -t ntfs -t ntfs3 -t fuseblk -t ext4 2>/dev/null || df -h
    fi
}

echo "========================================"
echo " NTFS Mount + Samba Share Script"
if [[ "$SUDO_MODE" == false ]]; then
echo " *** DIAGNOSTIC MODE (no sudo) ***"
fi
echo "========================================"

show_usage
echo ""

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

# ── Checking Dependencies ──────────────────────────────────────────────────
section "Checking Dependencies"

for pkg_check in "ntfs-3g:ntfs-3g" "smbd:samba" "smartctl:smartmontools" "duf:duf"; do
    cmd="${pkg_check%%:*}"
    pkg="${pkg_check##*:}"
    if ! command -v "$cmd" &>/dev/null; then
        info "$pkg not found. Attempting to install..."
        apt-get install -y "$pkg" &>/dev/null
    else
        ok "$pkg is installed"
    fi
done

# ── Driver Detection ─────────────────────────────────────────────────────────
NTFS_DRIVER="ntfs-3g"
# Attempt to load the module
MOD_ERR=$(modprobe ntfs3 2>&1)

if grep -qs "ntfs3" /proc/filesystems; then
    NTFS_DRIVER="ntfs3"
    ok "Native high-speed 'ntfs3' kernel driver detected! (2-3x faster, low CPU)"
else
    warn "Native 'ntfs3' driver NOT found. You are currently using the slower FUSE driver."
    echo ""
    echo -e "${YELLOW}PRO-TIP: Why this matters?${NC}"
    echo -e "   - ${BOLD}The Bad (FUSE/ntfs-3g)${NC}: High CPU usage, bottlenecks on 8TB drives."
    echo -e "   - ${BOLD}The Good (ntfs3/Kernel)${NC}: Native performance, 2-3x speed, low power."
    echo ""
    
    # Only ask for update if interactive and not already root (or we have sudo permissions)
    if [[ -t 0 ]]; then
        # echo -n "Would you like me to try and fix this by installing the kernel modules? [y/N] "
        read -r -t 30 -p $'\n\e[1;33m[INPUT NEEDED]\e[0m Install kernel modules for ntfs3? [y/N] ' choice
        read -r choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            info "Attempting to install 'linux-image-amd64'..."
            if apt-get install -y linux-image-amd64 &>/dev/null; then
                ok "Update successful. Re-trying modprobe..."
                modprobe ntfs3 &>/dev/null
                if grep -qs "ntfs3" /proc/filesystems; then
                    NTFS_DRIVER="ntfs3"
                    ok "Success! Switched to high-speed driver."
                else
                    warn "Update finished but 'ntfs3' still not found. A reboot might be needed."
                    note "Continuing with legacy 'ntfs-3g' for now."
                fi
            else
                fail "Apt update failed. Keeping 'ntfs-3g'."
            fi
        fi
    else
        note "Skipping interactive driver-fix (non-interactive mode)."
        note "Falling back to legacy 'ntfs-3g' (FUSE)."
    fi
fi

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

    echo -n "[ MOUNT ] $partition -> $MOUNT_POINT ($NTFS_DRIVER) ... "
    
    # Generic mount options that work for both drivers or are translated
    # ntfs3 uses: uid, gid, fmask, dmask
    # ntfs-3g uses: uid, gid, umask
    if [[ "$NTFS_DRIVER" == "ntfs3" ]]; then
        MOUNT_OPTS="rw,uid=$USER_ID,gid=$GROUP_ID,fmask=111,dmask=022,noatime,prealloc"
    else
        MOUNT_OPTS="rw,uid=$USER_ID,gid=$GROUP_ID,umask=022,noatime"
    fi

    if mount -t "$NTFS_DRIVER" -o "$MOUNT_OPTS" "$partition" "$MOUNT_POINT" 2>"$MOUNT_ERR"; then
        # Verification: Check if it's actually writable
        if touch "${MOUNT_POINT}/.mount_test" 2>/dev/null; then
            rm "${MOUNT_POINT}/.mount_test"
            echo -e "${GREEN}OK (Read-Write)${NC}"
        else
            echo -e "${YELLOW}OK (READ-ONLY)${NC}"
            warn "$partition was mounted as Read-Only. (Try ntfsfix or check Windows Fast-Startup)"
        fi
        MOUNTED=$((MOUNTED + 1))
    else
        ERR=$(cat "$MOUNT_ERR")
        # If mount failed, it might be due to a dirty bit
        if [[ "$NTFS_DRIVER" == "ntfs3" ]] || echo "$ERR" | grep -qi "hibernat\|dirty\|unclean"; then
            echo ""
            info "$partition has an unclean filesystem, attempting recovery with ntfsfix..."
            # -d clears the dirty flag
            ntfsfix -d "$partition" &>/dev/null
            
            # Try mounting again with ntfs3 first, then fallback to ntfs-3g
            if mount -t ntfs3 -o "$MOUNT_OPTS,force" "$partition" "$MOUNT_POINT" 2>/dev/null; then
                ok "Mounted with ntfs3 after recovery (RW)"
                MOUNTED=$((MOUNTED + 1))
            elif mount -t ntfs-3g -o "rw,uid=$USER_ID,gid=$GROUP_ID,umask=022,noatime,remove_hiberfile" "$partition" "$MOUNT_POINT" 2>/dev/null; then
                ok "Mounted with legacy ntfs-3g after recovery (RW)"
                MOUNTED=$((MOUNTED + 1))
            else
                fail "Could not mount $partition after recovery attempt"
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
    MOUNT_TYPE=$(echo "$line" | awk '{print $3}')

    # Check if this mount is one we care about
    if [[ "$MOUNT_TYPE" != "ntfs" && "$MOUNT_TYPE" != "ntfs-3g" && "$MOUNT_TYPE" != "ntfs3" && "$MOUNT_TYPE" != "fuseblk" ]]; then
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
echo " NTFS Mount + Samba Share Script"
echo "========================================"

show_usage
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
