#!/usr/bin/env bash
# disk-tool.sh — Disk info, wipe, and partition creation tool
# Usage:
#   disk-tool.sh                        Show all disks and partition info
#   disk-tool.sh -wipe sda              Wipe entire disk (partition table + all signatures)
#   disk-tool.sh -wipe sda2             Wipe a single partition (filesystem signature only)
#   disk-tool.sh -create sda -type btrfs|ext4|ext3|xfs|ntfs [-label MYDRIVE]
#                                       Create GPT table, single partition, format it

set -euo pipefail

# ─── Helpers ─────────────────────────────────────────────────────────────────

RED='\033[0;31m'
YEL='\033[1;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error:${RST} This operation requires root. Re-run with sudo."
        exit 1
    fi
}

require_cmd() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}Error:${RST} Required command '$cmd' not found. Install it and retry."
            exit 1
        fi
    done
}

# Resolve e.g. "sda" → "/dev/sda", "sda2" → "/dev/sda2", "/dev/sda" → "/dev/sda"
resolve_dev() {
    local input="$1"
    if [[ "$input" == /dev/* ]]; then
        echo "$input"
    else
        echo "/dev/$input"
    fi
}

# True if the argument looks like a whole disk (sda, nvme0n1) not a partition (sda2, nvme0n1p1)
is_whole_disk() {
    local dev="$1"                   # expects bare name, e.g. sda or nvme0n1
    # A whole disk has no trailing digit after a letter, OR is an nvme device without 'p\d'
    if [[ "$dev" =~ ^nvme[0-9]+n[0-9]+$ ]]; then
        return 0
    elif [[ "$dev" =~ ^[a-z]+$ ]]; then
        return 0
    else
        return 1
    fi
}

confirm() {
    local prompt="$1"
    echo -e "${YEL}⚠️  WARNING:${RST} ${prompt}"
    read -rp "    Type YES to continue: " answer
    if [[ "$answer" != "YES" ]]; then
        echo "Aborted."
        exit 0
    fi
}

# ─── Show ─────────────────────────────────────────────────────────────────────

cmd_show() {
    require_cmd lsblk df

    echo -e "\n${BLD}${CYN}══════════════════════════════════════════${RST}"
    echo -e "${BLD}${CYN}  Block Devices${RST}"
    echo -e "${BLD}${CYN}══════════════════════════════════════════${RST}\n"

    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS,RM,RO,MODEL \
          --exclude 7 \
          --tree

    echo -e "\n${BLD}${CYN}══════════════════════════════════════════${RST}"
    echo -e "${BLD}${CYN}  Mounted Filesystem Usage${RST}"
    echo -e "${BLD}${CYN}══════════════════════════════════════════${RST}\n"

    # Show only real filesystems (skip tmpfs, devtmpfs, etc.)
    df -hT --exclude-type=tmpfs \
           --exclude-type=devtmpfs \
           --exclude-type=efivarfs \
           --exclude-type=squashfs \
        | awk 'NR==1 { print; next } /^\/dev/ { print }'

    echo -e "\n${BLD}${CYN}══════════════════════════════════════════${RST}"
    echo -e "${BLD}${CYN}  Partition Details (blkid)${RST}"
    echo -e "${BLD}${CYN}══════════════════════════════════════════${RST}\n"

    if [[ $EUID -eq 0 ]]; then
        blkid | sort
    else
        echo -e "  ${YEL}(Run as root/sudo to see UUIDs and filesystem types via blkid)${RST}"
    fi

    echo ""
}

# ─── Wipe ─────────────────────────────────────────────────────────────────────

cmd_wipe() {
    require_root
    require_cmd wipefs

    local target_input="$1"
    local dev
    dev=$(resolve_dev "$target_input")
    local bare="${dev#/dev/}"   # strip /dev/ for is_whole_disk check

    if [[ ! -b "$dev" ]]; then
        echo -e "${RED}Error:${RST} '$dev' is not a block device."
        exit 1
    fi

    if is_whole_disk "$bare"; then
        confirm "This will DESTROY the partition table and ALL data on ${BLD}$dev${RST}."
        echo -e "${GRN}→${RST} Wiping entire disk: $dev"
        wipefs -a "$dev"

        # Also wipe signatures on any partitions that still exist in kernel
        for part in "${dev}"?* "${dev}"p?*; do
            [[ -b "$part" ]] && wipefs -a "$part" 2>/dev/null && \
                echo -e "   ${GRN}→${RST} Cleared partition: $part"
        done

        # Re-read partition table
        partprobe "$dev" 2>/dev/null || true
        echo -e "${GRN}Done.${RST} $dev is clean."
    else
        confirm "This will DESTROY the filesystem on partition ${BLD}$dev${RST} (partition entry kept)."
        echo -e "${GRN}→${RST} Wiping partition signature: $dev"
        wipefs -a "$dev"
        echo -e "${GRN}Done.${RST} $dev filesystem signature cleared."
    fi
}

# ─── Btrfs Setup (Subvolumes & Ops) ──────────────────────────────────────────

cmd_btrfs_setup() {
    require_root
    require_cmd btrfs

    local dev_input="$1"
    local dev
    dev=$(resolve_dev "$dev_input")

    if [[ ! -b "$dev" ]]; then
        echo -e "${RED}Error:${RST} '$dev' is not a block device."
        exit 1
    fi

    # Check if it's actually btrfs
    local fstype
    fstype=$(lsblk -no FSTYPE "$dev" || echo "unknown")
    if [[ "$fstype" != "btrfs" ]]; then
        echo -e "${RED}Error:${RST} Device $dev is not formatted as Btrfs (found $fstype)."
        exit 1
    fi

    echo -e "\n${BLD}${CYN}══════════════════════════════════════════${RST}"
    echo -e "${BLD}${CYN}  Btrfs Subvolume Wizard${RST}"
    echo -e "${BLD}${CYN}══════════════════════════════════════════${RST}\n"

    local mnt="/tmp/btrfs_setup_mnt"
    mkdir -p "$mnt"
    
    echo -e "${GRN}→${RST} Mounting $dev to $mnt..."
    mount "$dev" "$mnt"

    # Create standard subvolumes
    local subvols=("@data" "@snapshots" "@backups")
    for s in "${subvols[@]}"; do
        if [[ ! -d "$mnt/$s" ]]; then
            echo -e "   ${GRN}+${RST} Creating subvolume: $s"
            btrfs subvolume create "$mnt/$s"
        else
            echo -e "   ${YEL}!${RST} Subvolume $s already exists, skipping."
        fi
    done

    # Disable COW on @data if it's a large drive meant for DBs/VMs/Torrents (Optional)
    # echo -ne "\nDisable COW on @data? (good for large files/VMs) [y/N]: "
    # read -r nocow
    # if [[ "$nocow" =~ ^[Yy]$ ]]; then
    #     chattr +C "$mnt/@data"
    #     echo -e "   ${GRN}→${RST} NoCOW set on @data."
    # fi

    umount "$mnt"
    rmdir "$mnt"

    local uuid
    uuid=$(blkid -s UUID -o value "$dev")

    echo -e "\n${GRN}✔ Btrfs Setup Complete!${RST}"
    echo -e "\n${BLD}Recommended fstab entry for maximum performance/safety:${RST}"
    echo -e "${CYN}UUID=$uuid  /mnt/data  btrfs  subvol=@data,compress=zstd:3,noatime,autodefrag,space_cache=v2  0  0${RST}"
    echo -e "${CYN}UUID=$uuid  /mnt/snaps btrfs  subvol=@snapshots,compress=zstd:3,noatime,autodefrag,space_cache=v2  0  0${RST}"
    echo ""
    echo -e "${YEL}Note:${RST} 'compress=zstd' is highly recommended for 8TB drives to save space and IO."
    echo -e "      'autodefrag' is good for HDDs (spinning disks)."
    echo ""
}

# ─── Create ───────────────────────────────────────────────────────────────────

cmd_create() {
    require_root
    require_cmd wipefs parted partprobe

    local disk_input="$1"
    local fstype="$2"
    local label="${3:-}"

    local dev
    dev=$(resolve_dev "$disk_input")
    local bare="${dev#/dev/}"

    # Validate it's a whole disk
    if ! is_whole_disk "$bare"; then
        echo -e "${RED}Error:${RST} -create expects a whole disk (e.g. sda), not a partition (e.g. sda2)."
        echo "       To format an existing partition, use -wipe first then mkfs manually."
        exit 1
    fi

    if [[ ! -b "$dev" ]]; then
        echo -e "${RED}Error:${RST} '$dev' is not a block device."
        exit 1
    fi

    # Validate filesystem type
    local valid_types=("btrfs" "ext4" "ext3" "xfs" "ntfs")
    local matched=false
    for t in "${valid_types[@]}"; do
        [[ "$fstype" == "$t" ]] && matched=true && break
    done
    if ! $matched; then
        echo -e "${RED}Error:${RST} Unsupported filesystem type '$fstype'."
        echo "       Supported: ${valid_types[*]}"
        exit 1
    fi

    # Check mkfs tool exists
    local mkfs_cmd
    case "$fstype" in
        ntfs) mkfs_cmd="mkfs.ntfs" ;;
        *)    mkfs_cmd="mkfs.${fstype}" ;;
    esac
    require_cmd "$mkfs_cmd" parted

    local size
    size=$(lsblk -dn -o SIZE "$dev")
    confirm "This will ERASE $dev (${size}) and create a single ${fstype} partition using ALL space."

    echo -e "\n${GRN}[1/4]${RST} Wiping existing signatures on $dev..."
    wipefs -a "$dev"

    echo -e "${GRN}[2/4]${RST} Writing GPT partition table..."
    parted -s "$dev" mklabel gpt

    echo -e "${GRN}[3/4]${RST} Creating single partition (1MiB aligned)..."
    # Use 1MiB for start to ensure optimal alignment for 4k sectors/advanced format drives
    parted -a optimal -s "$dev" mkpart primary "${fstype}" 1MiB 100%
    partprobe "$dev"
    sleep 1   # give kernel a moment to register the new partition

    # Figure out the new partition name (sda→sda1, nvme0n1→nvme0n1p1)
    local new_part
    if [[ "$bare" =~ ^nvme ]]; then
        new_part="${dev}p1"
    else
        new_part="${dev}1"
    fi

    if [[ ! -b "$new_part" ]]; then
        echo -e "${RED}Error:${RST} Expected partition '$new_part' not found after partprobe. Try rebooting."
        exit 1
    fi

    echo -e "${GRN}[4/4]${RST} Formatting $new_part as ${fstype}..."
    local lbl_arg=""
    case "$fstype" in
        btrfs) 
            [[ -n "$label" ]] && lbl_arg="-L $label"
            # metadata DUP is default on single devices, but let's be explicit for safety on large drives
            mkfs.btrfs -f $lbl_arg -m dup "$new_part" 
            ;;
        ext4)  
            [[ -n "$label" ]] && lbl_arg="-L $label"
            mkfs.ext4  -F $lbl_arg "$new_part" 
            ;;
        ext3)  
            [[ -n "$label" ]] && lbl_arg="-L $label"
            mkfs.ext3  -F $lbl_arg "$new_part" 
            ;;
        xfs)   
            [[ -n "$label" ]] && lbl_arg="-L $label"
            mkfs.xfs   -f $lbl_arg "$new_part" 
            ;;
        ntfs)  
            [[ -n "$label" ]] && lbl_arg="-L $label"
            mkfs.ntfs  -f $lbl_arg "$new_part" 
            ;;
    esac

    echo -e "\n${GRN}✔ Done!${RST}"
    echo -e "  Partition : ${BLD}$new_part${RST}"
    echo -e "  Filesystem: ${BLD}$fstype${RST}"
    echo ""

    # Show UUID for fstab hint
    local uuid
    uuid=$(blkid -s UUID -o value "$new_part" 2>/dev/null || echo "unavailable")
    echo -e "  UUID      : ${BLD}$uuid${RST}"
    echo ""
    echo -e "  To mount permanently, add to ${BLD}/etc/fstab${RST}:"
    echo -e "  ${CYN}UUID=$uuid  /mnt/yourmount  $fstype  defaults  0  0${RST}"
    echo ""
}

# ─── Usage ────────────────────────────────────────────────────────────────────

usage() {
    echo ""
    echo -e "${BLD}disk-tool.sh${RST} — Disk info, wipe, and create tool"
    echo ""
    echo "  ${BLD}Usage:${RST}"
    echo "    disk-tool.sh                          Show all disks, partitions, usage"
    echo "    disk-tool.sh -wipe <disk|partition>   Wipe disk or partition"
    echo "    disk-tool.sh -create <disk> -type <fs> [-label <lbl>] Create + Format"
    echo "    disk-tool.sh -setup-btrfs <partition> Create subvolumes + get fstab"
    echo ""
    echo "  ${BLD}Filesystem types:${RST} btrfs  ext4  ext3  xfs  ntfs"
    echo ""
    echo "  ${BLD}Examples:${RST}"
    echo "    disk-tool.sh"
    echo "    sudo disk-tool.sh -wipe sda"
    echo "    sudo disk-tool.sh -create sda -type btrfs -label MY_8TB_DATA"
    echo "    sudo disk-tool.sh -setup-btrfs sda1"
    echo ""
}

# ─── Entry point ──────────────────────────────────────────────────────────────

case "${1:-}" in
    "")
        cmd_show
        ;;
    -wipe)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Error:${RST} -wipe requires a device argument (e.g. sda or sda2)"
            usage; exit 1
        fi
        cmd_wipe "$2"
        ;;
    -create)
        # Shift to handle potential label
        shift
        local disk="" fstype="" label=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -type)  fstype="$2"; shift 2 ;;
                -label) label="$2";  shift 2 ;;
                *)      disk="$1";   shift   ;;
            esac
        done

        if [[ -z "$disk" || -z "$fstype" ]]; then
            echo -e "${RED}Error:${RST} Missing disk or type."
            usage; exit 1
        fi
        cmd_create "$disk" "$fstype" "$label"
        ;;
    -setup-btrfs)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Error:${RST} -setup-btrfs requires a partition (e.g. sda1)"
            usage; exit 1
        fi
        cmd_btrfs_setup "$2"
        ;;
    -h|--help)
        usage
        ;;
    *)
        echo -e "${RED}Error:${RST} Unknown option '$1'"
        usage; exit 1
        ;;
esac
