#!/bin/bash
# Author: Roy Wiseman, Enhanced by Gemini AI
# Date: 2025-06-02
# Description: Interactive script to install and configure TightVNC server
#              with a user-selectable desktop environment on Debian-based systems.

# --- Configuration & Global Variables ---
SCRIPT_NAME=$(basename "$0")
USER_HOME=$(eval echo ~"$USER") # Reliable way to get user's home directory
VNC_DIR="$USER_HOME/.vnc"
PASSWORD_FILE="$VNC_DIR/${SCRIPT_NAME%.sh}-passwords.txt" # Plaintext password storage
LOG_FILE="$VNC_DIR/${SCRIPT_NAME%.sh}-$(date +'%Y-%m-%d_%H-%M-%S').log"

VNC_DISPLAY=":1"
VNC_GEOMETRY="1280x800" # Common default, can be changed by user later
VNC_DEPTH="24"         # 16 or 24 are common

# ANSI Color Codes
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'

C_TITLE="${C_BOLD}${C_BLUE}"
C_CMD="${C_GREEN}"
C_INFO="${C_CYAN}"
C_WARN="${C_BOLD}${C_YELLOW}"
C_ERR="${C_BOLD}${C_RED}"
C_INPUT="${C_BOLD}${C_MAGENTA}"

# --- Helper Functions ---
log() {
    # Appends to log file. Avoids using echo -e here if $1 might contain %
    printf "%s - %s\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
    echo -e "$1" # Still use echo -e for console output to interpret colors
}

