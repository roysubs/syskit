#!/bin/bash
# Author: Roy Wiseman 2025-05
#
# https://github.com/swarm-game/swarm/releases
# https://swarm-game.github.io/installing/#installing-via-binaries
# https://byorgey.wordpress.com/2022/06/20/swarm-status-report/

# Exit script on any error
set -e

# Define constants
REPO_URL="https://api.github.com/repos/swarm-game/swarm/releases/latest"
INSTALL_DIR="$HOME/.local/share/swarm"
BIN_DIR="$HOME/.local/bin"

# Ensure required directories exist
mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# Fetch the latest release info
LATEST_RELEASE=$(curl -sL "$REPO_URL")

# Extract asset download URLs using jq
BINARY_URL=$(echo "$LATEST_RELEASE" | jq -r '.assets[] | select(.name | test("swarm-Linux")) | .browser_download_url')
DATA_URL=$(echo "$LATEST_RELEASE" | jq -r '.assets[] | select(.name | test("swarm-data.zip")) | .browser_download_url')

if [[ -z "$BINARY_URL" || -z "$DATA_URL" ]]; then
  echo "Error: Could not find download URLs. Exiting."
  exit 1
fi

if ! command -v swarm &> /dev/null; then
    # Download the binary
    BINARY_PATH="swarm-Linux"
    echo "Downloading binary from $BINARY_URL..."
    curl -L -o "$BINARY_PATH" "$BINARY_URL"
    chmod +x "$BINARY_PATH"
    mv "$BINARY_PATH" "$BIN_DIR/swarm"
    
    # Download and extract the data
    DATA_ARCHIVE="swarm-data.zip"
    echo "Downloading data from $DATA_URL..."
    curl -L -o "$DATA_ARCHIVE" "$DATA_URL"
    unzip -o "$DATA_ARCHIVE" -d "$INSTALL_DIR"
    rm "$DATA_ARCHIVE"
    
    # Ensure the binary location is in the PATH
    if ! grep -q "$BIN_DIR" "$HOME/.bashrc"; then
      echo "Adding $BIN_DIR to PATH..."
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
      source "$HOME/.bashrc"
    fi

    # Create symlink for swarm if it's not already in PATH
    echo "Creating symlink for swarm..."
    ln -s "$BIN_DIR/swarm" "$BIN_DIR/swarm"
fi

# Inform the user
echo "Swarm has been installed successfully!"
echo "Binary location: $BIN_DIR/swarm"
echo "Data directory: $INSTALL_DIR"
echo "Swarm should now be available in your PATH."

