#!/bin/bash
# Author: Roy Wiseman 2025-03

echo "Update hostname in /etc/hostname, /etc/hosts, and hostnamectl"
echo "Current hostname: $(hostname)"

# Use $1 if provided, otherwise prompt the user for input
if [ -z "$1" ]; then
    read -p "Enter the new hostname: " new_hostname
else
    new_hostname=$1
fi

# Get the current hostname from /etc/hostname and hostnamectl
current_hostname=$(cat /etc/hostname)
system_hostname=$(hostnamectl --static)

# Get the current hostname in /etc/hosts
hosts_hostname=$(grep -oP '(?<=127.0.1.1\s).*' /etc/hosts)

# Show the changes that will be made
echo -e "\nThe following changes will be made:"
echo -e "\n1. The hostname in /etc/hostname will be changed from '$current_hostname' to '$new_hostname'."
echo -e "2. The hostname in /etc/hosts will be changed from '$hosts_hostname' to '$new_hostname'."
echo -e "3. The system hostname (current: '$system_hostname') will be updated via hostnamectl to '$new_hostname'."
echo
read -p "Do you want to continue? (y/N): " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    # Change the hostname in /etc/hostname
    echo "$new_hostname" | sudo tee /etc/hostname > /dev/null

    # Change the hostname in /etc/hosts
    sudo sed -i "s/\(127.0.1.1\s*\).*/\1$new_hostname/" /etc/hosts

    # Apply the hostname change
    sudo hostnamectl set-hostname "$new_hostname"

    echo -e "\nHostname has been changed to '$new_hostname'."
    echo -e "Please reboot your system for all changes to take effect."

else
    echo "Aborting changes."
fi

