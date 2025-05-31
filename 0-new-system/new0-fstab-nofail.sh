#!/bin/bash
# Author: Roy Wiseman 2025-01

# Add 'nofail' to non-root filesystems in /etc/fstab to suppress emergency mode; safe for home environments.

echo "
# Prevent Debian from entering emergency mode when there are errors in /etc/fstab.
# This is done by applying the nofail option for entries in fstab that we want
# the OS to be less strict about mounting at boot time.

# Bypassing fstab errors entirely during boot might lead to other issues, as some
# filesystems may be necessary for proper booting, but in a simple NAS setup,
# /dev/sdb, /dev/sdc and non-essential network mounts etc are not critical and so
# this will at least allow the system to continue booting with warnings rather
# than halting or entering emergency mode.

# Adding the nofail option to the relevant lines in /etc/fstab.
"

# First line checks running as root or with sudo (exit 1 if not). Second line auto-elevates the script as sudo.
# if [ "$(id -u)" -ne 0 ]; then echo "This script must be run as root or with sudo" 1>&2; exit 1; fi
if [ "$(id -u)" -ne 0 ]; then echo "Elevation required; rerunning with sudo..."; sudo "$0" "$@"; exit 0; fi

# Only update if it's been more than 2 days since the last update (to avoid constant updates)
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update && sudo apt upgrade; fi

# Define the file location and backup before modifying
FSTAB="/etc/fstab"
cp "$FSTAB" "$FSTAB.$(date +'%Y-%m-%d_%H-%M-%S').bak"
GRUB_CONF="/etc/default/grub"
cp "$GRUB_CONF" "$GRUB_CONF.$(date +'%Y-%m-%d_%H-%M-%S').bak"

# Function to update /etc/fstab
update_fstab() {
  echo "Backing up fstab..."
  cp "$FSTAB" "$FSTAB.bak"
  
  echo "Adding 'nofail' option to non-root filesystems in fstab..."
  awk 'BEGIN {FS=" "; OFS=" ";} 
      {
          # Skip comments and blank lines
          if ($1 ~ /^#/ || NF == 0) {
              print $0;
              next;
          }
          
          # Add 'nofail' option to non-root filesystem entries
          if ($2 != "/" && $2 != "swap") {
              for (i = 4; i <= NF; i++) {
                  if ($i == "nofail") {
                      print $0; 
                      next;
                  }
              }
              $4 = $4 " nofail";  # Add nofail to the mount options
          }
          print $0;
      }' "$FSTAB" > "$FSTAB.tmp" && mv "$FSTAB.tmp" "$FSTAB"

  echo "Updated /etc/fstab with 'nofail' for non-root filesystems."
}

# Function to update GRUB
update_grub() {
  echo "Backing up GRUB configuration..."
  cp "$GRUB_CONF" "$GRUB_BACKUP"

  echo "Updating GRUB to include 'rootflags=nofail'..."
  sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/ s/"$/ rootflags=nofail"/' "$GRUB_CONF"

  echo "Updating GRUB configuration..."
  update-grub
}

# Run both updates
update_fstab
update_grub

echo "All updates completed successfully!"
echo "A reboot is recommended to test the changes."
