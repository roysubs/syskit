#!/bin/bash
# Author: Roy Wiseman 2025-02

# Install Timeshift and create initial snapshot in rsync mode.

export PATH=$PATH:/usr/local/bin:/usr/bin:/bin

# First line checks running as root or with sudo (exit 1 if not). Second line auto-elevates the script as sudo.
# if [ "$(id -u)" -ne 0 ]; then echo "This script must be run as root or with sudo" 1>&2; exit 1; fi
if [ "$(id -u)" -ne 0 ]; then echo "Elevation required; rerunning as sudo..."; sudo "$0" "$@"; exit 0; fi

# Only update if it's been more than 2 days since the last update (to avoid constant updates)
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update && sudo apt upgrade; fi

# Check if timeshift is installed
if ! command -v timeshift &> /dev/null; then
  echo "Installing Timeshift..."; sudo apt update && apt install -y timeshift
  if ! command -v timeshift &> /dev/null; then echo "Timeshift failed to install. Exiting."; exit 1; fi
fi

# Offer to run the first snapshot creation
echo "Timeshift is now installed and set to rsync mode."
read -p "Do you want to create the first snapshot now? (y/n): " answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
  # Run first snapshot creation
  echo "Creating the first snapshot..."
  timeshift --create --rsync
  echo "First snapshot created."
else
  echo "First snapshot creation skipped."
fi

