#!/bin/bash
# Author: Roy Wiseman 2025-01

# Define colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}--- Interactive Debian X Forwarding Server Setup ---${NC}"
echo "This script will guide you through configuring your Debian system (the server)"
echo "to allow X11 graphical applications to be forwarded over SSH to another machine"
echo "(the client, e.g., your Windows PC running VcXsrv)."
echo "We'll explain each step and show the commands being run."
echo ""
read -p "Press Enter to continue..."

# --- Step 0: Ensure script is not run as root initially ---
if [ "$(id -u)" -eq 0 ]; then
  echo -e "${YELLOW}This script should not be run as root directly. It uses 'sudo' where necessary.${NC}"
  echo "Please run it as a regular user with sudo privileges."
  exit 1
fi

# --- Step 1: Update package lists (conditionally based on system-wide apt activity) ---
echo ""
echo -e "${CYAN}--- Step 1: Update Package Lists (System-Wide Check) ---${NC}"
echo "This script will check if 'apt update' has been run system-wide in the last 24 hours."

RECENT_APT_ACTIVITY_FOUND=false
# We need to check if any list file was updated, sudo is required to traverse /var/lib/apt/lists
echo "Checking system apt list modification times..."
if sudo find /var/lib/apt/lists -type f -mmin -1440 -print -quit 2>/dev/null | grep -q .; then
    # -mmin -1440: modified less than 1440 minutes (24 hours) ago.
    # -print -quit: find will print the first match and exit immediately (GNU extension, common on Linux).
    # grep -q .: checks if find produced any output (i.e., found a recent file).
    # 2>/dev/null: suppresses find errors (e.g., permission denied if not using sudo, though sudo should prevent this).
    echo -e "${YELLOW}A system-wide 'apt update' appears to have been run in the last 24 hours. Skipping 'apt update' for this script.${NC}"
    RECENT_APT_ACTIVITY_FOUND=true
else
    echo "No system-wide 'apt update' activity detected in the last 24 hours, or unable to determine."
fi

if [ "$RECENT_APT_ACTIVITY_FOUND" = false ]; then
    echo "Package lists will be updated to ensure installation of the latest software versions."
    echo -e "Command to be run: ${GREEN}sudo apt update${NC}"
    read -p "Press Enter to run this command..."
    sudo apt update
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}Package lists updated successfully.${NC}"
    else
        echo -e "${YELLOW}Failed to update package lists. Please check your internet connection and try again.${NC}"
        exit 1
    fi
else
    # If skipped, still give a positive confirmation that this step is okay.
    echo -e "${YELLOW}Package list check complete (system-wide update was recent, so 'apt update' by this script was skipped).${NC}"
fi

# --- Step 2: Install necessary packages (openssh-server and xauth) ---
echo ""
echo -e "${CYAN}--- Step 2: Install Required Packages ---${NC}"
echo "'openssh-server' is needed to accept SSH connections."
echo "'xauth' is a utility that manages X authentication cookies, which are essential for secure X forwarding."
echo "We'll install them if they are not already present."
echo -e "Command to be run: ${GREEN}sudo apt install -y openssh-server xauth${NC}"
read -p "Press Enter to run this command..."
sudo apt install -y openssh-server xauth
if [ $? -eq 0 ]; then
    echo -e "${YELLOW}openssh-server and xauth installed or already present.${NC}"
else
    echo -e "${YELLOW}Failed to install openssh-server or xauth. Please check for errors above.${NC}"
    exit 1
fi

# --- Step 3: Verify SSH server configuration for X11Forwarding ---
SSH_CONFIG_FILE="/etc/ssh/sshd_config"
SSH_CONFIG_NEEDS_CHANGE=false # Flag to track if sshd restart is needed

echo ""
echo -e "${CYAN}--- Step 3: Configure SSH Server for X11 Forwarding ---${NC}"
echo "The SSH server needs 'X11Forwarding yes' in its configuration file: $SSH_CONFIG_FILE"
echo ""
echo "Checking current 'X11Forwarding' setting..."

# Check for the canonical "X11Forwarding yes"
if grep -qE "^[[:space:]]*X11Forwarding[[:space:]]+yes" "$SSH_CONFIG_FILE"; then
    echo -e "${YELLOW}X11Forwarding is already enabled (canonically) in $SSH_CONFIG_FILE.${NC}"
