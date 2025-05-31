#!/bin/bash
# Author: Roy Wiseman 2025-01
#
# https://github.com/00-Evan/shattered-pixel-dungeon/releases
# Install Shattered Pixel Dungeon for Linux

# Exit script on any error
set -e

sudo apt update
sudo apt install libglfw3 libglfw3-dev libxrandr-dev libxi-dev libxxf86vm-dev
sudo apt install openjdk-11-jre

# Define constants
REPO_URL="https://api.github.com/repos/00-Evan/shattered-pixel-dungeon/releases/latest"
INSTALL_DIR="$HOME/.local/share/shattered-pixel-dungeon"
BIN_DIR="$HOME/.local/bin"
TEMP_DIR="/tmp/shattered-pixel-dungeon"

# Ensure required directories exist
mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$TEMP_DIR"

# Fetch the latest release info
LATEST_RELEASE=$(curl -sL "$REPO_URL")

# Extract the download URL for the Linux ZIP file using jq
ZIP_URL=$(echo "$LATEST_RELEASE" | jq -r '.assets[] | select(.name | test("Linux.zip")) | .browser_download_url')

if [[ -z "$ZIP_URL" ]]; then
  echo "Error: Could not find download URL for Linux ZIP. Exiting."
  exit 1
fi

# Download the Linux ZIP file
ZIP_FILE="$TEMP_DIR/ShatteredPD-Linux.zip"
echo "Downloading Shattered Pixel Dungeon from $ZIP_URL..."
curl -L -o "$ZIP_FILE" "$ZIP_URL"

# Unzip the downloaded file
echo "Unzipping the file..."
unzip -o "$ZIP_FILE" -d "$TEMP_DIR"

# Directly move the extracted folder to the installation directory
echo "Moving the extracted files to the installation directory..."
mv "$TEMP_DIR/shattered-pixel-dungeon" "$INSTALL_DIR"

# Clean up the temporary ZIP file
rm "$ZIP_FILE"

# Ensure the binary location is in the PATH
if ! grep -q "$BIN_DIR" "$HOME/.bashrc"; then
  echo "Adding $BIN_DIR to PATH..."
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  source "$HOME/.bashrc"
fi

# Create symlink for Shattered Pixel Dungeon binary if it's not already in PATH
SPDX_BINARY="$INSTALL_DIR/shattered-pixel-dungeon/bin/ShatteredPD"
if [ -f "$SPDX_BINARY" ]; then
  if ! command -v shatteredpd &>/dev/null; then
    echo "Creating symlink for Shattered Pixel Dungeon..."
    ln -s "$SPDX_BINARY" "$BIN_DIR/shatteredpd"
  fi
else
  echo "Error: Could not find ShatteredPD binary. Exiting."
  exit 1
fi

# Inform the user
echo "Shattered Pixel Dungeon has been installed successfully!"
echo "Binary location: $BIN_DIR/shatteredpd"
echo "Data directory: $INSTALL_DIR"
echo "Shattered Pixel Dungeon should now be available in your PATH."

# Clean up the temporary directory
rm -rf "$TEMP_DIR"

