#!/bin/bash
# Author: Roy Wiseman 2025-04

# Temporary fix for Debian /etc/apt/sources.list (bookworm main => bookworm main contrib non-free non-free-firmware).
# Current distro (2024-12) has distro setup that creates warnings
# Fix by changing:   bookworm main => bookworm main contrib non-free non-free-firmware

# Define the file to modify
sources_list="/etc/apt/sources.list"

# Backup the original file
sudo cp "$sources_list" "${sources_list}.$(date +'%Y-%m-%d_%H-%M-%S').bak"

# Perform replacements
sudo sed -i \
    -e 's|bookworm main$|bookworm main contrib non-free non-free-firmware|' \
    -e 's|bookworm-updates main$|bookworm-updates main contrib non-free non-free-firmware|' \
    -e 's|bookworm-security main$|bookworm-security main contrib non-free non-free-firmware|' \
    "$sources_list"

# Confirm changes
echo "Updated $sources_list. A backup was saved as ${sources_list}.bak."

sudo apt update

echo -e "\nRepository configuration $sources_list updated. The warning about 'non-free-firmware' should no longer appear.\n"

# Fix the Microsoft repo left over by pwsh7 (PowerShell) installation
# leaving a repo that is not properly setup in some cases.
#    /etc/apt/sources.list.d/microsoft-prod.list
#    /etc/apt/sources.list.d/microsoft.list

# Remove the Microsoft repository if it exists
echo "Removing Microsoft repository if it exists..."
if [ -f "/etc/apt/sources.list.d/microsoft-prod.list" ]; then
    sudo rm /etc/apt/sources.list.d/microsoft-prod.list
    echo "Microsoft repository removed."
else
    echo "Microsoft repository not found, skipping removal."
fi

# Remove the Microsoft repository if it exists
echo "Removing Microsoft repository if it exists..."
if [ -f "/etc/apt/sources.list.d/microsoft-prod.list" ]; then
    sudo rm /etc/apt/sources.list.d/microsoft.list
    echo "Microsoft repository removed."
else
    echo "Microsoft repository not found, skipping removal."
fi
