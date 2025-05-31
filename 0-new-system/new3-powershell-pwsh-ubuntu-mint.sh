#!/bin/bash
# Author: Roy Wiseman 2025-03

# Install and configure PowerShell 7.x for Ubuntu and Linux Mint 

echo "Install PowerShell 7.4 on Ubuntu or Linux Mint"

# Update the list of packages and ensure wget is installed
sudo apt-get update && sudo apt-get install -y wget

# Start tracking time and disk usage after initial steps
start_time=$(date +%s)
initial_free_space=$(df / --output=avail --block-size=1M | tail -1) # Available space in MB

# Download the Microsoft repository GPG keys and repository list for Ubuntu 22.04 (noble)
sudo wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb

# Check if the download was successful
if [ -f "packages-microsoft-prod.deb" ]; then
    sudo dpkg -i packages-microsoft-prod.deb

    # Delete the Microsoft repository GPG keys file
    rm -f packages-microsoft-prod.deb

    # Update the list of packages after adding the Microsoft repository
    sudo apt-get update

    # Install PowerShell
    sudo apt-get install -y powershell

    # Verify installation of PowerShell
    pwsh --version
else
    echo "Failed to download packages-microsoft-prod.deb. Please check your internet connection and try again."
    exit 1
fi

# End tracking of time and disk usage
end_time=$(date +%s)
total_time=$((end_time - start_time))
final_free_space=$(df / --output=avail --block-size=1M | tail -1)
used_space=$((initial_free_space - final_free_space))
echo "--------------------------------------------"
echo "Total time taken: $((total_time / 60)) minutes and $((total_time % 60)) seconds"
echo "Total disk space used by installations: $used_space MB"