# Check if it's set to 'yes' but with non-canonical casing
elif grep -qEi "^[[:space:]]*X11Forwarding[[:space:]]+yes" "$SSH_CONFIG_FILE"; then
    echo "X11Forwarding is set to 'yes' but potentially with non-canonical casing."
    echo "Attempting to canonicalize to 'X11Forwarding yes'..."
    BACKUP_FILE_SSH="${SSH_CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    echo -e "Command to backup: ${GREEN}sudo cp \"$SSH_CONFIG_FILE\" \"${BACKUP_FILE_SSH}\"${NC}"
    sudo cp "$SSH_CONFIG_FILE" "${BACKUP_FILE_SSH}" && echo -e "${YELLOW}Backed up config to ${BACKUP_FILE_SSH}${NC}"

    echo -e "Command: ${GREEN}sudo sed -i -E 's/^([[:space:]]*)([Xx]11[Ff]orwarding[[:space:]]+)yes/\1X11Forwarding yes/' \"$SSH_CONFIG_FILE\"${NC}"
    sudo sed -i -E 's/^([[:space:]]*)([Xx]11[Ff]orwarding[[:space:]]+)yes/\1X11Forwarding yes/' "$SSH_CONFIG_FILE"
    SSH_CONFIG_NEEDS_CHANGE=true
else
    echo -e "${YELLOW}X11Forwarding is NOT enabled or is commented out in $SSH_CONFIG_FILE.${NC}"
    echo "Attempting to enable X11Forwarding..."
    read -p "Press Enter to proceed..."

    BACKUP_FILE_SSH="${SSH_CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    echo -e "Command to backup: ${GREEN}sudo cp \"$SSH_CONFIG_FILE\" \"${BACKUP_FILE_SSH}\"${NC}"
    sudo cp "$SSH_CONFIG_FILE" "${BACKUP_FILE_SSH}" && echo -e "${YELLOW}Backed up config to ${BACKUP_FILE_SSH}${NC}"

    # Attempt to change any '# X11Forwarding no' or 'X11Forwarding no' (any case for keyword) to 'X11Forwarding yes'
    echo -e "Command: ${GREEN}sudo sed -i -E 's/^[[:space:]]*#?[[:space:]]*([Xx]11[Ff]orwarding[[:space:]]+)no/X11Forwarding yes/' \"$SSH_CONFIG_FILE\"${NC}"
    sudo sed -i -E 's/^[[:space:]]*#?[[:space:]]*([Xx]11[Ff]orwarding[[:space:]]+)no/X11Forwarding yes/' "$SSH_CONFIG_FILE"
    # Attempt to uncomment '# X11Forwarding yes' (any case for keyword) to 'X11Forwarding yes'
    echo -e "Command: ${GREEN}sudo sed -i -E 's/^[[:space:]]*#([[:space:]]*[Xx]11[Ff]orwarding[[:space:]]+yes)/\1X11Forwarding yes/' \"$SSH_CONFIG_FILE\"${NC}"
    sudo sed -i -E 's/^[[:space:]]*#([[:space:]]*[Xx]11[Ff]orwarding[[:space:]]+yes)/\1X11Forwarding yes/' "$SSH_CONFIG_FILE"

    if ! grep -qE "^[[:space:]]*X11Forwarding[[:space:]]+yes" "$SSH_CONFIG_FILE"; then
        echo "Adding 'X11Forwarding yes' as it was not found or couldn't be modified from 'no'."
        echo -e "Command: ${GREEN}echo \"X11Forwarding yes\" | sudo tee -a \"$SSH_CONFIG_FILE\" > /dev/null${NC}"
        echo "X11Forwarding yes" | sudo tee -a "$SSH_CONFIG_FILE" > /dev/null
    fi
    SSH_CONFIG_NEEDS_CHANGE=true
fi

