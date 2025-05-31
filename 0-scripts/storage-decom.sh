#!/bin/bash
# Author: Roy Wiseman 2025-05

# decommission-storage.sh
# Interactively unshares (Samba/NFS), unmounts, removes from fstab,
# and deletes partition(s) for a specified disk or partition.

# --- Color Definitions ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Configuration ---
FSTAB_FILE="/etc/fstab"
EXPORTS_FILE="/etc/exports"
SMB_CONF_FILE="/etc/samba/smb.conf" # Check this path for your system

# --- Helper Functions ---
_log_info() { echo -e "${GREEN}> $1${NC}"; }
_log_warn() { echo -e "${YELLOW}>> $1${NC}"; }
_log_error() { echo -e "${RED}>>> $1${NC}"; }
_log_step() { echo -e "\n${CYAN}${BOLD}--- $1 ---${NC}"; }

run_cmd() {
    echo -e "${ORANGE}Executing: $*${NC}"
    "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        _log_error "Command failed with exit code ${exit_code}: $*"
    fi
    return $exit_code
}

ask_yes_no() {
    local prompt_message="$1"
    local default_answer="${2:-N}"
    local answer
    local prompt_suffix="(y/N)"
    if [[ "$default_answer" =~ ^[Yy]$ ]]; then
        prompt_suffix="(Y/n)"
    fi

    while true; do
        echo -e -n "${YELLOW}${prompt_message} ${prompt_suffix}:${NC} "
        read -r answer
        answer="${answer:-${default_answer}}"
        case "$answer" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer 'y' or 'n'.";;
        esac
    done
}

backup_file() {
    local file_to_backup="$1"
    if [ ! -f "$file_to_backup" ]; then
        _log_warn "File '$file_to_backup' not found, skipping backup."
        return 1
    fi
    local backup_file="${file_to_backup}.bak.$(date +%Y%m%d-%H%M%S)"
    _log_info "Backing up '$file_to_backup' to '$backup_file'..."
    if sudo cp "$file_to_backup" "$backup_file"; then
        _log_info "Backup successful: $backup_file"
        return 0
    else
        _log_error "Backup of '$file_to_backup' FAILED."
        return 1
    fi
}

# --- Information Gathering Functions ---
get_partitions_on_disk() {
    local disk="$1"
    sudo lsblk -pnr -o NAME,TYPE "$disk" 2>/dev/null | awk '$2=="part" {print $1}'
}

get_mount_points_for_device() {
    local device_path="$1"
    # Only find mounts where $device_path is the SOURCE. Output is TARGET.
    sudo findmnt -nr -o TARGET -S "$device_path" 2>/dev/null
}

get_uuid() {
    local partition_device="$1"
    sudo blkid -s UUID -o value "$partition_device" 2>/dev/null
}

get_samba_shares_for_path() {
    local target_path="$1" # Unescaped path
    if ! command -v testparm >/dev/null; then echo ""; return 1; fi

    sudo testparm -s "$SMB_CONF_FILE" 2>/dev/null | awk -v t_path="$target_path" '
    BEGIN { current_share = ""; }
    $0 ~ /^\[.*\]$/ {
        gsub(/^\[|\]$/, "", $0);
        current_share = $0;
        next;
    }
    current_share != "" && current_share != "global" && current_share != "printers" {
        if (match($0, /^[ \t]*path[ \t]*=[ \t]*(.*)/, arr)) {
            gsub(/^[ \t]+|[ \t]+$/, "", arr[1]);
            if (arr[1] == t_path) {
                print current_share;
            }
        }
    }'
}

get_nfs_exports_for_path() {
    local path_to_check="$1" # Unescaped path
    if [ ! -f "$EXPORTS_FILE" ]; then echo ""; return 1; fi
    # Escape for grep ERE. Path itself is not escaped before passing to grep.
    local grep_safe_path=$(echo "$path_to_check" | sed 's/[].[*^$(){}?+|/\\]/\\&/g')
    grep -E "^\s*${grep_safe_path}([[:space:]]|$)" "$EXPORTS_FILE" | grep -v "^\s*#"
}


# --- Action Functions ---
unshare_samba_def() {
    local share_name_to_remove="$1"
    _log_step "Processing Samba Share Definition: [$share_name_to_remove]"

    if ! backup_file "$SMB_CONF_FILE"; then return 1; fi

    _log_info "Attempting to comment out Samba share [$share_name_to_remove] in '$SMB_CONF_FILE'..."
    if sudo awk -v share_target_name_awk="$share_name_to_remove" '
        BEGIN { in_section_to_comment = 0; modified_count = 0 }
        $0 ~ ("^\\[" share_target_name_awk "\\]$") {
            print "#DECOMMISSIONED: " $0;
            in_section_to_comment = 1;
            modified_count++; 
            next;
        }
        in_section_to_comment {
            if ($0 ~ /^\[.*\]$/) { 
                in_section_to_comment = 0;
                print $0; 
            } else {
                 print "#DECOMMISSIONED: " $0; 
                 # No need to increment modified_count for every line in section
            }
            next;
        }
        { print } 
        END { if (modified_count == 0) { print "Warning: Share [" share_target_name_awk "] not actively found to comment out in " FILENAME > "/dev/stderr";  } }
    ' "$SMB_CONF_FILE" > "${SMB_CONF_FILE}.tmp" && sudo mv "${SMB_CONF_FILE}.tmp" "$SMB_CONF_FILE"; then
        if grep -q "^\#DECOMMISSIONED: \[$share_name_to_remove\]" "$SMB_CONF_FILE"; then
            _log_info "Share [$share_name_to_remove] successfully commented out."
        else
            _log_warn "Share [$share_name_to_remove] not found or already commented. No changes made by awk."
        fi
        _log_info "Reloading Samba configuration (sudo systemctl reload smbd)..."
        sudo systemctl reload smbd || sudo systemctl restart smbd || _log_warn "Failed to reload/restart smbd."
        return 0
    else
        _log_error "Failed to process '$SMB_CONF_FILE' with awk for share [$share_name_to_remove]."
        rm -f "${SMB_CONF_FILE}.tmp" 
        return 1
    fi
}

