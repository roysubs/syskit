#!/bin/bash
# Author: Roy Wiseman 2025-04

# Install and configure PowerShell 7.x for Debian

echo "Install PowerShell 7.4 on Debian"
# https://learn.microsoft.com/en-us/powershell/scripting/install/install-debian?view=powershell-7.4

# Update the list of packages and ensure wget is installed
sudo apt-get update && sudo apt-get install -y wget

# Start tracking time and disk usage after initial steps
start_time=$(date +%s)
initial_free_space=$(df / --output=avail --block-size=1M | tail -1) # Available space in MB

# Get the version of Debian
VERSION_ID=$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')

# Download the Microsoft repository GPG keys
sudo wget -q https://packages.microsoft.com/config/debian/$VERSION_ID/packages-microsoft-prod.deb
sudo wget -q https://packages.microsoft.com/config/debian/$VERSION_ID/prod.list -O /etc/apt/sources.list.d/microsoft-prod.list

# Register the Microsoft repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb

# Delete the Microsoft repository GPG keys file
rm -f packages-microsoft-prod.deb

# Update the list of packages after we added packages.microsoft.com
sudo apt-get update

# Install PowerShell
sudo apt-get install -y powershell

# # Remove the Microsoft-prod.list as it is not required and may cause warnings
# sudo rm /etc/apt/sources.list.d/microsoft-prod.list

# Verify installation of PowerShell
pwsh --version

# End tracking of time and disk usage
end_time=$(date +%s)
total_time=$((end_time - start_time))
final_free_space=$(df / --output=avail --block-size=1M | tail -1)
used_space=$((initial_free_space - final_free_space))
echo "--------------------------------------------"
echo "Total time taken: $((total_time / 60)) minutes and $((total_time % 60)) seconds"
echo "Total disk space used by installations: $used_space MB"

