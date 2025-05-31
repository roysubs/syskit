#!/bin/bash
# Author: Roy Wiseman 2025-04

# Update package lists and install dependencies
echo "Updating package lists and installing dependencies..."
sudo apt update
sudo apt install -y lib32gcc1 lib32stdc++6 wget

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

