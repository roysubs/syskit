#!/bin/bash
# Author: Roy Wiseman 2025-03

# Update the package index
sudo apt update

# Install required dependencies
sudo apt install -y software-properties-common apt-transport-https wget

# Add the Webmin GPG key
wget -qO - https://www.webmin.com/jcameron-key.asc | sudo tee /etc/apt/trusted.gpg.d/webmin.asc

# Add the Webmin repository to your system
echo "deb http://download.webmin.com/download/repository sarge contrib" | sudo tee /etc/apt/sources.list.d/webmin.list

# Update the package index again after adding the Webmin repo
sudo apt update

# Install Webmin
sudo apt install -y webmin

# Start the Webmin service
sudo systemctl start webmin

# Enable Webmin to start on boot
sudo systemctl enable webmin

# Print success message
echo "Webmin installation completed successfully! You can access it at https://your_server_ip:10000"

