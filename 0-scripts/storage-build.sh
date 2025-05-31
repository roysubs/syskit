#!/bin/bash
# Author: Roy Wiseman 2025-01
# Revised by AI (Gemini) for error correction, enhancements, and extensive commenting.
# Patched by AI (Gemini) 2025-05-22 to prompt for a unified mount/share base name.

# ========== COMPREHENSIVE DISK PARTITIONING, MOUNTING & SHARING SCRIPT ==========
#
# This script automates the entire process of preparing a new disk or partitioning
# existing free space on a disk. It handles:
# - GPT partition table creation if needed.
# - Creating a new primary partition (ext4) using specified size or largest free space.
# - Aligning the partition correctly.
# - Formatting the partition with ext4 (lazy_itable_init).
# - Optionally adjusting reserved filesystem space using tune2fs.
# - Optionally mounting the partition via UUID and adding to /etc/fstab (with 'nofail').
#   Mount point and share names are based on a user-provided or derived base name.
# - Optionally creating NFS and Samba shares for the mounted partition.
#
# Features:
# - Root privilege check with auto-sudo elevation.
# - Supports human-readable sizes (e.g., 5G, 100M, 0.5T) for partitions.
# - Advanced ext4 formatting options.
# - Includes 'partprobe' to ensure kernel recognizes new partitions.
# - Idempotent checks for fstab, NFS, and Samba configurations.
# - Samba configuration validation using 'testparm'.
# - Detailed step-by-step output and error handling.
# - Interactive prompts for optional features, overridable by command-line switches.
#
# For full USAGE, run: ./storage-build.sh --help (or ./scriptname --help)
#
# SAFETY:
# - ALWAYS DOUBLE-CHECK THE TARGET DEVICE (/dev/sdX) BEFORE RUNNING!
# - This script performs disk-level operations and requires root privileges.
#   Incorrect use can lead to DATA LOSS. Use with EXTREME CAUTION.
# - It's recommended to run this on unmounted devices or devices where existing
#   data on the target free space is not needed.
# ===================================================================================

# --- Color Definitions ---
RESET_COLOR='\033[0m' # No Color / Reset
ERROR_COLOR='\033[0;31m'
SUCCESS_COLOR='\033[0;32m'
CMD_COLOR='\033[0;32m' # Green for commands themselves
DEVICE_COLOR='\033[0;32m' # Green for device names
WARN_COLOR='\033[1;33m'
HEADER_COLOR='\033[1;33m' # Yellow for phase headers & summary
INFO_COLOR='\033[1;36m' # Bright Cyan for script start etc.
CMD_PREFIX_COLOR="${RESET_COLOR}" # Normal white for "Running: " prefix
PROMPT_COLOR="${WARN_COLOR}" # Yellow for prompts

# --- Global Flags and Default Settings ---
PROMPT_USER=true
PAUSE_BETWEEN_STAGES=false
AUTO_ADD_FSTAB=false
AUTO_SETUP_SAMBA=false
AUTO_SETUP_NFS=false
RESERVED_PERCENT_VAL=""
FSTAB_MODIFIED=false
USER_CONFIG_NAME="" # Will store the user-defined base name for mount/shares

# --- Helper Functions ---

# Function: show_usage
# Description: Displays help information for the script.
show_usage() {
    echo -e "${INFO_COLOR}Comprehensive Disk Setup Script${RESET_COLOR}"
    echo "This script automates disk partitioning, formatting, mounting, and optionally sharing."
    echo "Mount point under /mnt/ and share names will be based on a name you provide during interactive setup,"
    echo "or derived from the partition name if run non-interactively."
    echo ""
    echo -e "${HEADER_COLOR}USAGE:${RESET_COLOR}"
    echo "  sudo ${0##*/} [OPTIONS] /dev/sdX [SIZE]"
    echo ""
    echo -e "${HEADER_COLOR}ARGUMENTS:${RESET_COLOR}"
    echo "  /dev/sdX      Target block device (e.g., /dev/sdb, /dev/nvme0n1). MANDATORY."
    echo -e "                ${WARN_COLOR}TIP${RESET_COLOR}: For stability, consider using persistent paths like '/dev/disk/by-id/...'"
    echo "  SIZE          (Optional) Desired size for the new partition (e.g., 5G, 100M, 0.5T)."
    echo "                If omitted, uses the largest available contiguous free space."
    echo ""
    echo -e "${HEADER_COLOR}OPTIONS:${RESET_COLOR}"
    echo "  -h, --help    Show this help message and exit."
    echo "  --noprompts   Suppress all interactive prompts for optional features."
    echo "                Defaults to 'no' for fstab, Samba, NFS, and no change for tune2fs,"
    echo "                unless overridden by specific feature switches below."
    echo "  --prompts     Pause after each major phase for user review (press Enter to continue)."
    echo ""
    echo -e "${HEADER_COLOR}Optional Feature Switches (override --noprompts for specific actions):${RESET_COLOR}"
    echo "  --fstab       Automatically add the new partition to /etc/fstab for persistent mounting."
    echo "  --samba       Automatically configure a Samba share for the new partition."
    echo "  --nfs         Automatically configure an NFS share for the new partition."
    echo "  --reserved X  Automatically set ext4 reserved space to X percent (e.g., --reserved 1.5)."
    echo ""
    echo -e "${HEADER_COLOR}EXAMPLES:${RESET_COLOR}"
    echo "  sudo ${0##*/} /dev/sdb 100G"
    echo "  sudo ${0##*/} --fstab --samba --reserved 1 /dev/sdc"
    echo "  sudo ${0##*/} --noprompts /dev/sdd"
    echo ""
    echo -e "${WARN_COLOR}SAFETY: ALWAYS double-check the target device. Incorrect use can lead to data loss.${RESET_COLOR}"
}

# Function: run_command
# Description: Executes a given command, displays it, and exits the script if the command fails.
run_command() {
    echo -e "${CMD_PREFIX_COLOR}Running: ${CMD_COLOR}$*${RESET_COLOR}"
    "$@"
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "${ERROR_COLOR}ERROR: Command failed with exit code $exit_code: $*${RESET_COLOR}"
        exit $exit_code
    fi
    return $exit_code
}

