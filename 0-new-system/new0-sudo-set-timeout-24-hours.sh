#!/bin/bash
# Author: Roy Wiseman 2025-01

# sudo will only require a password every 24 hours (or for new sessions; fine for home systems).

# First line checks running as root or with sudo (exit 1 if not). Second line auto-elevates the script as sudo.
# if [ "$(id -u)" -ne 0 ]; then echo "This script must be run as root or with sudo" 1>&2; exit 1; fi
if [ "$(id -u)" -ne 0 ]; then echo "Elevation required; rerunning as sudo..."; sudo "$0" "$@"; exit 0; fi

# Only update if it's been more than 2 days since the last update (to avoid constant updates)
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update && sudo apt upgrade; fi

# Define the line to be added
SUDOERS_LINE="Defaults        timestamp_timeout=1440"

# Check if the line already exists in the sudoers file
if grep -q "^Defaults.*timestamp_timeout" /etc/sudoers; then
  echo "timestamp_timeout is already set in /etc/sudoers."
  echo "To manually alter the value, run:    sudo visudo"
else
  # Safely add the line to the sudoers file using visudo
  echo "Adding timestamp_timeout setting to /etc/sudoers..."
  echo "$SUDOERS_LINE" | EDITOR='tee -a' visudo > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "Successfully added 'Defaults  timestamp_timeout=1440' to /etc/sudoers."
  else
    echo "Failed to update /etc/sudoers. Please check for errors."
    exit 1
  fi
fi

