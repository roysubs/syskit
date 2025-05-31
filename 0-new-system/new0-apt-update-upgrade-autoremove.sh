#!/bin/bash
# Author: Roy Wiseman 2025-01

# Run through main apt package maintenance tasks for Debian-based systems

if type apt &>/dev/null; then
    manager="apt"
    DISTRO="Debian/Ubuntu"
else
    echo "This script is designed for Debian-based systems only."
    return 1
fi

# Utility functions, separator and displaying/running commands
separator() { echo -e "\n>>>>>>>>\n"; }
displayandrun() { echo -e "\$ $*"; "$@"; }

# Update package manager
echo -e "\nCheck updates for '$DISTRO' using '$manager':"
separator
displayandrun sudo apt update --ignore-missing -y
separator
displayandrun sudo apt dist-upgrade -y
separator
displayandrun sudo apt --fix-broken install -y  # Fix any broken installs

# Update apt-file if present
if type apt-file &>/dev/null; then
    separator
    displayandrun sudo apt-file update
fi

# Install essential packages and remove unnecessary ones
separator
displayandrun sudo apt install ca-certificates -y
separator
displayandrun sudo apt autoremove -y

# Check if a reboot is required
if [ -f /var/run/reboot-required ]; then
    echo "A reboot is required (/var/run/reboot-required is present)." >&2
    echo "Re-run this script after reboot to check." >&2
    return
fi
echo "Update completed successfully."
