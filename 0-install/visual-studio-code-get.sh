#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-04

# Script to install Visual Studio Code

install_vscode() {
    if command -v brew &>/dev/null; then
        echo "Installing Visual Studio Code via Homebrew..."
        brew install --cask visual-studio-code
        return
    fi

    if command -v apt &>/dev/null; then
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
    elif command -v dnf &>/dev/null; then
        echo "Importing Microsoft's GPG key..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo "Adding Visual Studio Code repository..."
        echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
        echo "Installing Visual Studio Code..."
        sudo dnf check-update &>/dev/null
        sudo dnf install -y code
    elif command -v zypper &>/dev/null; then
        echo "Importing Microsoft's GPG key..."
        sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
        echo "Adding Visual Studio Code repository..."
        sudo zypper --non-interactive addrepo -f https://packages.microsoft.com/yumrepos/vscode vscode
        sudo zypper --non-interactive refresh
        echo "Installing Visual Studio Code..."
        sudo zypper install -y code
    else
        echo "No supported package manager found (need brew/apt/zypper/dnf)." >&2
        exit 1
    fi
}

install_vscode

# Launch Visual Studio Code (optional)
echo "Visual Studio Code installation complete. You can now launch it by typing 'code' in the terminal."

# Finished
echo "Installation script completed."

