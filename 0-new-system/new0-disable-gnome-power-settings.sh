#!/bin/bash
# Author: Roy Wiseman 2025-01

# Script to attempt disabling GNOME Power Management Settings
# It will first check if 'gsettings' command is available.

# Check if gsettings command is available
if ! command -v gsettings &> /dev/null
then
    echo "---------------------------------------------------------------------"
    echo "INFO: 'gsettings' command not found. This script requires GNOME"
    echo "      Desktop environment and its associated tools."
    echo "      If you are not running GNOME or if it's not fully installed,"
    echo "      this script cannot modify GNOME-specific settings."
    echo "      No changes will be made."
    echo "---------------------------------------------------------------------"
    exit 1
fi

echo "INFO: 'gsettings' command found. Attempting to apply power settings..."
echo "---------------------------------------------------------------------"

# --- Disable GNOME Power Management Sleep/Suspend Settings ---
# Note: GNOME can enforce sleep or suspend modes.
# We disable key settings where applicable.
# The '|| true' part ensures the script continues even if a key doesn't exist or fails to set,
# preventing premature exit if only some keys are problematic.
# More specific error messages for individual keys are now handled by gsettings itself or can be added if needed.

echo "Attempting to set 'sleep-inactive-ac-type' to 'nothing'..."
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' || echo "  WARNING: Could not set 'sleep-inactive-ac-type'. Key might not exist on this GNOME version."

echo "Attempting to set 'sleep-inactive-battery-type' to 'nothing'..."
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' || echo "  WARNING: Could not set 'sleep-inactive-battery-type'. Key might not exist on this GNOME version."

# This key was duplicated in the original script with different values ('nothing' and 'false').
# 'false' typically means suspend is enabled when lid is closed.
# 'nothing' means no action is taken when lid is closed.
# Assuming 'nothing' is the desired state to prevent suspend.
echo "Attempting to set 'button-lid-suspend' to 'nothing' (to prevent suspend on lid close)..."
gsettings set org.gnome.settings-daemon.plugins.power button-lid-suspend 'nothing' || echo "  WARNING: Could not set 'button-lid-suspend'. Key might not exist on this GNOME version."
# If you specifically wanted to set it to 'false' for some reason, you would use:
# gsettings set org.gnome.settings-daemon.plugins.power button-lid-suspend false || echo "  WARNING: Could not set 'button-lid-suspend' to false."


# --- Disable GNOME Session Idle and Screensaver ---
echo "Attempting to disable screen idle timeout (set 'idle-delay' to 0)..."
gsettings set org.gnome.desktop.session idle-delay 0 || echo "  WARNING: Could not set 'idle-delay'. Key might not exist on this GNOME version."

echo "Attempting to disable screensaver activation ('idle-activation-enabled' to false)..."
gsettings set org.gnome.desktop.screensaver idle-activation-enabled false || echo "  WARNING: Could not set 'idle-activation-enabled'. Key might not exist on this GNOME version."


# --- Disable Suspend on Power Button Press ---
echo "Attempting to set 'power-button-action' to 'nothing'..."
gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing' || echo "  WARNING: Could not set 'power-button-action'. Key might not exist on this GNOME version."

echo "---------------------------------------------------------------------"
echo "INFO: GNOME power settings modification attempt finished."
echo "      Review any WARNING messages above to see if specific settings"
echo "      could not be applied (they might be deprecated or named"
echo "      differently in your GNOME version)."
echo "---------------------------------------------------------------------"

# Optional: Check GNOME Logs
# If issues persist, review GNOME logs for unexpected power-related events:
# journalctl -f | grep -i -E 'gnome|power|sleep|suspend'
# (Using 'journalctl -f' will follow the log in real-time)

exit 0

