#!/usr/bin/env bash

# ==============================================================================
# NTFS Mount + Samba Share Script
# Optimized for: openSUSE, Debian/Ubuntu/Mint, Fedora/RHEL, Arch, macOS
# ==============================================================================

set -euo pipefail

# ── Colors & Formatting ───────────────────────────────────────────────────────
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

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
    path = $share_path
    valid users = $smb_user
    read only = no
    browsable = yes
    writable = yes
    guest ok = no
    create mask = 0775
    directory mask = 0775
EOF
}

pkg_install() {
    local pkgs=("$@")
    if command -v zypper &>/dev/null; then
        zypper --non-interactive install --auto-agree-with-licenses -y "${pkgs[@]}"
    elif command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
    elif command -v dnf &>/dev/null; then
        dnf install -y "${pkgs[@]}"
    elif command -v yum &>/dev/null; then
        yum install -y "${pkgs[@]}"
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm "${pkgs[@]}"
    elif command -v apk &>/dev/null; then
        apk add "${pkgs[@]}"
    fi
}

print_smart_summary() {
    local disk="$1"
    if ! command -v smartctl &>/dev/null; then
        warn "smartctl not installed — skipping health check"
        return
    fi
    local output
    output=$(timeout 5s smartctl -n standby -H "$disk" 2>/dev/null || true)
    if echo "$output" | grep -iq "PASSED\|OK"; then
        ok "$disk: SMART Health PASSED"
    elif echo "$output" | grep -iq "FAILED"; then
        fail "$disk: SMART Health FAILED — BACKUP IMMEDIATELY!"
    else
        note "$disk: SMART Health status unknown or device sleeping"
    fi
}

# ── Dynamic OS Root Disk Detection ───────────────────────────────────────────
OS_ROOT_DISK=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE / 2>/dev/null || echo '/dev/sdb2')" 2>/dev/null || echo "sdb")
if [[ -z "$OS_ROOT_DISK" ]]; then OS_ROOT_DISK="sdb"; fi

# ── Auto-Sudo Re-Execution ────────────────────────────────────────────────────
SUDO_MODE=false
if [[ $EUID -eq 0 ]]; then
    SUDO_MODE=true
else
    info "Not running as root — attempting to re-launch with sudo..."
    exec sudo bash "$0" "$@"
    exit $?
fi

echo "========================================"
echo " NTFS Mount + Samba Share Script"
echo "========================================"