# Verify and clean up X11Forwarding
if grep -qE "^[[:space:]]*X11Forwarding[[:space:]]+yes" "$SSH_CONFIG_FILE"; then
    echo -e "${YELLOW}X11Forwarding is now configured to 'yes'.${NC}"
    # Comment out any other non-canonical active X11Forwarding lines
    # This means: if a line matches case-insensitively X11Forwarding, but NOT "X11Forwarding yes", and is active, comment it.
    TEMP_SED_SCRIPT=$(mktemp)
    # Lines that are NOT 'X11Forwarding yes' AND match '[Xx]11[Ff]orwarding...' AND are not already commented
    # The `[^#]` at the beginning of the line check inside the condition avoids commenting already commented lines.
    echo '/^[[:space:]]*X11Forwarding[[:space:]]+yes/b' > "$TEMP_SED_SCRIPT" # If it's the canonical one, skip
    echo '/^[[:space:]]*[Xx]11[Ff]orwarding[[:space:]]+/ { /^[^#]/ s/^/# -- Deactivated duplicate: / }' >> "$TEMP_SED_SCRIPT"
    echo -e "Command (cleanup): ${GREEN}sudo sed -i -f \"$TEMP_SED_SCRIPT\" \"$SSH_CONFIG_FILE\"${NC}"
    sudo sed -i -f "$TEMP_SED_SCRIPT" "$SSH_CONFIG_FILE"
    rm "$TEMP_SED_SCRIPT"
else
    echo -e "${YELLOW}Failed to set X11Forwarding to 'yes'. Please manually edit $SSH_CONFIG_FILE.${NC}"
    exit 1
fi


# --- Step 4: Check/Configure X11UseLocalhost ---
echo ""
echo -e "${CYAN}--- Step 4: Configure X11UseLocalhost ---${NC}"
echo "The 'X11UseLocalhost' directive defaults to 'yes', restricting X11 forwarding to the server's loopback interface (more secure)."
echo "'X11UseLocalhost no' makes it listen on all interfaces, which might be needed for some complex setups but is less secure."
echo "We recommend 'X11UseLocalhost yes'."

# Check for "X11UseLocalhost no" (any case for keyword)
if grep -qEi "^[[:space:]]*X11UseLocalhost[[:space:]]+no" "$SSH_CONFIG_FILE"; then
    echo -e "${YELLOW}Warning: 'X11UseLocalhost no' (or similar casing) seems to be active.${NC}"
    read -p "Do you want to change this to the recommended 'X11UseLocalhost yes'? (Y/n) " choice
    if [[ "$choice" =~ ^[Yy]([Ee][Ss])?$|^$ ]]; then # Default to Yes
        echo "Changing to 'X11UseLocalhost yes'..."
        if [ "$SSH_CONFIG_NEEDS_CHANGE" = false ] && [ ! -f "${BACKUP_FILE_SSH}" ]; then # Backup if not done already in this script run
            BACKUP_FILE_SSH="${SSH_CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
            echo -e "Command to backup: ${GREEN}sudo cp \"$SSH_CONFIG_FILE\" \"${BACKUP_FILE_SSH}\"${NC}"
            sudo cp "$SSH_CONFIG_FILE" "${BACKUP_FILE_SSH}" && echo -e "${YELLOW}Backed up config to ${BACKUP_FILE_SSH}${NC}"
        fi
        # Change any active '[Xx]11[Uu]se[Ll]ocalhost no' to 'X11UseLocalhost yes'
        echo -e "Command: ${GREEN}sudo sed -i -E 's/^([[:space:]]*)([Xx]11[Uu]se[Ll]ocalhost[[:space:]]+)no/\1X11UseLocalhost yes/' \"$SSH_CONFIG_FILE\"${NC}"
        sudo sed -i -E 's/^([[:space:]]*)([Xx]11[Uu]se[Ll]ocalhost[[:space:]]+)no/\1X11UseLocalhost yes/' "$SSH_CONFIG_FILE"
        SSH_CONFIG_NEEDS_CHANGE=true
    else
        echo "Keeping 'X11UseLocalhost no' as per your choice. Be aware of security implications."
    fi
# Check for "X11UseLocalhost yes" (any case for keyword, but not canonical)
elif grep -qEi "^[[:space:]]*X11UseLocalhost[[:space:]]+yes" "$SSH_CONFIG_FILE" && \
     ! grep -qE "^[[:space:]]*X11UseLocalhost[[:space:]]+yes" "$SSH_CONFIG_FILE"; then
    echo "Found 'X11UseLocalhost yes' but with non-canonical casing. Correcting..."
    if [ "$SSH_CONFIG_NEEDS_CHANGE" = false ] && [ ! -f "${BACKUP_FILE_SSH}" ]; then
        BACKUP_FILE_SSH="${SSH_CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        echo -e "Command to backup: ${GREEN}sudo cp \"$SSH_CONFIG_FILE\" \"${BACKUP_FILE_SSH}\"${NC}"
        sudo cp "$SSH_CONFIG_FILE" "${BACKUP_FILE_SSH}" && echo -e "${YELLOW}Backed up config to ${BACKUP_FILE_SSH}${NC}"
    fi
    echo -e "Command: ${GREEN}sudo sed -i -E 's/^([[:space:]]*)([Xx]11[Uu]se[Ll]ocalhost[[:space:]]+)yes/\1X11UseLocalhost yes/' \"$SSH_CONFIG_FILE\"${NC}"
    sudo sed -i -E 's/^([[:space:]]*)([Xx]11[Uu]se[Ll]ocalhost[[:space:]]+)yes/\1X11UseLocalhost yes/' "$SSH_CONFIG_FILE"
    SSH_CONFIG_NEEDS_CHANGE=true
