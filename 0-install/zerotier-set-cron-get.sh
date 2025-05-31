#!/bin/bash
# Author: Roy Wiseman 2025-03

echo "
This script will check/enable/start ZeroTier, then join a ZeroTier network,
and verify the network status. Then, a monitoring script will be setup in
~/.config and a cron job will be created to restart the service if it goes down.
"

# Prompt the user for the ZeroTier network ID
echo -e "\033[1;32mStep 1: Input the ZeroTier Network ID\033[0m"
read -p "Please enter your ZeroTier network ID (e.g., 9f77fc393eeda812): " network_id

# Step 2: Install ZeroTier if not already installed
echo -e "\033[1;32mStep 2: Installing ZeroTier...\033[0m"
if ! command -v zerotier-cli &> /dev/null; then
    echo "Installing ZeroTier package with: sudo apt install -y zerotier-one"
    sudo apt install -y zerotier-one
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

