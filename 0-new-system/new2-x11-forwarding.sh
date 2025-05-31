#!/bin/bash
# Author: Roy Wiseman 2025-01

# Title: Configure X11 Forwarding
# Description: This script installs necessary packages, configures the SSH server
#              for X11 forwarding, adjusts firewall settings, and provides
#              instructions for client-side setup.

# --- Configuration ---
SSHD_CONFIG_FILE="/etc/ssh/sshd_config"
REQUIRED_PACKAGES=(
    "openssh-server" # For SSH connectivity
    "xauth"          # For X11 authentication
    "x11-apps"       # For basic X11 apps like xclock (for testing)
    "xclip"          # For clipboard integration
)

# --- Helper Functions ---

# Function to print messages
_msg() {
    echo "INFO: $1"
}

_warn() {
    echo "WARN: $1"
}

_err() {
    echo "ERROR: $1" >&2
}

# Function to check if a command exists
_command_exists() {
    command -v "$1" &>/dev/null
}

# Function to ensure a line is present and correct in sshd_config
_ensure_sshd_config() {
    local key="$1"
    local value="$2"
    local current_value
    _msg "Ensuring SSHD config: '${key}' is set to '${value}'..."

    # Check if key exists (commented or uncommented)
    if sudo grep -qE "^\s*#?\s*${key}\s+" "${SSHD_CONFIG_FILE}"; then
        current_value=$(sudo grep -E "^\s*#?\s*${key}\s+" "${SSHD_CONFIG_FILE}" | awk '{print $2}')
        if [[ "$current_value" == "$value" ]] && sudo grep -qE "^\s*${key}\s+${value}" "${SSHD_CONFIG_FILE}"; then
            _msg "'${key} ${value}' is already correctly set and uncommented."
            return
        fi
        # Modify the existing line (uncomment and set value)
        sudo sed -i -E "s/^\s*#?\s*${key}\s+.*/${key} ${value}/" "${SSHD_CONFIG_FILE}"
        _msg "Modified existing line for '${key}' to '${value}'."
    else
        # If key is not present, add it
        echo "${key} ${value}" | sudo tee -a "${SSHD_CONFIG_FILE}" > /dev/null
        _msg "Added '${key} ${value}' to ${SSHD_CONFIG_FILE}."
    fi
}

# --- Main Script ---

# Check if the script is run as root or with sudo
if [ "$EUID" -ne 0 ]; then
  _err "This script must be run as root or with sudo."
  exit 1
fi

_msg "Starting X11 Forwarding Setup..."

# 1. Update package lists
_msg "Updating package lists..."
if ! sudo apt update; then
    _err "Failed to update package lists. Please check your network connection and repositories."
    exit 1
fi

# 2. Install necessary packages
_msg "Installing required packages: ${REQUIRED_PACKAGES[*]}..."
missing_packages=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg -s "$pkg" &>/dev/null; then
        missing_packages+=("$pkg")
    else
        _msg "Package '$pkg' is already installed."
    fi
done

