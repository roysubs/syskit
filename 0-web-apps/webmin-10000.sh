#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
if [ "$(uname -s)" = "Darwin" ]; then
    echo "webmin-10000.sh installs Webmin from a Debian apt repository as a systemd service, and does not apply on macOS."
    echo "Not applicable on macOS. Use Screen Sharing for graphical remote access, or Terminal ssh for shell access."
    exit 0
fi
# Author: Roy Wiseman 2025-03
# openSUSE: this script uses apt and a Debian apt repository, not automated for zypper.
if command -v zypper &>/dev/null; then
    echo "Webmin: not automated for openSUSE. Install it from https://webmin.com/download/ instead."
    exit 0
fi

# Update the package index
sudo apt update

# Install required dependencies
sudo apt install -y software-properties-common apt-transport-https wget

# Add the Webmin GPG key
wget -qO - https://www.webmin.com/jcameron-key.asc | sudo tee /etc/apt/trusted.gpg.d/webmin.asc

# Add the Webmin repository to your system
echo "deb http://download.webmin.com/download/repository sarge contrib" | sudo tee /etc/apt/sources.list.d/webmin.list

# Update the package index again after adding the Webmin repo
sudo apt update

# Install Webmin
sudo apt install -y webmin

# Start the Webmin service
sudo systemctl start webmin

# Enable Webmin to start on boot
sudo systemctl enable webmin

# Print success message
echo "Webmin installation completed successfully! You can access it at https://your_server_ip:10000"