# Check if "X11UseLocalhost" is commented out or absent, then ensure it's 'yes'
elif ! grep -qE "^[[:space:]]*X11UseLocalhost[[:space:]]+yes" "$SSH_CONFIG_FILE"; then
    echo "'X11UseLocalhost yes' (canonical) not found. Ensuring it's active."
    echo "This might involve uncommenting it or adding it if completely absent."
    read -p "Press Enter to proceed..."
    if [ "$SSH_CONFIG_NEEDS_CHANGE" = false ] && [ ! -f "${BACKUP_FILE_SSH}" ]; then
        BACKUP_FILE_SSH="${SSH_CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        echo -e "Command to backup: ${GREEN}sudo cp \"$SSH_CONFIG_FILE\" \"${BACKUP_FILE_SSH}\"${NC}"
        sudo cp "$SSH_CONFIG_FILE" "${BACKUP_FILE_SSH}" && echo -e "${YELLOW}Backed up config to ${BACKUP_FILE_SSH}${NC}"
    fi
    # Uncomment '# X11UseLocalhost yes' (any case) to 'X11UseLocalhost yes'
    echo -e "Command: ${GREEN}sudo sed -i -E 's/^[[:space:]]*#([[:space:]]*[Xx]11[Uu]se[Ll]ocalhost[[:space:]]+yes)/\1X11UseLocalhost yes/' \"$SSH_CONFIG_FILE\"${NC}"
    sudo sed -i -E 's/^[[:space:]]*#([[:space:]]*[Xx]11[Uu]se[Ll]ocalhost[[:space:]]+yes)/\1X11UseLocalhost yes/' "$SSH_CONFIG_FILE"
    # Change '# X11UseLocalhost no' (any case) to 'X11UseLocalhost yes'
    echo -e "Command: ${GREEN}sudo sed -i -E 's/^[[:space:]]*#([[:space:]]*[Xx]11[Uu]se[Ll]ocalhost[[:space:]]+)no/\1X11UseLocalhost yes/' \"$SSH_CONFIG_FILE\"${NC}"
    sudo sed -i -E 's/^[[:space:]]*#([[:space:]]*[Xx]11[Uu]se[Ll]ocalhost[[:space:]]+)no/\1X11UseLocalhost yes/' "$SSH_CONFIG_FILE"

    if ! grep -qE "^[[:space:]]*X11UseLocalhost[[:space:]]+yes" "$SSH_CONFIG_FILE"; then
        echo "Adding 'X11UseLocalhost yes' as it's still not found."
        echo -e "Command: ${GREEN}echo \"X11UseLocalhost yes\" | sudo tee -a \"$SSH_CONFIG_FILE\" > /dev/null${NC}"
        echo "X11UseLocalhost yes" | sudo tee -a "$SSH_CONFIG_FILE" > /dev/null
    fi
    SSH_CONFIG_NEEDS_CHANGE=true
fi

# Verify and clean up X11UseLocalhost (if we aimed for 'yes')
if grep -qE "^[[:space:]]*X11UseLocalhost[[:space:]]+yes" "$SSH_CONFIG_FILE"; then
    echo -e "${YELLOW}X11UseLocalhost is now configured to 'yes' (or was already).${NC}"
    # Comment out any other non-canonical active X11UseLocalhost lines that are not 'yes'
    TEMP_SED_SCRIPT_ULH=$(mktemp)
    echo '/^[[:space:]]*X11UseLocalhost[[:space:]]+yes/b' > "$TEMP_SED_SCRIPT_ULH" # If it's the canonical 'yes', skip
    # Comment active lines matching '[Xx]11[Uu]se[Ll]ocalhost' that are not the one above
    echo '/^[[:space:]]*[Xx]11[Uu]se[Ll]ocalhost[[:space:]]+/ { /^[^#]/ s/^/# -- Deactivated duplicate: / }' >> "$TEMP_SED_SCRIPT_ULH"
    echo -e "Command (cleanup): ${GREEN}sudo sed -i -f \"$TEMP_SED_SCRIPT_ULH\" \"$SSH_CONFIG_FILE\"${NC}"
    sudo sed -i -f "$TEMP_SED_SCRIPT_ULH" "$SSH_CONFIG_FILE"
    rm "$TEMP_SED_SCRIPT_ULH"
