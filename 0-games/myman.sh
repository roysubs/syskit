#!/bin/bash
# Author: Roy Wiseman 2025-05

# Check if running as sudo
if [ "$(id -u)" -ne 0 ]; then echo "This script must be run with sudo or as root."; exit 1; fi

wget https://excellmedia.dl.sourceforge.net/project/myman/myman-cvs/myman-cvs-2009-10-30/myman-wip-2009-10-30.tar.gz
tar -xvf myman-wip-2009-10-30.tar.gz

cd myman-wip-2009-10-30/

# MyMan installation script
# Ensure you run this script from the directory containing the MyMan source

set -e  # Exit on error

# Check for prerequisites
echo "Checking for required tools..."
for tool in gcc make bash ncurses6-config; do
    if ! command -v $tool &>/dev/null; then
        echo "Error: $tool is not installed. Please install it and try again."
        exit 1
    fi
done

echo "All required tools are installed."

# Step 1: Configure the build
echo "Configuring the build..."
/bin/bash ./configure SHELL=/bin/bash

# Step 2: Build the project
echo "Building MyMan..."
make

# Step 3: Install the binaries (requires root permissions)
echo "Installing MyMan (you may be prompted for your password)..."
sudo make install

# Step 4: Test the installation
echo "Testing MyMan installation..."
if command -v myman &>/dev/null; then
    echo "Installation successful! Run 'myman' to start the game."
else
    echo "Installation failed. Please check the output for errors."
    exit 1
fi

