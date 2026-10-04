#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

# --- macOS ---
# macOS has three separate names (see remote-access-mac.sh) and no /etc/hostname,
# /etc/hosts 127.0.1.1 line or hostnamectl. Set all three with scutil.
macos_change_hostname() {
    local new_hostname="$1" cur_host cur_local cur_computer confirm

    if ! cur_host=$(scutil --get HostName 2>/dev/null); then cur_host="(not set)"; fi
    if ! cur_local=$(scutil --get LocalHostName 2>/dev/null); then cur_local="(not set)"; fi
    if ! cur_computer=$(scutil --get ComputerName 2>/dev/null); then cur_computer="(not set)"; fi

    echo "Update HostName, LocalHostName and ComputerName with scutil (macOS)"
    echo "Current HostName:      $cur_host"
    echo "Current LocalHostName: $cur_local"
    echo "Current ComputerName:  $cur_computer"

    if [ -z "$new_hostname" ]; then
        read -p "Enter the new hostname: " new_hostname
    fi
    if [ -z "$new_hostname" ]; then
        echo "No hostname given. Aborting."
        return 1
    fi
    # LocalHostName becomes the Bonjour name (<name>.local), so it allows letters, digits and hyphens only
    if [[ ! "$new_hostname" =~ ^[A-Za-z0-9-]+$ ]]; then
        echo "'$new_hostname' is not valid: use letters, digits and hyphens only (no spaces or dots)."
        return 1
    fi

    echo -e "\nThe following changes will be made:"
    echo "1. HostName      '$cur_host' -> '$new_hostname'"
    echo "2. LocalHostName '$cur_local' -> '$new_hostname'"
    echo "3. ComputerName  '$cur_computer' -> '$new_hostname'"
    echo
    read -p "Do you want to continue? (y/N): " confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        sudo scutil --set HostName "$new_hostname" || return 1
        sudo scutil --set LocalHostName "$new_hostname" || return 1
        sudo scutil --set ComputerName "$new_hostname" || return 1
        echo -e "\nHostname has been changed to '$new_hostname'."
        echo "No reboot is needed on macOS. New SSH sessions will show the new name."
    else
        echo "Aborting changes."
    fi
}

if [ "$(uname -s)" = "Darwin" ]; then
    macos_change_hostname "$1"
    exit $?
fi

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

