#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-03

# macOS only: ZeroTier is distributed as a GUI cask, not a formula
cask_install() {
    brew install --cask "$@"
}

# Function to print in green
print_green() {
    echo -e "\033[0;32m$1\033[0m"
}

# Step 1: Prompt user to enter the ZeroTier network ID
read -p "Please enter your ZeroTier network ID (e.g., 9f77fc393eeda812): " NETWORK_ID

# macOS: ZeroTier One is a GUI app with its own service, so no systemd and no CLI join.
# Install the cask, then point the user at the app to join. The Linux path below is unchanged.
if [[ "$(uname)" == "Darwin" ]]; then
    if ! command -v brew &>/dev/null; then echo "Homebrew is required. Install it from https://brew.sh first." >&2; exit 1; fi
    print_green "Installing ZeroTier One with Homebrew (cask)..."
    cask_install zerotier-one
    print_green "Now join the network from the app (it is not joined from the command line on macOS):"
    echo "  1. Open 'ZeroTier One' from Applications (menu bar icon)."
    echo "  2. Click the icon, then Join Network... and enter: $NETWORK_ID"
    echo "  3. If macOS asks, approve the ZeroTier system extension in System Settings > Privacy & Security."
    echo "  4. Authorize this Mac in the ZeroTier web console if required."
    exit 0
fi

# Step 2: Install ZeroTier
print_green "Step 2: Installing ZeroTier..."

if command -v zypper &>/dev/null; then
    print_green "Not automated for openSUSE: install ZeroTier from https://www.zerotier.com/download/ first. Continuing with the service and network-join steps."
else
    # Add the ZeroTier repository
    print_green "Adding the ZeroTier repository..."
    print_green "Running: curl -s https://install.zerotier.com | sudo bash"
    curl -s https://install.zerotier.com | sudo bash

    # Install ZeroTier package
    print_green "Running: sudo apt install -y zerotier-one"
    sudo apt update
    sudo apt install -y zerotier-one
fi

# Step 3: Start and enable ZeroTier service
print_green "Step 3: Starting and enabling ZeroTier service..."
print_green "Running: sudo systemctl enable --now zerotier-one"
sudo systemctl enable --now zerotier-one

# Step 4: Join the ZeroTier network (using the user-provided network ID)
print_green "Step 4: Joining the ZeroTier network with ID $NETWORK_ID..."
print_green "Running: sudo zerotier-cli join $NETWORK_ID"
sudo zerotier-cli join $NETWORK_ID

# Step 5: Verify the ZeroTier status
print_green "Step 5: Verifying ZeroTier network status..."
print_green "Running: sudo zerotier-cli listnetworks"
sudo zerotier-cli listnetworks

# Optionally, list network members and status
print_green "Listing ZeroTier network members..."
print_green "Running: sudo zerotier-cli listpeers"
sudo zerotier-cli listpeers

# Step 6: (Optional) Check if ZeroTier is successfully connected
print_green "Step 6: Checking ZeroTier status..."
print_green "Running: sudo zerotier-cli info"
sudo zerotier-cli info

print_green "ZeroTier installation and network join completed. Please authorize the device in the ZeroTier web console if required."

