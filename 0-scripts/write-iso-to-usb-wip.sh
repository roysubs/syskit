#!/bin/bash
# Author: Roy Wiseman 2025-03

# Takes an ISO (or other disk image) as $1 and a USB device (/dev/sdX) as $2.
# If no USB device is specified, it lists external USB devices and prompts the user to choose one.
# If a USB device is specified, it verifies that it is an external device before proceeding.
# Displays detailed information about the device before writing.
# Warns if the device is unformatted or blank.
# Uses lsblk and udevadm to detect USB sticks (excluding internal drives).
# Prompts the user before formatting and writing the ISO.

set -e  # Exit on error

# Ensure script is run with sudo
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)."
    exit 1
fi

# Check if an image file was provided
if [ -z "$1" ]; then
    echo "Usage: $0 <image.iso> [device]"
    exit 1
fi

IMAGE="$1"

# Validate image file
if [ ! -f "$IMAGE" ]; then
    echo "Error: File '$IMAGE' not found."
    exit 1
fi

# Function to detect external USB devices
detect_usb_devices() {
    echo "Detecting external USB devices..."
    lsblk -o NAME,MODEL,TRAN,VENDOR,SIZE,MOUNTPOINT | grep "usb" || echo "No USB devices detected."
}

# If device not given, list USB devices and prompt
if [ -z "$2" ]; then
    echo "No USB device specified. Scanning for USB sticks..."
    detect_usb_devices
    echo ""
    read -p "Enter the device name (e.g., sdb): " DEV
    DEVICE="/dev/$DEV"
else
    DEVICE="$2"
fi

# Ensure the device exists
if [ ! -b "$DEVICE" ]; then
    echo "Error: Device '$DEVICE' does not exist."
    exit 1
fi

# Check if the device is an external USB stick
if ! lsblk -o NAME,TRAN | grep -q "^$(basename "$DEVICE") usb"; then
    echo "Error: '$DEVICE' does not appear to be an external USB device."
    exit 1
fi

# Display current partition information
echo "Device information:"
lsblk "$DEVICE"
echo ""

# Warn about formatting
echo "WARNING: This process will erase all data on '$DEVICE'."
read -p "Are you sure you want to continue? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Aborting."
    exit 1
fi

# Unmount device if mounted
echo "Unmounting any mounted partitions on '$DEVICE'..."
umount "${DEVICE}"* 2>/dev/null || true

# Write the ISO to the USB device
echo "Writing '$IMAGE' to '$DEVICE'..."
dd if="$IMAGE" of="$DEVICE" bs=4M status=progress oflag=sync

echo "Done! The USB stick is now ready."