unshare_nfs_def() {
    local path_to_unshare="$1"
    _log_step "Processing NFS Export Definition for Path: $path_to_unshare"

    if ! backup_file "$EXPORTS_FILE"; then return 1; fi

    _log_info "Attempting to comment out NFS export for '$path_to_unshare' in '$EXPORTS_FILE'..."
    local sed_escaped_path=$(echo "$path_to_unshare" | sed 's#[\/\.\*^$\[\]]#\\&#g') # Escape for sed pattern

    # Use a different delimiter for sed s command, like %
    if sudo sed -i.nfs_rm_bak."$(date +%s)" -E "s%^(\s*${sed_escaped_path}([[:space:]]+.*|$))%#DECOMMISSIONED: \1%" "$EXPORTS_FILE"; then
        if grep -q "^\#DECOMMISSIONED: \s*${sed_escaped_path}" "$EXPORTS_FILE"; then
            _log_info "NFS export for '$path_to_unshare' commented out."
            _log_info "Re-exporting NFS shares (sudo exportfs -ra)..."
            sudo exportfs -ra || _log_error "exportfs -ra failed."
            return 0
        else
            _log_warn "Did not find an exact line to comment for NFS export '$path_to_unshare', or line was already commented."
            return 0 
        fi
    else
        _log_error "Failed to modify '$EXPORTS_FILE' for path '$path_to_unshare'."
        return 1
    fi
}

unmount_filesystem_path() {
    local mount_point="$1"
    _log_step "Unmounting Filesystem at: $mount_point"

    if ! sudo mountpoint -q "$mount_point"; then
        _log_info "'$mount_point' is not currently mounted or is not a mountpoint."
        return 0
    fi

    _log_info "Attempting to unmount '$mount_point'..."
    local fuser_check_passed=false # Flag to see if fuser initially indicated not busy

    # Check if busy first using the silent (-s) option of fuser
    if ! sudo fuser -mvs "$mount_point" >/dev/null 2>&1; then
        fuser_check_passed=true # Not busy according to fuser's silent check
    fi

    if [ "$fuser_check_passed" = "false" ]; then # Was busy or fuser command had an issue
        _log_warn "Filesystem '$mount_point' is currently busy. Processes using it:"
        local fuser_display_output
        fuser_display_output=$(sudo fuser -mv "$mount_point" 2>&1 || true) # Get detailed output, proceed even if fuser exits with error (e.g. nothing found)
        echo "${fuser_display_output}" # Display the processes

        if echo "${fuser_display_output}" | grep -qE '(smbd|nfsd|lockd|rpc.mountd|statd)'; then
            _log_warn "${YELLOW}CAUTION: Network share-related processes (Samba/NFS) detected!${NC}"
            _log_warn "${YELLOW} > Ensure all client machines (e.g., Windows Explorer, other Linux systems) have CLOSED connections to shares on '$mount_point'.${NC}"
            _log_warn "${YELLOW} > Persistent network handles can prevent a clean unmount and may require a REBOOT to fully delete the partition later, even if a lazy unmount seems to succeed.${NC}"
        fi

        if ask_yes_no "Attempt a lazy unmount ('umount -l') for '$mount_point'?"; then
            if ! run_cmd sudo umount -l "$mount_point"; then return 1; else _log_info "'$mount_point' unmounted (lazily)."; fi
        else
            _log_warn "Skipping unmount of busy filesystem '$mount_point'."
            return 1
        fi
    elif ! run_cmd sudo umount "$mount_point"; then # Not busy initially by fuser -s, but standard umount failed
        _log_warn "Standard unmount failed for '$mount_point'."
        _log_warn "This can happen if processes started using it after the initial check."
        _log_warn "Processes possibly using it now (running fuser again):"
        sudo fuser -mv "$mount_point" || true # Show current processes
        if ask_yes_no "Standard unmount failed. Attempt lazy unmount ('umount -l') for '$mount_point'?"; then
            if ! run_cmd sudo umount -l "$mount_point"; then return 1; else _log_info "'$mount_point' unmounted (lazily)."; fi
        else
            return 1
        fi
    else # Standard unmount successful
        _log_info "'$mount_point' unmounted successfully."
    fi

    sleep 1 # Give the system a moment, especially after lazy unmount
    if sudo mountpoint -q "$mount_point"; then
        _log_error "'$mount_point' still reported as mounted after unmount attempt."
        _log_warn "${YELLOW}If a lazy unmount was performed, the mount point may appear 'mounted' if background${NC}"
        _log_warn "${YELLOW}processes are still finalizing operations, even if it's inaccessible for new activity.${NC}"
        _log_warn "${YELLOW}This could affect subsequent partition deletion steps without a reboot.${NC}"
        return 1
    fi
    return 0
}

