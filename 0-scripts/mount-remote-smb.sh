#!/bin/bash
# Author: Roy Wiseman 2025-04
# Discover SAMBA/CIFS disk shares from a server
# Input servername as argument
# Prompts for username and password interactively unless -remove is used
# - Samba is the software (on Linux/Unix) that implements the SMB/CIFS protocol.
# - SMB (Server Message Block) is the protocol family. CIFS (Common Internet File System) is a dialect of SMB, primarily used in older versions (like SMB1).
# - Modern usage often just says "SMB share" to be protocol-neutral and up-to-date, especially since CIFS is considered legacy.
# - mount.cifs is the name of the userspace mount helper for SMB shares, and despite its name, it supports modern SMB dialects (SMB2, SMB3), not just CIFS (SMB1).
#   The underlying kernel module is also called cifs.ko, even though it speaks newer SMB dialects.
# TROUBLESHOOTING WINDOWS:
# If your main Windows account is a Microsoft account (i.e. "someusername@hotmail.com", truncated to 5-char "someu" in Windows):
# - Make sure File and Printer Sharing is enabled on Windows
#     Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"
# - It might be possible to connect from Linux with the below, but these are both unlikely (various other settings have to be in place)
#     smbclient -L servername -U "servername\\someusername@hotmail.com"   # Note \\ to escape the \ in bash
#     smbclient -L servername -U "someusername@hotmail.com%password"
#   It's usually best to create a separate user and use that for sharing:   net user smbuser mypass
#     sudo mount -t cifs //white/d /mnt/test -o user=boss,vers=3.0   # Remember that /mnt/test folder must exist before running this
# Check the share's permissions: Right-click the shared folder → Properties → Sharing → Advanced Sharing → Permissions.
# https://chatgpt.com/share/6816ee6d-a774-8006-a7eb-9876f8142547

# --- Adjust PATH to include sbin directories ---
# This helps find commands like mount.cifs that might not be in a user's default PATH
PATH="/sbin:/usr/sbin:$PATH"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Default Input Variables ---
REMOVE_FLAG=""
SERVER_NAME=""
USERNAME="" # Will be prompted if not removing
PASSWORD="" # Will be prompted if not removing

# --- Argument Parsing ---

# Check if any arguments were provided
if [ $# -eq 0 ]; then
  echo "Scan a hostname or IP to find all of its shares and mount them locally under /mnt"
  
  echo "Usage:    ${0##*/} <server_name>"   # Replace $(basename $0) by ${0##*/}
  echo "          ${0##*/} <server_name> -remove"
  exit 1
fi

# Parse arguments sequentially
# We expect exactly one positional argument (server_name) and optional flags (-remove)
arg_count=0
for arg in "$@"; do
    case "$arg" in
        -remove)
            REMOVE_FLAG="-remove"
            ;;
        -*)
            echo "Unknown option: $arg"
            echo "Usage:    $(basename "$0") <server_name>"
            echo "          $(basename "$0") <server_name> -remove"
            exit 1
            ;;
        *) # This is a positional argument (doesn't start with -)
            arg_count=$((arg_count + 1))
            case "$arg_count" in
                1) SERVER_NAME="$arg" ;; # Assign the first positional argument as SERVER_NAME
                *) # More than one positional argument is now considered an error
                    echo "Too many arguments."
                    echo "Usage:    $(basename "$0") <server_name>"
                    echo "          $(basename "$0") <server_name> -remove"
                    exit 1
                    ;;
            esac
            ;;
    esac
done

# --- Validation and Input Prompt ---

# Check if the required server name was provided
if [ -z "$SERVER_NAME" ]; then
    echo "Error: Server name is required."
    echo "Usage:    $(basename "$0") <server_name>"
    echo "          $(basename "$0") <server_name> -remove"
    exit 1
fi

# Based on whether -remove was used, either proceed to remove or prompt for credentials
if [ "$REMOVE_FLAG" == "-remove" ]; then
    # In remove mode, only server_name is needed. arg_count should be exactly 1.
    if [ "$arg_count" -ne 1 ]; then
        echo "Error: In remove mode, only the server name should be provided."
        echo "Usage: $(basename "$0") <server_name> -remove"
        exit 1
    fi
    echo "Server name for removal: $SERVER_NAME"
    # USERNAME and PASSWORD remain empty, which is correct for remove mode