# Function: convert_size_to_bytes
# Description: Converts a human-readable size string to bytes using numfmt.
convert_size_to_bytes() {
    local size_in="$1"
    local value_bytes
    if [ -z "$size_in" ]; then
        echo -e "${ERROR_COLOR}ERROR: Size input cannot be empty.${RESET_COLOR}"
        return 1
    fi
    value_bytes=$(numfmt --from=iec "$size_in" 2>/dev/null)
    local exit_code=$?
    if [ $exit_code -ne 0 ] || ! [[ "$value_bytes" =~ ^[0-9]+$ ]]; then
        echo -e "${ERROR_COLOR}ERROR: Invalid size format or unable to convert '$size_in' to bytes.${RESET_COLOR}"
        echo -e "${ERROR_COLOR}        Please use standard numbers and IEC units (e.g., '1024', '512K', '100M', '0.5G', '2T').${RESET_COLOR}"
        if [ $exit_code -ne 0 ]; then
            echo -e "${ERROR_COLOR}        (numfmt utility failed with exit code $exit_code).${RESET_COLOR}"
        fi
        return 1
    fi
    echo "$value_bytes"
    return 0
}

# Function: ask_yes_no_question
# Description: Prompts the user with a yes/no question.
# Arguments: $1 - The question string.
#            $2 - Default answer ("yes" or "no").
# Returns: 0 for Yes, 1 for No.
ask_yes_no_question() {
    local question="$1"
    local default_answer="$2" # "yes" or "no"
    local answer_prompt
    local actual_answer

    if [ "$default_answer" = "yes" ]; then
        answer_prompt=" (Y/n): "
    else
        answer_prompt=" (y/N): "
    fi

    while true; do
        read -r -p "$(echo -e "${PROMPT_COLOR}${question}${answer_prompt}${RESET_COLOR}")" actual_answer
        if [ -z "$actual_answer" ]; then # User pressed Enter
            if [ "$default_answer" = "yes" ]; then return 0; else return 1; fi
        fi
        case "$actual_answer" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;; # Yes
            [Nn]|[Nn][Oo]) return 1   ;; # No
            *) echo -e "${WARN_COLOR}Please answer 'yes' or 'no'.${RESET_COLOR}" ;;
        esac
    done
}

# Function: pause_if_interactive
# Description: Pauses script execution if --prompts flag is set.
pause_if_interactive() {
    local phase_name="$1"
    if [ "$PAUSE_BETWEEN_STAGES" = true ]; then
        echo -e "${PROMPT_COLOR}------------------------------------------------------------${RESET_COLOR}"
        read -r -p "$(echo -e "${PROMPT_COLOR}Phase '${phase_name}' complete. Press Enter to continue or Ctrl+C to abort...${RESET_COLOR}")"
        echo -e "${PROMPT_COLOR}------------------------------------------------------------${RESET_COLOR}"
    fi
}


# --- Store all original arguments for sudo re-execution and initial checks ---
ALL_ORIGINAL_ARGS=("$@")

# --- Parse Command Line Arguments ---
parsed_device=""
parsed_size=""
remaining_args=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_usage; exit 0 ;;
        --noprompts)
            PROMPT_USER=false; shift ;;
        --prompts)
            PAUSE_BETWEEN_STAGES=true; shift ;;
        --fstab)
            AUTO_ADD_FSTAB=true; shift ;;
        --samba)
            AUTO_SETUP_SAMBA=true; shift ;;
        --nfs)
            AUTO_SETUP_NFS=true; shift ;;
        --reserved)
            if [[ -n "$2" ]] && ! [[ "$2" =~ ^-- ]]; then
                RESERVED_PERCENT_VAL="$2"
                if ! [[ "$RESERVED_PERCENT_VAL" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
                    echo -e "${ERROR_COLOR}ERROR: Invalid percentage for --reserved: '$RESERVED_PERCENT_VAL'. Must be a positive number.${RESET_COLOR}"; show_usage; exit 1;
                fi
                local percent_float=$(awk "BEGIN {print $RESERVED_PERCENT_VAL}")
                if (( $(echo "$percent_float < 0 || $percent_float > 50" | bc -l) )); then
                    echo -e "${ERROR_COLOR}ERROR: Reserved percentage '$RESERVED_PERCENT_VAL' must be between 0 and 50.${RESET_COLOR}"; show_usage; exit 1;
                fi
                shift 2
            else
                echo -e "${ERROR_COLOR}ERROR: --reserved option requires a percentage value.${RESET_COLOR}"; show_usage; exit 1;
            fi ;;
        -*)
            echo -e "${ERROR_COLOR}Unknown option: $1${RESET_COLOR}"; show_usage; exit 1 ;;
        *)
            remaining_args+=("$1"); shift ;;
    esac
done

