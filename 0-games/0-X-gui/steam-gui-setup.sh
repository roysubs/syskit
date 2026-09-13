#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-04

# Update package lists and install dependencies

pkg_install() {
    if command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

echo "Updating package lists and installing dependencies..."
sudo apt update
pkg_install lib32gcc1 lib32stdc++6 wget

# Create a directory for SteamCMD
echo "Creating directory for SteamCMD..."
mkdir -p ~/steamcmd
cd ~/steamcmd

# Download SteamCMD tarball
echo "Downloading SteamCMD..."
wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz

# Extract the tarball
echo "Extracting SteamCMD..."
tar -xvzf steamcmd_linux.tar.gz

# Optional: Create a symlink to make steamcmd accessible globally
echo "Creating symlink for easy access to steamcmd..."
sudo ln -s ~/steamcmd/steamcmd.sh /usr/local/bin/steamcmd

# Run SteamCMD
echo "Running SteamCMD for the first time to update..."
./steamcmd.sh +quit

echo "SteamCMD installation is complete!"
echo "You can now run SteamCMD by typing 'steamcmd' from anywhere."

