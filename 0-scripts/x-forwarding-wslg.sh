#!/bin/bash
# Author: Roy Wiseman 2025-02

# This script helps set up and verify X forwarding within WSL2 using WSLg.
# It assumes you have a recent version of Windows 10/11 with WSL2 and WSLg installed.

echo "Starting WSLg X forwarding setup and verification..."

# --- Step 1: Update package lists ---
echo "Updating package lists..."
sudo apt update
if [ $? -eq 0 ]; then
    echo "Package lists updated successfully."
else
    echo "Failed to update package lists. Please check your internet connection and try again."
    exit 1
fi

# --- Step 2: Install necessary X11 applications (if not already installed) ---
# x11-apps includes xclock, xeyes, etc., useful for testing X forwarding.
echo "Installing x11-apps package (if needed)..."
sudo apt install -y x11-apps
if [ $? -eq 0 ]; then
    echo "x11-apps installed or already present."
else
    echo "Failed to install x11-apps. Please check for errors above."
    exit 1
fi

# --- Step 3: Verify DISPLAY environment variable ---
# WSLg typically sets this automatically, but we'll check and suggest adding it to .bashrc
echo "Checking DISPLAY environment variable..."
if [ -z "$DISPLAY" ]; then
    echo "DISPLAY variable is not set. This is unusual if WSLg is running."
    echo "WSLg should automatically set this."
    echo "You might need to restart your WSL instance or Windows."
    echo "If the issue persists, you can manually add 'export DISPLAY=:0' to your ~/.bashrc file,"
    echo "but be aware that WSLg's automatic setting is usually preferred."
else
    echo "DISPLAY is set to: $DISPLAY"
    echo "This looks correct for WSLg."

    # Check if DISPLAY is already in .bashrc (to avoid duplicates if manually added previously)
    if grep -q "export DISPLAY=" ~/.bashrc; then
        echo "Note: A line setting DISPLAY was found in your ~/.bashrc."
        echo "If WSLg is setting it correctly, this manual line might not be needed."
    fi
fi

# --- Step 4: Instruct user on how to test ---
echo ""
echo "---------------------------------------------------"
echo "Setup steps completed."
echo "To test X forwarding, simply type 'xclock' and press Enter."
echo "A clock window should appear on your Windows desktop."
echo "If 'xclock' doesn't work, try closing and reopening your WSL terminal."
echo "If it still fails, ensure WSLg is enabled and running on your Windows machine."
echo "---------------------------------------------------"

exit 0