else
    # Not in remove mode, we need credentials. arg_count should be exactly 1.
     if [ "$arg_count" -ne 1 ]; then
        echo "Error: When mounting, only the server name should be provided as argument."
        echo "Usage: $(basename "$0") <server_name>"
        echo "          $(basename "$0") <server_name> -remove"
        exit 1
    fi
    echo "Server name: $SERVER_NAME"
    echo "--- Enter credentials for mounting shares ---"

    # Prompt for username
    read -r -p "Username for $SERVER_NAME: " USERNAME

    # Prompt for password (hidden input using -s flag)
    read -r -s -p "Password for $USERNAME@$SERVER_NAME: " PASSWORD
    echo # Add a newline after the hidden password input

    # Basic check if username was entered
    if [ -z "$USERNAME" ]; then
        echo "Error: Username cannot be empty."
        exit 1
    fi
    # Password can technically be empty for some guest shares, so we won't error here
fi

# Set the base directory where shares will be mounted - This is done after SERVER_NAME is set
BASE_MOUNT_DIR="/mnt/$SERVER_NAME"


# --- Remove Mode ---
# The logic inside this block uses $SERVER_NAME and REMOVE_FLAG
# USERNAME and PASSWORD are not used in this block
if [ "$REMOVE_FLAG" == "-remove" ]; then
    echo "Entering remove mode for server: $SERVER_NAME"

    # Check if base mount directory exists
    if [ ! -d "$BASE_MOUNT_DIR" ]; then
        echo "Error: Base directory '$BASE_MOUNT_DIR' does not exist."
        exit 1
    fi

    # Loop through all subdirectories (shares) and unmount/remove them
    for share in "$BASE_MOUNT_DIR"/*; do
        if [ -d "$share" ]; then
            SHARE_NAME=$(basename "$share")

            echo "Unmounting and cleaning share: $SHARE_NAME"

            # Unmount the share
            sudo umount "$share"

            # Check if the share directory is empty
            if [ "$(ls -A "$share")" ]; then
                echo "Warning: Directory $share is not empty, skipping removal."
            else
                # Remove the directory if empty
                sudo rm -rf "$share"
                echo "Removed empty directory: $share"
            fi
        fi
    done

    # After cleaning share directories, check if the base mount directory is empty
    if [ "$(ls -A "$BASE_MOUNT_DIR")" ]; then
        echo "Warning: Base directory $BASE_MOUNT_DIR is not empty, skipping removal."
    else
        sudo rm -rf "$BASE_MOUNT_DIR"
        echo "Removed empty base directory: $BASE_MOUNT_DIR"
    fi

    exit 0
fi

# --- Create Shares (Mounting Mode) ---
# The logic inside this block uses $SERVER_NAME, $USERNAME, and $PASSWORD
# REMOVE_FLAG is not relevant in this block, as we already exited if in remove mode

# WARNING message about previous insecure method (can be removed or kept as a note)
echo "Note: Script will now prompt for username and password interactively."


# --- Prerequisite Checks ---
# Ensure cifs-utils is installed (provides mount.cifs)
# Now checks the adjusted PATH
if ! command -v mount.cifs &> /dev/null; then
    echo "Error: mount.cifs command not found even after adjusting PATH."
    echo "Please ensure cifs-utils package is correctly installed."
    exit 1
fi

# Ensure smbclient is installed
# smbclient is typically in /usr/bin, which is usually in the default PATH, but checking is good.
if ! command -v smbclient &> /dev/null; then
    echo "Error: smbclient command not found."
    echo "Please install it: sudo apt update && sudo apt install smbclient"
    exit 1
fi

# --- Find Shares ---
# This section now uses the $USERNAME and $PASSWORD obtained from the interactive prompt
echo "Listing shares on $SERVER_NAME for user $USERNAME..."

# Use smbclient to list shares (-L), provide username and password directly
# Redirect stderr to /dev/null to suppress potential smbclient errors/warnings
# Use awk to filter lines: Type is "Disk", share name is not "IPC$", and share name does not end with "$"
# Added quotes around the entire smbclient command for better readability and safety
SHARE_LIST=$(smbclient -L //"$SERVER_NAME" -U "$USERNAME%$PASSWORD" 2>/dev/null | \
             awk '$2 == "Disk" && $1 != "IPC$" && $1 !~ /\$$/ { print $1 }')

# --- Check if any mountable shares were found ---
if [ -z "$SHARE_LIST" ]; then
    echo "No non-admin Disk shares found on $SERVER_NAME or failed to list shares with provided credentials."
    echo "Check server name, username, password, network connectivity, and Windows share permissions."
    exit 1
fi

# --- Prepare Base Mount Directory ---
echo "Ensuring base mount directory exists: $BASE_MOUNT_DIR"
# Use || { ...; exit 1; } for robust error handling on mkdir
sudo mkdir -p "$BASE_MOUNT_DIR" || { echo "Error creating base directory '$BASE_MOUNT_DIR'. Exiting."; exit 1; }


# --- List Found Shares ---
echo "-------------------------"
echo "Found mountable shares:"
# Convert the list to a readable format by adding a dash before each share name
echo "$SHARE_LIST" | sed 's/^/- /'
echo "-------------------------"


# --- Mount Shares ---
echo "Proceeding to process and mount shares under $BASE_MOUNT_DIR..."

# Arrays to track results for the summary
MOUNTED_SHARES=()
SKIPPED_SHARES=()
FAILED_MOUNTS=()

# Read the share list line by line
# 'while IFS= read -r' is the robust way to loop through a string containing newlines
while IFS= read -r SHARE_NAME; do
    # --- Clean Share Name ---
    # Replace characters not typically valid in Linux filenames (and spaces) with underscores.
    # Characters: \ / : * ? " < > | and space
    CLEAN_SHARE_NAME=$(echo "$SHARE_NAME" | sed 's/[\\/:*?"<>| ]/_/g')

    # Define the full local mount point path for this specific share
    MOUNT_POINT="$BASE_MOUNT_DIR/$CLEAN_SHARE_NAME"

    echo "--> Processing share: '${SHARE_NAME}' (Local path target: '${MOUNT_POINT}')"

    # --- Check if Local Mount Point Exists ---
    if [ -d "$MOUNT_POINT" ]; then
        echo "--> Skipping '${SHARE_NAME}': Mount point directory '${MOUNT_POINT}' already exists."
        SKIPPED_SHARES+=("${SHARE_NAME}") # Add original name to skipped list
        continue # Skip to the next share
    fi

    # --- Create Mount Point Directory ---
    echo "--> Creating mount point directory: ${MOUNT_POINT}"
    sudo mkdir -p "$MOUNT_POINT"
    # Check if directory creation was successful
    if [ $? -ne 0 ]; then
        echo "--> Error: Could not create mount point directory $MOUNT_POINT. Skipping ${SHARE_NAME}."
        FAILED_MOUNTS+=("${SHARE_NAME} (Mkdir Failed)") # Add original name to failed list
        continue # Skip to the next share
    fi

    # --- Attempt to Mount ---
    echo "--> Attempting to mount //${SERVER_NAME}/${SHARE_NAME} to ${MOUNT_POINT}..."
    # Mount the share using cifs, providing path, mount point, and options:
    # username/password, and setting ownership (uid/gid) to the current user
    # This now uses the $USERNAME and $PASSWORD variables populated from the prompt
    sudo mount -t cifs //"$SERVER_NAME"/"$SHARE_NAME" "$MOUNT_POINT" \
        -o username="$USERNAME",password="$PASSWORD",uid=$(id -u),gid=$(id -g)

    # Check if the mount command was successful
    if [ $? -eq 0 ]; then
        echo "--> Successfully mounted '${SHARE_NAME}'."
        MOUNTED_SHARES+=("${SHARE_NAME}") # Add to mounted list
    else
        echo "--> Error mounting '${SHARE_NAME}' to '${MOUNT_POINT}'."
        echo "    Check network connectivity, credentials, or Windows share permissions."
        FAILED_MOUNTS+=("${SHARE_NAME} (Mount Failed)") # Add to failed list
    fi

done <<< "$SHARE_LIST" # Use process substitution to feed SHARE_LIST line by line into the loop

echo "--- Mounting Process Complete ---"

# --- Summary ---
echo "Summary of Operations:"
echo "---------------------------------"

if [ ${#SKIPPED_SHARES[@]} -gt 0 ]; then
    echo -e "${RED}Skipped Shares (Mount point directory existed):${NC}"
    for s in "${SKIPPED_SHARES[@]}"; do echo " - $s"; done
    echo "---------------------------------"
fi

if [ ${#FAILED_MOUNTS[@]} -gt 0 ]; then
    echo -e "${RED}Failed Shares (Errors during mkdir or mount):${NC}"
    for s in "${FAILED_MOUNTS[@]}"; do echo " - $s"; done
    echo "---------------------------------"
fi

if [ ${#MOUNTED_SHARES[@]} -gt 0 ]; then
    echo -e ${GREEN}"Successfully Mounted Shares:${NC}"
    for s in "${MOUNTED_SHARES[@]}"; do echo " - $s"; done
else
    echo "No shares were successfully mounted."
fi
echo "---------------------------------"
