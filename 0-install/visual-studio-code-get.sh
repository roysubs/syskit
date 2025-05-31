#!/bin/bash
# Author: Roy Wiseman 2025-04

# Script to install Visual Studio Code on Debian with MATE

# Update the package list
echo "Updating package list..."
sudo apt update -y

# Install dependencies
echo "Installing dependencies..."
sudo apt install -y wget gpg

# Import Microsoft's GPG key
echo "Importing Microsoft's GPG key..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg

# Add VS Code repository
echo "Adding Visual Studio Code repository..."
echo "deb [signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/vscode stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

# Update the package list again to include VS Code repository
echo "Updating package list after adding VS Code repository..."
sudo apt update -y

# Install Visual Studio Code
echo "Installing Visual Studio Code..."
sudo apt install -y code

# Launch Visual Studio Code (optional)
echo "Visual Studio Code installation complete. You can now launch it by typing 'code' in the terminal."

# Finished
echo "Installation script completed."

