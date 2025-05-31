#!/bin/bash
# Author: Roy Wiseman 2025-03

# Install LazyDocker docker management tool
if command -v lazydocker >/dev/null 2>&1; then
    echo "LazyDocker is already installed. Exiting."
    exit 0
fi
echo "LazyDocker not found. Proceeding with installation..."

# Update package list and install prerequisites
sudo apt update && sudo apt install -y wget git unzip

# Start tracking time and disk usage after initial steps
start_time=$(date +%s)
initial_free_space=$(df / --output=avail --block-size=1M | tail -1) # Available space in MB

# Fetch the latest release of LazyDocker
LAZYDOCKER_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
wget "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz" -O lazydocker.tar.gz

# Extract and install LazyDocker
tar -xzf lazydocker.tar.gz
sudo install lazydocker /usr/local/bin

# Clean up
rm -rf lazydocker lazydocker.tar.gz
rm -f README.md
rm -f LICENSE

# Verify installation
echo "LazyDocker version and build:"
lazydocker --version

# End tracking of time and disk usage
end_time=$(date +%s)
total_time=$((end_time - start_time))
final_free_space=$(df / --output=avail --block-size=1M | tail -1)
used_space=$((initial_free_space - final_free_space))
echo "--------------------------------------------"
echo "Total time taken: $((total_time / 60)) minutes and $((total_time % 60)) seconds"
echo "Total disk space used by installations: $used_space MB"

echo "More info: https://www.youtube.com/watch?v=IUAk1pjXDWM

