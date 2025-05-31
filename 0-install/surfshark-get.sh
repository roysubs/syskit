#!/bin/bash
# Author: Roy Wiseman 2025-02

# Function to install Snap (if not already installed)
install_snap() {
    echo "Checking if Snap is installed..."
    if ! command -v snap &> /dev/null; then
        echo "Snap is not installed. Installing Snap..."
        sudo apt update
        sudo apt install -y snapd
        sudo snap install snapd
        echo "Snap installation completed. Please restart your system or log out and log back in before continuing."
        exit 1
    else
        echo "Snap is already installed."
    fi
}

# Function to install Surfshark via Snap
install_surfshark() {
    echo "Installing Surfshark VPN using Snap..."
    if ! snap list | grep -q surfshark; then
        sudo snap install surfshark
        echo "Surfshark VPN installed."
    else
        echo "Surfshark is already installed."
    fi
}

# Function to log in to Surfshark
login_surfshark() {
    echo "Please enter your Surfshark account credentials to log in."
    read -p "Email: " username
    read -sp "Password: " password
    echo
    echo "$password" | snap run surfshark login --user "$username"
}

# Function to display post-install help
show_usage_guide() {
    echo
    echo "✅ Surfshark is now installed via Snap and ready to use."
    echo
    echo "👉 Common commands:"
    echo "  Connect to the fastest server:"
    echo "    sudo surfshark connect"
    echo
    echo "  Connect to a specific country (e.g., Norway):"
    echo "    sudo surfshark connect --country NO"
    echo
    echo "  Disconnect:"
    echo "    sudo surfshark disconnect"
    echo
    echo "  Check connection status:"
    echo "    sudo surfshark status"
    echo
    echo "  View available locations:"
    echo "    sudo surfshark locations"
    echo
    echo "  View settings or enable features:"
    echo "    sudo surfshark settings"
    echo
    echo "  Log out:"
    echo "    sudo surfshark logout"
    echo
    echo "ℹ️ Note: You can also prepend 'snap run' if needed, e.g., 'sudo snap run surfshark status'"
}

# Run all setup steps
install_snap
install_surfshark
login_surfshark
show_usage_guide