elif grep -qEi "^[[:space:]]*X11UseLocalhost[[:space:]]+no" "$SSH_CONFIG_FILE"; then
    echo -e "${YELLOW}X11UseLocalhost remains configured to 'no' as per user choice or existing state.${NC}"
else
    echo -e "${YELLOW}Failed to definitively set X11UseLocalhost. Please check $SSH_CONFIG_FILE manually.${NC}"
    # It's possible it's just commented out and thus defaults to 'yes', which is fine.
    # Add a check for commented out. If neither 'yes' nor 'no' is active, it defaults to 'yes'.
    if ! grep -qE "^[[:space:]]*[Xx]11[Uu]se[Ll]ocalhost" "$SSH_CONFIG_FILE"; then
        echo "X11UseLocalhost is not explicitly set, defaulting to 'yes', which is recommended."
    fi
fi

# --- Step 5: Restart SSH Service (if changes were made) ---
echo ""
echo -e "${CYAN}--- Step 5: Restart SSH Service ---${NC}"
if [ "$SSH_CONFIG_NEEDS_CHANGE" = true ]; then
    echo "Changes were made to the SSH server configuration ($SSH_CONFIG_FILE)."
    echo "The SSH service (sshd) needs to be restarted for these changes to take effect."
    echo -e "Command to be run: ${GREEN}sudo systemctl restart sshd${NC}"
    read -p "Press Enter to restart the SSH service..."
    sudo systemctl restart sshd
    if [ $? -eq 0 ]; then
        echo -e "${YELLOW}SSH service restarted successfully.${NC}"
    else
        echo -e "${YELLOW}Failed to restart SSH service. Please try restarting it manually using 'sudo systemctl restart sshd'.${NC}"
        echo "You can check its status with 'sudo systemctl status sshd'."
        exit 1
    fi
else
    echo -e "${YELLOW}No changes requiring SSH service restart were made to $SSH_CONFIG_FILE by this script.${NC}"
fi

echo ""
echo -e "${YELLOW}---------------------------------------------------${NC}"
echo -e "${YELLOW}Debian server-side X forwarding setup steps completed!${NC}"
echo ""
echo -e "${CYAN}Next Steps on Your Client Machine (e.g., Windows with VcXsrv):${NC}"
echo "1.  Ensure your X Server (e.g., VcXsrv, XQuartz) is running on your client machine."
echo "    For VcXsrv: Ensure 'Disable access control' is UNCHECKED for better security"
echo "    (as 'X11UseLocalhost yes' is the recommended server setting)."
echo "2.  Connect from your client to this Debian machine using SSH with X forwarding enabled:"
echo -e "    Command: ${GREEN}ssh -X your_username@your_debian_ip_address_or_hostname${NC}"
echo -e "    (Alternatively, use ${GREEN}ssh -Y your_username@your_debian_ip_address_or_hostname${NC} if -X gives you trouble."
echo "     -Y is less secure as it bypasses X11 security extension controls)."
echo "3.  Once connected via SSH, try running a graphical application from the Debian terminal:"
echo -e "    Example commands: ${GREEN}xclock${NC}, ${GREEN}xeyes${NC}, ${GREEN}xfce4-terminal${NC}"
echo ""
echo -e "${YELLOW}Troubleshooting Tips:${NC}"
echo -e "- If it doesn't work, double-check firewall settings on both the Debian server (e.g., ufw) and your client machine."
echo -e "- Use verbose SSH output for clues: ${GREEN}ssh -v -X user@host${NC} (or -vv, -vvv for more verbosity)."
echo -e "- Check the SSH server logs on Debian: ${GREEN}sudo journalctl -u sshd -f${NC}"
echo -e "- Ensure ${GREEN}X11Forwarding yes${NC} and ${GREEN}X11UseLocalhost yes${NC} (or commented out, which defaults to 'yes') are in ${GREEN}/etc/ssh/sshd_config${NC} for security."
echo -e "${YELLOW}---------------------------------------------------${NC}"

exit 0
