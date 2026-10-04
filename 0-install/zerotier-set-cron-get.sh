#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03


pkg_install() {
    if [[ "$(uname)" == "Darwin" ]]; then brew install "$@"
    elif command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

# macOS only: ZeroTier is distributed as a GUI cask, not a formula
cask_install() {
    brew install --cask "$@"
}

echo "
This script will check/enable/start ZeroTier, then join a ZeroTier network,
and verify the network status. Then, a monitoring script will be setup in
~/.config and a cron job will be created to restart the service if it goes down.
"

# Prompt the user for the ZeroTier network ID
echo -e "\033[1;32mStep 1: Input the ZeroTier Network ID\033[0m"
read -p "Please enter your ZeroTier network ID (e.g., 9f77fc393eeda812): " network_id

# macOS: no systemd, and the CLI join needs root, so this path does not join or touch root cron.
# It installs ZeroTier One if missing, writes a status-check script (zerotier-cli, no sudo),
# and PRINTS the crontab line for the user to add themselves. The Linux path below is unchanged.
if [[ "$(uname)" == "Darwin" ]]; then
    if [[ ! -d "/Applications/ZeroTier One.app" ]]; then
        if ! command -v brew &>/dev/null; then echo "Homebrew is required. Install it from https://brew.sh first." >&2; exit 1; fi
        cask_install zerotier-one
    else
        echo "ZeroTier One is already installed"
    fi
    echo "Join network $network_id from the ZeroTier One app (menu bar icon > Join Network...)."
    mkdir -p ~/.config
    cat << 'EOF' > ~/.config/check_zerotier.sh
#!/bin/bash
# macOS check: is ZeroTier ONLINE? (macOS has no systemd)
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
if zerotier-cli info 2>/dev/null | grep -q ONLINE; then
    echo "ZeroTier service is online"
else
    echo "ZeroTier is not online. Open the ZeroTier One app to restart it."
fi
EOF
    chmod +x ~/.config/check_zerotier.sh
    echo "Check script written to ~/.config/check_zerotier.sh"
    echo "The crontab was NOT changed. To check every 10 minutes, run 'crontab -e' and add:"
    echo "*/10 * * * * $HOME/.config/check_zerotier.sh"
    exit 0
fi

# Step 2: Install ZeroTier if not already installed
echo -e "\033[1;32mStep 2: Installing ZeroTier...\033[0m"
if ! command -v zerotier-cli &> /dev/null; then
    echo "Installing ZeroTier package with: sudo apt install -y zerotier-one"
    pkg_install zerotier-one
else
    echo "ZeroTier is already installed"
fi

# Step 3: Enable and start ZeroTier service
echo -e "\033[1;32mStep 3: Starting and enabling ZeroTier service...\033[0m"
sudo systemctl enable --now zerotier-one

# Step 4: Join the ZeroTier network
echo -e "\033[1;32mStep 4: Joining the ZeroTier network with ID $network_id...\033[0m"
sudo zerotier-cli join $network_id

# Step 5: Verifying ZeroTier network status
echo -e "\033[1;32mStep 5: Verifying ZeroTier network status...\033[0m"
sudo zerotier-cli listnetworks

# Step 6: Checking ZeroTier status
echo -e "\033[1;32mStep 6: Checking ZeroTier status...\033[0m"
sudo zerotier-cli info

# Step 7: Create cron job for monitoring and restarting ZeroTier
echo -e "\033[1;32mStep 7: Setting up cron job to monitor and restart ZeroTier...\033[0m"
# Define the cron job command with the location of the script
cron_cmd="~/.config/check_zerotier.sh"
cron_entry="*/10 * * * * $cron_cmd"

# Check if the cron job already exists
if ! crontab -l | grep -q "$cron_cmd"; then
    echo "Adding cron job to check and restart ZeroTier every 10 minutes."
    # Add the cron job if it doesn't exist
    (crontab -l ; echo "$cron_entry") | crontab -
else
    echo "Cron job already exists. Skipping..."
fi

# Step 8: Create the check_zerotier.sh script for monitoring
echo -e "\033[1;32mStep 8: Creating check_zerotier.sh script...\033[0m"
mkdir -p ~/.config
cat << EOF > ~/.config/check_zerotier.sh
#!/bin/bash

# Check if the ZeroTier service is running
if ! systemctl is-active --quiet zerotier-one; then
    echo "ZeroTier is not running. Restarting ZeroTier service..."
    # Restart the ZeroTier service
    sudo systemctl restart zerotier-one
    # Rejoin the ZeroTier network (optional if you want to ensure it reconnects)
    sudo zerotier-cli join $network_id
else
    echo "ZeroTier service is running"
fi
EOF

# Make sure the check_zerotier.sh script is executable
chmod +x ~/.config/check_zerotier.sh

echo -e "\033[1;32mZeroTier installation, network join, and cron job setup completed.\033[0m"

