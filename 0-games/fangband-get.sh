#!/bin/bash
# Author: Roy Wiseman 2025-05

# Install dependencies
sudo apt update
sudo apt install -y build-essential ncurses-dev git cmake

# Clone the FAangband repository into your home directory
git clone https://github.com/NickMcConnell/FAangband.git ~/FAangband

# Navigate into the FAangband directory
cd ~/FAangband

# Run CMake to configure the build
cmake .

# Compile the source code
make

# Optional: Install the game system-wide
sudo make install

# Output success message
echo "FAangband has been successfully installed in ~/FAangband!"

