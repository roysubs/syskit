#!/bin/bash

# ---
# Advanced P3X OneNote Installer/Manager for Debian-based Linux
#
# Author: Gemini
# Version: 2.3
#
# Features:
# - Idempotent: Checks if already installed.
# - On-demand Sudo: Asks for password only when needed.
# - Interactive & Silent modes.
# - Full uninstall and purge capabilities.
# - Proactively handles the Linux Mint snapd block and streamlines the install flow.
# ---

# --- Configuration ---
APP_NAME="p3x-onenote"
APP_USER_DATA_DIR="$HOME/snap/$APP_NAME"
NOSNAP_PREF="/etc/apt/preferences.d/nosnap.pref"

# --- Flags ---
SILENT=false
UNINSTALL=false
PURGE=false

# --- Helper Functions ---

# Function to display help/usage information
show_help() {
    echo "P3X OneNote Installer/Manager"
    echo "A script to seamlessly install, uninstall, or purge the P3X OneNote snap package."
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message and exit."
    echo "  -s, --silent      Run in silent mode, answering 'yes' to all prompts."
    echo "  -y, --yes         Synonym for --silent."
    echo "  -u, --uninstall   Uninstall $APP_NAME."
    echo "  -p, --purge       Uninstall $APP_NAME and completely delete all local user data."
    echo ""
    echo "If no options are provided, the script will run the standard installation process."
}

# A robust way to check if a command is available
command_exists() {
    command -v "$1" &>/dev/null
}

# Universal confirmation prompter that respects the SILENT flag
confirm() {
    if [ "$SILENT" = true ]; then
        return 0 # Automatically return success (yes)
    fi

    # Loop until the user provides a valid response
    while true; do
        read -p "$1 [y/n]: " yn
        case $yn in
            [Yy]* ) return 0;; # Success (yes)
            [Nn]* ) return 1;; # Failure (no)
            * ) echo "Please answer yes or no.";;
        esac
    done
}


# --- Core Logic Functions ---

install_onenote() {
    echo "--- Starting OneNote Installation ---"

    # 1. Idempotency Check: Is OneNote already installed?
    if command_exists $APP_NAME; then
        echo "✅ $APP_NAME is already installed. Launching now."
        nohup $APP_NAME &>/dev/null &
        exit 0
    fi
    echo "🔍 $APP_NAME not found. Proceeding with installation."

    # 2. Dependency Check: Is snapd installed?
    if ! command_exists snap; then
        echo "⚠️  The '$APP_NAME' application requires 'snapd', which is not found on your system."

        # Proactively check for Linux Mint's snapd block
        if [ -f "$NOSNAP_PREF" ]; then
            echo "⚠️ It looks like you're on a Linux Mint system that blocks Snap."
            echo "   The block is configured in: $NOSNAP_PREF"
            if confirm "Do you want to remove this block to allow snapd installation?"; then
                echo "🔧 Removing snap block..."
                sudo rm -f "$NOSNAP_PREF"
                echo "🔄 Updating package lists to apply changes..."
                sudo apt-get update
                echo "🔧 Installing snapd..."
                sudo apt-get install -y snapd
            else
                echo "🛑 Installation aborted by user. Cannot proceed without removing the block."
                exit 1
            fi
        else
            # Not a Mint block issue, so ask for generic confirmation
            if confirm "Do you want to install snapd now?"; then
                echo "🔧 Installing snapd..."
                sudo apt-get update
                sudo apt-get install -y snapd
            else
                echo "🛑 Installation aborted by user."
                exit 1
            fi
        fi

        # Final verification of snapd install after either path
        if ! command_exists snap; then
            echo "❌ Snapd installation failed. Please review the errors above and diagnose manually."
            exit 1
        fi
        echo "✅ Snapd installed successfully."

    else
        echo "✅ Snapd is already installed."
    fi

    # 3. Install P3X OneNote
    echo "🚀 Installing $APP_NAME..."
    sudo snap install $APP_NAME
    if ! command_exists $APP_NAME; then
        echo "❌ $APP_NAME installation failed via snap. Please check for errors above."
        exit 1
    fi

    echo "✅ $APP_NAME installed successfully!"
    echo "🎉 Launching OneNote. Please log in with your Microsoft account in the app window."
    nohup $APP_NAME &>/dev/null &
}

uninstall_onenote() {
    echo "--- Starting OneNote Uninstall ---"

    if ! command_exists $APP_NAME; then
        echo "✅ $APP_NAME is not installed. Nothing to do."
        return 0
    fi

    if confirm "Are you sure you want to uninstall $APP_NAME?"; then
        echo "🗑️ Removing $APP_NAME..."
        sudo snap remove $APP_NAME
        echo "✅ Uninstallation complete."
    else
        echo "🛑 Uninstall aborted by user."
    fi
}

purge_onenote() {
    echo "--- Starting OneNote Purge ---"
    echo "🔥 WARNING: Purging will uninstall the application AND permanently delete all local data"
    echo "   (notes, settings, login information). This action cannot be undone."

    if confirm "Are you absolutely sure you want to purge $APP_NAME and all its data?"; then
        # Perform removal if the app exists
        if command_exists $APP_NAME; then
            echo "🗑️ Removing $APP_NAME application..."
            sudo snap remove $APP_NAME
        fi

        # Delete the user data directory
        if [ -d "$APP_USER_DATA_DIR" ]; then
            echo "🔥 Deleting user data from $APP_USER_DATA_DIR..."
            rm -rf "$APP_USER_DATA_DIR"
            echo "✅ User data has been purged."
        else
            echo "✅ No user data directory found to purge."
        fi
        echo "✅ Purge complete."
    else
        echo "🛑 Purge aborted by user."
    fi
}

# --- Main Execution ---

# Parse command-line arguments
if [ $# -eq 0 ]; then
    # No arguments, run default install
    install_onenote
    exit 0
fi

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--silent|-y|--yes)
            SILENT=true
            shift
            ;;
        -u|--uninstall)
            UNINSTALL=true
            shift
            ;;
        -p|--purge)
            PURGE=true
            shift
            ;;
        *)
            echo "Unknown parameter passed: $1"
            show_help
            exit 1
            ;;
    esac
done

# Execute actions based on flags
if [ "$PURGE" = true ]; then
    purge_onenote
elif [ "$UNINSTALL" = true ]; then
    uninstall_onenote
else
    # If only --silent was passed, default to install
    install_onenote
fi

exit 0

