#!/bin/bash
# Author: Roy Wiseman 2025-05

# Make sure python3 and git are present for unimatrix setup
echo "Updating package list..."
sudo apt update
echo "Installing dependencies..."
sudo apt install -y python3 python3-pip git # build-essential
# Install cmatrix and bb
sudo apt install cmatrix bb hollywood -y

# Clone Unimatrix repository
REPO_URL="https://github.com/will8211/unimatrix"
BASE_DIR=$(realpath ~)/scripts
mkdir -p "$BASE_DIR"
echo "Cloning Unimatrix repository from $REPO_URL to $BASE_DIR/unimatrix..."
git clone "$REPO_URL" "$BASE_DIR/unimatrix"

# Change directory to Unimatrix
cd ~/scripts/unimatrix || { echo "Failed to enter unimatrix directory"; exit 1; }

# Install Python dependencies if requirements.txt exists
if [ -f "requirements.txt" ]; then
    echo "Installing Python dependencies..."
    pip3 install -r requirements.txt
else
    echo "No requirements.txt found. Skipping Python dependencies installation."
fi

# Create a symlink in /usr/local/bin
echo "Creating symlink for unimatrix..."
sudo ln -sf "$(pwd)/unimatrix.py" /usr/local/bin/unimatrix
sudo chmod +x /usr/local/bin/unimatrix

# Run the Unimatrix application (adjust command based on actual setup)
echo "Running Unimatrix..."
python3 unimatrix.py
# Or, if there is a different executable:
# ./unimatrix

echo "
==========

unimatrix has been setup in ~/scripts/unimatrix
Symbolic link 'unimatrix' added on \$PATH at /usr/local/bin:
    sudo ln -sf "$(pwd)/unimatrix.py" /usr/local/bin/unimatrix
    sudo chmod +x /usr/local/bin/unimatrix
Could alternatively alias with:
    alias unimatrix='python3 ~/unimatrix/unimatrix.py'
unimatrix is based on cmatrix. The following should produce virtually
the same output as CMatrix:
    unimatrix -n -s 96 -l o

cmatrix setup via apt package; alternative Matrix screensaver

bb setup via apt package; ascii graphics toy

hollywood setup via apt package; ascii graphics screensaver toy
"