if [ ${#remaining_args[@]} -ge 1 ]; then parsed_device="${remaining_args[0]}"; fi
if [ ${#remaining_args[@]} -ge 2 ]; then parsed_size="${remaining_args[1]}"; fi
if [ ${#remaining_args[@]} -gt 2 ]; then echo -e "${ERROR_COLOR}ERROR: Too many positional arguments provided after options.${RESET_COLOR}"; show_usage; exit 1; fi

if [ ${#ALL_ORIGINAL_ARGS[@]} -eq 0 ]; then show_usage; exit 0; fi

# ---- Initial Checks and Setup ----
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${WARN_COLOR}Root privileges required. Rerunning with sudo...${RESET_COLOR}\n"
    exec sudo -E "$0" "${ALL_ORIGINAL_ARGS[@]}"
fi

echo -e "${INFO_COLOR}Starting Comprehensive Disk Setup Script...${RESET_COLOR}"

if [ -z "$parsed_device" ]; then echo -e "${ERROR_COLOR}ERROR: Target block device not specified.${RESET_COLOR}"; show_usage; exit 1; fi
device="$parsed_device"
user_requested_size="$parsed_size"

if [ ! -b "$device" ]; then
    echo -e "${ERROR_COLOR}ERROR: Device '$device' is not a valid block device. Please verify.${RESET_COLOR}"
    echo "Available block devices (excluding partitions, showing full paths):"
    lsblk -dpno NAME,TYPE,SIZE,MODEL
    exit 1
fi

echo -e "\n${HEADER_COLOR}Phase 1: Device Information and Preparation${RESET_COLOR}"
echo -e "Target device: ${DEVICE_COLOR}$device${RESET_COLOR}"
[ -n "$user_requested_size" ] && echo -e "Requested partition size: ${INFO_COLOR}$user_requested_size${RESET_COLOR}"

echo "Displaying current disk layout for all devices (lsblk ...):"
run_command lsblk -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,FSTYPE,UUID,MOUNTPOINT,LABEL,MODEL
echo "Details for target device '$device' (lsblk \"$device\" ...):"
run_command lsblk "$device" -o NAME,MAJ:MIN,RM,SIZE,RO,TYPE,FSTYPE,UUID,MOUNTPOINT,LABEL,MODEL

sector_size_bytes=$(blockdev --getss "$device")
if [ $? -ne 0 ] || ! [[ "$sector_size_bytes" =~ ^[0-9]+$ ]] || [ "$sector_size_bytes" -le 0 ]; then
    echo -e "${WARN_COLOR}WARNING: Could not reliably determine sector size for '$device' using blockdev. Attempting fallback with parted...${RESET_COLOR}"
    sector_size_bytes=$(parted --script "$device" unit B print | awk '/Sector size \(logical\/physical\):/ {gsub(/B/,"",$3); split($3,a,"/"); print a[1]; exit}')
    if ! [[ "$sector_size_bytes" =~ ^[0-9]+$ ]] || [ "$sector_size_bytes" -le 0 ]; then
        echo -e "${ERROR_COLOR}ERROR: Failed to determine a valid sector size for '$device'. Exiting.${RESET_COLOR}"; exit 1;
    fi
    echo "Determined sector size (via parted fallback): $sector_size_bytes bytes"
else
    echo "Determined sector size (via blockdev): $sector_size_bytes bytes"
fi

echo -e "\n${INFO_COLOR}Step 1.1: Checking and ensuring GPT partition table on $device...${RESET_COLOR}"
if ! parted_output=$(parted --script "$device" print 2>&1); then
    if echo "$parted_output" | grep -qi "unrecognised disk label"; then
        echo "Unrecognised disk label on $device. Creating a new GPT partition table..."
        run_command parted --script "$device" mklabel gpt
        echo -e "${SUCCESS_COLOR}GPT partition table created successfully.${RESET_COLOR}"
    else
        echo -e "${ERROR_COLOR}ERROR: 'parted print' failed for $device for an unknown reason. Output:${RESET_COLOR}"; echo "$parted_output"; exit 1;
    fi
elif echo "$parted_output" | grep -qi "unrecognised disk label"; then # Should be caught by above, but as a safeguard
    echo "Unrecognised disk label on $device (despite parted print success). Creating a new GPT partition table..."
    run_command parted --script "$device" mklabel gpt
    echo -e "${SUCCESS_COLOR}GPT partition table created successfully.${RESET_COLOR}"
else
    echo "Existing valid partition table found on $device."
fi
echo "Current partition layout on $device (parted ... print free):"
run_command parted --script "$device" unit s print free

pause_if_interactive "Device Information and Preparation"

# ---- Partition Creation Logic ----
echo -e "\n${HEADER_COLOR}Phase 2: Partition Definition and Creation${RESET_COLOR}"
echo "Analyzing free space on $device (units in sectors)..."
parted_free_output=$(parted --script "$device" unit s print free)
echo "$parted_free_output"
largest_start_s=0; largest_end_s=0; largest_size_s=0
largest_free_block_info=$(echo "$parted_free_output" | \
    awk '
    BEGIN { max_size = 0; start_s = 0; end_s = 0; }
    /Free Space/ {
        current_start = ""; current_end = ""; current_size = "";
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^[0-9]+s$/) {
                val = $i; sub(/s$/, "", val);
                if (current_start == "") current_start = val;
                else if (current_end == "") current_end = val;
                else if (current_size == "") { current_size = val; break; }
            }
        }
        if (current_size != "" && current_size + 0 > max_size + 0) {
            max_size = current_size; start_s = current_start; end_s = current_end;
        }
    }
    END { if (max_size > 0) print start_s, end_s, max_size; }
    ')
if [ -z "$largest_free_block_info" ]; then
    echo -e "${WARN_COLOR}WARNING: No usable 'Free Space' segments found by primary method. Attempting fallback...${RESET_COLOR}"
    largest_free_block_info=$(echo "$parted_free_output" | awk '
        BEGIN { max_size = 0; start_s = 0; end_s = 0; }
        NF >= 3 && $1 ~ /^[0-9]+s$/ && $2 ~ /^[0-9]+s$/ && $3 ~ /^[0-9]+s$/ && \
        ($4 == "" || tolower($4) == "loop" || tolower($4) == "free") {
            cs = $1; sub(/s$/,"",cs); ce = $2; sub(/s$/,"",ce); csize = $3; sub(/s$/,"",csize);
            if (csize+0 > max_size+0) { max_size=csize; start_s=cs; end_s=ce;}
        }
        END { if (max_size > 0) print start_s, end_s, max_size; }
    ')
    if [ -z "$largest_free_block_info" ]; then
        echo -e "${ERROR_COLOR}ERROR: Fallback method also failed to find any usable unallocated space. Inspect '$device' manually.${RESET_COLOR}"; exit 1;
    fi
    echo "Found unallocated space (fallback method)."
fi
read -r largest_start_s largest_end_s largest_size_s <<< "$largest_free_block_info"
echo "Identified largest free/unallocated block: StartSector=${largest_start_s}s, EndSector=${largest_end_s}s, SizeInSectors=${largest_size_s}s"
sectors_for_1mib_alignment=$((1048576 / sector_size_bytes))
sectors_for_1mib_alignment=$((sectors_for_1mib_alignment > 0 ? sectors_for_1mib_alignment : 1))
aligned_start_s=$(( ( (largest_start_s + sectors_for_1mib_alignment - 1) / sectors_for_1mib_alignment ) * sectors_for_1mib_alignment ))
if [ "$aligned_start_s" -lt "$largest_start_s" ]; then aligned_start_s=$((aligned_start_s + sectors_for_1mib_alignment)); fi
if [ "$aligned_start_s" -ge "$largest_end_s" ]; then echo -e "${ERROR_COLOR}ERROR: Calculated aligned start sector ($aligned_start_s) is at or beyond free block end ($largest_end_s).${RESET_COLOR}"; exit 1; fi
echo "Calculated aligned start sector for new partition: ${aligned_start_s}s"
max_possible_sectors_from_aligned_start=$((largest_end_s - aligned_start_s + 1))
if [ "$max_possible_sectors_from_aligned_start" -le 0 ]; then echo -e "${ERROR_COLOR}ERROR: No space available after aligning start sector.${RESET_COLOR}"; exit 1; fi
actual_part_end_s=""; partition_size_desc=""; final_sector_count=0
if [ -n "$user_requested_size" ]; then
    echo "Processing user requested size: $user_requested_size"
    requested_bytes=$(convert_size_to_bytes "$user_requested_size")
    if [ $? -ne 0 ] || [ -z "$requested_bytes" ]; then exit 1; fi
    echo "Requested size in bytes: $requested_bytes"
    if [ "$sector_size_bytes" -le 0 ]; then echo -e "${ERROR_COLOR}CRITICAL ERROR: Sector size invalid.${RESET_COLOR}"; exit 1; fi
    requested_sectors_count=$((requested_bytes / sector_size_bytes))
    echo "Requested size in sectors (count): $requested_sectors_count"
    if [ "$requested_sectors_count" -le 0 ]; then echo -e "${ERROR_COLOR}ERROR: Requested size too small (<=0 sectors).${RESET_COLOR}"; exit 1; fi
    if [ "$requested_sectors_count" -gt "$max_possible_sectors_from_aligned_start" ]; then
        echo -e "${WARN_COLOR}WARNING: Requested size ($requested_sectors_count sectors) exceeds available space ($max_possible_sectors_from_aligned_start sectors). Using maximum available.${RESET_COLOR}"
        actual_part_end_s="$largest_end_s"
        final_sector_count=$max_possible_sectors_from_aligned_start
    else
        actual_part_end_s=$((aligned_start_s + requested_sectors_count - 1))
        final_sector_count=$requested_sectors_count
    fi
    partition_size_desc="$user_requested_size (resolved to $final_sector_count sectors)"
else
    echo "No specific size requested. Using all available space in the largest free block from aligned start."
    actual_part_end_s="$largest_end_s"
    final_sector_count=$max_possible_sectors_from_aligned_start
    partition_size_desc="maximum available ($final_sector_count sectors from aligned start)"
fi
if [ "$aligned_start_s" -ge "$actual_part_end_s" ]; then echo -e "${ERROR_COLOR}CRITICAL ERROR: Partition start ($aligned_start_s) not less than end ($actual_part_end_s). Zero or negative size.${RESET_COLOR}"; exit 1; fi
if [ "$actual_part_end_s" -gt "$largest_end_s" ]; then echo -e "${ERROR_COLOR}CRITICAL ERROR: Partition end ($actual_part_end_s) exceeds free block end ($largest_end_s).${RESET_COLOR}"; exit 1; fi
echo "Creating new partition: StartSector=${aligned_start_s}s, EndSector=${actual_part_end_s}s. Intended size: $partition_size_desc"
run_command parted --script -a optimal "$device" mkpart primary ext4 ${aligned_start_s}s ${actual_part_end_s}s
echo "Forcing kernel to reload partition table for $device (partprobe)..."
run_command partprobe "$device"
echo "Waiting a few seconds for kernel to process partition changes..."
sleep 3
echo "Identifying the newly created partition on $device..."
device_escaped_for_grep=$(echo "$device" | sed 's/[][\/.*^$]/\\&/g')
new_partition=$(lsblk -rnp -o NAME,TYPE | awk -v dev_pattern="^${device_escaped_for_grep}[p]?[0-9]+$" '$1 ~ dev_pattern && $2 == "part" {print $1}' | tail -n 1)

if [ -z "$new_partition" ]; then
    echo -e "${ERROR_COLOR}ERROR: Failed to detect the new partition on '$device'. Check 'lsblk $device'.${RESET_COLOR}"; lsblk "$device"; exit 1;
fi
echo -e "New partition detected: ${DEVICE_COLOR}$new_partition${RESET_COLOR}"

# ---- Phase 2.5: Define Mount/Share Name ----
echo -e "\n${HEADER_COLOR}Phase 2.5: Define Mount Point and Share Base Name${RESET_COLOR}"
if [ "$PROMPT_USER" = true ] && { [ "$AUTO_ADD_FSTAB" = true ] || [ "$AUTO_SETUP_SAMBA" = true ] || [ "$AUTO_SETUP_NFS" = true ] || \
    ask_yes_no_question "Do you want to configure mounting and/or sharing for '$new_partition'?" "yes" ;} ; then
    
    temp_basename_for_suggestion=$(basename "$new_partition" | sed 's/[^a-zA-Z0-9_-]//g')
    if [ -z "$temp_basename_for_suggestion" ]; then temp_basename_for_suggestion="newvolume"; fi

    while true; do
        read -r -p "$(echo -e "${PROMPT_COLOR}Enter a base name for /mnt/... and shares (e.g., 'downloads', 'data', default: '$temp_basename_for_suggestion'): ${RESET_COLOR}")" user_input_name
        USER_CONFIG_NAME="${user_input_name:-$temp_basename_for_suggestion}"

        if [[ "$USER_CONFIG_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
            if [[ "${#USER_CONFIG_NAME}" -gt 15 ]] && { [ "$AUTO_SETUP_SAMBA" = true ] || ask_yes_no_question "Will you be setting up a Samba share (name '$USER_CONFIG_NAME' is >15 chars)?" "no" ;}; then
                 echo -e "${WARN_COLOR}Warning: Name '$USER_CONFIG_NAME' is longer than 15 characters, which might cause issues with older NetBIOS clients if used for Samba.${RESET_COLOR}"
                 if ! ask_yes_no_question "Continue with this name?" "yes"; then
                    continue # Re-ask for the name
                 fi
            fi
            echo -e "${INFO_COLOR}Base name for mount/shares will be: '${USER_CONFIG_NAME}'${RESET_COLOR}"
            break
        else
            echo -e "${WARN_COLOR}Invalid name. Please use letters, numbers, underscores, or hyphens, starting with a letter or number. Try again.${RESET_COLOR}"
        fi
    done
else
    # Non-interactive mode, or user opted out of all mounting/sharing in initial Phase 2.5 question
    if { [ "$AUTO_ADD_FSTAB" = true ] || [ "$AUTO_SETUP_SAMBA" = true ] || [ "$AUTO_SETUP_NFS" = true ]; } && [ "$PROMPT_USER" = false ]; then
        # If any auto feature is on in non-interactive mode, derive the name
        USER_CONFIG_NAME=$(basename "$new_partition" | sed 's/[^a-zA-Z0-9_-]//g')
        if [ -z "$USER_CONFIG_NAME" ]; then USER_CONFIG_NAME="auto_storage"; fi # Absolute fallback
        echo -e "${INFO_COLOR}Using base name '$USER_CONFIG_NAME' for mount/shares (non-interactive mode).${RESET_COLOR}"
    else
        # User opted out of mounting/sharing in Phase 2.5 prompt, or no auto-flags and non-interactive
        USER_CONFIG_NAME="" # Explicitly clear it if no mounting/sharing is intended from this point
        echo -e "${INFO_COLOR}Skipping specific name configuration for mount/shares as it's not requested or not in interactive mode without auto-flags.${RESET_COLOR}"
    fi
fi

pause_if_interactive "Partition Definition and Creation & Naming" # Combined pause point

# ---- Formatting, Optional tune2fs, Optional Mounting & fstab ----
echo -e "\n${HEADER_COLOR}Phase 3: Formatting and System Integration${RESET_COLOR}"

if mount | grep -q "^$new_partition "; then
    echo -e "${ERROR_COLOR}CRITICAL ERROR: Partition '$new_partition' is ALREADY MOUNTED. Cannot format.${RESET_COLOR}"; exit 1;
fi

echo "Formatting $new_partition as ext4 (lazy init options)..."
run_command mkfs.ext4 -F -E lazy_itable_init=1,lazy_journal_init=1 "$new_partition"
echo -e "${SUCCESS_COLOR}$new_partition successfully formatted as ext4.${RESET_COLOR}"

# --- Optional: tune2fs for reserved space ---
perform_tune2fs=false
new_reserved_percent="$RESERVED_PERCENT_VAL"

if [ -n "$new_reserved_percent" ]; then
    perform_tune2fs=true
elif [ "$PROMPT_USER" = true ]; then
    echo -e "\n${INFO_COLOR}Filesystem Reserved Space Adjustment (tune2fs):${RESET_COLOR}"
    echo "Newly formatted ext4 partitions reserve space (typically 5%) for root user and system stability."
    echo "You can adjust this percentage. Reducing it gives more space to users but less buffer for the system."
    total_blocks=$(tune2fs -l "$new_partition" | awk -F': *' '/^Block count:/ {print $2}')
    block_size_bytes=$(tune2fs -l "$new_partition" | awk -F': *' '/^Block size:/ {print $2}')
    current_reserved_blocks=$(tune2fs -l "$new_partition" | awk -F': *' '/^Reserved block count:/ {print $2}')
    if [ -n "$total_blocks" ] && [ -n "$block_size_bytes" ] && [ -n "$current_reserved_blocks" ]; then
        partition_size_bytes=$((total_blocks * block_size_bytes))
        current_reserved_bytes=$((current_reserved_blocks * block_size_bytes))
        current_reserved_percent_actual=$(awk "BEGIN {printf \"%.2f\", ($current_reserved_blocks/$total_blocks)*100}")
        echo "Partition size: $(numfmt --to=iec-i --suffix=B --format="%.2f" "$partition_size_bytes")"
        echo "Current reserved space: $current_reserved_percent_actual% ($(numfmt --to=iec-i --suffix=B --format="%.2f" "$current_reserved_bytes"))"
        percent_1_bytes=$((partition_size_bytes / 100)); percent_01_bytes=$((partition_size_bytes / 1000))
        echo "  - 1% reserved would be: $(numfmt --to=iec-i --suffix=B --format="%.2f" "$percent_1_bytes")"
        echo "  - 0.1% reserved would be: $(numfmt --to=iec-i --suffix=B --format="%.2f" "$percent_01_bytes")"
    else echo -e "${WARN_COLOR}Could not retrieve detailed block information to calculate current/example reserved sizes.${RESET_COLOR}"; fi

    if ask_yes_no_question "Do you want to adjust the reserved space percentage? (Suggesting 1%)" "no"; then
        perform_tune2fs=true
        read -r -p "$(echo -e "${PROMPT_COLOR}Enter desired reserved percentage (e.g., 1, 0.5, default 1 if empty): ${RESET_COLOR}")" user_percent
        new_reserved_percent=${user_percent:-1}
        if ! [[ "$new_reserved_percent" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            echo -e "${ERROR_COLOR}Invalid percentage '$new_reserved_percent'. Must be a number. Skipping adjustment.${RESET_COLOR}"; perform_tune2fs=false;
        else
            percent_float_val=$(awk "BEGIN {print $new_reserved_percent}")
            if (( $(echo "$percent_float_val < 0 || $percent_float_val > 50" | bc -l) )); then
                echo -e "${ERROR_COLOR}Reserved percentage '$new_reserved_percent' must be between 0 and 50. Skipping adjustment.${RESET_COLOR}"; perform_tune2fs=false;
            fi
        fi
    else echo "Keeping default reserved space."; fi
fi
if [ "$perform_tune2fs" = true ] && [ -n "$new_reserved_percent" ]; then
    echo "Adjusting reserved space on $new_partition to $new_reserved_percent%...";
    run_command tune2fs -m "$new_reserved_percent" "$new_partition";
    echo -e "${SUCCESS_COLOR}Reserved space adjusted.${RESET_COLOR}";
fi

# --- Optional: Mounting and /etc/fstab entry ---
mount_point="" # Will be set if fstab/shares are configured
uuid=""

# Decide if fstab setup is needed based on USER_CONFIG_NAME and flags/prompts
should_add_to_fstab="$AUTO_ADD_FSTAB"
if [ -n "$USER_CONFIG_NAME" ]; then # Only proceed if a base name was set
    mount_point="/mnt/$USER_CONFIG_NAME" # Define the mount point path
    if [ "$AUTO_ADD_FSTAB" = false ] && [ "$PROMPT_USER" = true ]; then
        # If Samba or NFS will be auto-setup, fstab is implied as useful.
        if { [ "$AUTO_SETUP_SAMBA" = true ] || [ "$AUTO_SETUP_NFS" = true ]; } && \
           ! ask_yes_no_question "Configure persistent mounting at $mount_point (recommended for shares)?" "yes"; then
            echo -e "${WARN_COLOR}Skipping fstab entry for $mount_point. Shares might not work after reboot without manual mounting.${RESET_COLOR}"
            should_add_to_fstab=false
        elif { [ "$AUTO_SETUP_SAMBA" = true ] || [ "$AUTO_SETUP_NFS" = true ]; }; then
             echo -e "${INFO_COLOR}Persistent mounting at $mount_point will be configured as it's recommended for shares.${RESET_COLOR}"
             should_add_to_fstab=true # Implicitly yes if shares are auto and not explicitly declined
        elif ask_yes_no_question "Add $new_partition to /etc/fstab for persistent mounting at $mount_point?" "no"; then
            should_add_to_fstab=true
        fi
    elif [ "$AUTO_ADD_FSTAB" = true ]; then # --fstab flag was used
        echo -e "${INFO_COLOR}Persistent mounting at $mount_point will be configured due to --fstab flag.${RESET_COLOR}"
        should_add_to_fstab=true
    fi
else # USER_CONFIG_NAME is empty, means user opted out of all naming in Phase 2.5
    should_add_to_fstab=false
fi


if [ "$should_add_to_fstab" = true ] && [ -n "$mount_point" ]; then
    if [ ! -d "$mount_point" ]; then
        echo "Creating mount point directory: $mount_point..."
        run_command mkdir -p "$mount_point"
    fi
    echo "Retrieving UUID for $new_partition..."
    uuid=$(blkid -s UUID -o value "$new_partition")
    if [ -z "$uuid" ]; then
        echo -e "${ERROR_COLOR}ERROR: Could not retrieve UUID for '$new_partition'. Cannot add to fstab or mount by UUID.${RESET_COLOR}";
        should_add_to_fstab=false
    else
        echo -e "UUID for $new_partition is: ${SUCCESS_COLOR}$uuid${RESET_COLOR}"
        echo "Mounting $new_partition (UUID=$uuid) at $mount_point..."
        run_command mount UUID="$uuid" "$mount_point"
        echo -e "${SUCCESS_COLOR}$new_partition successfully mounted at $mount_point.${RESET_COLOR}"
        fstab_entry="UUID=$uuid $mount_point ext4 defaults,nofail 0 2"
        fstab_file="/etc/fstab"
        echo "Checking $fstab_file for existing active entries for UUID '$uuid' or mount point '$mount_point'..."
        escaped_mount_point_for_grep=$(echo "$mount_point" | sed 's#/#\\/#g')
        if grep -Eq "^[^#]*UUID=$uuid" "$fstab_file" || \
           grep -Eq "^[^#]*[[:space:]]$escaped_mount_point_for_grep[[:space:]]" "$fstab_file"; then
            echo -e "${WARN_COLOR}WARNING: An active (non-commented) entry for UUID '$uuid' or mount point '$mount_point' appears to exist in $fstab_file. Not adding a duplicate.${RESET_COLOR}"
            grep --color=always -E "(UUID=$uuid| $escaped_mount_point_for_grep )" "$fstab_file" || true
        else
            echo "Adding fstab entry to $fstab_file: $fstab_entry"
            echo "# Entry for $new_partition ($mount_point) added by $(basename "$0") on $(date)" | sudo tee -a "$fstab_file" > /dev/null
            if echo "$fstab_entry" | sudo tee -a "$fstab_file" > /dev/null; then
                echo -e "${SUCCESS_COLOR}Entry successfully added to $fstab_file.${RESET_COLOR}"; FSTAB_MODIFIED=true;
            else echo -e "${ERROR_COLOR}ERROR: Failed to append entry to $fstab_file.${RESET_COLOR}"; fi
        fi
    fi
else
    if [ -z "$USER_CONFIG_NAME" ]; then # This means they explicitly skipped naming in Phase 2.5
      echo "Skipping fstab entry and persistent mounting as no base name was configured."
    elif [ -n "$new_partition" ]; then # Base name was configured but fstab was declined/not auto
      echo "Skipping fstab entry for $mount_point as per user choice or flags."
      echo "You can manually mount $new_partition if needed (e.g., 'sudo mount $new_partition $mount_point')."
    fi
fi

if [ "$FSTAB_MODIFIED" = true ]; then
    echo "Reloading systemd manager configuration due to fstab changes (systemctl daemon-reexec)..."
    run_command systemctl daemon-reexec
fi

pause_if_interactive "Formatting and System Integration"

# ---- Optional Network Sharing ----
echo -e "\n${HEADER_COLOR}Phase 4: Optional Network Sharing Setup${RESET_COLOR}"

if [ -z "$USER_CONFIG_NAME" ] || [ -z "$mount_point" ]; then
    echo -e "${INFO_COLOR}Skipping network sharing setup as no base name/mount point was configured.${RESET_COLOR}"
    AUTO_SETUP_NFS=false # Ensure these don't run if USER_CONFIG_NAME is not set
    AUTO_SETUP_SAMBA=false
else
    echo -e "${INFO_COLOR}Using base name '$USER_CONFIG_NAME' and mount point '$mount_point' for any shares.${RESET_COLOR}"
fi

# ----- NFS Share Setup -----
should_setup_nfs="$AUTO_SETUP_NFS"
if [ -n "$USER_CONFIG_NAME" ] && [ "$AUTO_SETUP_NFS" = false ] && [ "$PROMPT_USER" = true ]; then
    if ask_yes_no_question "Configure an NFS share for $mount_point?" "no"; then
        should_setup_nfs=true
    fi
fi

if [ "$should_setup_nfs" = true ] && [ -n "$mount_point" ]; then # Check mount_point again in case fstab was skipped
    echo -e "\n${INFO_COLOR}Attempting to set up NFS Share for $mount_point...${RESET_COLOR}"
    exports_file="/etc/exports"
    # NFS primarily uses the path for export. Conceptual name is $USER_CONFIG_NAME.
    nfs_share_options="*(rw,sync,no_subtree_check,all_squash,anonuid=$(id -u),anongid=$(id -g))"
    if command -v exportfs &>/dev/null; then
        echo "NFS server tools (exportfs command) found."
        escaped_mount_point_for_grep_nfs=$(echo "$mount_point" | sed 's/[].[*^$(){}?+|/\\]/\\&/g')
        if grep -q "^\s*${escaped_mount_point_for_grep_nfs}[[:space:]]" "$exports_file"; then
            echo -e "${WARN_COLOR}WARNING: An NFS share for '$mount_point' seems to already exist in $exports_file. Skipping addition.${RESET_COLOR}"
            grep --color=always "^\s*${escaped_mount_point_for_grep_nfs}[[:space:]]" "$exports_file" || true
        else
            nfs_share_entry="$mount_point $nfs_share_options"
            echo "Adding NFS share entry to $exports_file: $nfs_share_entry"
            if echo "$nfs_share_entry" | sudo tee -a "$exports_file" > /dev/null; then
                echo "NFS share entry added. Re-exporting all shares (exportfs -ra)..."; run_command exportfs -ra;
                echo "Displaying currently active NFS exports (filtered for '$mount_point'):"
                (exportfs -v | grep --color=always "$mount_point") || echo "(No active export found for $mount_point, check nfs-server status or logs)"
                echo -e "${SUCCESS_COLOR}NFS share for '$mount_point' has been configured.${RESET_COLOR}"
            else echo -e "${ERROR_COLOR}ERROR: Failed to append NFS share entry to $exports_file.${RESET_COLOR}"; fi
        fi
        if ! (systemctl is-active --quiet nfs-kernel-server || systemctl is-active --quiet nfs-server); then
             echo -e "${WARN_COLOR}INFO: NFS server service does not seem active/installed. If sharing fails, install (e.g., 'sudo apt install nfs-kernel-server') and enable it.${RESET_COLOR}";
        else echo "NFS server service appears to be active."; fi
    else echo -e "${WARN_COLOR}NFS server tools (exportfs) not found. Skipping NFS share creation.${RESET_COLOR}"; fi
else
    if [ "$AUTO_SETUP_NFS" = false ]; then echo "Skipping NFS share configuration."; fi
fi


# ----- Samba Share Setup -----
should_setup_samba="$AUTO_SETUP_SAMBA"
samba_share_name="$USER_CONFIG_NAME" # Use the unified name

if [ -n "$USER_CONFIG_NAME" ] && [ "$AUTO_SETUP_SAMBA" = false ] && [ "$PROMPT_USER" = true ]; then
    if ask_yes_no_question "Configure a Samba share named '[$samba_share_name]' for $mount_point?" "no"; then
        should_setup_samba=true
    fi
fi

if [ "$should_setup_samba" = true ] && [ -n "$mount_point" ] && [ -n "$samba_share_name" ]; then # Check all needed vars
    echo -e "\n${INFO_COLOR}Attempting to set up Samba Share '[$samba_share_name]' for $mount_point...${RESET_COLOR}"
    smb_conf_file="/etc/samba/smb.conf"
    samba_share_config_block="\n[$samba_share_name]\n   path = $mount_point\n   browseable = yes\n   writable = yes\n   guest ok = yes\n   read only = no\n   create mask = 0664\n   directory mask = 0775\n   comment = Auto-configured share for $mount_point ($samba_share_name)\n"
    if command -v smbd &>/dev/null; then
        echo "Samba server tools (smbd command) found."
        escaped_mount_point_path_samba=$(echo "$mount_point" | sed 's/[].[*^$(){}?+|/\\]/\\&/g')
        escaped_samba_share_name=$(echo "$samba_share_name" | sed 's/[].[*^$(){}?+|/\\]/\\&/g') # Escape for grep
        if grep -qE "(^\[${escaped_samba_share_name}\]|^\s*path\s*=\s*${escaped_mount_point_path_samba}\s*$)" "$smb_conf_file"; then
            echo -e "${WARN_COLOR}WARNING: A Samba share named '[$samba_share_name]' or for path '$mount_point' seems to exist in $smb_conf_file. Skipping.${RESET_COLOR}"
            (grep --color=always -A7 -E "(^\[${escaped_samba_share_name}\]|^\s*path\s*=\s*${escaped_mount_point_path_samba}\s*$)" "$smb_conf_file" | head -n 8) || true
        else
            echo "Adding Samba share configuration to $smb_conf_file for share name '[$samba_share_name]'..."
            if echo -e "$samba_share_config_block" | sudo tee -a "$smb_conf_file" > /dev/null; then
                echo "Samba share configuration added. Validating with 'testparm -s'...";
                if testparm -s; then
                    echo "Samba configuration valid. Restarting Samba services (smbd and nmbd)..."
                    run_command systemctl restart smbd; run_command systemctl restart nmbd;
                    echo -e "${SUCCESS_COLOR}Samba share '[$samba_share_name]' for '$mount_point' should be active.${RESET_COLOR}"
                else echo -e "${ERROR_COLOR}ERROR: 'testparm -s' reported issues. Review $smb_conf_file. Services NOT restarted.${RESET_COLOR}"; fi
            else echo -e "${ERROR_COLOR}ERROR: Failed to append Samba config to $smb_conf_file.${RESET_COLOR}"; fi
        fi
        if ! (systemctl is-active --quiet smbd && systemctl is-active --quiet nmbd); then
            echo -e "${WARN_COLOR}INFO: Samba services do not seem active/installed. If sharing fails, install samba and enable services.${RESET_COLOR}";
        else echo "Samba services (smbd, nmbd) appear to be active."; fi
    else echo -e "${WARN_COLOR}Samba server tools (smbd) not found. Skipping Samba share creation.${RESET_COLOR}"; fi
else
    if [ "$AUTO_SETUP_SAMBA" = false ]; then echo "Skipping Samba share configuration."; fi
fi

pause_if_interactive "Optional Network Sharing Setup"

# ---- Final Summary ----
echo -e "\n${HEADER_COLOR}========== All Steps Completed ==========${RESET_COLOR}"
echo -e "Device processed: ${DEVICE_COLOR}$device${RESET_COLOR}"
if [ -n "$new_partition" ]; then
    echo -e "New partition created: ${DEVICE_COLOR}$new_partition${RESET_COLOR}"
    echo -e "Partition size detail: ${INFO_COLOR}$partition_size_desc${RESET_COLOR}"
    if [ "$should_add_to_fstab" = true ] && [ -n "$uuid" ] && [ -n "$mount_point" ]; then
        echo -e "Mounted at: ${DEVICE_COLOR}$mount_point${RESET_COLOR} (UUID: ${SUCCESS_COLOR}$uuid${RESET_COLOR})"
    elif [ -n "$USER_CONFIG_NAME" ] && [ -n "$mount_point" ]; then # If name was configured but fstab skipped
        echo -e "Target mount path for operations: ${DEVICE_COLOR}$mount_point${RESET_COLOR} (Ensure it's mounted if fstab entry was skipped)."
    fi

    echo -e "\n${HEADER_COLOR}Final Disk Layout for $device (lsblk \"$device\" ...):${RESET_COLOR}"
    lsblk "$device" -o NAME,SIZE,TYPE,FSTYPE,UUID,MOUNTPOINT,LABEL

    if [ "$should_add_to_fstab" = true ] && [ -n "$mount_point" ] && mountpoint -q "$mount_point"; then
        echo -e "\n${HEADER_COLOR}Filesystem Usage for new mount (df -h \"$mount_point\"):${RESET_COLOR}"
        df -h "$mount_point"
    fi

    if [ "$should_add_to_fstab" = true ] && [ -n "$uuid" ] && [ -n "$mount_point" ]; then
        echo -e "\n${HEADER_COLOR}Relevant /etc/fstab entry (grep ... $fstab_file):${RESET_COLOR}"
        escaped_mount_point_for_grep_final=$(echo "$mount_point" | sed 's#/#\\/#g')
        grep --color=always -E "(UUID=$uuid| ${escaped_mount_point_for_grep_final} )" "$fstab_file" || true
    fi

    if [ "$should_setup_nfs" = true ] && [ -n "$mount_point" ] && command -v exportfs &>/dev/null; then
        escaped_mount_point_for_grep_nfs_final=$(echo "$mount_point" | sed 's/[].[*^$(){}?+|/\\]/\\&/g')
        if grep -q "^\s*${escaped_mount_point_for_grep_nfs_final}[[:space:]]" "$exports_file"; then
            echo -e "\n${HEADER_COLOR}NFS Share Status for $mount_point (grep ... $exports_file):${RESET_COLOR}"
            grep --color=always "^\s*${escaped_mount_point_for_grep_nfs_final}[[:space:]]" "$exports_file" || true
            echo "Currently exported by NFS server (filtered for $mount_point):"
            (exportfs -v | grep --color=always "$mount_point") || echo "(Share for $mount_point not found in active NFS exports)"
        fi
    fi

    if [ "$should_setup_samba" = true ] && [ -n "$mount_point" ] && [ -n "$samba_share_name" ] && command -v smbd &>/dev/null; then
        escaped_samba_share_name_final=$(echo "$samba_share_name" | sed 's/[].[*^$(){}?+|/\\]/\\&/g')
        escaped_mount_point_path_samba_final=$(echo "$mount_point" | sed 's/[].[*^$(){}?+|/\\]/\\&/g')
        if grep -qE "(^\[${escaped_samba_share_name_final}\]|^\s*path\s*=\s*${escaped_mount_point_path_samba_final}\s*$)" "$smb_conf_file"; then
            echo -e "\n${HEADER_COLOR}Samba Share Status for '[$samba_share_name]' ($mount_point) (grep ... $smb_conf_file):${RESET_COLOR}"
            (grep --color=always -A7 -E "(^\[${escaped_samba_share_name_final}\]|^\s*path\s*=\s*${escaped_mount_point_path_samba_final}\s*$)" "$smb_conf_file" | head -n 8) || true
        fi
    fi
else
    echo -e "${WARN_COLOR}No new partition was fully processed. Check earlier messages for errors.${RESET_COLOR}"
fi

echo -e "\n${INFO_COLOR}Script finished. Please verify all configurations and test access to any configured shares.${RESET_COLOR}"
if [ -n "$mount_point" ] && ( [ -d "$mount_point" ] || [ -f "$mount_point" ] ); then # Check if mount_point was ever defined
  echo "Remember to adjust share permissions (e.g., 'sudo chmod -R a+rwX \"$mount_point\"') and security settings according to your needs."
  echo "This will probably be required to make the share writeable from remote connections."
fi

exit 0
