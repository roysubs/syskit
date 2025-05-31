#!/bin/bash
# Author: Roy Wiseman 2025-02

# Check if the required arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: ${0##*/} <WINDOWS_NAME_OR_IP> <SHARE_NAME> <USER_NAME>"
    echo "   If connecting via hostname, it must be visible from this system."
    exit 1
fi

# Check if running as root or with sudo (exit 1 if not):
# if [ "$(id -u)" -ne 0 ]; then echo "This script must be run as root or with sudo" 1>&2; exit 1; fi
# If not running as root, auto-elevate and rerun script with sudo:
if [ "$(id -u)" -ne 0 ]; then echo "Elevation required; rerunning as sudo..."; sudo "$0" "$@"; exit 0; fi

# Only update if it's been more than 2 days since the last update (to avoid constant updates)
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update && sudo apt upgrade; fi

# Check if cifs-utils is installed
if ! dpkg -l | grep -q cifs-utils; then echo "Installing cifs-utils..."; sudo apt install -y cifs-utils; fi
# sudo yum install -y cifs-utils
# sudo pacman -S --noconfirm cifs-utils

# Parse arguments
WIN_NAME_OR_IP=$1
SHARE_NAME=$2
USER_NAME=$3
# Variables
UNC_PATH=//$WIN_NAME_OR_IP/$SHARE_NAME
MOUNTPOINT=/mnt/$(echo "${WIN_NAME_OR_IP}-${SHARE_NAME}" | tr '[:upper:]' '[:lower:]')
# Determine the home directory of the sudo user
if [ -n "$SUDO_USER" ]; then
    SUDO_USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
else
    SUDO_USER_HOME="/root"
fi
MOUNTPOINT_USER=${SUDO_USER_HOME}/$(echo "${WIN_NAME_OR_IP}-${SHARE_NAME}" | tr '[:upper:]' '[:lower:]')

# Prompt user for mount method
echo "Connect to $UNC_PATH"
read -p "Mount globally under $MOUNTPOINT or locally under $MOUNTPOINT_USER? [g/l]: " choice
# Set the mount point (use ~/ if no traditional mount point is preferred)

if [[ "$choice" =~ ^[Gg]$ ]]; then
    TARGET="$MOUNTPOINT"
    sudo mkdir -p "$TARGET"
    echo "Mounting under $TARGET..."
elif [[ "$choice" =~ ^[Ll]$ ]]; then
    TARGET="$MOUNTPOINT_USER"
    mkdir -p "$TARGET"   # No need for sudo in users own home directory
    echo "Mounting under $TARGET..."
else
    echo "Invalid choice. Exiting."
    exit 1
fi

# Check if the directory is already mounted
if mountpoint -q "$TARGET"; then
    echo "$TARGET is already mounted."
    echo "Mounted to: $(findmnt -n -o SOURCE "$TARGET")"

    # Ask if the user wants to unmount it
    read -p "Do you want to unmount it? [y/n]: " unmount_choice
    if [[ "$unmount_choice" =~ ^[Yy]$ ]]; then
        sudo umount "$TARGET" && echo "$TARGET unmounted successfully."
    else
        echo "Leaving existing mount intact."
        exit 1  # Exit without remounting if user opts not to unmount
    fi
else
    echo "$TARGET exists but is not mounted. Proceeding with mount..."
fi

# Prompt for credentials
read -s -p "Enter password for $USER_NAME to connect to the Samba/CIFS share: " SMB_PASS
echo

# # Mount the share
# echo "Mounting $UNC_PATH to $TARGET..."
# sudo mount -t cifs "$UNC_PATH" "$TARGET" -o username="$USER_NAME",password="$SMB_PASS",rw,file_mode=0777,dir_mode=0777 && echo "Mount successful."

# Mount the share
echo "Mounting $UNC_PATH to $TARGET..."
MOUNT_OUTPUT=$(sudo mount -t cifs "$UNC_PATH" "$TARGET" -o username="$USER_NAME",password="$SMB_PASS",rw,file_mode=0777,dir_mode=0777 2>&1)

# Check if the mount command was successful
if [ $? -eq 0 ]; then
    echo "Mount successful."
else
    echo "Mount failed: $MOUNT_OUTPUT"
    exit 1  # Exit the script if mount fails
fi

# Add to /etc/fstab for persistent mount
read -p "Add this mount to /etc/fstab for persistence? [y/n]: " persist
if [[ "$persist" =~ ^[Yy]$ ]]; then
    FSTAB_ENTRY="$UNC_PATH $TARGET cifs username=$SMB_USER,password=$SMB_PASS,rw,nofail 0 0"
    
    # Check if the UNC path is already in /etc/fstab
    if grep -q "^$UNC_PATH $TARGET" /etc/fstab; then
        echo "The following entry for $UNC_PATH already exists in /etc/fstab:"
        grep "^$UNC_PATH" /etc/fstab
        echo "No changes made to /etc/fstab."
    else
        echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab
        echo "Entry added to /etc/fstab."
    fi
fi

echo "Done."

# The mount -a command attempts to mount all filesystems defined in /etc/fstab
# that are not already mounted, except for those marked with the noauto option.
# It is a useful way to apply changes to the /etc/fstab file without rebooting.
#
# Mount notes
# sudo mount -t cifs \
#    //"${WIN_NAME_OR_IP}/${SHARE_NAME}" \
#    "$MOUNT_POINT" \
#    -o username=$USER_NAME,password=1234,vers=3.0,rw,uid=$(id -u),gid=$(id -g),file_mode=0777,dir_mode=0777
#    # ,uid=$(id -u),gid=$(id -g),file_mode=0644,dir_mode=0755
#
# Notes:
# If we use 'rw' as part of -o, by default, CIFS mounts are owned by root unless explicitly configured otherwise.
# So, writing on that share would require 'sudo', e.g. 'sudo mkdir myfld' due to how ownership and permissions are managed.
# Resolution: Specify the ownership and permissions explicitly when mounting the share with:
#   rw,uid=$(id -u),gid=$(id -g)
#     uid=$(id -u) sets the user ownership of the mount to your current user.
#     gid=$(id -g) sets the group ownership of the mount to your current user's group.
# Permission Problem: The file_mode and dir_mode options control permissions for files and directories.
#   file_mode=0644: permissions for files in the mounted filesystem.
#   0: No special mode bits (no setuid, setgid, or sticky bits).
#   6 (Owner): Read (4) + Write (2) = 6.
#   4 (Group): Read (4).
#   4 (Others): Read (4).
#   This means: Owner can read and write files. Group and Others can only read files.
#   dir_mode=0755: permissions for directories in the mounted filesystem.
#   0: No special mode bits.
#   7 (Owner): Read (4) + Write (2) + Execute (1) = 7.
#   5 (Group): Read (4) + Execute (1).
#   5 (Others): Read (4) + Execute (1).
#   This means: Owner can read, write, and access directories. Group and Others can read and access directories (but cannot modify them).
#   777 sets Owner, Group, and Others to Read (4) + Write (2) + Execute (1) = 7
