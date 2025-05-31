#!/bin/bash
# Author: Roy Wiseman 2025-03

# Add current user to sudo group (without requiring sudo), and update /etc/sudoers
# nosudo - this line prevents setup-new-system.py from running this with sudo.

echo "This script adds the current user access to sudo on a new system."
echo "As the user would have no access yet, it has to 'sudo without sudo'"
echo "to setup the access, running commands with 'su -c' (the root password"
echo "must be known to use this script)."
echo

# Get the current username
USERNAME=$(whoami)

# Prompt for the root password early
echo "Enter the root password to proceed with configuration:"
read -sp "Root Password: " ROOT_PASSWORD
echo

# Check if the user is in the 'sudo' group
if groups "$USERNAME" | grep -q '\bsudo\b'; then
    echo "User $USERNAME is already in the 'sudo' group."
    # Check if sudo is enabled in /etc/sudoers
    echo "Checking if sudo is active in /etc/sudoers..."
    if echo "$ROOT_PASSWORD" | su -c 'grep -q "sudo" /etc/sudoers' 2>/dev/null; then
        echo "sudo is active in /etc/sudoers. Exiting."
        exit 0
    else
        echo "sudo is not active in /etc/sudoers."
    fi
fi

# The rest of the script proceeds only if the root password is correct
echo -e "\nOn Debian systems:
- The root account is used for administrative tasks by default.
- The 'sudo' group is not always enabled by default.
- Some systems use the 'admin' group for sudo privileges."

# Check if the 'sudo' group exists
if getent group sudo &>/dev/null; then
    echo -e "\nThe 'sudo' group exists on your system."
else
    echo -e "\nThe 'sudo' group does not exist. Creating it now..."
    if echo "$ROOT_PASSWORD" | su -c 'groupadd sudo'; then
        echo "The 'sudo' group has been successfully created."
    else
        echo "Failed to create the 'sudo' group. Exiting." >&2
        exit 1
    fi
fi

# Check if the '%sudo' line is already in the /etc/sudoers file
echo -e "\nChecking /etc/sudoers for 'sudo' group configuration..."
if ! echo "$ROOT_PASSWORD" | su -c "grep -q '^%sudo\s*ALL=(ALL:ALL) ALL' /etc/sudoers"; then
    echo -e "\n'%sudo' line not found in /etc/sudoers, adding it now..."
    if echo "$ROOT_PASSWORD" | su -c "echo '%sudo   ALL=(ALL:ALL) ALL' >> /etc/sudoers"; then
        echo "The '%sudo' line has been added successfully."
    else
        echo "Failed to add the '%sudo' line to /etc/sudoers. Exiting." >&2
        exit 1
    fi
else
    echo -e "\n'%sudo' line already exists in /etc/sudoers, skipping addition."
fi

# Remove duplicate %sudo line if present
echo -e "\nRemoving any duplicate '%sudo' lines from /etc/sudoers..."
if echo "$ROOT_PASSWORD" | su -c "grep -n \"^%sudo\s*ALL=(ALL:ALL) ALL\" /etc/sudoers | awk -F: 'NR > 1 {print \$1}' | xargs -I{} sed -i '{}d' /etc/sudoers"; then
    echo "Duplicate '%sudo' lines removed."
else
    echo "Failed to remove duplicate '%sudo' lines. Exiting." >&2
    exit 1
fi

# Check if the user is in the 'sudo' group
echo -e "\nChecking if user '$USERNAME' is a member of the 'sudo' group..."
if groups "$USERNAME" | grep -qw "sudo"; then
    echo "User '$USERNAME' is already a member of the 'sudo' group."
else
    echo "User '$USERNAME' is not a member of the 'sudo' group. Adding now..."
    if echo "$ROOT_PASSWORD" | su -c "/usr/sbin/usermod -aG sudo '$USERNAME'"; then
        echo "User '$USERNAME' has been added to the 'sudo' group."
        echo "Please log out and log back in for the changes to take effect."
    else
        echo "Failed to add user '$USERNAME' to the 'sudo' group. Exiting." >&2
        exit 1
    fi
fi

echo "
Configuration complete.
Remember that group membership changes normally only take effect in new sessions.
Restart the session to enable 'sudo' access.

The 'sudo' group exists and is configured in /etc/sudoers.
- The user '$USERNAME' has been added to the 'sudo' group (if they were not already a member).

Common group membership commands:
  sudo adduser bert --ingroup sudo  # Create user bert and add him to a group (sudo)
  sudo usermod -aG sudo bert        # Add an already-created user to a group (sudo)
  sudo gpasswd -d bert sudo         # Delete bert from a group (sudo)
  getent group sudo                 # View members of a group (sudo)
  members sudo                      # Alternative tool to view members of a group

If you encounter issues, ensure that the /etc/sudoers file has no syntax errors using 'sudo visudo'.
"

