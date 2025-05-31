#!/bin/bash
# Author: Roy Wiseman 2025-04

# Script to mount a partition or display info about devices/mounts
# Version 1.1

# Automatically elevate privileges with sudo if not running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Elevation required; rerunning as sudo..." 1>&2 # Print to stderr
    sudo "$0" "$@" # Rerun the current script with sudo and pass all arguments
    exit $? # Exit the current script with the exit code of the sudo command
fi

# --- Configuration ---
APP_NAME="${0##*/}"

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Global Variables ---
DEVICE=""
MOUNT_POINT=""
FS_TYPE=""
MOUNT_OPTIONS=""
TARGET_USER=""
TARGET_PERMS="0755" # Default permissions for the mount point after mounting
AUTO_YES="false"
CURRENT_INVOKING_USER="" # User who originally invoked the script

# --- Functions ---

print_step() {
    echo -e "\n${YELLOW}>>> STEP: $1${NC}"
}

print_info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}WARN: $1${NC}"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

# Function to print command that will be run (sudo)
print_sudo_command() {
    echo -e "${GREEN}# sudo $1${NC}"
}

# Function to print command that will be run (local)
print_local_command() {
    echo -e "${GREEN}# $1${NC}"
}

# Function to run a command with sudo, print it first
run_sudo_command() {
    print_sudo_command "$1"
    if [ "$AUTO_YES" = "false" ] && [[ "$1" == mount* || "$1" == umount* || "$1" == mkdir* || "$1" == rm* || "$1" == chown* || "$1" == chmod* ]]; then
        read -p "Run this command? (y/N): " confirm
        if [[ ! "$confirm" =~ ^[yY](es)?$ ]]; then
            print_warn "Skipping command."
            return 1 # Indicates command was skipped
        fi
    fi
    sudo bash -c "$1"
    return $?
}

# Function to run a command that doesn't need user confirmation but needs sudo (e.g. blkid)
run_sudo_command_no_confirm() {
    print_sudo_command "$1"
    sudo bash -c "$1"
    return $?
}

# Function to run a command that doesn't need sudo (e.g. local tests, lsblk, findmnt)
run_local_command() {
    print_local_command "$1"
    bash -c "$1"
    return $?
}

show_usage() {
    echo "Usage: $APP_NAME <device> <mount_point> [options]  (to mount)"
    echo "   or: $APP_NAME <device_or_mountpoint> [options] (to display info)"
    echo ""
    echo "Mounts a partition <device> to <mount_point>, or shows info."
    echo ""
    echo "Mount Mode (2 arguments):"
    echo "  Summary of steps:"
    echo "    1. Validate arguments and paths."
    echo "    2. Show currently mounted filesystems (for context)."
    echo "    3. Check if the device or mount point is already in use for mounting."
    echo "    4. Create the mount point directory if it doesn't exist."
    echo "    5. Attempt to detect filesystem type (if not specified via -t)."
    echo "    6. Mount the partition."
    echo "    7. Set ownership and permissions on the mount point (after mounting)."
    echo "    8. Display final mount status."
    echo ""
    echo "Info Mode (1 argument):"
    echo "  - If <device_or_mountpoint> is a device (e.g. /dev/sda1, UUID=xxx):"
    echo "    Shows lsblk, blkid, and current mount status for the device."
    echo "  - If <device_or_mountpoint> is an existing directory:"
    echo "    Shows ls -ld, findmnt status, and df usage if it's a mount point."
    echo ""
    echo "Required Arguments for Mounting:"
    echo "  <device>                   : The partition device to mount (e.g., /dev/sdb1, UUID=..., LABEL=...)."
    echo "  <mount_point>              : The absolute path where the partition should be mounted."
    echo ""
    echo "Argument for Information:"
    echo "  <device_or_mountpoint>     : A device identifier or an existing directory path."
    echo ""
    echo "Options (apply to both modes where relevant, primarily for mount mode):"
    echo "  -t, --type <fstype>        : Filesystem type (e.g., ext4, ntfs, vfat). Auto-detected if not provided for mounting."
    echo "  -o, --options <opts>       : Comma-separated mount options (e.g., 'rw,users,uid=1000,gid=1000')."
    echo "                             : Defaults for mount: 'defaults' for most, sensible options for NTFS/VFAT."
    echo "  -u, --user <user[:group]>  : Mount mode: Set owner (and group) of the mounted filesystem's root."
    echo "                             : Defaults to the user who invoked sudo."
    echo "                             : Note: For FAT/NTFS, use uid/gid in -o options for effective ownership."
    echo "  -m, --mode <mode>          : Mount mode: Set permissions (e.g., 0755) for the mounted filesystem's root."
    echo "                             : Default: $TARGET_PERMS."
    echo "                             : Note: For FAT/NTFS, use fmask/dmask in -o options for effective permissions."
    echo "  -y, --yes                  : Automatically answer yes to prompts (use with caution)."
    echo "  -h, --help                 : Show this help message."
    exit 0
}

