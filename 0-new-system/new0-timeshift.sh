#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-02

# Install Timeshift and create initial snapshot in rsync mode.

export PATH=$PATH:/usr/local/bin:/usr/bin:/bin

pkg_install() {
    if command -v brew &>/dev/null; then brew install "$@"
    elif command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need brew/apt/zypper/dnf)." >&2; exit 1
    fi
}

# First line checks running as root or with sudo (exit 1 if not). Second line auto-elevates the script as sudo.
# if [ "$(id -u)" -ne 0 ]; then echo "This script must be run as root or with sudo" 1>&2; exit 1; fi
if [ "$(id -u)" -ne 0 ]; then echo "Elevation required; rerunning as sudo..."; sudo "$0" "$@"; exit 0; fi

# Only update if it's been more than 2 days since the last update (to avoid constant updates)
if command -v apt &>/dev/null; then
  if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update && sudo apt upgrade; fi
fi

# Check if timeshift is installed
if ! command -v timeshift &> /dev/null; then
  echo "Installing Timeshift..."; pkg_install timeshift
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