is_pkg_installed() {
    # Returns 0 if package is installed and configured, 1 otherwise
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

print_title() { log "${C_TITLE}=== $1 ===${C_RESET}"; }
print_info() { log "${C_INFO}$1${C_RESET}"; }
print_warn() { log "${C_WARN}WARN: $1${C_RESET}"; }
print_error() { log "${C_ERR}ERROR: $1${C_RESET}"; }
print_cmd() { log "${C_CMD}\$ $1${C_RESET}"; } # For displaying commands to be run

# --- Initial Setup ---
mkdir -p "$VNC_DIR"
# Initialize log file and set permissions
# (printf used above will create/append)
chmod 600 "$LOG_FILE" &>/dev/null # Mute chmod error if file just created by printf

# --- Script Start ---
print_title "VNC Server Setup Script (TightVNC)"
print_info "This script will guide you through installing and configuring TightVNC server."
print_info "A detailed log of this session is being saved to: $LOG_FILE"
echo # Newline for readability

# --- Sudo Check ---
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. It uses 'sudo' for privileged commands."
   exit 1
fi
if ! sudo -v; then # Check if sudo credentials are valid / prompt if needed
    print_error "Sudo credentials check failed. Please ensure you can run sudo."
    exit 1
fi
echo # Newline

# --- Step 1: System Prerequisite Checks ---
print_title "Step 1: System Prerequisite Checks"

# 1.1 Check for X Window System / Desktop Environment Components
print_info "Checking for existing X Window System or Desktop Environment components..."
x_env_found=false
if is_pkg_installed "xserver-xorg-core"; then
    print_info "Package 'xserver-xorg-core' is installed."
    x_env_found=true
elif [ -f /usr/bin/Xorg ]; then
    print_info "File '/usr/bin/Xorg' (X server executable) found."
    x_env_found=true
else
    # If primary Xorg checks fail, check for common DE session managers
    if is_pkg_installed "xfce4-session"; then
        print_info "Package 'xfce4-session' is installed (indicates XFCE components are present)."
        x_env_found=true
    elif is_pkg_installed "mate-session-manager"; then
        print_info "Package 'mate-session-manager' is installed (indicates MATE components are present)."
        x_env_found=true
    elif is_pkg_installed "plasma-workspace"; then # KDE
        print_info "Package 'plasma-workspace' is installed (indicates KDE components are present)."
        x_env_found=true
    elif is_pkg_installed "gnome-session"; then # GNOME
        print_info "Package 'gnome-session' is installed (indicates GNOME components are present)."
        x_env_found=true
    # Add any other DE checks here if needed
    fi
fi

if $x_env_found; then
    print_info "An X Window System or components of a desktop environment appear to be installed."
    read -r -p "$(echo -e "${C_INPUT}Proceed with VNC server setup using an available/selected DE? (Y/n): ${C_RESET}")" confirm_vnc_setup
    confirm_vnc_setup="${confirm_vnc_setup:-Y}" # Default to Yes
    if [[ ! "$confirm_vnc_setup" =~ ^[Yy]$ ]]; then
        print_error "Aborting: VNC server setup declined."
        exit 1
    fi
else
    print_warn "A standard X Window System (Xorg) or common desktop environment components do not appear to be installed according to dpkg."
    print_warn "Installing a graphical desktop environment for VNC might require significant downloads."
    read -r -p "$(echo -e "${C_INPUT}Proceed with installing Xorg components (if needed by selected DE) and a desktop environment? (y/N): ${C_RESET}")" confirm_xorg_de_install
    confirm_xorg_de_install="${confirm_xorg_de_install:-N}" # Default to No
    if [[ ! "$confirm_xorg_de_install" =~ ^[Yy]$ ]]; then
        print_error "Aborting: Xorg/DE installation declined."
        exit 1
    fi
fi
echo # Newline

# 1.2 Define Available Desktop Environments/Window Managers
# Format: "Name;Package(s);Startup Command;Resource Level"
declare -a DESKTOP_ENVIRONMENTS=(
    "XFCE;task-xfce-desktop xfce4-goodies;startxfce4;Lightweight"
    "MATE;task-mate-desktop;mate-session;Medium"
    "LXQt;task-lxqt-desktop;startlxqt;Lightweight"
    "LXDE;task-lxde-desktop;startlxde;Lightweight (older, LXQt often preferred)"
    "Openbox;openbox obconf menumaker;openbox-session;Very Lightweight (minimal, requires manual menu setup)"
    "Fluxbox;fluxbox;startfluxbox;Very Lightweight (minimal)"
    "IceWM;icewm;icewm-session;Very Lightweight (minimal)"
    # Add other DEs like GNOME/KDE if desired, but they can be heavier and more complex for VNC
)

print_info "Available Desktop Environments/Window Managers for VNC:"
DEFAULT_DE_CHOICE=""
TEMP_DE_LIST=() # For storing display lines

for i in "${!DESKTOP_ENVIRONMENTS[@]}"; do
    IFS=';' read -r name packages command resource <<< "${DESKTOP_ENVIRONMENTS[$i]}"
    status_msg=""
    primary_package=$(echo "$packages" | cut -d' ' -f1) # Check based on the task or main package
    if dpkg -s "$primary_package" >/dev/null 2>&1; then
        status_msg="${C_GREEN}[INSTALLED]${C_RESET}"
        # Auto-select if current desktop matches (simple check)
        if [ -n "$XDG_CURRENT_DESKTOP" ]; then
            if [[ "$XDG_CURRENT_DESKTOP" == *"$name"* ]] || \
               [[ "$XDG_CURRENT_DESKTOP" == *"XFCE"* && "$name" == "XFCE" ]] || \
               [[ "$XDG_CURRENT_DESKTOP" == *"MATE"* && "$name" == "MATE" ]]; then
                DEFAULT_DE_CHOICE=$((i+1))
            fi
        fi
    fi
    TEMP_DE_LIST+=("$(echo -e "${C_INFO}$((i+1)). $name ($resource) $status_msg${C_RESET}")")
done

# If no auto-selection, try to default to installed XFCE if present
if [ -z "$DEFAULT_DE_CHOICE" ]; then
    for i in "${!DESKTOP_ENVIRONMENTS[@]}"; do
        IFS=';' read -r name packages _ _ <<< "${DESKTOP_ENVIRONMENTS[$i]}"
        primary_package=$(echo "$packages" | cut -d' ' -f1)
        if [[ "$name" == "XFCE" ]] && dpkg -s "$primary_package" >/dev/null 2>&1; then
            DEFAULT_DE_CHOICE=$((i+1))
            break
        fi
    done
fi

# Print the constructed list
for line in "${TEMP_DE_LIST[@]}"; do echo -e "$line"; done

SELECTED_DE_INDEX=""
while true; do
    prompt_msg="${C_INPUT}Select the Desktop Environment for VNC (enter number"
    [ -n "$DEFAULT_DE_CHOICE" ] && prompt_msg+=", default $DEFAULT_DE_CHOICE"
    prompt_msg+="): ${C_RESET}"
    read -r -p "$(echo -e "$prompt_msg")" choice
    choice="${choice:-$DEFAULT_DE_CHOICE}" # Use default if input is empty

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#DESKTOP_ENVIRONMENTS[@]}" ]; then
        SELECTED_DE_INDEX=$((choice-1))
        break
    else
        print_warn "Invalid selection. Please enter a number from the list."
    fi
done

IFS=';' read -r SELECTED_DE_NAME SELECTED_DE_PACKAGES SELECTED_DE_CMD RESOURCE_LEVEL <<< "${DESKTOP_ENVIRONMENTS[$SELECTED_DE_INDEX]}"
print_info "You selected: ${C_BOLD}$SELECTED_DE_NAME${C_RESET}"
echo # Newline

PACKAGES_TO_INSTALL="tightvncserver expect dbus-x11" # Core VNC packages
NEEDS_DESKTOP_INSTALL=false
primary_selected_package=$(echo "$SELECTED_DE_PACKAGES" | cut -d' ' -f1)

if ! dpkg -s "$primary_selected_package" >/dev/null 2>&1; then
    print_warn "$SELECTED_DE_NAME is not currently installed. It will be added to the installation list."
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $SELECTED_DE_PACKAGES"
    NEEDS_DESKTOP_INSTALL=true
else
    print_info "$SELECTED_DE_NAME appears to be already installed."
    # If DE is installed, ensure 'expect' and 'dbus-x11' are also considered if somehow missing
    for pkg_check in expect dbus-x11; do
        if ! dpkg -s "$pkg_check" >/dev/null 2>&1; then
            PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $pkg_check"
        fi
    done
fi
echo # Newline

# --- Step 2: System Update and Package Installation ---
print_title "Step 2: System Update and Package Installation"
print_info "The following packages will be installed/ensured: ${C_BOLD}$PACKAGES_TO_INSTALL${C_RESET}"
read -r -p "$(echo -e "${C_INPUT}Proceed with system update and package installation? (Y/n): ${C_RESET}")" confirm_install
if [[ "$confirm_install" =~ ^[Nn]$ ]]; then
    print_error "Aborting: Package installation declined."
    exit 1
fi

print_cmd "sudo apt update"
sudo apt update 2>&1 | tee -a "$LOG_FILE" # Log stderr too
print_warn "During updates/installs, you might see 'W: Possible missing firmware...' messages."
print_warn "These are generally non-critical for VNC. If they relate to your hardware (e.g., amdgpu, iwlwifi),"
print_warn "you can install relevant firmware packages later (e.g., 'firmware-amd-graphics', 'firmware-iwlwifi')."

print_cmd "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y"
if ! sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y 2>&1 | tee -a "$LOG_FILE"; then
    print_warn "apt upgrade encountered some issues. Check log. Continuing with package installation..."
    # Non-fatal for upgrade, proceed to install
fi

print_info "Installing packages. This may take some time. Configuration prompts will be handled with defaults."
print_cmd "sudo DEBIAN_FRONTEND=noninteractive apt install -y $PACKAGES_TO_INSTALL"
if sudo DEBIAN_FRONTEND=noninteractive apt install -y $PACKAGES_TO_INSTALL 2>&1 | tee -a "$LOG_FILE"; then
    print_info "${C_GREEN}Packages installed successfully.${C_RESET}"
else
    exit_status=$?
    print_error "Failed to install necessary packages (exit code: $exit_status)."
    print_error "Please review the output above and the detailed log: $LOG_FILE"
    print_error "This script uses DEBIAN_FRONTEND=noninteractive to attempt to avoid interactive prompts."
    print_error "If issues persist (e.g., broken packages, conflicts), manual intervention may be required."
    exit 1
fi
echo # Newline

# --- Step 3: VNC Password Setup ---
print_title "Step 3: VNC Password Setup"
VNC_PASSWORD=""
VIEW_ONLY_PASSWORD="" # Initialize as empty

while true; do
    read -s -r -p "$(echo -e "${C_INPUT}Enter VNC full access password (6-8 chars recommended for TightVNC): ${C_RESET}")" VNC_PASSWORD
    echo # Newline after password input
    if [ ${#VNC_PASSWORD} -lt 6 ] || [ ${#VNC_PASSWORD} -gt 8 ]; then
        print_warn "Password length is ideally 6-8 characters for TightVNC compatibility."
        # Allow user to proceed if they insist
    fi
    read -s -r -p "$(echo -e "${C_INPUT}Verify VNC full access password: ${C_RESET}")" VNC_PASSWORD_VERIFY
    echo
    if [ "$VNC_PASSWORD" == "$VNC_PASSWORD_VERIFY" ]; then
        break
    else
        print_warn "Passwords do not match. Please try again."
    fi
done

read -r -p "$(echo -e "${C_INPUT}Set up a view-only password? (y/N): ${C_RESET}")" setup_view_only
setup_view_only="${setup_view_only:-n}" # Default to 'n'
if [[ "$setup_view_only" =~ ^[Yy]$ ]]; then
    while true; do
        read -s -r -p "$(echo -e "${C_INPUT}Enter VNC view-only password (6-8 chars): ${C_RESET}")" VIEW_ONLY_PASSWORD
        echo
        if [ ${#VIEW_ONLY_PASSWORD} -lt 6 ] || [ ${#VIEW_ONLY_PASSWORD} -gt 8 ]; then
            print_warn "Password length is ideally 6-8 characters."
        fi
        read -s -r -p "$(echo -e "${C_INPUT}Verify VNC view-only password: ${C_RESET}")" VIEW_ONLY_PASSWORD_VERIFY
        echo
        if [ "$VIEW_ONLY_PASSWORD" == "$VIEW_ONLY_PASSWORD_VERIFY" ]; then
            break
        else
            print_warn "View-only passwords do not match. Please try again."
        fi
    done
fi

print_info "Setting VNC passwords using 'vncpasswd' utility..."
# Ensure .vnc directory exists (should already from script start, but good for vncpasswd)
mkdir -p "$VNC_DIR"

# Create a temporary expect script
# Ensure the EOF marker for the heredoc is on a line by itself, no leading/trailing spaces.
EXPECT_SCRIPT_CONTENT=$(cat <<EOF
#!/usr/bin/expect -f
set timeout 10
spawn vncpasswd
expect "Password:"
send "$VNC_PASSWORD\r"
expect "Verify:"
send "$VNC_PASSWORD\r"
expect "Would you like to enter a view-only password (y/n)?"
if {"$VIEW_ONLY_PASSWORD" != ""} {
    send "y\r"
    expect "Password:"
    send "$VIEW_ONLY_PASSWORD\r"
    expect "Verify:"
    send "$VIEW_ONLY_PASSWORD\r"
} else {
    send "n\r"
}
expect eof
EOF
) # Closing parenthesis for command substitution

# For logging, show expect script content without passwords
LOGGED_EXPECT_SCRIPT_CONTENT=$(echo "$EXPECT_SCRIPT_CONTENT" | sed "s/$VNC_PASSWORD/********/g" | sed "s/$VIEW_ONLY_PASSWORD/********/g")
print_cmd "Automated vncpasswd process (passwords redacted in log):"
echo "$LOGGED_EXPECT_SCRIPT_CONTENT" >> "$LOG_FILE" # Log the (redacted) script

# Execute the expect script
echo "$EXPECT_SCRIPT_CONTENT" | expect -f - >> "$LOG_FILE" 2>&1

# Optionally store passwords in a file (with strong warning)
print_warn "VNC passwords have been set."
read -r -p "$(echo -e "${C_INPUT}Store these passwords in plaintext in $PASSWORD_FILE? (y/N) (SECURITY RISK!): ${C_RESET}")" store_pass
if [[ "$store_pass" =~ ^[Yy]$ ]]; then
    echo "VNC Full Access Password: $VNC_PASSWORD" > "$PASSWORD_FILE"
    if [ -n "$VIEW_ONLY_PASSWORD" ]; then
        echo "VNC View-Only Password: $VIEW_ONLY_PASSWORD" >> "$PASSWORD_FILE"
    fi
    chmod 600 "$PASSWORD_FILE"
    print_info "Passwords stored in $PASSWORD_FILE (permissions set to 600)."
else
    print_info "Passwords not stored in plaintext file by user choice."
    # Clear the file if it existed and user chose not to store
    >"$PASSWORD_FILE" # Truncate file or remove if desired: rm -f "$PASSWORD_FILE"
fi
echo # Newline

# --- Step 4: Configure VNC Server Environment ---
print_title "Step 4: Configure VNC Server Environment"

# 4a. Ensuring VNC Display is Free
print_info "Ensuring VNC display $VNC_DISPLAY is free before configuring and starting..."
MAX_KILL_ATTEMPTS=3
attempt=0
killed_definitively=false

while [ $attempt -lt $MAX_KILL_ATTEMPTS ] && ! $killed_definitively; do
    attempt=$((attempt + 1))
    print_cmd "vncserver -kill $VNC_DISPLAY (attempt $attempt/$MAX_KILL_ATTEMPTS)"
    VNC_KILL_OUTPUT=$(vncserver -kill "$VNC_DISPLAY" 2>&1) # Capture output
    echo "Kill attempt $attempt output for $VNC_DISPLAY: $VNC_KILL_OUTPUT" >> "$LOG_FILE"

    if echo "$VNC_KILL_OUTPUT" | grep -q -E "Killing Xtightvnc process|process is successfully killed"; then
        print_info "Existing VNC server on $VNC_DISPLAY reported killed by 'vncserver -kill'."
        killed_definitively=true
    elif echo "$VNC_KILL_OUTPUT" | grep -q -E "no process running|Can't find file.*${VNC_DISPLAY}\.pid|No server running"; then
        print_info "No VNC server was reported running on $VNC_DISPLAY by 'vncserver -kill'."
        killed_definitively=true # Display is considered free
    else
        print_warn "Kill attempt $attempt for $VNC_DISPLAY was inconclusive or failed. Output: $VNC_KILL_OUTPUT"
        if [ $attempt -lt $MAX_KILL_ATTEMPTS ]; then
            sleep 2
        fi
    fi
done

if ! $killed_definitively; then
    print_warn "'vncserver -kill $VNC_DISPLAY' was not definitively successful after $MAX_KILL_ATTEMPTS attempts."
    print_warn "You may need to manually kill lingering Xtightvnc processes for display $VNC_DISPLAY."
fi

VNC_HOSTNAME_FOR_FILES=$(hostname) # Get hostname for PID/log file names
print_info "Cleaning up potential stale VNC PID file for display $VNC_DISPLAY..."
rm -f "$VNC_DIR/${VNC_HOSTNAME_FOR_FILES}${VNC_DISPLAY}.pid"
# Also remove the socket file if it exists (for TightVNC, Xorg-based VNC)
rm -f "/tmp/.X11-unix/X${VNC_DISPLAY#:}"
rm -f "/tmp/.X${VNC_DISPLAY#:}-lock"

sleep 1 # Brief pause to ensure resources are freed.

# 4b. Configure ~/.vnc/xstartup
print_info "Configuring VNC startup script: $VNC_DIR/xstartup"
XSTARTUP_FILE="$VNC_DIR/xstartup"

if [ -f "$XSTARTUP_FILE" ]; then
    BACKUP_XSTARTUP="$XSTARTUP_FILE-$(date +'%Y-%m-%d_%H-%M-%S').bak"
    print_info "Backing up existing $XSTARTUP_FILE to $BACKUP_XSTARTUP"
    cp "$XSTARTUP_FILE" "$BACKUP_XSTARTUP"
fi

# Ensure the EOF marker for the heredoc is on a line by itself, no leading/trailing spaces.
# And ensure the closing parenthesis for the command substitution $() is correctly placed.
XSTARTUP_CONTENT=$(cat <<EOF
#!/bin/sh
# This file is automatically generated by $SCRIPT_NAME

# Disable DPMS (Energy Star) features and screen saver for VNC session
xset s off -dpms >/dev/null 2>&1

# Unset session variables that might interfere with VNC'd desktop
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Load X resources if they exist
if [ -r "\$HOME/.Xresources" ]; then
    xrdb "\$HOME/.Xresources"
fi

# Start the selected Desktop Environment / Window Manager
# For $SELECTED_DE_NAME:
exec $SELECTED_DE_CMD
EOF
) # Closing parenthesis for XSTARTUP_CONTENT=$(cat <<EOF...)

print_info "The following content will be written to $XSTARTUP_FILE:"
echo -e "${C_CMD}--- xstartup content ---${C_RESET}"
echo "$XSTARTUP_CONTENT" | sed 's/^/   /' # Indent for display
echo -e "${C_CMD}--- end xstartup content ---${C_RESET}"
# Log the actual content to the log file for debugging
echo "Writing to $XSTARTUP_FILE:" >> "$LOG_FILE"
echo "$XSTARTUP_CONTENT" >> "$LOG_FILE"
echo "--- End of xstartup content in log ---" >> "$LOG_FILE"

echo "$XSTARTUP_CONTENT" > "$XSTARTUP_FILE"
chmod +x "$XSTARTUP_FILE"
print_info "$XSTARTUP_FILE configured and made executable."
echo # Newline

# --- Step 5: Start VNC Server ---
print_title "Step 5: Start VNC Server"
print_info "Attempting to start VNC server on display $VNC_DISPLAY with geometry $VNC_GEOMETRY and depth $VNC_DEPTH..."
print_cmd "vncserver $VNC_DISPLAY -geometry $VNC_GEOMETRY -depth $VNC_DEPTH -localhost no"
# -localhost no allows connections from other machines. For only local access (e.g. SSH tunnel), use -localhost yes or omit.

VNC_START_OUTPUT=$(vncserver "$VNC_DISPLAY" -geometry "$VNC_GEOMETRY" -depth "$VNC_DEPTH" -localhost no 2>&1)
echo "VNC Start Output: $VNC_START_OUTPUT" >> "$LOG_FILE" # Log the raw output

VNC_SERVER_LOG_FILE_GUESS="$VNC_DIR/${VNC_HOSTNAME_FOR_FILES}${VNC_DISPLAY}.log"

if echo "$VNC_START_OUTPUT" | grep -q "New 'X' desktop is"; then
    print_info "${C_GREEN}VNC server started successfully!${C_RESET}"
    echo -e "${C_GREEN}$(echo "$VNC_START_OUTPUT" | grep -E "New 'X' desktop is|Log file is")${C_RESET}"
    VNC_SERVER_LOG_FILE_REPORTED=$(echo "$VNC_START_OUTPUT" | grep "Log file is" | awk '{print $NF}')
    [ -n "$VNC_SERVER_LOG_FILE_REPORTED" ] && VNC_SERVER_LOG_FILE_GUESS="$VNC_SERVER_LOG_FILE_REPORTED"
elif echo "$VNC_START_OUTPUT" | grep -q -E "A VNC server is already running|Fatal server error.*Cannot establish any listening sockets"; then
    print_error "VNC server reported it is ALREADY RUNNING on $VNC_DISPLAY or cannot listen (port possibly in use)."
    print_error "This occurred even after attempts to kill and clean up. Output: $VNC_START_OUTPUT"
    print_error "Please check manually: ${C_CMD}ps aux | grep -Ei 'vnc|Xtightvnc'${C_RESET} and ${C_CMD}ss -tulnp | grep 590${VNC_DISPLAY#:}${C_RESET}"
    print_error "Also review VNC server log: ${C_BOLD}$VNC_SERVER_LOG_FILE_GUESS${C_RESET}"
else
    print_error "VNC server may not have started correctly. Output: $VNC_START_OUTPUT"
    print_error "Review this script's log: ${C_BOLD}$LOG_FILE${C_RESET}"
    print_error "And the VNC server's own log (if created): ${C_BOLD}$VNC_SERVER_LOG_FILE_GUESS${C_RESET}"
fi
echo # Newline

# --- Step 6: Firewall Configuration (UFW) ---
print_title "Step 6: Firewall Configuration (UFW)"
VNC_PORT_NUMBER=$((5900 + ${VNC_DISPLAY#:}) # Calculate port from display number, e.g., :1 -> 5901

if command -v ufw &> /dev/null; then
    print_info "UFW firewall manager is detected."
    if sudo ufw status | grep -qw active; then
        print_cmd "sudo ufw allow $VNC_PORT_NUMBER/tcp comment \"VNC for display $VNC_DISPLAY\""
        sudo ufw allow "$VNC_PORT_NUMBER/tcp" comment "VNC for display $VNC_DISPLAY" 2>&1 | tee -a "$LOG_FILE"
        print_info "UFW rule added for port $VNC_PORT_NUMBER/tcp. You may need to reload UFW if it was already active."
        print_cmd "sudo ufw reload # (If UFW was already active and you want to apply changes now)"
    else
        print_warn "UFW is installed but not active. Rule for $VNC_PORT_NUMBER/tcp added, but UFW needs to be enabled."
        print_cmd "sudo ufw allow $VNC_PORT_NUMBER/tcp comment \"VNC for display $VNC_DISPLAY\""
        sudo ufw allow "$VNC_PORT_NUMBER/tcp" comment "VNC for display $VNC_DISPLAY" 2>&1 | tee -a "$LOG_FILE" # Add rule anyway
        print_info "To enable UFW (will deny other incoming traffic by default): ${C_CMD}sudo ufw enable${C_RESET}"
    fi
else
    print_warn "UFW firewall manager not found. Skipping automatic firewall configuration."
    print_warn "If you use another firewall (e.g., firewalld), please ensure port $VNC_PORT_NUMBER/tcp is open."
fi
echo # Newline

# --- Step 7: Final Information ---
print_title "Step 7: VNC Setup Complete - Information"
SERVER_HOSTNAME=$(hostname)
SERVER_IP=$(hostname -I | awk '{print $1}') # Gets the first IP address

print_info "${C_GREEN}VNC server setup process is complete!${C_RESET}"
print_info "You should now be able to connect using a VNC client."
echo -e "${C_INFO}Connection Details:${C_RESET}"
echo -e "${C_INFO}  Desktop Environment: ${C_BOLD}$SELECTED_DE_NAME${C_RESET}"
echo -e "${C_INFO}  VNC Display:         ${C_BOLD}${VNC_DISPLAY}${C_RESET}"
echo -e "${C_INFO}  Connect to:          ${C_BOLD}${SERVER_HOSTNAME}${VNC_DISPLAY}${C_RESET} (e.g., ${SERVER_HOSTNAME}:1)"
echo -e "${C_INFO}  Or by IP:            ${C_BOLD}${SERVER_IP}${VNC_DISPLAY}${C_RESET} (e.g., ${SERVER_IP}:1)"
print_info "(Note: VNC clients typically use the 'server:display' format, like '${SERVER_IP}:1'. Some might support 'server::port' like '${SERVER_IP}::${VNC_PORT_NUMBER}'.)"

echo -e "\n${C_INFO}Passwords:${C_RESET}"
echo -e "${C_INFO}  Full Access:     (You set this during the script)"
if [ -n "$VIEW_ONLY_PASSWORD" ]; then
    echo -e "${C_INFO}  View-Only Access: (You set this during the script)"
fi
if [ -f "$PASSWORD_FILE" ] && grep -q "Password" "$PASSWORD_FILE"; then
    echo -e "${C_INFO}  Passwords were also saved to: $PASSWORD_FILE (if you chose to)"
fi

echo -e "\n${C_INFO}Managing the VNC Server:${C_RESET}"
echo -e "${C_INFO}  To STOP the VNC server on display $VNC_DISPLAY: ${C_CMD}vncserver -kill $VNC_DISPLAY${C_RESET}"
echo -e "${C_INFO}  To START it again (using current settings): ${C_CMD}vncserver $VNC_DISPLAY -geometry $VNC_GEOMETRY -depth $VNC_DEPTH -localhost no${C_RESET}"
echo -e "${C_INFO}  To list all running VNC servers for you: ${C_CMD}vncserver -list${C_RESET}"
echo -e "${C_INFO}  To see listening VNC ports (TCP):       ${C_CMD}ss -tulnp | grep -E 'Xtightvnc|${VNC_PORT_NUMBER}'${C_RESET}"

echo -e "\n${C_INFO}Customizing VNC Session:${C_RESET}"
echo -e "${C_INFO}  The VNC startup script is: ${C_BOLD}$XSTARTUP_FILE${C_RESET}"
echo -e "${C_INFO}  Color Depth: Set to ${C_BOLD}$VNC_DEPTH-bit${C_RESET}. Change with ${C_CMD}-depth <8|16|24|32>${C_RESET} on server start."
echo -e "${C_INFO}  Geometry (Resolution): Set to ${C_BOLD}$VNC_GEOMETRY${C_RESET}. Change with ${C_CMD}-geometry <WxH>${C_RESET} on server start."

echo -e "\n${C_INFO}Troubleshooting:${C_RESET}"
echo -e "${C_INFO}  This script's detailed log: ${C_BOLD}$LOG_FILE${C_RESET}"
if [ -n "$VNC_SERVER_LOG_FILE_GUESS" ] && [ -f "$VNC_SERVER_LOG_FILE_GUESS" ]; then
    echo -e "${C_INFO}  VNC server's own log:     ${C_BOLD}$VNC_SERVER_LOG_FILE_GUESS${C_RESET}"
else
    echo -e "${C_INFO}  VNC server's own log is typically at: ${C_BOLD}$VNC_DIR/${VNC_HOSTNAME_FOR_FILES}${VNC_DISPLAY}.log${C_RESET}"
fi
echo -e "${C_INFO}  Check these logs if you encounter connection or display issues."

if $NEEDS_DESKTOP_INSTALL; then
    print_warn "A new desktop environment ($SELECTED_DE_NAME) was installed."
    print_warn "A system reboot might be beneficial to ensure all services are correctly started, but is not always strictly necessary."
fi

print_title "Setup Finished!"