# --- Sanity Checks & Argument Parsing ---
if [ "$(id -u)" -eq 0 ]; then # Already root
    CURRENT_INVOKING_USER="${SUDO_USER:-root}"
else
    CURRENT_INVOKING_USER="${USER}"
fi

TEMP_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -t|--type) FS_TYPE="$2"; shift 2;;
        -o|--options) MOUNT_OPTIONS="$2"; shift 2;;
        -u|--user) TARGET_USER="$2"; shift 2;;
        -m|--mode) TARGET_PERMS="$2"; shift 2;;
        -y|--yes) AUTO_YES="true"; shift;;
        -h|--help) show_usage; exit 0;;
        --) shift; TEMP_ARGS+=("$@"); break;;
        -*) print_error "Unknown option: $1"; show_usage; exit 1;;
        *) TEMP_ARGS+=("$1"); shift;;
    esac
done
set -- "${TEMP_ARGS[@]}" # Restore positional arguments

# Default TARGET_USER if not set by -u option (relevant for mount mode)
if [ -z "$TARGET_USER" ]; then
    TARGET_USER="$CURRENT_INVOKING_USER"
fi

# --- Main Script Logic ---
echo "Mount/Info Script: $APP_NAME"
echo "--------------------------------------------"
if [ "$AUTO_YES" = "true" ]; then
    print_warn "Running in non-interactive mode (-y). Assuming 'yes' to all confirmations for mount operations."
fi

# Mode Dispatch based on number of positional arguments
if [ "$#" -eq 0 ]; then
    print_info "No device or mount point specified. Showing general mount overview."
    print_step "Current mounts (df -hT)"
    run_local_command "df -hT | grep -Ev 'squash|loop|overlay'"
    echo ""
    print_step "Current mounts (lsblk -f)"
    run_local_command "lsblk -f | grep -Ev 'squash|loop|overlay'"
    show_usage
    exit 0

