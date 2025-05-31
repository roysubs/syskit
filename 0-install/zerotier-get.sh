#!/bin/bash
# Author: Roy Wiseman 2025-03

# Function to print in green
print_green() {
    echo -e "\033[0;32m$1\033[0m"
}

# Step 1: Prompt user to enter the ZeroTier network ID
read -p "Please enter your ZeroTier network ID (e.g., 9f77fc393eeda812): " NETWORK_ID

# Step 2: Install ZeroTier
print_green "Step 2: Installing ZeroTier..."

# Add the ZeroTier repository
print_green "Adding the ZeroTier repository..."
print_green "Running: curl -s https://install.zerotier.com | sudo bash"
curl -s https://install.zerotier.com | sudo bash

# Install ZeroTier package
print_green "Running: sudo apt install -y zerotier-one"
sudo apt update
sudo apt install -y zerotier-one

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

