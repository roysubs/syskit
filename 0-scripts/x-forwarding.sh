#!/bin/bash
# Author: Roy Wiseman 2025-01

# This script helps set up the server side (your Debian machine)
# for X forwarding over SSH.
# It assumes you will be connecting from another machine (the client)
# that has an X server running and an SSH client.

echo "Starting Debian X forwarding server setup..."

# --- Step 1: Update package lists ---
echo "Updating package lists..."
sudo apt update
if [ $? -eq 0 ]; then
    echo "Package lists updated successfully."
else
    echo "Failed to update package lists. Please check your internet connection and try again."
    exit 1
fi

# --- Step 2: Install necessary packages (openssh-server and xauth) ---
echo "Installing openssh-server and xauth (if needed)..."
sudo apt install -y openssh-server xauth
if [ $? -eq 0 ]; then
    echo "openssh-server and xauth installed or already present."
else
    echo "Failed to install openssh-server or xauth. Please check for errors above."
    exit 1
fi

# --- Step 3: Verify SSH server configuration for X11Forwarding ---
SSH_CONFIG="/etc/ssh/sshd_config"
echo "Checking SSH server configuration file: $SSH_CONFIG"

# Check if X11Forwarding is enabled
if grep -qE "^[[:space:]]*X11Forwarding[[:space:]]+yes" "$SSH_CONFIG"; then
    echo "X11Forwarding is already enabled in $SSH_CONFIG."
else
    echo "X11Forwarding is NOT enabled or commented out in $SSH_CONFIG."
    echo "Attempting to enable X11Forwarding..."

    # Backup the original config file
    sudo cp "$SSH_CONFIG" "${SSH_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    echo "Backed up original config to ${SSH_CONFIG}.bak.*"

    # Use sed to uncomment or add X11Forwarding yes
    # First, uncomment if line exists and is commented
    sudo sed -i 's/^[[:space:]]*#\?[[:space:]]*X11Forwarding[[:space:]]+no/X11Forwarding yes/' "$SSH_CONFIG"
    # Then, add if line doesn't exist or is still commented/wrong value
    if ! grep -qE "^[[:space:]]*X11Forwarding[[:space:]]+yes" "$SSH_CONFIG"; then
        echo "Adding 'X11Forwarding yes' to $SSH_CONFIG."
        echo "X11Forwarding yes" | sudo tee -a "$SSH_CONFIG" > /dev/null
    fi

    if grep -qE "^[[:space:]]*X11Forwarding[[:space:]]+yes" "$SSH_CONFIG"; then
        echo "X11Forwarding successfully set to yes in $SSH_CONFIG."
        echo "Restarting SSH service to apply changes..."
        sudo systemctl restart sshd
        if [ $? -eq 0 ]; then
            echo "SSH service restarted successfully."
        else
            echo "Failed to restart SSH service. Please restart it manually using 'sudo systemctl restart sshd'."
            exit 1
        fi
    else
        echo "Failed to set X11Forwarding to yes. Please manually edit $SSH_CONFIG."
        exit 1
    fi
fi

# --- Step 4: Check if X11UseLocalhost is disabled (recommended for some setups) ---
# While X11Forwarding yes is key, sometimes disabling X11UseLocalhost helps.
# Check if X11UseLocalhost is disabled or commented out
if grep -qE "^[[:space:]]*X11UseLocalhost[[:space:]]+no" "$SSH_CONFIG"; then
    echo "X11UseLocalhost is already set to no or commented out in $SSH_CONFIG."
else
    echo "X11UseLocalhost is NOT set to no or commented out in $SSH_CONFIG."
    echo "Attempting to set X11UseLocalhost to no..."

    # Use sed to uncomment or add X11UseLocalhost no
    # First, uncomment if line exists and is commented
    sudo sed -i 's/^[[:space:]]*#\?[[:space:]]*X11UseLocalhost[[:space:]]+yes/X11UseLocalhost no/' "$SSH_CONFIG"
    # Then, add if line doesn't exist or is still commented/wrong value
    if ! grep -qE "^[[:space:]]*X11UseLocalhost[[:space:]]+no" "$SSH_CONFIG"; then
        echo "Adding 'X11UseLocalhost no' to $SSH_CONFIG."
        echo "X11UseLocalhost no" | sudo tee -a "$SSH_CONFIG" > /dev/null
    fi

    if grep -qE "^[[:space:]]*X11UseLocalhost[[:space:]]+no" "$SSH_CONFIG"; then
        echo "X11UseLocalhost successfully set to no in $SSH_CONFIG."
        echo "Restarting SSH service to apply changes..."
        sudo systemctl restart sshd
        if [ $? -eq 0 ]; then
            echo "SSH service restarted successfully."
        else
            echo "Failed to restart SSH service. Please restart it manually using 'sudo systemctl restart sshd'."
            exit 1
        fi
    else
        echo "Failed to set X11UseLocalhost to no. Please manually edit $SSH_CONFIG."
        exit 1
    fi
fi


echo ""
echo "---------------------------------------------------"
echo "Debian server setup steps completed."
echo "Now, from your client machine (where you want the display to appear):"
echo "1. Ensure you have an X server running (e.g., VcXsrv on Windows, XQuartz on macOS, or a desktop environment on Linux)."
echo "2. Connect to this Debian machine using SSH with the -X or -Y flag:"
echo "   ssh -X your_username@your_debian_ip_address"
echo "   (Use -Y if -X causes issues, it's less secure but sometimes works better)"
echo "3. Once connected, try running an X application, like 'xclock' or 'xeyes'."
echo "   xclock"
echo "   xeyes"
echo ""
echo "If it doesn't work, check firewall rules on both client and server, and ensure your client's X server is running and accessible."
echo "You can also try 'ssh -v -X your_username@your_debian_ip_address' for verbose output to help diagnose issues."
echo "---------------------------------------------------"

exit 0

