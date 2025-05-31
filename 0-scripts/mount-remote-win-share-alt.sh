#!/bin/bash
# Author: Roy Wiseman 2025-03

# Check if the required arguments are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <WINDOWS_NAME_OR_IP> <SHARE_NAME> <USER_NAME>"
    exit 1
fi

# Parse arguments
WIN_NAME_OR_IP=$1
SHARE_NAME=$2
USER_NAME=$3

# Set the mount point (use ~/ if no traditional mount point is preferred)
MOUNT_POINT=~/$(echo "${WIN_NAME_OR_IP}-${SHARE_NAME}" | tr '[:upper:]' '[:lower:]')

# Ensure the mount point exists
mkdir -p "$MOUNT_POINT"

# Mount the share
sudo mount -t cifs \
    //"${WIN_NAME_OR_IP}/${SHARE_NAME}" \
    "$MOUNT_POINT" \
    -o username=$USER_NAME,password=1234,vers=3.0,rw,uid=$(id -u),gid=$(id -g),file_mode=0777,dir_mode=0777
    # ,uid=$(id -u),gid=$(id -g),file_mode=0644,dir_mode=0755
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

# Check if the mount succeeded
if [ $? -eq 0 ]; then
    echo "Successfully mounted //${WIN_NAME_OR_IP}/${SHARE_NAME} at ${MOUNT_POINT}"
else
    echo "Failed to mount //${WIN_NAME_OR_IP}/${SHARE_NAME}. Please check your credentials and network."
    exit 1
fi

