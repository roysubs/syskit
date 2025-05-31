#!/bin/bash
# Author: Roy Wiseman 2025-03

# Title: Comprehensive XRDP Setup & Troubleshooting Script
# Description: Installs XRDP, attempts to auto-configure for the current desktop environment,
#              sets up the firewall, and offers an optional troubleshooting section.

# --- Configuration ---
RDP_PORT="3389"
XSESSION_FILE="$HOME/.xsession"

# --- Helper Functions ---
_msg() {
    echo "INFO: $1"
}

_warn() {
    echo "WARN: $1"
}

_err() {
    echo "ERROR: $1" >&2
}

_cmd_exists() {
    command -v "$1" &>/dev/null
}

_is_pkg_installed() {
    dpkg -s "$1" &>/dev/null
}

# --- Desktop Environment Detection & Configuration ---

# List of DEs: "Name" "session_command" "core_package_for_dpkg_check" "pgrep_pattern"
# Order matters for pgrep fallback (more specific first if overlap)
# For dpkg, use a core package that indicates the DE is installed.
# For pgrep, use a reasonably unique process name for the session.
SUPPORTED_DESKTOP_ENVIRONMENTS=(
    "Cinnamon" "cinnamon-session" "cinnamon-core" "cinnamon-session"
    "MATE" "mate-session" "mate-desktop-environment-core" "mate-session"
    "GNOME" "gnome-session" "gnome-session" "gnome-session" # gnome-shell might also work for pgrep
    "KDE Plasma" "startplasma-x11" "plasma-desktop" "startplasma-x11" # or ksmserver
    "XFCE" "startxfce4" "xfce4-session" "xfce4-session"
    "LXQt" "startlxqt" "lxqt-core" "lxqt-session"
    "Unity" "unity" "unity-session" "unity-settings-daemon" # Unity process might be just 'unity' or related
    "Pantheon" "pantheon-session" "pantheon-session" "pantheon-agent" # or gala
    # Add more if needed
)

