#!/bin/bash
# Author: Roy Wiseman, 2025-05
# Revised by Gemini
#
# Description: Installs the latest OneDrive client by compiling it from the
#              developer's official source code. This is the most reliable
#              method for new OS releases like Ubuntu 24.04.

# --- Configuration ---
# Ensure an email argument is provided for user guidance
if [[ -z "$1" ]]; then
    echo "Usage: $0 your-email@example.com"
    echo "Please provide the Microsoft account email you intend to use."
    exit 1
fi

EMAIL="$1"
# Create a temporary directory for the source code that cleans up on exit
TEMP_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEMP_DIR"' EXIT

# --- Cleanup & Dependency Installation ---
echo "Preparing to build the latest OneDrive client from source..."

# Remove the old APT version if it exists to prevent conflicts
if dpkg -l | grep -q " onedrive "; then
    echo "Removing any existing apt-managed versions of onedrive..."
    sudo apt-get purge -y onedrive
    sudo apt-get autoremove -y
fi

# Install dependencies required to build the software
# ADDED: libdbus-1-dev for desktop notification support
echo "Installing build dependencies..."
sudo apt-get update
sudo apt-get install -y build-essential libcurl4-openssl-dev libsqlite3-dev libnotify-dev git ldc libphobos2-ldc-dev libdbus-1-dev

# --- Build and Install from Source ---
echo "Downloading the latest source code..."
git clone https://github.com/abraunegg/onedrive.git "$TEMP_DIR"
cd "$TEMP_DIR" || exit

echo "Compiling and installing..."
./configure
make
sudo make install

# Refresh the system's shared library cache
sudo ldconfig

# --- Configuration & Authentication ---
echo
echo "--- OneDrive Configuration Required ---"
echo "You now need to authorize this application with your Microsoft account: $EMAIL"
echo

# 1. The command below will generate a login URL.
# 2. Copy and paste this URL into your web browser.
# 3. Log in to your Microsoft account and grant access.
# 4. After authorization, your browser will be redirected to a blank page.
# 5. IMPORTANT: Copy the full URL from your browser's address bar (it will start with 'https://login.microsoftonline.com/common/oauth2/nativeclient').
# 6. Paste the entire URL back into this terminal when prompted.

echo "Press Enter to begin the authentication process."
read -p ""

# Run the onedrive command to start authentication. It will wait for the response URI.
onedrive

# --- Systemd Service Setup ---
echo
echo "--- Enabling Automatic Syncing ---"
echo "Configuring the OneDrive service to start automatically on login."

# Enable the systemd service for the current user
systemctl --user enable onedrive
systemctl --user start onedrive

echo
# Check the status of the service
echo "OneDrive service status:"
systemctl --user status onedrive --no-pager

echo
echo "--- Setup Complete ---"
echo "The latest version of OneDrive has been installed and configured."
echo "Your files will now begin syncing to ~/OneDrive."
echo "You can check sync status with 'onedrive --monitor'."

exit 0