if [ ${#missing_packages[@]} -gt 0 ]; then
    if ! sudo apt install -y "${missing_packages[@]}"; then
        _err "Failed to install some required packages: ${missing_packages[*]}. Please check for errors."
        # Optionally, exit here or let it continue if some are non-critical
        # exit 1
    else
        _msg "Successfully installed: ${missing_packages[*]}."
    fi
else
    _msg "All required packages are already installed."
fi

# 3. Configure SSH server for X11 Forwarding
_msg "Configuring SSH server for X11 Forwarding..."

# Backup the original sshd_config before modifying
if [ ! -f "${SSHD_CONFIG_FILE}.bak.$(date +%F)" ]; then # Avoid multiple backups per day
    _msg "Backing up ${SSHD_CONFIG_FILE} to ${SSHD_CONFIG_FILE}.bak.$(date +%F)..."
    sudo cp "${SSHD_CONFIG_FILE}" "${SSHD_CONFIG_FILE}.bak.$(date +%F)"
else
    _msg "Daily backup of ${SSHD_CONFIG_FILE} already exists."
fi

_ensure_sshd_config "X11Forwarding" "yes"
_ensure_sshd_config "X11DisplayOffset" "10"
_ensure_sshd_config "X11UseLocalhost" "yes" # 'yes' binds to localhost on server, generally more secure.

# 4. Configure Firewall
_msg "Configuring firewall to allow SSH connections on port 22..."
if _command_exists ufw; then
    if sudo ufw status | grep -qw active; then
        _msg "UFW is active. Allowing SSH (port 22/tcp)..."
        sudo ufw allow ssh # 'ssh' is an alias for 22/tcp in ufw
        sudo ufw status verbose | grep -E "22/tcp.*ALLOW IN|ssh.*ALLOW IN" # Display relevant rule
    else
        _warn "UFW is installed but not active. Consider enabling it with 'sudo ufw enable'."
    fi
elif _command_exists firewall-cmd; then
    _msg "Firewalld detected. Ensuring SSH service is allowed..."
    if ! sudo firewall-cmd --query-service=ssh --permanent &>/dev/null; then
         sudo firewall-cmd --permanent --add-service=ssh
         sudo firewall-cmd --reload
         _msg "SSH service added to firewalld permanent rules and reloaded."
    else
        _msg "SSH service is already allowed in firewalld permanent rules."
    fi
elif _command_exists iptables; then
    _warn "Using iptables. Attempting to add rule for port 22/tcp (persistence not guaranteed)."
    if ! sudo iptables -C INPUT -p tcp --dport 22 -j ACCEPT &>/dev/null; then
        sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        _msg "iptables rule added for port 22/tcp. Ensure you save your iptables rules for persistence (e.g., using 'iptables-persistent')."
    else
        _msg "iptables rule for port 22/tcp already appears to exist."
    fi
else
    _warn "No recognized firewall management tool (ufw, firewalld, iptables) found. Please configure your firewall manually to allow SSH on port 22 if needed."
fi

# 5. Restart SSH service to apply changes
_msg "Restarting SSH service (sshd)..."
if ! sudo systemctl restart sshd; then
    _err "Failed to restart sshd service. Check service status with 'sudo systemctl status sshd' and logs with 'sudo journalctl -u sshd'."
    exit 1
fi
_msg "SSH service restarted successfully."

# 6. Summary and Instructions
echo ""
echo "--------------------------------------------------------------------"
echo " X11 Forwarding Server-Side Setup Complete!"
echo "--------------------------------------------------------------------"
echo ""
echo "Summary of changes on this server:"
echo "  1. Ensured necessary packages are installed: ${REQUIRED_PACKAGES[*]}."
echo "  2. Configured '${SSHD_CONFIG_FILE}' to enable X11 forwarding."
echo "  3. Attempted to configure the firewall to allow SSH on port 22."
echo "  4. Restarted the SSH service (sshd)."
echo ""
echo "--------------------------------------------------------------------"
echo " Client-Side Setup & Usage Instructions"
echo "--------------------------------------------------------------------"
echo ""
echo "To use X11 forwarding, you need an X Server running on your **client** machine."
echo ""
echo "**1. For Linux Clients:**"
echo "   Most desktop Linux distributions have an X server running by default."
echo "   Connect using: ssh -X your_user@$(hostname -I | awk '{print $1}')"
echo "   (Replace 'your_user' with your username on this server)."
echo ""
echo "**2. For macOS Clients:**"
echo "   Install XQuartz (from xquartz.org). After installation, log out and log back in or reboot."
echo "   XQuartz should start automatically when an X11 application tries to connect."
echo "   Connect using: ssh -X your_user@$(hostname -I | awk '{print $1}')"
echo ""
echo "**3. For Windows Clients:**"
echo "   a. Install an X Server application, such as:"
echo "      - VcXsrv (sourceforge.net/projects/vcxsrv/)"
echo "      - Xming (sourceforge.net/projects/xming/)"
echo "   b. Launch your X Server. For VcXsrv, 'Multiple windows' display setting is common."
echo "      Ensure 'Disable access control' is checked OR that your client IP is permitted if access control is enabled."
echo "   c. Configure your SSH Client (e.g., PuTTY, Windows Terminal with OpenSSH):"
echo "      - **PuTTY:**"
echo "        Connection -> SSH -> X11 -> Check 'Enable X11 forwarding'."
echo "        Set 'X display location' to: localhost:0.0"
echo "      - **OpenSSH (Windows Terminal/PowerShell/CMD):**"
echo "        Connect using: ssh -X your_user@$(hostname -I | awk '{print $1}')"
echo ""
echo "**4. Testing X11 Forwarding:**"
echo "   Once connected via SSH with X11 forwarding enabled, try running a graphical application from this server's terminal, e.g.:"
echo "     xclock"
echo "     xeyes"
echo "   A window for the application should appear on your client machine's desktop."
echo ""
echo "**5. Using xclip (Clipboard Integration):**"
echo "   `xclip` allows you to copy text from this server to your client's clipboard."
echo "   Example: Copy the content of a file to your client's clipboard:"
echo "     cat /path/to/your/file.txt | xclip -selection clipboard"
echo "   Then, you should be able to paste it on your client machine."
echo ""
echo "Troubleshooting:"
echo "  - Ensure your client's firewall is not blocking incoming X11 connections."
echo "  - Check SSH server logs on this machine for errors: sudo journalctl -u sshd"
echo "  - For PuTTY, check the PuTTY event log for X11-related messages."
echo "--------------------------------------------------------------------"
echo ""
_msg "Setup script finished."