show_usage() {
    echo "  Usage:"
    echo "    $0                   Run full auto-mount and share setup"
    echo "    $0 --help            Show this help"
    echo ""
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_usage
    exit 0
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION A — DRIVE DISCOVERY (Non-OS Disks)
# ════════════════════════════════════════════════════════════════════════════
section "Current Disk Usage"
if command -v duf &>/dev/null; then
    duf 2>/dev/null || df -h
else
    df -h
fi

section "Drive Discovery"
echo "  All block devices:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS | sed 's/^/    /'

echo ""

while IFS= read -r disk; do
    [[ -z "$disk" ]] && continue
    DISK_NAME=$(basename "$disk")
    PARTITIONS=$(lsblk -lno NAME,TYPE "$disk" 2>/dev/null | awk '$2=="part"{print "/dev/"$1}')
    PART_COUNT=$(echo "$PARTITIONS" | grep -c '/dev/' 2>/dev/null || echo 0)

    echo "  /dev/$DISK_NAME:"

    if [[ $PART_COUNT -eq 0 ]]; then
        RAW_FS=$(blkid -s TYPE -o value "$disk" 2>/dev/null || true)
        if [[ -n "$RAW_FS" ]]; then
            note "/dev/$DISK_NAME has no partition table but has filesystem: $RAW_FS"
        else
            warn "/dev/$DISK_NAME has no partitions and no filesystem detected!"
        fi
    else
        note "/dev/$DISK_NAME has $PART_COUNT partition(s)"
        echo "    Partitions:"
        while IFS= read -r part; do
            [[ -z "$part" ]] && continue
            PTYPE=$(blkid -s TYPE -o value "$part" 2>/dev/null || echo "unknown")
            PLABEL=$(blkid -s LABEL -o value "$part" 2>/dev/null || echo "(none)")
            PSIZE=$(lsblk -lno SIZE "$part" 2>/dev/null || echo "unknown")
            PMOUNT=$(grep "^$part " /proc/mounts | awk '{print $2}' | head -1 || true)
            STATUS=""
            [[ -n "$PMOUNT" ]] && STATUS=" (mounted at $PMOUNT)"
            echo "      $part  size=$PSIZE  type=$PTYPE  label=$PLABEL$STATUS"
        done <<< "$PARTITIONS"
    fi
    echo ""

done < <(lsblk -lno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | grep -v "$OS_ROOT_DISK")

# ════════════════════════════════════════════════════════════════════════════
# SECTION B — CURRENT MOUNTS SUMMARY
# ════════════════════════════════════════════════════════════════════════════
section "Current NTFS Mounts"

NTFS_MOUNTS=$(grep -E '\s(ntfs|ntfs3|fuseblk)\s' /proc/mounts 2>/dev/null || true)
if [[ -n "$NTFS_MOUNTS" ]]; then
    echo "$NTFS_MOUNTS" | awk '{printf "  %-15s -> %-25s (%s)\n", $1, $2, $3}'
else
    info "No NTFS partitions currently mounted"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION C — CURRENT SMB SHARES SUMMARY
# ════════════════════════════════════════════════════════════════════════════
section "Current SMB Shares"

if [[ -r "$SMB_CONF" ]]; then
    SHARES=$(grep -i '^\[' "$SMB_CONF" | grep -iv '^\[global\]\|^\[homes\]\|^\[printers\]\|^\[print\$\]' || true)
    if [[ -n "$SHARES" ]]; then
        echo "$SHARES" | sed 's/^/  /'
    else
        info "No custom SMB shares found in $SMB_CONF"
    fi
else
    note "Cannot read $SMB_CONF without sudo"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION D — FULL SETUP (sudo required)
# ════════════════════════════════════════════════════════════════════════════

REAL_USER="${SUDO_USER:-$USER}"
USER_ID=$(id -u "$REAL_USER" 2>/dev/null || echo 1000)
GROUP_ID=$(id -g "$REAL_USER" 2>/dev/null || echo 1000)
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
    if ! command -v "$cmd" &>/dev/null && ! [ -x "/usr/sbin/$cmd" ] && ! [ -x "/sbin/$cmd" ]; then
        info "$pkg not found. Attempting to install..."
        pkg_install "$pkg"
    else
        ok "$pkg is installed"
    fi
done

# ── Driver Detection ─────────────────────────────────────────────────────────
NTFS_DRIVER="ntfs-3g"
MOD_ERR=$(timeout 3s modprobe ntfs3 2>&1 || true)

if grep -qs "ntfs3" /proc/filesystems; then
    NTFS_DRIVER="ntfs3"
    ok "Native high-speed 'ntfs3' kernel driver detected! (2-3x faster, low CPU)"
else
    warn "Native 'ntfs3' driver NOT found. You are currently using legacy 'ntfs-3g' FUSE driver."
fi

# ── Samba user check ──────────────────────────────────────────────────────────
section "Checking Samba User"

SMB_USER="$REAL_USER"
if timeout 5s pdbedit -L 2>/dev/null | grep -qi "^${SMB_USER}:"; then
    ok "Samba user '$SMB_USER' exists"
else
    echo ""
    fail "Samba user '$SMB_USER' does not exist in the Samba database."
    echo ""
    echo "  To create it, run:"
    echo "    sudo smbpasswd -a $SMB_USER"
    echo ""
    echo "  Then re-run this script."
    exit 1
fi

# ── SMART health check ────────────────────────────────────────────────────────
section "SMART Drive Health"

while IFS= read -r disk; do
    [[ -z "$disk" ]] && continue
    DISK_NAME=$(basename "$disk")
    echo "  /dev/$DISK_NAME:"
    print_smart_summary "$disk"
    echo ""
done < <(lsblk -lno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}' | grep -v "$OS_ROOT_DISK")

# ── Mount NTFS partitions ─────────────────────────────────────────────────────
section "Mounting NTFS Partitions"

while IFS= read -r partition; do
    [[ -z "$partition" ]] && continue

    UUID=$(blkid -s UUID -o value "$partition" 2>/dev/null || true)
    LABEL=$(blkid -s LABEL -o value "$partition" 2>/dev/null || true)
    DEV_BASE=$(basename "$partition")
    SIZE_BYTES=$(lsblk -bno SIZE "$partition" 2>/dev/null || echo 0)
    PSIZE=$(lsblk -dno SIZE "$partition" 2>/dev/null || echo "")

    # Skip small system/recovery partitions (< 1GB) or system reserved partitions
    if [[ "$SIZE_BYTES" -lt 1073741824 ]] || [[ "$LABEL" =~ (System[_\ ]Reserved|Recovery|MSR|EFI) ]]; then
        skip "$partition (${LABEL:-System Partition}, $PSIZE) is a system/boot partition — skipping"
        continue
    fi

    if grep -qs "^$partition " /proc/mounts; then
        MOUNT_POINT=$(grep "^$partition " /proc/mounts | awk '{print $2}' | head -1)
        skip "$partition already mounted at $MOUNT_POINT"
        continue
    fi
    if [[ -n "$UUID" ]] && grep -qs "UUID=$UUID" /proc/mounts; then
        skip "$partition (UUID=$UUID) already mounted"
        continue
    fi

    DIR_NAME=""
    if [[ -n "$LABEL" ]]; then
        LABEL_CLEAN=$(echo "$LABEL" | tr ' ' '_' | tr -cd '[:alnum:]_-')
        DIR_NAME="${DEV_BASE}-${LABEL_CLEAN}"
    else
        DEFAULT_NAME="${DEV_BASE}-${PSIZE:-Data}"
        if [[ -t 0 ]]; then
            read -r -t 15 -p $'\n\e[1;33m[INPUT NEEDED]\e[0m Partition '"$partition ($PSIZE)"' has no volume label. Enter custom mount name [default: '"$DEFAULT_NAME"']: ' USER_CUSTOM_NAME || true
            USER_CUSTOM_NAME=$(echo "${USER_CUSTOM_NAME:-}" | tr ' ' '_' | tr -cd '[:alnum:]_-')
        else
            USER_CUSTOM_NAME=""
        fi
        if [[ -n "$USER_CUSTOM_NAME" ]]; then
            DIR_NAME="$USER_CUSTOM_NAME"
        else
            DIR_NAME="$DEFAULT_NAME"
        fi
    fi

    MOUNT_POINT="${MOUNT_BASE}/${DIR_NAME}"
    mkdir -p "$MOUNT_POINT"

    echo -n "[ MOUNT ] $partition -> $MOUNT_POINT ($NTFS_DRIVER) ... "
    
    if [[ "$NTFS_DRIVER" == "ntfs3" ]]; then
        MOUNT_OPTS="rw,uid=$USER_ID,gid=$GROUP_ID,umask=000,iocharset=utf8,noatime,prealloc"
    else
        MOUNT_OPTS="rw,uid=$USER_ID,gid=$GROUP_ID,umask=000,noatime"
    fi

    if mount -t "$NTFS_DRIVER" -o "$MOUNT_OPTS" "$partition" "$MOUNT_POINT" 2>"$MOUNT_ERR"; then
        if touch "${MOUNT_POINT}/.mount_test" 2>/dev/null; then
            rm -f "${MOUNT_POINT}/.mount_test"
            echo -e "${GREEN}OK (Read-Write)${NC}"
        else
            echo -e "${YELLOW}OK (READ-ONLY)${NC}"
            warn "$partition was mounted as Read-Only."
        fi
        MOUNTED=$((MOUNTED + 1))
    else
        ERR=$(cat "$MOUNT_ERR")
        if [[ "$NTFS_DRIVER" == "ntfs3" ]] || echo "$ERR" | grep -qi "hibernat\|dirty\|unclean"; then
            echo ""
            info "$partition has an unclean filesystem, attempting recovery with ntfsfix..."
            ntfsfix -d "$partition" &>/dev/null || true
            
            if mount -t ntfs3 -o "$MOUNT_OPTS,force" "$partition" "$MOUNT_POINT" 2>/dev/null; then
                ok "Mounted with ntfs3 after recovery (RW)"
                MOUNTED=$((MOUNTED + 1))
            elif mount -t ntfs-3g -o "rw,uid=$USER_ID,gid=$GROUP_ID,umask=000,noatime,remove_hiberfile" "$partition" "$MOUNT_POINT" 2>/dev/null; then
                ok "Mounted with legacy ntfs-3g after recovery (RW)"
                MOUNTED=$((MOUNTED + 1))
            else
                fail "Could not mount $partition after recovery attempt"
                rmdir "$MOUNT_POINT" 2>/dev/null || true
            fi
        else
            fail "$partition: $ERR"
            rmdir "$MOUNT_POINT" 2>/dev/null || true
        fi
    fi

done < <(blkid -t TYPE=ntfs -o device 2>/dev/null | sort)

# ── Samba shares ──────────────────────────────────────────────────────────────
section "Setting Up Samba Shares"

SMB_CHANGED=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    DEVICE=$(echo "$line" | awk '{print $1}')
    MOUNT_POINT=$(echo "$line" | awk '{print $2}')
    MOUNT_TYPE=$(echo "$line" | awk '{print $3}')

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

done < <(grep -E '\s(ntfs|ntfs3|fuseblk)\s' /proc/mounts 2>/dev/null || true)

# ── Restart Samba ─────────────────────────────────────────────────────────────
if [[ "$SMB_CHANGED" -eq 1 ]]; then
    section "Samba Restart"

    echo -n "[ SMB  ] Testing config ... "
    if testparm -s "$SMB_CONF" &>/dev/null; then
        echo "OK"
        echo -n "[ SMB  ] Restarting Samba daemon ... "
        if systemctl restart smb 2>/dev/null || systemctl restart smbd 2>/dev/null || service smbd restart 2>/dev/null; then
            echo "OK"
        else
            fail "Could not restart Samba (try: sudo systemctl restart smb)"
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
grep -E '\s(ntfs|ntfs3|fuseblk)\s' /proc/mounts 2>/dev/null | awk '{print $2}' | while read -r mp; do
    df -h "$mp" 2>/dev/null | tail -1 | awk -v path="$mp" '{
        printf "  %-25s  size=%-8s used=%-8s avail=%-8s use%%=%s\n", path, $2, $3, $4, $5
    }'
done

echo ""
echo "  Mounted NTFS partitions:"
grep -E '\s(ntfs|ntfs3|fuseblk)\s' /proc/mounts 2>/dev/null | awk '{printf "  %-15s -> %s\n", $1, $2}' || echo "  (none)"

echo ""
echo "  SMB shares:"
grep -i '^\[' "$SMB_CONF" 2>/dev/null | grep -iv '^\[global\]\|^\[homes\]\|^\[printers\]\|^\[print\$\]' | sed 's/^/  /' || echo "  (none)"