remove_fstab_entries_for_identifier() {
    local identifier="$1" 
    _log_step "Fstab Cleanup: Searching for entries related to '$identifier'"
    _log_info "Searching for fstab entries matching '$identifier'..."
    local id_for_awk="$identifier" 
    
    # Grep first for display to user - escape for grep ERE
    local id_for_grep_ERE=$(echo "$identifier" | sed 's/[].[*^$(){}?+|/\\]/\\&/g')
    local grep_pattern_for_display="^\s*UUID=${id_for_grep_ERE}([[:space:]]|$)|^\s*${id_for_grep_ERE}[[:space:]]|^\s*[^[:space:]]+[[:space:]]+${id_for_grep_ERE}([[:space:]]|$)"
    
    local fstab_lines_found
    mapfile -t fstab_lines_found < <(grep -E "$grep_pattern_for_display" "$FSTAB_FILE" | grep -v "^\s*#DECOMMISSIONED:")

    if [ ${#fstab_lines_found[@]} -eq 0 ]; then
        _log_info "No active fstab entries found matching '$identifier'."
        return 0
    fi

    _log_warn "Found the following active fstab entry/entries for '$identifier':"
    for line in "${fstab_lines_found[@]}"; do echo "  $line"; done

    if ask_yes_no "Do you want to comment out these fstab entries?"; then
    if ! backup_file "$FSTAB_FILE"; then return 1; fi   # Only backup if user confirms making changes
        # Use awk to comment out matching lines
        if sudo awk -v id_match_str="$id_for_awk" '
            BEGIN{ modified_count=0 }
            !/^\s*#DECOMMISSIONED:/ {
                is_match = 0;
                # Check field 1 (device or UUID=device) or field 2 (mount point)
                if ($1 == id_match_str) is_match = 1;
                if ($1 == "UUID=" id_match_str) is_match = 1; # For when id_match_str is a UUID
                if (NF >= 2 && $2 == id_match_str) is_match = 1; # For when id_match_str is a mount path

                if (is_match) {
                    print "#DECOMMISSIONED: " $0;
                    modified_count++;
                    next;
                }
            }
            { print }
        ' "$FSTAB_FILE" > "${FSTAB_FILE}.tmp" && sudo mv "${FSTAB_FILE}.tmp" "$FSTAB_FILE"; then
            # Verify if commenting actually happened by checking modified_count (awk doesn't easily pass this out)
            # Instead, grep the file again for the DECOMMISSIONED lines.
            local commented_lines_count=$(grep -cE "^\s*#DECOMMISSIONED: .*(${id_for_grep_ERE})" "$FSTAB_FILE")
            if [ "$commented_lines_count" -gt 0 ]; then
                 _log_info "Relevant fstab entries related to '$identifier' commented out."
            else
                 _log_warn "No fstab lines were actually modified for '$identifier' (they might not have matched awk criteria or were already commented)."
            fi
            _log_info "Reloading systemd manager configuration (sudo systemctl daemon-reexec)..."
            sudo systemctl daemon-reexec || _log_warn "systemctl daemon-reexec failed."
        else
            _log_error "Error processing '$FSTAB_FILE' with awk for '$identifier'."
            rm -f "${FSTAB_FILE}.tmp" # Clean up on error
            return 1
        fi
        return 0
    else
        _log_warn "Fstab entries for '$identifier' were NOT removed."
        return 1 
    fi
}

delete_partition_device() {
    local partition_device="$1"
    _log_step "Deleting Partition: $partition_device"

    local base_disk
    base_disk=$(sudo lsblk -np -o PKNAME "$partition_device" 2>/dev/null)
    if [ -z "$base_disk" ]; then
        _log_error "Could not determine base disk for partition '$partition_device'. Cannot delete."
        return 1
    fi
    # Note: The buggy line 'base_disk="/dev/$base_disk"' is correctly absent here.

    local part_num_str
    part_num_str=$(sudo lsblk -npo PARTN "$partition_device" 2>/dev/null)
    if ! [[ "$part_num_str" =~ ^[0-9]+$ ]]; then
        _log_warn "lsblk PARTN for '$partition_device' not found/invalid, attempting string manipulation fallback..."
        part_num_str=$(echo "$partition_device" | grep -oE '[0-9]+$')
    fi

    if ! [[ "$part_num_str" =~ ^[0-9]+$ ]]; then
        _log_error "Could not reliably determine partition number for '$partition_device' on '$base_disk'. (Extracted: '$part_num_str')"
        return 1
    fi

    _log_info "Partition '$partition_device' is identified as number '$part_num_str' on disk '$base_disk'."
    # Re-check mount status very carefully before deletion
    if sudo findmnt -S "$partition_device" -n >/dev/null; then
        _log_error "CRITICAL: Partition '$partition_device' or its filesystem STILL appears to be mounted."
        _log_warn "Output of 'sudo findmnt -S $partition_device':"
        sudo findmnt -S "$partition_device"
        _log_warn "Cannot delete a mounted partition. Ensure unmount operations (including for lazy unmounts) have fully completed and the kernel has released the device."
        return 1
    fi
    _log_info "Confirmed: Partition '$partition_device' appears to be unmounted."

    if ask_yes_no "CONFIRM DELETION of partition '$partition_device' (number $part_num_str from $base_disk)? THIS IS DESTRUCTIVE."; then
        _log_info "Running partprobe on $base_disk before attempting partition deletion..."
        sudo partprobe "$base_disk" && sleep 2

        if run_cmd sudo parted --script "$base_disk" rm "$part_num_str"; then
            _log_info "Partition $part_num_str successfully deleted from $base_disk."
            _log_info "Reloading partition table (sudo partprobe $base_disk)..."
            # Run partprobe multiple times as sometimes the kernel needs a bit more persuasion or time
            sudo partprobe "$base_disk" && sleep 1 && sudo partprobe "$base_disk" || _log_warn "partprobe failed for $base_disk. A reboot might be required for changes to be fully visible."
            return 0
        else
            # run_cmd will have already logged: ">>> Command failed with exit code X: sudo parted..."
            _log_warn "${YELLOW}PARTITION DELETION COMMAND FAILED or reported errors.${NC}"
            _log_warn "${YELLOW}If the error message from 'parted' (see above) mentions it was 'unable to inform the kernel'${NC}"
            _log_warn "${YELLOW}about changes, this is often because the partition is still in use.${NC}"
            _log_warn "${YELLOW} -- A primary cause is active network connections (e.g., from Windows Explorer to a Samba share,${NC}"
            _log_warn "${YELLOW}    or an NFS client) that were not fully closed before or during this script's operation.${NC}"
            _log_warn "${YELLOW} -- In this case, 'parted' might have successfully updated the partition table on the DISK ITSELF,${NC}"
            _log_warn "${YELLOW}    but the operating system's kernel is still using the old layout.${NC}"
            _log_warn "${YELLOW} -- A SYSTEM REBOOT is typically required for the changes to update and the partition to be fully gone.${NC}"
            _log_warn "${YELLOW} -- Before rebooting, ensure all client systems are disconnected from any shares that were on this${NC}"
            _log_warn "${YELLOW}    partition to prevent issues on next startup.${NC}"
            _log_warn "${YELLOW}The failure can also happen if the kernel still holds a reference for other reasons like LVM, LUKS,${NC}"
            _log_warn "${YELLOW}software RAID not fully dismantled, or if partprobe itself couldn't update the kernel.${NC}"
            return 1
        fi
    else
        _log_warn "Partition '$partition_device' was NOT deleted."
        return 1
    fi
}

wipe_disk_signatures() {
    local disk_device="$1"
    _log_step "Wiping Partition Table Signatures from Disk: $disk_device"

    if ask_yes_no "CONFIRM wiping ALL partition signatures from '$disk_device'? THIS IS VERY DESTRUCTIVE."; then
        if run_cmd sudo wipefs --all --force "$disk_device"; then
            _log_info "Signatures wiped from '$disk_device'."
            return 0
        else
            _log_error "Failed to wipe signatures from '$disk_device'."
            return 1
        fi
    else
        _log_warn "Partition table signatures on '$disk_device' were NOT wiped."
        return 1
    fi
}

display_usage() {
    echo -e "${BOLD}Usage: ${0##*/} /dev/sdX (to decommission a whole disk)${NC}"
    echo -e "${BOLD}   or: ${0##*/} /dev/sdXN (to decommission a specific partition)${NC}"
    echo -e ""
    echo -e "This script helps to decommission storage by interactively performing the following steps"
    echo -e "for the specified target (disk or partition):"
    echo -e ""
    echo -e "  1. ${YELLOW}Information Gathering:${NC} Displays current status of the target:"
    echo -e "     - Partitions on the disk (if a disk is targeted)."
    echo -e "     - Mount points associated with the target partition(s)."
    echo -e "     - Related entries in /etc/fstab."
    echo -e "     - Associated Samba shares."
    echo -e "     - Associated NFS exports."
    echo -e "  2. ${YELLOW}Overall Confirmation:${NC} Asks if you want to proceed with decommissioning."
    echo -e "  3. ${YELLOW}Step-by-Step Actions (each with y/N confirmation):${NC}"
    echo -e "     a. Unshare Samba: Comments out relevant share definitions from '$SMB_CONF_FILE'."
    echo -e "     b. Unshare NFS: Comments out relevant exports from '$EXPORTS_FILE'."
    echo -e "     c. Unmount Filesystems: Unmounts target paths."
    echo -e "     d. Remove /etc/fstab Entries: Comments out relevant lines from '$FSTAB_FILE'."
    echo -e "     e. Delete Partition(s): Removes the partition definition(s) from the disk."
    echo -e "  4. ${YELLOW}Wipe Disk Signatures (Optional, for whole disk target only):${NC}"
    echo -e "     - If a whole disk was targeted and its partitions are removed, offers to wipe"
    echo -e "       all partition table signatures from the disk using 'wipefs'."
    echo -e ""
    echo -e "${RED}WARNING: This script performs DESTRUCTIVE operations.${NC}"
    echo -e "Always ensure data is backed up. Proceed with extreme caution."
    exit 1
}

# --- Main Script ---
if [ -z "$1" ]; then
    display_usage
fi

if [ "$(id -u)" -ne 0 ]; then
    _log_warn "Root privileges required. Rerunning with sudo..."
    exec sudo -E "$0" "$@"
    exit $? 
fi

TARGET_INPUT="$1"
TARGET_IS_DISK=false
TARGET_IS_PARTITION=false
BASE_DISK_FOR_OPERATIONS=""
declare -a PARTITIONS_TO_DECOM 
declare -A PARTITION_STATUS 

echo -e "${CYAN}${BOLD}--- Storage Decommissioning Utility ---${NC}"
_log_info "Target specified: $TARGET_INPUT"

if [ ! -b "$TARGET_INPUT" ]; then 
    _log_error "Target '$TARGET_INPUT' is not a valid block device or does not exist."
    exit 1
fi

TARGET_TYPE=$(sudo lsblk -dno TYPE "$TARGET_INPUT" 2>/dev/null)

if [[ "$TARGET_TYPE" == "disk" ]]; then
    TARGET_IS_DISK=true
    BASE_DISK_FOR_OPERATIONS="$TARGET_INPUT"
    _log_info "Target is a whole disk. All its partitions will be processed for decommissioning."
    mapfile -t PARTITIONS_TO_DECOM < <(get_partitions_on_disk "$TARGET_INPUT")
    if [ ${#PARTITIONS_TO_DECOM[@]} -eq 0 ]; then
        _log_info "No partitions found on disk '$TARGET_INPUT'."
    fi
elif [[ "$TARGET_TYPE" == "part" ]]; then
    TARGET_IS_PARTITION=true
    PARTITIONS_TO_DECOM=("$TARGET_INPUT")
    BASE_DISK_FOR_OPERATIONS=$(sudo lsblk -np -o PKNAME "$TARGET_INPUT" 2>/dev/null)
    _log_info "Target is a partition. Operations will be specific to '$TARGET_INPUT'."
    if [ -z "$BASE_DISK_FOR_OPERATIONS" ]; then
        _log_error "Could not determine parent disk for partition '$TARGET_INPUT'."
        exit 1
    fi
else
    _log_error "Target '$TARGET_INPUT' is not recognized as a disk or partition (type: '$TARGET_TYPE'). Valid types are 'disk' or 'part'."
    exit 1
fi

_log_step "Step 0: Initial Information Review for Target(s)"
if $TARGET_IS_DISK; then
    echo "Disk to Process: $BASE_DISK_FOR_OPERATIONS"
    if [ ${#PARTITIONS_TO_DECOM[@]} -gt 0 ]; then
        _log_info "Partitions on this disk that will be targeted:"
        for part_device_info in "${PARTITIONS_TO_DECOM[@]}"; do echo "  - $part_device_info"; done
    fi
    sudo lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,LABEL,UUID "$BASE_DISK_FOR_OPERATIONS"
else 
    _log_info "Partition to Process: ${PARTITIONS_TO_DECOM[0]}"
    _log_info "Parent Disk: $BASE_DISK_FOR_OPERATIONS"
    sudo lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,LABEL,UUID "${PARTITIONS_TO_DECOM[0]}"
fi

echo "--- Current Associated Mount Points, fstab, Samba, and NFS details ---"
declare -A ALL_UNIQUE_MOUNT_POINTS_FOR_TARGETS 
if [ ${#PARTITIONS_TO_DECOM[@]} -gt 0 ]; then
    for part_device_info_loop in "${PARTITIONS_TO_DECOM[@]}"; do
        echo -e "\n${YELLOW}Gathering details for partition: $part_device_info_loop${NC}"
        
        # Only get mount points where this partition is the SOURCE
        mount_info_output_display=$(get_mount_points_for_device "$part_device_info_loop")
        if [ -n "$mount_info_output_display" ]; then
            echo "  Currently mounted at (from findmnt -S $part_device_info_loop):"
            echo "$mount_info_output_display" | while IFS= read -r line_mp; do # Changed var name
                echo "    $line_mp"
                # findmnt -nr -o TARGET -S <dev> outputs only the target path per line
                # So $line_mp is the mount path if the function returns single column
                if [ -n "$line_mp" ] && [[ "$line_mp" == "/"* ]] && [[ "$line_mp" != "/" ]]; then 
                    ALL_UNIQUE_MOUNT_POINTS_FOR_TARGETS["$line_mp"]=1; 
                fi
            done
        else
            echo "  Not currently found as directly mounted (via findmnt -S $part_device_info_loop)."
        fi
        
        part_uuid_current_display=$(get_uuid "$part_device_info_loop")
        echo "  UUID: ${part_uuid_current_display:-N/A}"

        echo "  Relevant fstab entries (by UUID or device path matching '$part_device_info_loop'):"
        part_device_esc_grep_display=$(echo "$part_device_info_loop" | sed 's/[].[*^$(){}?+|/\\]/\\&/g')
        fstab_grep_pattern_part_display="${part_device_esc_grep_display}[[:space:]]"
        if [ -n "$part_uuid_current_display" ]; then
            fstab_grep_pattern_part_display="UUID=${part_uuid_current_display}([[:space:]]|$)|${fstab_grep_pattern_part_display}"
        fi
        grep_output_display=$(grep -E "(${fstab_grep_pattern_part_display})" "$FSTAB_FILE" | grep -v "^\s*#DECOMMISSIONED:")
        if [ -n "$grep_output_display" ]; then 
            echo "$grep_output_display" | sed 's/^/    /'
            echo "$grep_output_display" | awk '{print $2}' | while IFS= read -r mp_fstab; do # Changed var name
                if [ -n "$mp_fstab" ] && [[ "$mp_fstab" == "/"* ]] && [ "$mp_fstab" != "/" ]; then 
                    ALL_UNIQUE_MOUNT_POINTS_FOR_TARGETS["$mp_fstab"]=1; 
                fi
            done
        else 
            echo "    No active fstab entries found."
        fi
    done 

    if [ ${#ALL_UNIQUE_MOUNT_POINTS_FOR_TARGETS[@]} -gt 0 ]; then
        echo ""
        _log_info "Consolidated unique mount paths (from active mounts and fstab) to check for shares:"
        for mp_consolidated in "${!ALL_UNIQUE_MOUNT_POINTS_FOR_TARGETS[@]}"; do  # Changed var name
            echo "  - Path: $mp_consolidated"
            s_shares=$(get_samba_shares_for_path "$mp_consolidated")
            if [ -n "$s_shares" ]; then _log_info "    Samba shares found: $(echo "$s_shares" | tr '\n' ', ' | sed 's/, $//')"; fi
            n_exports=$(get_nfs_exports_for_path "$mp_consolidated")
            if [ -n "$n_exports" ]; then _log_info "    NFS exports found:"; echo "$n_exports" | sed 's/^/      /'; fi
        done
    else
        echo "  No current or fstab-defined mount paths identified to check for shares for targeted partition(s)."
    fi
else
    if $TARGET_IS_DISK; then
      _log_info "Disk '$TARGET_INPUT' has no partitions to gather detailed info for."
    fi
fi
echo "-----------------------------------------------------"

if ! ask_yes_no "Are you sure you want to proceed with INTERACTIVE decommissioning of '$TARGET_INPUT' and its (potential) components?"; then
    _log_info "Operation cancelled by user."
    exit 0
fi

# --- Step-by-step Decommissioning ---
for part_device_main_loop in "${PARTITIONS_TO_DECOM[@]}"; do
    PARTITION_STATUS["${part_device_main_loop}:samba_unshared"]="true" 
    PARTITION_STATUS["${part_device_main_loop}:nfs_unshared"]="true"
    PARTITION_STATUS["${part_device_main_loop}:unmounted"]="false" 
    PARTITION_STATUS["${part_device_main_loop}:fstab_cleared"]="false"
    PARTITION_STATUS["${part_device_main_loop}:deleted"]="false"
done

if [ ${#PARTITIONS_TO_DECOM[@]} -eq 0 ] && $TARGET_IS_DISK; then
    _log_info "No partitions on '$TARGET_INPUT' to decommission individually. Proceeding to disk signature wipe option."
else
    for part_device_main_loop in "${PARTITIONS_TO_DECOM[@]}"; do
        echo -e "\n${CYAN}${BOLD}>>> Processing Partition: $part_device_main_loop <<<${NC}"
        
        declare -a mount_paths_for_this_part_actions=() 
        mapfile -t current_mounts_for_this_device_action < <(get_mount_points_for_device "$part_device_main_loop")
        for mp_action_current in "${current_mounts_for_this_device_action[@]}"; do # Changed var name
            if [[ "$mp_action_current" == "/"* ]] && [[ "$mp_action_current" != "/" ]]; then 
                mount_paths_for_this_part_actions+=("$mp_action_current"); 
            fi
        done
        
        part_uuid_current_processing_loop=$(get_uuid "$part_device_main_loop") # Changed var name
        part_device_esc_grep_processing_loop=$(echo "$part_device_main_loop" | sed 's/[].[*^$(){}?+|/\\]/\\&/g') # Changed var name
        fstab_grep_pattern_processing_loop="${part_device_esc_grep_processing_loop}[[:space:]]" # Changed var name
        if [ -n "$part_uuid_current_processing_loop" ]; then
            fstab_grep_pattern_processing_loop="UUID=${part_uuid_current_processing_loop}([[:space:]]|$)|${fstab_grep_pattern_processing_loop}"
        fi
        mapfile -t fstab_mps_for_processing_loop < <(grep -E "(${fstab_grep_pattern_processing_loop})" "$FSTAB_FILE" 2>/dev/null | grep -v "^\s*#DECOMMISSIONED:" | awk '{print $2}') # Changed var name
        for mp_action_fstab in "${fstab_mps_for_processing_loop[@]}"; do # Changed var name
            if [[ "$mp_action_fstab" == "/"* ]] && [[ "$mp_action_fstab" != "/" ]]; then 
                mount_paths_for_this_part_actions+=("$mp_action_fstab"); 
            fi
        done
        mapfile -t current_unique_mount_points_to_process < <(echo "${mount_paths_for_this_part_actions[@]}" | tr ' ' '\n' | sort -u | grep -v '^$')

        # --- Unshare Samba ---
        if [ ${#current_unique_mount_points_to_process[@]} -gt 0 ]; then
            _log_step "Samba Unsharing for $part_device_main_loop related paths: ${current_unique_mount_points_to_process[*]}"
            temp_samba_unshared_all_for_part_s=true
            for mp_samba_action in "${current_unique_mount_points_to_process[@]}"; do # Changed var name
                shares_on_mp_samba_action=$(get_samba_shares_for_path "$mp_samba_action") # Changed var name
                if [ -n "$shares_on_mp_samba_action" ]; then
                    for sn_samba_action in $shares_on_mp_samba_action; do  # Changed var name
                        if ask_yes_no "Unshare Samba share [$sn_samba_action] (path $mp_samba_action)?"; then
                            if ! unshare_samba_def "$sn_samba_action"; then temp_samba_unshared_all_for_part_s=false; fi
                        else 
                            _log_warn "Skipped unsharing Samba for [$sn_samba_action] at $mp_samba_action."
                            temp_samba_unshared_all_for_part_s=false
                        fi
                    done
                else 
                    _log_info "No Samba shares found configured for path '$mp_samba_action'."
                fi
            done
            PARTITION_STATUS["${part_device_main_loop}:samba_unshared"]=$temp_samba_unshared_all_for_part_s
        else
            _log_info "No mount paths identified for $part_device_main_loop to check for Samba shares."
            PARTITION_STATUS["${part_device_main_loop}:samba_unshared"]="true" 
        fi
        
        # --- Unshare NFS ---
        if [ ${#current_unique_mount_points_to_process[@]} -gt 0 ]; then
            _log_step "NFS Unsharing for $part_device_main_loop related paths: ${current_unique_mount_points_to_process[*]}"
            temp_nfs_unshared_all_for_part_n=true
            for mp_nfs_action in "${current_unique_mount_points_to_process[@]}"; do # Changed var name
                exports_on_mp_nfs_action=$(get_nfs_exports_for_path "$mp_nfs_action") # Changed var name
                if [ -n "$exports_on_mp_nfs_action" ]; then
                    _log_info "NFS exports for '$mp_nfs_action':"; echo "$exports_on_mp_nfs_action" | sed 's/^/  /'
                    if ask_yes_no "Unshare NFS for path '$mp_nfs_action'?"; then
                        if ! unshare_nfs_def "$mp_nfs_action"; then temp_nfs_unshared_all_for_part_n=false; fi
                    else 
                        _log_warn "Skipped unsharing NFS for $mp_nfs_action."
                        temp_nfs_unshared_all_for_part_n=false
                    fi
                else 
                    _log_info "No NFS exports found for path '$mp_nfs_action'."
                fi
            done
            PARTITION_STATUS["${part_device_main_loop}:nfs_unshared"]=$temp_nfs_unshared_all_for_part_n
        else
            _log_info "No mount paths identified for $part_device_main_loop to check for NFS shares."
            PARTITION_STATUS["${part_device_main_loop}:nfs_unshared"]="true" 
        fi

        # --- Unmount ---
        _log_step "Unmounting for $part_device_main_loop"
        mapfile -t actual_mounts_for_part_device_unmount_action < <(get_mount_points_for_device "$part_device_main_loop")
        temp_unmount_current_part_successful_u=true
        if [ ${#actual_mounts_for_part_device_unmount_action[@]} -gt 0 ]; then
            _log_info "Partition $part_device_main_loop is currently mounted at:"
            for mp_to_unmount_action_loop in "${actual_mounts_for_part_device_unmount_action[@]}"; do echo "  - $mp_to_unmount_action_loop"; done # Changed var name
            for mp_to_unmount_action_loop in "${actual_mounts_for_part_device_unmount_action[@]}"; do # Changed var name
                if ! unmount_filesystem_path "$mp_to_unmount_action_loop"; then
                    temp_unmount_current_part_successful_u=false
                    _log_warn "Failed to unmount '$mp_to_unmount_action_loop' for partition $part_device_main_loop."
                    if ! ask_yes_no "Unmount failed for $mp_to_unmount_action_loop. Continue with fstab/delete for $part_device_main_loop (NOT RECOMMENDED)?"; then
                        PARTITION_STATUS["${part_device_main_loop}:unmounted"]="false"
                        continue 2 
                    fi
                    break 
                fi
            done
        else
            _log_info "Partition $part_device_main_loop is not currently mounted."
            # This correctly sets success if it's already unmounted
        fi
        PARTITION_STATUS["${part_device_main_loop}:unmounted"]=$temp_unmount_current_part_successful_u

        # --- Remove Fstab Entries ---
        _log_step "Fstab Cleanup for $part_device_main_loop"
        temp_fstab_current_part_successful_f=true
        # Use the same unique mount points identified for share processing
        for mp_fstab_check_action_loop in "${current_unique_mount_points_to_process[@]}"; do # Changed var name
             if [[ "$mp_fstab_check_action_loop" != "/" ]]; then 
                remove_fstab_entries_for_identifier "$mp_fstab_check_action_loop" || temp_fstab_current_part_successful_f=false; 
             fi
        done
        # Also specifically try by device path and UUID for good measure
        if [[ "$part_device_main_loop" != "/" ]]; then remove_fstab_entries_for_identifier "$part_device_main_loop" || temp_fstab_current_part_successful_f=false; fi
        if [ -n "$part_uuid_current_processing_loop" ]; then # was part_uuid_current_action
            remove_fstab_entries_for_identifier "$part_uuid_current_processing_loop" || temp_fstab_current_part_successful_f=false
        fi
        PARTITION_STATUS["${part_device_main_loop}:fstab_cleared"]=$temp_fstab_current_part_successful_f
        
        # --- Delete Partition ---
        if [[ "${PARTITION_STATUS[${part_device_main_loop}:unmounted]}" != "true" ]]; then
             if ! ask_yes_no "${RED}Partition $part_device_main_loop may still be mounted or unmount failed. Delete partition anyway (VERY RISKY)?${NC}"; then
                _log_warn "Skipping deletion of partition $part_device_main_loop due to mount status."
                PARTITION_STATUS["${part_device_main_loop}:deleted"]="false"
                continue 
             fi
        fi
        if [[ "${PARTITION_STATUS[${part_device_main_loop}:fstab_cleared]}" != "true" ]]; then 
            if ! ask_yes_no "${YELLOW}Fstab entries for $part_device_main_loop might still persist or removal was skipped. Delete partition anyway (fstab entries will become orphaned)?${NC}"; then
                 _log_warn "Skipping deletion of partition $part_device_main_loop due to fstab concerns."
                 PARTITION_STATUS["${part_device_main_loop}:deleted"]="false"
                 continue
            fi
        fi

        _log_step "Partition Deletion for $part_device_main_loop"
        if delete_partition_device "$part_device_main_loop"; then
            PARTITION_STATUS["${part_device_main_loop}:deleted"]="true"
        else
            PARTITION_STATUS["${part_device_main_loop}:deleted"]="false"
        fi
    done 
fi 

# --- Wipe Disk Signatures (if whole disk was targeted) ---
if $TARGET_IS_DISK; then
    _log_step "Disk Signature Wipe for $BASE_DISK_FOR_OPERATIONS (Optional)"
    all_partitions_on_disk_confirmed_deleted_for_wipe=true
    if [ ${#PARTITIONS_TO_DECOM[@]} -gt 0 ]; then 
        for part_dev_wipe_check_loop in "${PARTITIONS_TO_DECOM[@]}"; do # Changed var name
            if [[ "${PARTITION_STATUS[${part_dev_wipe_check_loop}:deleted]:-false}" != "true" ]]; then
                all_partitions_on_disk_confirmed_deleted_for_wipe=false
                _log_warn "Partition $part_dev_wipe_check_loop was not confirmed as deleted."
                break
            fi
        done
    fi
    
    # Final check if any partitions are still listed by lsblk on the disk
    # Ensure partprobe ran after last deletion attempt. It's in delete_partition_device.
    if sudo lsblk -lnp -o NAME,TYPE "$BASE_DISK_FOR_OPERATIONS" 2>/dev/null | awk '$2=="part" {print $1}' | grep -q .; then
        if $all_partitions_on_disk_confirmed_deleted_for_wipe; then
             _log_warn "lsblk still shows partitions on $BASE_DISK_FOR_OPERATIONS after deletion attempts. Partprobe might need more time or a reboot."
        fi
        all_partitions_on_disk_confirmed_deleted_for_wipe=false 
    fi

    if $all_partitions_on_disk_confirmed_deleted_for_wipe; then
        _log_info "All known partitions on $BASE_DISK_FOR_OPERATIONS appear to be deleted and are not listed by lsblk."
        if ask_yes_no "Do you want to wipe all partition table signatures from the disk '$BASE_DISK_FOR_OPERATIONS'?"; then
            wipe_disk_signatures "$BASE_DISK_FOR_OPERATIONS"
        fi
    else
        _log_warn "Not all partitions were confirmed deleted on '$BASE_DISK_FOR_OPERATIONS', or some may still exist according to lsblk."
        if ask_yes_no "${RED}Do you STILL want to attempt to wipe all partition table signatures from disk '$BASE_DISK_FOR_OPERATIONS' (EXTREMELY RISKY if active partitions remain)?${NC}"; then
            wipe_disk_signatures "$BASE_DISK_FOR_OPERATIONS"
        fi
    fi
fi

_log_info "\nDecommissioning process for '$TARGET_INPUT' has finished."
_log_info "Final status of affected disk(s):"
if $TARGET_IS_DISK; then
    sudo lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,LABEL,UUID "$TARGET_INPUT"
else 
    sudo lsblk -o NAME,SIZE,FSTYPE,TYPE,MOUNTPOINT,LABEL,UUID "$BASE_DISK_FOR_OPERATIONS"
fi

exit 0