elif [ "$#" -eq 1 ]; then
    # --- INFO MODE ---
    ARG_INFO="$1"
    print_step "Information Mode for: $ARG_INFO"
    FOUND_INFO=false

    # Attempt to treat as device first
    if [[ "$ARG_INFO" == /dev/* ]] || [[ "$ARG_INFO" == UUID=* ]] || [[ "$ARG_INFO" == LABEL=* ]]; then
        print_info "Checking '$ARG_INFO' as a device/identifier..."
        ACTUAL_DEVICE_FOR_BLKID="$ARG_INFO"
        RESOLVED_DEV=""

        if [[ "$ARG_INFO" == UUID=* ]] || [[ "$ARG_INFO" == LABEL=* ]]; then
             RESOLVED_DEV=$(findfs "$ARG_INFO" 2>/dev/null)
             if [ -n "$RESOLVED_DEV" ]; then
                 print_info "Identifier '$ARG_INFO' resolved to device '$RESOLVED_DEV'."
                 ACTUAL_DEVICE_FOR_BLKID="$RESOLVED_DEV"
             else
                 print_warn "Could not resolve identifier '$ARG_INFO' to a specific device path via findfs. Some info might be limited."
             fi
        fi

        # Check if the resolved path is a block device, or if it's an identifier lsblk might handle
        if [ -b "$ACTUAL_DEVICE_FOR_BLKID" ] || [[ "$ARG_INFO" == UUID=* ]] || [[ "$ARG_INFO" == LABEL=* ]]; then
            print_info "Displaying block device information for '$ARG_INFO':"
            run_local_command "lsblk -f \"$ARG_INFO\"" # lsblk handles UUID/LABEL/device paths

            if [ -b "$ACTUAL_DEVICE_FOR_BLKID" ]; then # blkid prefers an actual device path
                run_sudo_command_no_confirm "blkid \"$ACTUAL_DEVICE_FOR_BLKID\""
            elif [ -n "$RESOLVED_DEV" ] && [ ! -b "$RESOLVED_DEV" ]; then # Resolved but not block device?
                 print_warn "Resolved path '$RESOLVED_DEV' for '$ARG_INFO' is not a block device. Skipping blkid."
            else
                 print_warn "Cannot run detailed blkid for '$ARG_INFO' without a resolved block device path."
            fi

            echo -e "\n${YELLOW}Current mount status for source '$ARG_INFO':${NC}"
            if findmnt --source "$ARG_INFO" --raw --noheadings &>/dev/null; then
                run_local_command "findmnt --source \"$ARG_INFO\""
            else
                print_info "Source '$ARG_INFO' is not currently mounted (or identifier unknown to findmnt)."
            fi
            FOUND_INFO=true
        fi
    fi

    # If not treated as a device above, or if it might also be a directory, check as directory
    if [ -e "$ARG_INFO" ]; then
        if [ -d "$ARG_INFO" ]; then
            if [ "$FOUND_INFO" = "true" ]; then # Already processed as device, now also as dir
                 print_step "Additional Information for '$ARG_INFO' as a Directory"
            else
                 print_info "Checking '$ARG_INFO' as a directory/mount point..."
            fi

            echo -e "\n${YELLOW}Directory permissions and type:${NC}"
            run_local_command "ls -ld \"$ARG_INFO\""
            echo -e "\n${YELLOW}Checking if '$ARG_INFO' is a target mount point:${NC}"
            if findmnt --target "$ARG_INFO" --raw --noheadings &>/dev/null; then
                run_local_command "findmnt \"$ARG_INFO\"" # Shows info if $ARG_INFO is a mount target
                echo -e "\n${YELLOW}Filesystem usage for '$ARG_INFO':${NC}"
                run_local_command "df -hT \"$ARG_INFO\" | grep -Ev 'squash|loop|overlay'"
            else
                print_info "'$ARG_INFO' is not currently a mount point target."
                if [ -n "$(ls -A "$ARG_INFO" 2>/dev/null)" ]; then # Added 2>/dev/null for permission denied cases before mount
                     print_warn "Directory '$ARG_INFO' is not empty."
                else
                     print_info "Directory '$ARG_INFO' is empty."
                fi
            fi
            FOUND_INFO=true
        elif [ ! "$FOUND_INFO" = "true" ]; then # Exists but not a directory, and not processed as device
            print_error "'$ARG_INFO' exists but is not a directory."
            FOUND_INFO=false # Mark as not successfully found usable info
        fi
    elif [ ! "$FOUND_INFO" = "true" ]; then # Does not exist, and not processed as device
        print_error "Path '$ARG_INFO' does not exist."
        FOUND_INFO=false
    fi

    if [ "$FOUND_INFO" = "true" ]; then
        exit 0
    else
        print_error "Could not find relevant information for '$ARG_INFO'."
        show_usage
        exit 1
    fi

elif [ "$#" -eq 2 ]; then
    # --- MOUNT MODE ---
    DEVICE="$1"
    MOUNT_POINT="$2"
    print_step "Mount Mode: Device '$DEVICE' to Mount Point '$MOUNT_POINT'"

    # Step 1: Validate arguments (specific to mount mode)
    if [[ ! "$DEVICE" == /dev/* && ! "$DEVICE" == UUID=* && ! "$DEVICE" == LABEL=* ]]; then
        print_warn "Device '$DEVICE' does not look like a common block device path, UUID, or LABEL."
    fi
    # Existence of device is implicitly checked by mount, but blkid might fail earlier if it's bogus
    if [[ ! "$MOUNT_POINT" == /* ]]; then
        print_error "Mount point '$MOUNT_POINT' must be an absolute path (e.g., /mnt/data)."
        exit 1
    fi
    print_info "Device to mount: $DEVICE"
    print_info "Target mount point: $MOUNT_POINT"
    [ -n "$FS_TYPE" ] && print_info "Filesystem type specified: $FS_TYPE"
    [ -n "$MOUNT_OPTIONS" ] && print_info "Mount options specified: $MOUNT_OPTIONS"
    print_info "Target owner for mount point (post-mount): $TARGET_USER"
    print_info "Target permissions for mount point (post-mount): $TARGET_PERMS"

    # Step 2: Show current mount points (context)
    print_step "Current mount points (df -hT)"
    run_local_command "df -hT | grep -Ev 'squash|loop|overlay'"
    echo ""
    print_step "Current mount points (lsblk -f)"
    run_local_command "lsblk -f | grep -Ev 'squash|loop|overlay'"

    # Step 3: Check if device or mount point is already in use
    print_step "Checking existing mounts for $DEVICE and $MOUNT_POINT"
    
    EXISTING_TARGET_RAW=$(findmnt --source "$DEVICE" --noheadings --raw -o TARGET)
    
    if [ -n "$EXISTING_TARGET_RAW" ]; then
        # Device is already mounted somewhere.
        EXISTING_TARGET_MSG=$(echo "$EXISTING_TARGET_RAW" | tr '\n' ' ' | sed 's/ $//') # For messages

        IS_ALREADY_MOUNTED_AT_INTENDED_TARGET=false
        while IFS= read -r line; do
            if [ "$line" == "$MOUNT_POINT" ]; then
                IS_ALREADY_MOUNTED_AT_INTENDED_TARGET=true
                break
            fi
        done <<< "$EXISTING_TARGET_RAW"

        if $IS_ALREADY_MOUNTED_AT_INTENDED_TARGET; then
            # Device is already mounted at the exact target path.
            print_info "Device '$DEVICE' is already mounted at the intended target '$MOUNT_POINT'."
            run_local_command "lsblk -f \"$DEVICE\"" # Show current state
            run_local_command "findmnt \"$MOUNT_POINT\""
            if [ "$AUTO_YES" = "false" ]; then
                read -p "Device already mounted here. Proceed to re-apply options/permissions or exit? (P/e) [default: Exit]: " confirm_proceed
                if [[ "$confirm_proceed" =~ ^[Pp]$ ]]; then
                     print_info "Proceeding. This may remount with new options or just apply post-mount actions."
                     # Script will continue to the standard mount steps
                else
                    print_info "Exiting as device is already mounted at the target and user chose not to proceed."
                    exit 0
                fi
            else
                 print_info "Device already mounted at target. In non-interactive mode, proceeding (may remount or be no-op for mount itself)."
                 # Script will continue
            fi
        else
            # Device is mounted, but NOT at the user's intended new $MOUNT_POINT. This is bind mount territory.
            print_warn "Device '$DEVICE' is already providing content to: $EXISTING_TARGET_MSG"
            print_warn "A standard ('direct') filesystem mount to a new, different location ('$MOUNT_POINT') is generally not done while it's active elsewhere."
            print_info "However, you can create a 'bind mount'. A bind mount makes the existing content from one of the current mount points also accessible at '$MOUNT_POINT'."
            print_info "Changes made via either path (the original or the new bind mount) will affect the same data."

            FIRST_EXISTING_TARGET=$(echo "$EXISTING_TARGET_RAW" | head -n1) # Pick one existing mount as source for bind

            SHOULD_BIND_MOUNT="no"
            if [ "$AUTO_YES" = "true" ]; then
                print_info "AUTO_YES: Assuming 'yes' to creating a bind mount."
                SHOULD_BIND_MOUNT="yes"
            else
                echo -e "${YELLOW}A bind mount will essentially mirror the content from '${NC}$FIRST_EXISTING_TARGET${YELLOW}' to '${NC}$MOUNT_POINT${YELLOW}'.${NC}"
                read -p "Do you want to create this bind mount? (y/N): " confirm_bind
                if [[ "$confirm_bind" =~ ^[yY](es)?$ ]]; then
                    SHOULD_BIND_MOUNT="yes"
                fi
            fi

            if [ "$SHOULD_BIND_MOUNT" = "yes" ]; then
                print_step "Attempting Bind Mount: '$FIRST_EXISTING_TARGET' to '$MOUNT_POINT'"
                
                # Ensure target directory for bind mount exists
                if [ ! -d "$MOUNT_POINT" ]; then
                    print_info "Directory '$MOUNT_POINT' for bind mount does not exist. Creating it."
                    run_sudo_command "mkdir -p \"$MOUNT_POINT\"" || {
                        print_error "Failed to create directory '$MOUNT_POINT' for bind mount."
                        exit 1
                    }
                elif [ -n "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ]; then # Check if dir is non-empty
                     print_warn "Target directory '$MOUNT_POINT' for bind mount is not empty. Its current contents will be hidden by the bind mount."
                fi

                BIND_MOUNT_CMD="mount --bind \"$FIRST_EXISTING_TARGET\" \"$MOUNT_POINT\""
                # Note: Original -o options are typically not passed to --bind.
                # Permissions (-u, -m) for bind mounts affect the source. We won't apply them separately here.

                if run_sudo_command "$BIND_MOUNT_CMD"; then
                    print_info "Successfully created bind mount from '$FIRST_EXISTING_TARGET' to '$MOUNT_POINT'."
                    print_step "Final Bind Mount Status"
                    echo -e "${GREEN}Original source device:${NC}"
                    run_local_command "lsblk -f \"$DEVICE\""
                    echo -e "\n${GREEN}Path used as source for bind:${NC} $FIRST_EXISTING_TARGET"
                    echo -e "${GREEN}Path used as target for bind:${NC} $MOUNT_POINT"
                    echo -e "\n${YELLOW}Mount point information for '$MOUNT_POINT':${NC}"
                    run_local_command "findmnt \"$MOUNT_POINT\""
                    echo ""
                    run_local_command "df -hT \"$MOUNT_POINT\""
                    echo -e "\n${GREEN}Directory listing for the new bind mount point:${NC}"
                    run_local_command "ls -ld \"$MOUNT_POINT\""
                    echo ""
                    print_info "To unmount THIS specific bind mount: sudo umount '$MOUNT_POINT'"
                    print_warn "Unmounting '$MOUNT_POINT' will NOT affect the original mount at '$FIRST_EXISTING_TARGET'."
                    print_info "Script finished successfully (Bind Mount)."
                    exit 0 # Successfully created bind mount, main task done.
                else
                    print_error "Failed to create bind mount from '$FIRST_EXISTING_TARGET' to '$MOUNT_POINT'."
                    exit 1
                fi
            else
                print_info "Bind mount declined by user. Exiting."
                exit 1 # User declined offered action.
            fi
        fi # End of "is device already mounted at INTENDED target?" vs "offer bind mount"
    fi # End of "is device already mounted SOMEWHERE?"

    # If we've reached here, it means either:
    # 1. The device was not mounted anywhere.
    # 2. The device was already mounted at the *intended target*, and the user chose to proceed (for remount/permission update).

    # Fall-through to check if MOUNT_POINT is used by a DIFFERENT device
    if findmnt --target "$MOUNT_POINT" --noheadings --raw &>/dev/null; then
        # This means $MOUNT_POINT is a mount point.
        # The previous block (if $DEVICE was mounted) would have handled cases where $DEVICE is mounted at $MOUNT_POINT.
        # So, if we are here, and $MOUNT_POINT is mounted, it must be by a *different* source.
        EXISTING_SOURCE_AT_TARGET=$(findmnt --target "$MOUNT_POINT" --noheadings --raw -o SOURCE)
        print_error "Mount point '$MOUNT_POINT' is already in use by a different source: '$EXISTING_SOURCE_AT_TARGET'."
        exit 1
    fi

    # Step 4: Create mount point directory
    print_step "Preparing mount point directory: $MOUNT_POINT"
    if [ -d "$MOUNT_POINT" ]; then
        print_info "Directory '$MOUNT_POINT' already exists."
        if [ -n "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ] && ! findmnt --target "$MOUNT_POINT" --noheadings --raw &>/dev/null ; then
             # If directory is not empty AND it's not already a mount point for something else
            print_warn "Directory '$MOUNT_POINT' is not empty. Mounting will hide its current contents."
        fi
    else
        print_info "Directory '$MOUNT_POINT' does not exist. Creating it."
        run_sudo_command "mkdir -p \"$MOUNT_POINT\"" || { print_error "Failed to create directory '$MOUNT_POINT'."; exit 1; }
        run_sudo_command_no_confirm "chmod 0700 \"$MOUNT_POINT\"" # Initial restrictive perms
    fi

    # Step 5: Detect filesystem type if not specified
    DETECTED_FS_TYPE=""
    ACTUAL_DEVICE_FOR_FS_DETECT="$DEVICE" # Could be /dev/sda1, UUID=xxx, LABEL=yyy
    if [ -z "$FS_TYPE" ]; then
        print_step "Attempting to detect filesystem type for $DEVICE"
        # Resolve UUID/LABEL to actual device for blkid if possible
        if [[ "$DEVICE" == UUID=* || "$DEVICE" == LABEL=* ]]; then
            RESOLVED_DEV_FOR_FS=$(findfs "$DEVICE" 2>/dev/null)
            if [ -n "$RESOLVED_DEV_FOR_FS" ] && [ -b "$RESOLVED_DEV_FOR_FS" ]; then
                ACTUAL_DEVICE_FOR_FS_DETECT="$RESOLVED_DEV_FOR_FS"
                print_info "$DEVICE resolved to $ACTUAL_DEVICE_FOR_FS_DETECT for FS detection."
            else
                print_warn "Could not resolve $DEVICE to specific block device for FS type detection. Mount will try to auto-detect."
            fi
        fi

        if [ -b "$ACTUAL_DEVICE_FOR_FS_DETECT" ]; then # Only run blkid if we have a block device
            DETECTED_FS_TYPE=$(sudo blkid -s TYPE -o value "$ACTUAL_DEVICE_FOR_FS_DETECT" 2>/dev/null)
            if [ -n "$DETECTED_FS_TYPE" ]; then
                print_info "Detected filesystem type for '$ACTUAL_DEVICE_FOR_FS_DETECT' as '$DETECTED_FS_TYPE'."
                FS_TYPE="$DETECTED_FS_TYPE"
            else
                print_warn "Could not automatically detect filesystem type for '$ACTUAL_DEVICE_FOR_FS_DETECT'. Will attempt generic mount."
            fi
        elif [[ ! "$DEVICE" == UUID=* && ! "$DEVICE" == LABEL=* ]]; then # If not UUID/LABEL and not block device
            print_warn "Device path '$DEVICE' is not a block device. Filesystem type detection skipped."
        fi
    fi


    # Step 6: Mount the partition
    print_step "Mounting $DEVICE to $MOUNT_POINT"
    MOUNT_CMD_STR="mount"
    FINAL_MOUNT_OPTIONS="$MOUNT_OPTIONS" # Start with user-provided options

    if [ -n "$FS_TYPE" ]; then
        MOUNT_CMD_STR="$MOUNT_CMD_STR -t \"$FS_TYPE\""
        # Sensible defaults if FS_TYPE known and no user options
        if [ -z "$MOUNT_OPTIONS" ]; then
            INVOKING_UID=$(id -u "$CURRENT_INVOKING_USER")
            INVOKING_GID=$(id -g "$CURRENT_INVOKING_USER")
            case "$FS_TYPE" in
                ntfs|ntfs-3g)
                    FINAL_MOUNT_OPTIONS="rw,users,uid=$INVOKING_UID,gid=$INVOKING_GID,dmask=002,fmask=113,windows_names,umask=007,locale=en_US.UTF-8"
                    print_info "Applying default options for $FS_TYPE: $FINAL_MOUNT_OPTIONS"
                    ;;
                vfat|fat32|exfat)
                    FINAL_MOUNT_OPTIONS="rw,users,uid=$INVOKING_UID,gid=$INVOKING_GID,dmask=002,fmask=113,shortname=mixed,utf8"
                    print_info "Applying default options for $FS_TYPE: $FINAL_MOUNT_OPTIONS"
                    ;;
                *) # For ext4, xfs, btrfs etc.
                    FINAL_MOUNT_OPTIONS="defaults"
                    print_info "Applying default options for $FS_TYPE: $FINAL_MOUNT_OPTIONS"
                    ;;
            esac
        fi
    elif [ -z "$MOUNT_OPTIONS" ]; then # No FS_TYPE and no MOUNT_OPTIONS
         FINAL_MOUNT_OPTIONS="defaults" # Generic fallback
         print_info "No FS_TYPE or options specified, using generic mount options: $FINAL_MOUNT_OPTIONS"
    fi


    if [ -n "$FINAL_MOUNT_OPTIONS" ]; then
        MOUNT_CMD_STR="$MOUNT_CMD_STR -o \"$FINAL_MOUNT_OPTIONS\""
    fi
    MOUNT_CMD_STR="$MOUNT_CMD_STR \"$DEVICE\" \"$MOUNT_POINT\""

    if run_sudo_command "$MOUNT_CMD_STR"; then
        print_info "Successfully mounted '$DEVICE' at '$MOUNT_POINT'."
    else
        print_error "Failed to mount '$DEVICE' to '$MOUNT_POINT'."
        print_warn "Check 'dmesg | tail' or 'journalctl -xe' for detailed error messages."
        # Simple cleanup: if we created the dir and it's empty and not mounted, try rmdir
        if ! findmnt --target "$MOUNT_POINT" --noheadings --raw &>/dev/null && \
           [ -z "$(ls -A "$MOUNT_POINT" 2>/dev/null)" ] && \
           grep -q "Directory '$MOUNT_POINT' does not exist. Creating it." /tmp/mount_script_log_$$ 2>/dev/null ; then # Approximated check
             print_warn "Attempting to remove created empty mount point directory '$MOUNT_POINT'."
             run_sudo_command_no_confirm "rmdir \"$MOUNT_POINT\" 2>/dev/null"
        fi
        rm -f /tmp/mount_script_log_$$ # Clean up temp log
        exit 1
    fi
    #rm -f /tmp/mount_script_log_$$ # Clean up temp log on success too

    # Step 7: Set ownership and permissions (after successful mount)
    print_step "Setting final ownership and permissions on $MOUNT_POINT (if applicable)"
    FS_OF_MOUNT_POINT=$(findmnt -n -o FSTYPE -T "$MOUNT_POINT" 2>/dev/null) # Get type of mounted fs
    CAN_CHMOD_CHOWN=true
    if [[ "$FS_OF_MOUNT_POINT" == "vfat" || "$FS_OF_MOUNT_POINT" == "exfat" || "$FS_OF_MOUNT_POINT" == "ntfs" || "$FS_OF_MOUNT_POINT" == "fuseblk" ]]; then
        print_warn "Filesystem type is $FS_OF_MOUNT_POINT. 'chown' and 'chmod' after mount are usually ineffective."
        print_warn "For these types, use 'uid', 'gid', 'fmask', 'dmask' in mount options (-o) for permissions control."
        CAN_CHMOD_CHOWN=false
    fi

    # Proceed if FS supports it, or if user explicitly set non-default user/perms
    APPLY_CHOWN_CHMOD=false
    if [ "$CAN_CHMOD_CHOWN" = "true" ]; then
        APPLY_CHOWN_CHMOD=true
    # Check if user specified target owner different from default, or non-default perms
    elif [ "$TARGET_USER" != "$CURRENT_INVOKING_USER" ] || [ "$TARGET_PERMS" != "0755" ]; then
        print_warn "User specified non-default owner/permissions. Attempting to apply them, but may not be effective for $FS_OF_MOUNT_POINT."
        APPLY_CHOWN_CHMOD=true
    fi


    if [ "$APPLY_CHOWN_CHMOD" = "true" ]; then
        if [ -n "$TARGET_USER" ]; then
            print_info "Setting owner of '$MOUNT_POINT' to '$TARGET_USER'."
            run_sudo_command "chown '$TARGET_USER' '$MOUNT_POINT'" || print_warn "Failed to set owner on '$MOUNT_POINT'. This might be expected for $FS_OF_MOUNT_POINT."
        fi

        if [ -n "$TARGET_PERMS" ]; then
            print_info "Setting permissions of '$MOUNT_POINT' to '$TARGET_PERMS'."
            run_sudo_command "chmod '$TARGET_PERMS' '$MOUNT_POINT'" || print_warn "Failed to set permissions on '$MOUNT_POINT'. This might be expected for $FS_OF_MOUNT_POINT."
        fi
    else
        print_info "Skipping explicit chown/chmod as filesystem type ($FS_OF_MOUNT_POINT) handles permissions via mount options, or defaults are sufficient."
    fi

    # Step 8: Display mount status
    print_step "Final Mount Status"
    echo -e "${GREEN}Device information:${NC}"
    run_local_command "lsblk -f \"$DEVICE\""
    echo ""
    echo -e "${GREEN}Mount point information:${NC}"
    run_local_command "findmnt \"$MOUNT_POINT\""
    echo ""
    echo -e "${GREEN}Directory listing for the mount point's parent (to see mount point itself):${NC}"
    run_local_command "ls -ld \"$MOUNT_POINT\""
    echo ""
    print_info "To unmount: sudo umount '$MOUNT_POINT'  OR sudo umount '$DEVICE'"
    print_info "Script finished."
    exit 0

else
    print_error "Invalid number of arguments."
    show_usage
    exit 1
fi

# Redirect script output to a temp file for analysis if needed (e.g., for cleanup logic)
# This line would typically be at the very start of the script.
# exec &> >(tee "/tmp/mount_script_log_$$")
# And ensure /tmp/mount_script_log_$$ is cleaned up.
# For now, the simple grep check on a log is removed for clarity in this version.