get_desktop_environment() {
    local detected_de=""

    _msg "Attempting to detect desktop environment..."

    # 1. Try XDG_CURRENT_DESKTOP
    if [[ -n "$XDG_CURRENT_DESKTOP" ]]; then
        # Handle colon-separated list, take the first one
        local xdg_de_raw="${XDG_CURRENT_DESKTOP%%:*}"
        _msg "XDG_CURRENT_DESKTOP found: $xdg_de_raw"
        for ((i=0; i<${#SUPPORTED_DESKTOP_ENVIRONMENTS[@]}; i+=4)); do
            if [[ "${SUPPORTED_DESKTOP_ENVIRONMENTS[i]}" == *"$xdg_de_raw"* || "$xdg_de_raw" == *"${SUPPORTED_DESKTOP_ENVIRONMENTS[i]}"* ]]; then
                detected_de="${SUPPORTED_DESKTOP_ENVIRONMENTS[i]}"
                _msg "Matched XDG_CURRENT_DESKTOP to: $detected_de"
                break
            fi
        done
    fi

    # 2. Try pgrep for running session processes (if not found by XDG)
    if [[ -z "$detected_de" ]]; then
        _msg "XDG_CURRENT_DESKTOP did not yield a match or was empty. Checking running processes..."
        for ((i=0; i<${#SUPPORTED_DESKTOP_ENVIRONMENTS[@]}; i+=4)); do
            local pgrep_pattern="${SUPPORTED_DESKTOP_ENVIRONMENTS[i+3]}"
            if pgrep -f "$pgrep_pattern" > /dev/null; then
                detected_de="${SUPPORTED_DESKTOP_ENVIRONMENTS[i]}"
                _msg "Detected running session process for: $detected_de (via pgrep -f '$pgrep_pattern')"
                break
            fi
        done
    fi

    # 3. Try dpkg for installed packages (if still not found)
    if [[ -z "$detected_de" ]]; then
        _msg "No running session process detected for known DEs. Checking installed packages..."
        for ((i=0; i<${#SUPPORTED_DESKTOP_ENVIRONMENTS[@]}; i+=4)); do
            local core_pkg="${SUPPORTED_DESKTOP_ENVIRONMENTS[i+2]}"
            if _is_pkg_installed "$core_pkg"; then
                detected_de="${SUPPORTED_DESKTOP_ENVIRONMENTS[i]}"
                _msg "Detected installed package for: $detected_de (via dpkg -s '$core_pkg')"
                break
            fi
        done
    fi

    if [[ -n "$detected_de" ]]; then
        echo "$detected_de"
    else
        _warn "Could not reliably detect a supported desktop environment."
        echo ""
    fi
}

get_session_command() {
    local de_name="$1"
    for ((i=0; i<${#SUPPORTED_DESKTOP_ENVIRONMENTS[@]}; i+=4)); do
        if [[ "${SUPPORTED_DESKTOP_ENVIRONMENTS[i]}" == "$de_name" ]]; then
            echo "${SUPPORTED_DESKTOP_ENVIRONMENTS[i+1]}"
            return
        fi
    done
    echo "" # Not found
}

display_desktop_info() {
    local de_name="$1"
    _msg "Selected Desktop Environment: $de_name"
    # (You can re-add the detailed descriptions from new2-xrdp1.sh here if desired)
}

configure_xsession() {
    local session_cmd="$1"
    if [[ -z "$session_cmd" ]]; then
        _err "No session command provided for .xsession configuration."
        return 1
    fi
    _msg "Configuring $XSESSION_FILE to start: $session_cmd"
    echo "$session_cmd" > "$XSESSION_FILE"
    chmod +x "$XSESSION_FILE"
    _msg "$XSESSION_FILE configured and made executable."

    # Advise on /etc/xrdp/startwm.sh if issues persist (for system-wide or other users)
    _msg "Note: This configures XRDP for the current user ($USER) via $XSESSION_FILE."
    _msg "If other users need XRDP or if issues occur, you might need to configure /etc/xrdp/startwm.sh."
    _msg "A common practice is to ensure /etc/xrdp/startwm.sh sources ~/.xsession if it exists:"
    _msg "Example line for /etc/xrdp/startwm.sh: [ -r \"\$HOME/.xsession\" ] && . \"\$HOME/.xsession\""
}

# --- Main Setup ---
run_setup() {
    _msg "Starting XRDP Installation and Configuration..."

    # 0. Root check
    if [ "$EUID" -ne 0 ]; then
      _err "This setup routine must be run as root or with sudo."
      exit 1
    fi

    # 1. Update package lists and install XRDP
    _msg "Updating package lists..."
    if ! sudo apt update; then
        _err "Failed to update package lists. Please check your network connection and repositories."
        # Decide if you want to exit or continue
    fi

    _msg "Installing XRDP..."
    if ! _is_pkg_installed "xrdp"; then
        if ! sudo apt install -y xrdp; then
            _err "Failed to install XRDP. Aborting setup."
            exit 1
        fi
        _msg "XRDP installed successfully."
    else
        _msg "XRDP is already installed."
    fi
    # Install dbus-x11 as it's often needed
    if ! _is_pkg_installed "dbus-x11"; then
        _msg "Installing dbus-x11 (often required for desktop environments over XRDP)..."
        sudo apt install -y dbus-x11
    fi


    # 2. Detect and configure Desktop Environment
    DETECTED_DE=$(get_desktop_environment)
    SESSION_COMMAND=""

    if [[ -n "$DETECTED_DE" ]]; then
        display_desktop_info "$DETECTED_DE"
        SESSION_COMMAND=$(get_session_command "$DETECTED_DE")
    else
        _warn "Could not auto-detect a desktop environment."
        read -p "Enter the session command for your DE (e.g., startxfce4, mate-session), or leave blank to skip .xsession config: " MANUAL_SESSION_CMD
        if [[ -n "$MANUAL_SESSION_CMD" ]]; then
            SESSION_COMMAND="$MANUAL_SESSION_CMD"
        else
            _warn "Skipping $XSESSION_FILE configuration. You may need to configure it manually or use /etc/xrdp/startwm.sh."
        fi
    fi

    if [[ -n "$SESSION_COMMAND" ]]; then
        # Configuration of .xsession is done by the user running the script, so no sudo here
        # Ensure user context for this part if script was elevated temporarily
        sudo -u "$SUDO_USER" bash -c "$(declare -f configure_xsession _msg _err); configure_xsession '$SESSION_COMMAND'" \
            || _warn "Could not configure $XSESSION_FILE as $SUDO_USER. Do it manually."
    fi

    # 3. Configure Firewall
    _msg "Configuring firewall to allow RDP connections on port $RDP_PORT/tcp..."
    if _cmd_exists ufw; then
        if sudo ufw status | grep -qw active; then
            _msg "UFW is active. Allowing $RDP_PORT/tcp..."
            sudo ufw allow "$RDP_PORT/tcp"
            sudo ufw status verbose | grep "$RDP_PORT/tcp"
        else
            _warn "UFW is installed but not active. Consider enabling it with 'sudo ufw enable'."
        fi
    elif _cmd_exists firewall-cmd; then
        _msg "Firewalld detected. Ensuring RDP port $RDP_PORT/tcp is allowed..."
        if ! sudo firewall-cmd --query-port="$RDP_PORT/tcp" --permanent &>/dev/null; then
             sudo firewall-cmd --permanent --add-port="$RDP_PORT/tcp"
             sudo firewall-cmd --reload
             _msg "Port $RDP_PORT/tcp added to firewalld permanent rules and reloaded."
        else
            _msg "Port $RDP_PORT/tcp is already allowed in firewalld permanent rules."
        fi
    else
        _warn "No UFW or Firewalld found. Please configure your firewall manually for port $RDP_PORT/tcp if needed."
    fi

    # 4. Enable and Restart XRDP service
    _msg "Enabling and restarting XRDP service..."
    sudo systemctl enable xrdp
    sudo systemctl restart xrdp
    if sudo systemctl is-active --quiet xrdp; then
        _msg "XRDP service is active."
    else
        _err "XRDP service failed to start. Check status with 'sudo systemctl status xrdp'."
    fi

    # 5. Final Information
    echo
    _msg "XRDP Setup Summary:"
    _msg " - XRDP installed."
    _msg " - Attempted to configure $XSESSION_FILE for user $SUDO_USER with session: ${SESSION_COMMAND:-'Not configured'}"
    _msg " - Firewall rule for port $RDP_PORT/tcp hopefully applied."
    _msg " - XRDP service enabled and restarted."
    echo
    _msg "You should now be able to connect to this machine using an RDP client on port $RDP_PORT."
    _msg "Common clients: Remote Desktop Connection (Windows), Remmina (Linux)."
    _msg "If you encounter a blank screen or issues, consider the troubleshooting section of this script."
    echo
}

# --- Troubleshooting Section ---
run_troubleshooting() {
    _msg "Starting XRDP Troubleshooting (Interactive)..."
    CURRENT_USER_FOR_TROUBLESHOOTING="${SUDO_USER:-$USER}" # User who ran sudo or current user

    # Function to pause for user confirmation
    _ask_to_run_step() {
        local step_description="$1"
        local step_command="$2"
        echo
        read -p "TROUBLESHOOT: $step_description (y/n)? " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            eval "$step_command" # Use with caution, ensure commands are safe
            return 0
        else
            _msg "Skipping step."
            return 1
        fi
    }

    _ask_to_run_step "Check D-Bus service status and attempt restart if inactive." "
        sudo systemctl status dbus --no-pager
        if ! sudo systemctl is-active --quiet dbus; then
            _warn 'D-Bus is not active. Attempting to start and enable...'
            sudo systemctl start dbus && sudo systemctl enable dbus && _msg 'D-Bus started/enabled.' || _err 'Failed to start D-Bus.'
        else
            _msg 'D-Bus service is active.'
        fi
    "

    _ask_to_run_step "Restart XRDP service." "
        _msg 'Restarting XRDP service...'
        sudo systemctl restart xrdp && _msg 'XRDP restarted.' || _err 'Failed to restart XRDP.'
        sudo systemctl status xrdp --no-pager
    "

    _ask_to_run_step "Verify/recreate $HOME/.xsession for user $CURRENT_USER_FOR_TROUBLESHOOTING." "
        DETECTED_DE_TROUBLESHOOT=\$(get_desktop_environment) # Run detection again
        SESSION_COMMAND_TROUBLESHOOT=''
        if [[ -n \"\$DETECTED_DE_TROUBLESHOOT\" ]]; then
            _msg \"Detected DE for troubleshooting: \$DETECTED_DE_TROUBLESHOOT\"
            SESSION_COMMAND_TROUBLESHOOT=\$(get_session_command \"\$DETECTED_DE_TROUBLESHOOT\")
        else
            read -p \"Could not detect DE. Enter session command for $CURRENT_USER_FOR_TROUBLESHOOTING (e.g., startxfce4): \" SESSION_COMMAND_TROUBLESHOOT
        fi

        if [[ -n \"\$SESSION_COMMAND_TROUBLESHOOT\" ]]; then
            _msg \"Attempting to configure $XSESSION_FILE for $CURRENT_USER_FOR_TROUBLESHOOTING with: \$SESSION_COMMAND_TROUBLESHOOT\"
            sudo -u \"$CURRENT_USER_FOR_TROUBLESHOOTING\" bash -c \
                \"echo '\$SESSION_COMMAND_TROUBLESHOOT' > \\\"\$HOME/.xsession\\\"; chmod +x \\\"\$HOME/.xsession\\\"; echo '$XSESSION_FILE configured.'\" \
                || _warn \"Failed to configure $XSESSION_FILE for $CURRENT_USER_FOR_TROUBLESHOOTING.\"
            _msg \"Contents of $CURRENT_USER_FOR_TROUBLESHOOTING's $XSESSION_FILE:\"
            sudo -u \"$CURRENT_USER_FOR_TROUBLESHOOTING\" cat \"\$HOME/.xsession\"
        else
            _warn \"No session command determined. Skipping .xsession check for $CURRENT_USER_FOR_TROUBLESHOOTING.\"
        fi
    "
    # Note: The above uses sudo -u to act as the user. This is safer.
    # declare -f wasn't working well with sudo -u bash -c for complex functions directly.

    _ask_to_run_step "Inspect /etc/xrdp/xrdp.ini for port and basic settings." "
        _msg 'Contents of /etc/xrdp/xrdp.ini (look for [Globals] port, security_layer, etc.):'
        sudo cat /etc/xrdp/xrdp.ini | grep -E -i 'port=|security_layer=|use_vsock=|crypt_level=|\[Globals\]|\[Logging\]|\[Channels\]' --color=always | less -R
        _msg \"Ensure 'port=' matches $RDP_PORT or your intended port.\"
    "

    _ask_to_run_step "Inspect /etc/xrdp/sesman.ini for session manager settings." "
        _msg 'Contents of /etc/xrdp/sesman.ini (look for session allocation, X11 server settings, etc.):'
        sudo cat /etc/xrdp/sesman.ini | grep -vE '^\s*#|^\s*$' --color=always | less -R
    "
    
    _ask_to_run_step "Inspect /etc/xrdp/startwm.sh script (system-wide session starter)." "
        _msg 'Contents of /etc/xrdp/startwm.sh:'
        _msg 'This script is run if ~/.xsession is not found or not executable.'
        _msg 'It should typically try to start your desired window manager or source ~/.xsession.'
        sudo cat /etc/xrdp/startwm.sh | less -R
    "

    _ask_to_run_step "View recent XRDP session manager logs (xrdp-sesman)." "
        _msg 'Last 20 lines of xrdp-sesman service log:'
        sudo journalctl -u xrdp-sesman --no-pager -n 20
    "

    _ask_to_run_step "View recent XRDP main service logs (xrdp)." "
        _msg 'Last 20 lines of xrdp service log:'
        sudo journalctl -u xrdp --no-pager -n 20
    "

    _ask_to_run_step "Check for common PolicyKit issues (manual step)." "
        _msg 'Modern Desktop Environments often require PolicyKit rules for XRDP sessions to function fully (e.g., for mounting drives, network management, color management).'
        _msg 'If you see authentication errors or missing functionality, search online for 'xrdp policikit <Your_DE_Name>'.'
        _msg 'Example: For XFCE, you might need rules in /etc/polkit-1/rules.d/ like 45-allow-colord.rules or similar.'
        _msg 'This step is for awareness; specific rules depend on your DE and distribution.'
    "

    _ask_to_run_step "Ensure all relevant packages are installed (for detected or chosen DE)." "
        # This is complex to make fully generic. We'll check xrdp and dbus-x11.
        # For the DE itself, the user should ensure it's fully installed.
        _msg 'Checking core XRDP packages...'
        for pkg_check in xrdp dbus-x11; do
            if _is_pkg_installed \"\$pkg_check\"; then
                _msg \"Package '\$pkg_check' is installed.\"
            else
                _warn \"Package '\$pkg_check' is NOT installed. Consider installing it: sudo apt install \$pkg_check\"
            fi
        done
        _msg 'Also ensure your chosen Desktop Environment (e.g., xfce4, mate-desktop-environment) is fully installed.'
    "

    _ask_to_run_step "Consider creating a new test user to isolate profile issues." "
        _msg 'If XRDP works for a brand new user but not your existing user, the issue is likely in your user profile (e.g., .xsession, .profile, DE configs).'
        read -p 'Enter username for a new temporary test user (or leave blank to skip): ' new_test_user
        if [[ -n \"\$new_test_user\" ]]; then
            sudo adduser \"\$new_test_user\" && _msg \"User '\$new_test_user' created. Try logging in as them via XRDP. Remember to configure their ~/.xsession or ensure /etc/xrdp/startwm.sh is generic.\" || _err \"Failed to create user '\$new_test_user'.\"
        fi
    "
    _msg "Troubleshooting steps finished. Review any output above for clues."
}


# --- Main Script Logic ---
if [[ "$1" == "--troubleshoot" || "$1" == "troubleshoot" ]]; then
    if [ "$EUID" -ne 0 ]; then # Troubleshooting might need sudo for commands
      _warn "Running troubleshooting. Some steps might require sudo privileges."
      # Allow to continue, steps will use sudo internally where needed
    fi
    run_troubleshooting
elif [[ "$1" == "--setup" || "$1" == "setup" || -z "$1" ]]; then
    run_setup
else
    echo "Usage: $0 [setup|--setup|troubleshoot|--troubleshoot]"
    echo "  setup (default): Runs the XRDP installation and initial configuration."
    echo "  troubleshoot:    Runs interactive troubleshooting steps for XRDP."
    exit 1
fi

exit 0
