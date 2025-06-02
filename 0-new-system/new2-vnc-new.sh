#!/bin/bash
# Author: Roy Wiseman, Enhanced by Gemini AI 2025-06
# Description: Interactive script to install and configure TightVNC server
#              with a user-selectable desktop environment.

# --- Configuration & Color Definitions ---
SCRIPT_NAME=$(basename "$0")
USER_HOME=$(eval echo ~"$USER") # More reliable way to get home dir
VNC_DIR="$USER_HOME/.vnc"
PASSWORD_FILE="$VNC_DIR/${SCRIPT_NAME%.sh}-passwords.txt"
LOG_FILE="$VNC_DIR/${SCRIPT_NAME%.sh}-$(date +'%Y-%m-%d_%H-%M-%S').log"

# ANSI Color Codes
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'
C_WHITE='\033[0;37m'

C_TITLE="${C_BOLD}${C_BLUE}"
C_CMD="${C_GREEN}"
C_INFO="${C_CYAN}"
C_WARN="${C_BOLD}${C_YELLOW}"
C_ERR="${C_BOLD}${C_RED}"
C_INPUT="${C_BOLD}${C_MAGENTA}"

# --- Helper Functions ---
log() {
    echo -e "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

print_title() {
    log "${C_TITLE}=== $1 ===${C_RESET}"
}

print_info() {
    log "${C_INFO}$1${C_RESET}"
}

print_warn() {
    log "${C_WARN}WARN: $1${C_RESET}"
}

print_error() {
    log "${C_ERR}ERROR: $1${C_RESET}"
}

print_cmd() {
    log "${C_CMD}\$ $1${C_RESET}"
}

# --- Ensure .vnc directory exists ---
mkdir -p "$VNC_DIR"
touch "$LOG_FILE" # Initialize log file
chmod 600 "$LOG_FILE"

# --- Script Start ---
print_title "VNC Server Setup Script"
print_info "This script will guide you through installing and configuring TightVNC server."
print_info "Log file for this session: $LOG_FILE"

# --- Check for Sudo ---
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. It will use 'sudo' when necessary."
   exit 1
fi

# --- System Prerequisite Checks ---
print_title "Step 1: System Prerequisite Checks"

# 1.1 Check for X Window System
print_info "Checking for existing X Window System installation..."
if dpkg -s xserver-xorg-core >/dev/null 2>&1 || [ -f /usr/bin/Xorg ]; then
    print_info "X Window System (Xorg) appears to be installed."
else
    print_warn "X Window System (Xorg) does not appear to be installed."
    print_warn "Installing a graphical desktop environment for VNC will require a significant download."
    read -r -p "$(echo -e "${C_INPUT}Do you want to proceed with installing Xorg and a desktop environment? (y/N): ${C_RESET}")" confirm_xorg
    if [[ ! "$confirm_xorg" =~ ^[Yy]$ ]]; then
        print_error "Aborting script as Xorg installation was declined."
        exit 1
    fi
fi

# 1.2 Define Available Desktop Environments/Window Managers
# Format: "Name;Package(s);Startup Command;Resource Level"
declare -a DESKTOP_ENVIRONMENTS=(
    "XFCE;task-xfce-desktop xfce4-goodies;startxfce4;Lightweight"
    "MATE;task-mate-desktop;mate-session;Medium"
    "LXQt;task-lxqt-desktop;startlxqt;Lightweight"
    "LXDE;task-lxde-desktop;startlxde;Lightweight (older, LXQt is preferred)"
    "Openbox;openbox obconf menumaker;openbox-session;Very Lightweight (minimal)"
    "Fluxbox;fluxbox;startfluxbox;Very Lightweight (minimal)"
    "IceWM;icewm;icewm-session;Very Lightweight (minimal)"
    # "GNOME;task-gnome-desktop;gnome-session;Heavyweight" # Often requires more setup for VNC
    # "KDE Plasma;task-kde-desktop;startplasma-x11;Heavyweight" # Often requires more setup for VNC
)

print_info "Checking currently installed desktop environments..."
echo -e "${C_INFO}Available Desktop Environments/Window Managers for VNC:${C_RESET}"
INSTALLED_DE_CMD=""
DEFAULT_DE_CHOICE=""

for i in "${!DESKTOP_ENVIRONMENTS[@]}"; do
    IFS=';' read -r name packages command resource <<< "${DESKTOP_ENVIRONMENTS[$i]}"
    status_msg=""
    # Check if primary package is installed (first in list)
    primary_package=$(echo "$packages" | cut -d' ' -f1)
    if dpkg -s "$primary_package" >/dev/null 2>&1; then
        status_msg="${C_GREEN}[CURRENTLY INSTALLED]${C_RESET}"
        # Simple logic: if user has XFCE and script detects it, make it default choice
        if [ -n "$XDG_CURRENT_DESKTOP" ] && [[ "$XDG_CURRENT_DESKTOP" == *"XFCE"* ]] && [[ "$name" == "XFCE" ]]; then
            DEFAULT_DE_CHOICE=$((i+1))
        elif [ -n "$XDG_CURRENT_DESKTOP" ] && [[ "$XDG_CURRENT_DESKTOP" == *"MATE"* ]] && [[ "$name" == "MATE" ]]; then
            DEFAULT_DE_CHOICE=$((i+1))
        fi
    fi
    echo -e "${C_INFO}$((i+1)). $name ($resource) $status_msg${C_RESET}"
done

if [ -z "$DEFAULT_DE_CHOICE" ] && dpkg -s xfce4-session >/dev/null 2>&1; then
    # If XFCE is installed but not the current desktop, find its index for default
    for i in "${!DESKTOP_ENVIRONMENTS[@]}"; do
        IFS=';' read -r name _ _ _ <<< "${DESKTOP_ENVIRONMENTS[$i]}"
        if [[ "$name" == "XFCE" ]]; then DEFAULT_DE_CHOICE=$((i+1)); break; fi
    done
fi


SELECTED_DE_INDEX=""
while true; do
    read -r -p "$(echo -e "${C_INPUT}Select the Desktop Environment to use with VNC (enter number${DEFAULT_DE_CHOICE:+, default $DEFAULT_DE_CHOICE}): ${C_RESET}")" choice
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

PACKAGES_TO_INSTALL="tightvncserver expect dbus-x11"
NEEDS_DESKTOP_INSTALL=false

primary_selected_package=$(echo "$SELECTED_DE_PACKAGES" | cut -d' ' -f1)
if ! dpkg -s "$primary_selected_package" >/dev/null 2>&1; then
    print_warn "$SELECTED_DE_NAME is not installed. It will be installed."
    PACKAGES_TO_INSTALL="$PACKAGES_TO_INSTALL $SELECTED_DE_PACKAGES"
    NEEDS_DESKTOP_INSTALL=true
else
    print_info "$SELECTED_DE_NAME is already installed."
fi

# --- Step 2: System Update and Package Installation ---
print_title "Step 2: System Update and Package Installation"
print_info "The following packages will be installed/ensured: ${C_BOLD}$PACKAGES_TO_INSTALL${C_RESET}"
read -r -p "$(echo -e "${C_INPUT}Do you want to proceed with system update and package installation? (Y/n): ${C_RESET}")" confirm_install
if [[ "$confirm_install" =~ ^[Nn]$ ]]; then
    print_error "Aborting script as package installation was declined."
    exit 1
fi

print_cmd "sudo apt update"
sudo apt update | tee -a "$LOG_FILE"
print_warn "You might see warnings about missing firmware during updates/installs."
print_warn "These are usually non-critical for VNC but might affect other hardware (e.g., AMD GPU)."
print_warn "Consider running 'sudo apt install firmware-linux firmware-amd-graphics' (or similar) later if needed."

print_cmd "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y"
# Temporarily set DEBIAN_FRONTEND to noninteractive for the upgrade
if ! sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y | tee -a "$LOG_FILE"; then
    print_warn "apt upgrade encountered an issue. Check the log. Continuing with package installation..."
    # Depending on the error, you might choose to exit here, but often non-critical errors can be ignored for upgrade.
fi


print_info "Installing packages. This may take some time. Configuration prompts will be handled automatically with default values."
print_cmd "sudo DEBIAN_FRONTEND=noninteractive apt install -y $PACKAGES_TO_INSTALL"
# Temporarily set DEBIAN_FRONTEND to noninteractive for the install
# The output is piped to tee, so check the exit status of apt install itself
# by putting it in the if condition.
if sudo DEBIAN_FRONTEND=noninteractive apt install -y $PACKAGES_TO_INSTALL 2>&1 | tee -a "$LOG_FILE"; then
    print_info "${C_GREEN}Packages installed successfully.${C_RESET}"
else
    # Check the specific exit code if needed, or just use the general failure
    exit_status=$?
    print_error "Failed to install necessary packages (exit code: $exit_status). Please check the output above and in the log file: $LOG_FILE."
    print_error "This script attempted to use default answers for any configuration prompts by setting DEBIAN_FRONTEND=noninteractive."
    print_error "If problems persist (e.g., due to broken packages or complex conflicts), you might need to resolve them manually."
    exit 1
fi

# --- Step 3: VNC Password Setup ---
print_title "Step 3: VNC Password Setup"
VNC_PASSWORD=""
VIEW_ONLY_PASSWORD=""
while true; do
    read -s -r -p "$(echo -e "${C_INPUT}Enter VNC full access password (6-8 characters recommended): ${C_RESET}")" VNC_PASSWORD
    echo
    if [ ${#VNC_PASSWORD} -lt 6 ] || [ ${#VNC_PASSWORD} -gt 8 ]; then
        print_warn "Password length should ideally be between 6 and 8 characters for TightVNC."
    fi
    read -s -r -p "$(echo -e "${C_INPUT}Verify VNC full access password: ${C_RESET}")" VNC_PASSWORD_VERIFY
    echo
    if [ "$VNC_PASSWORD" == "$VNC_PASSWORD_VERIFY" ]; then
        break
    else
        print_warn "Passwords do not match. Please try again."
    fi
done

while true; do
    read -r -p "$(echo -e "${C_INPUT}Would you like to enter a view-only password? (y/N): ${C_RESET}")" setup_view_only
    setup_view_only="${setup_view_only:-n}"
    if [[ "$setup_view_only" =~ ^[Yy]$ ]]; then
        read -s -r -p "$(echo -e "${C_INPUT}Enter VNC view-only password (6-8 characters recommended): ${C_RESET}")" VIEW_ONLY_PASSWORD
        echo
        if [ ${#VIEW_ONLY_PASSWORD} -lt 6 ] || [ ${#VIEW_ONLY_PASSWORD} -gt 8 ]; then
            print_warn "Password length should ideally be between 6 and 8 characters for TightVNC."
        fi
        read -s -r -p "$(echo -e "${C_INPUT}Verify VNC view-only password: ${C_RESET}")" VIEW_ONLY_PASSWORD_VERIFY
        echo
        if [ "$VIEW_ONLY_PASSWORD" == "$VIEW_ONLY_PASSWORD_VERIFY" ]; then
            break
        else
            print_warn "View-only passwords do not match. Please try again."
        fi
    elif [[ "$setup_view_only" =~ ^[Nn]$ ]]; then
        VIEW_ONLY_PASSWORD="" # Ensure it's empty
        break
    else
        print_warn "Invalid input. Please enter 'y' or 'n'."
    fi
done


print_info "Setting VNC passwords..."
# Ensure .vnc directory exists for vncpasswd
mkdir -p "$VNC_DIR"

expect_script=$(mktemp)
cat > "$expect_script" <<EOF
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

print_cmd "expect script for vncpasswd"
# Log the expect script content without passwords for security, or with dummy passwords
cat "$expect_script" | sed "s/$VNC_PASSWORD/********/g" | sed "s/$VIEW_ONLY_PASSWORD/********/g" >> "$LOG_FILE"

expect -f "$expect_script" >> "$LOG_FILE" 2>&1
rm -f "$expect_script"

# Store passwords (optional, with warning)
print_warn "Storing passwords in plain text in $PASSWORD_FILE."
print_warn "Ensure this file is secured (permissions will be set to 600)."
echo "VNC Full Access Password: $VNC_PASSWORD" > "$PASSWORD_FILE"
if [ -n "$VIEW_ONLY_PASSWORD" ]; then
    echo "VNC View-Only Password: $VIEW_ONLY_PASSWORD" >> "$PASSWORD_FILE"
fi
chmod 600 "$PASSWORD_FILE"
print_info "VNC passwords set. Plaintext versions (if chosen) are in $PASSWORD_FILE"

# --- Step 4: Configure xstartup ---
print_title "Step 4: Configure ~/.vnc/xstartup"
XSTARTUP_FILE="$VNC_DIR/xstartup"

# Kill any existing VNC server on display :1 before modifying xstartup
print_info "Attempting to kill any existing VNC server on display :1..."
print_cmd "vncserver -kill :1"
vncserver -kill :1 >> "$LOG_FILE" 2>&1 # Output might indicate no server, which is fine

if [ -f "$XSTARTUP_FILE" ]; then
    BACKUP_XSTARTUP="$XSTARTUP_FILE-$(date +'%Y-%m-%d_%H-%M-%S').bak"
    print_info "Backing up existing $XSTARTUP_FILE to $BACKUP_XSTARTUP"
    cp "$XSTARTUP_FILE" "$BACKUP_XSTARTUP"
fi

XSTARTUP_CONTENT=$(cat <<EOF
#!/bin/sh

# This file is automatically generated by $SCRIPT_NAME

# Disable DPMS (Energy Star) features and screen saver
xset s off -dpms

# Uncomment the following two lines for normal desktop:
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Load X resources (if any)
if [ -r "\$HOME/.Xresources" ]; then
    xrdb "\$HOME/.Xresources"
fi

# Set a default background color (useful for troubleshooting if DE doesn't start)
# xsetroot -solid grey

# Start the selected Desktop Environment / Window Manager
# For $SELECTED_DE_NAME:
exec $SELECTED_DE_CMD
EOF
)

print_info "The following content will be written to $XSTARTUP_FILE:"
echo -e "${C_CMD}--- xstartup content ---${C_RESET}"
echo -e "${C_CMD}${XSTARTUP_CONTENT}${C_RESET}"
echo -e "${C_CMD}--- end xstartup content ---${C_RESET}"

echo "$XSTARTUP_CONTENT" > "$XSTARTUP_FILE"
chmod +x "$XSTARTUP_FILE"
print_info "$XSTARTUP_FILE configured and made executable."

# --- Step 5: Start VNC Server ---
print_title "Step 5: Start VNC Server"
VNC_DISPLAY=":1"
VNC_GEOMETRY="1280x800" # Common default, can be changed
VNC_DEPTH="24" # 16 or 24 are common

print_info "Starting VNC server on display $VNC_DISPLAY with geometry $VNC_GEOMETRY and depth $VNC_DEPTH..."
print_cmd "vncserver $VNC_DISPLAY -geometry $VNC_GEOMETRY -depth $VNC_DEPTH -localhost no"
# Note: -localhost no allows connections from other machines. Remove if only local access is needed.
# If issues arise, you might need to specify the Xorg path for some VNC versions:
# vncserver $VNC_DISPLAY -geometry $VNC_GEOMETRY -depth $VNC_DEPTH -noxstartup - értelmező /usr/bin/Xorg
# However, TightVNCServer usually handles this well.

VNC_START_OUTPUT=$(vncserver "$VNC_DISPLAY" -geometry "$VNC_GEOMETRY" -depth "$VNC_DEPTH" -localhost no 2>&1)
echo "$VNC_START_OUTPUT" >> "$LOG_FILE"

if echo "$VNC_START_OUTPUT" | grep -q "New 'X' desktop is"; then
    print_info "${C_GREEN}VNC server started successfully!${C_RESET}"
    echo -e "${C_GREEN}${VNC_START_OUTPUT}${C_RESET}"
    VNC_LOG_FILE=$(echo "$VNC_START_OUTPUT" | grep "Log file is" | awk '{print $NF}')
    if [ -n "$VNC_LOG_FILE" ]; then
        print_info "VNC server log file: ${C_BOLD}$VNC_LOG_FILE${C_RESET}"
    fi
else
    print_error "VNC server may not have started correctly. Check output above and log: $LOG_FILE"
    print_error "Also check the VNC server's own log file (usually in $VNC_DIR)."
    echo -e "${C_RED}${VNC_START_OUTPUT}${C_RESET}"
fi

# --- Step 6: Firewall Configuration (UFW) ---
print_title "Step 6: Firewall Configuration (UFW)"
VNC_PORT=$((5900 + ${VNC_DISPLAY#:}) # Calculate port from display number, e.g., :1 -> 5901
if command -v ufw &> /dev/null; then
    print_info "UFW firewall is detected."
    print_cmd "sudo ufw allow $VNC_PORT/tcp # VNC Port for display $VNC_DISPLAY"
    sudo ufw allow "$VNC_PORT/tcp" comment "VNC for display $VNC_DISPLAY" | tee -a "$LOG_FILE"
    # print_cmd "sudo ufw status" # Optional: show status
    # sudo ufw status | tee -a "$LOG_FILE"
    print_info "If UFW is active, port $VNC_PORT/tcp has been allowed for VNC."
    print_info "You might need to run 'sudo ufw enable' if the firewall is not already active."
else
    print_warn "UFW firewall manager not found. Skipping automatic firewall configuration."
    print_warn "If you use another firewall, please ensure port $VNC_PORT/tcp is open."
fi

# --- Step 7: Final Information ---
print_title "Step 7: VNC Setup Complete - Information"
HOSTNAME_GUESS=$(hostname)
IP_GUESS=$(hostname -I | awk '{print $1}')

print_info "${C_GREEN}VNC server setup is complete!${C_RESET}"
print_info "You should now be able to connect using a VNC client."
echo -e "${C_INFO}Connect to:${C_RESET}"
echo -e "${C_INFO}  Hostname: ${C_BOLD}${HOSTNAME_GUESS}${VNC_DISPLAY}${C_RESET} (e.g., ${HOSTNAME_GUESS}:1)"
echo -e "${C_INFO}  IP Address: ${C_BOLD}${IP_GUESS}${VNC_DISPLAY}${C_RESET} (e.g., ${IP_GUESS}:1)"
print_info "(Note: VNC clients use the display number, like ':1', not the raw TCP port 5901 directly in the server address field for TightVNC, TigerVNC etc. Some clients like UltraVNC might use 'server::port' notation like '192.168.1.100::5901' or 'server:display' like '192.168.1.100:1'.)"

echo -e "\n${C_INFO}Passwords:${C_RESET}"
echo -e "${C_INFO}  Full Access:     ${C_BOLD}$VNC_PASSWORD${C_RESET}"
if [ -n "$VIEW_ONLY_PASSWORD" ]; then
    echo -e "${C_INFO}  View-Only Access: ${C_BOLD}$VIEW_ONLY_PASSWORD${C_RESET}"
fi
if [ -f "$PASSWORD_FILE" ]; then
    echo -e "${C_INFO}  (These were also saved to: $PASSWORD_FILE)${C_RESET}"
fi

echo -e "\n${C_INFO}Managing the VNC Server:${C_RESET}"
echo -e "${C_INFO}  To stop the VNC server on display $VNC_DISPLAY: ${C_CMD}vncserver -kill $VNC_DISPLAY${C_RESET}"
echo -e "${C_INFO}  To start it again (if needed):        ${C_CMD}vncserver $VNC_DISPLAY -geometry $VNC_GEOMETRY -depth $VNC_DEPTH -localhost no${C_RESET}"
echo -e "${C_INFO}  To list running VNC servers:          ${C_CMD}vncserver -list${C_RESET} (or ${C_CMD}ps aux | grep Xtightvnc${C_RESET})"
echo -e "${C_INFO}  To list VNC listening ports (TCP):    ${C_CMD}ss -tulnp | grep -E 'Xtightvnc|590[0-9]'${C_RESET}"

echo -e "\n${C_INFO}Customizing VNC Session:${C_RESET}"
echo -e "${C_INFO}  Desktop Environment: ${C_BOLD}$SELECTED_DE_NAME${C_RESET} (configured in $XSTARTUP_FILE)"
echo -e "${C_INFO}  Color Depth: Currently set to ${C_BOLD}$VNC_DEPTH-bit${C_RESET}. You can change this with the ${C_CMD}-depth${C_RESET} option when starting ${C_CMD}vncserver${C_RESET}."
echo -e "${C_INFO}    (e.g., ${C_CMD}-depth 16${C_RESET} for 16-bit color, potentially faster on slow connections)."
echo -e "${C_INFO}  Geometry: Currently ${C_BOLD}$VNC_GEOMETRY${C_RESET}. Change with the ${C_CMD}-geometry${C_RESET} option."

echo -e "\n${C_INFO}Troubleshooting:${C_RESET}"
echo -e "${C_INFO}  Primary log for this script: ${C_BOLD}$LOG_FILE${C_RESET}"
if [ -n "$VNC_LOG_FILE" ] && [ -f "$VNC_LOG_FILE" ]; then
    echo -e "${C_INFO}  VNC server's own log file:   ${C_BOLD}$VNC_LOG_FILE${C_RESET}"
else
    echo -e "${C_INFO}  VNC server's own log file is typically in ${C_BOLD}$VNC_DIR/$(hostname)${VNC_DISPLAY}.log${C_RESET}"
fi
echo -e "${C_INFO}  Check these logs if you encounter connection issues."

if $NEEDS_DESKTOP_INSTALL; then
    print_warn "A new desktop environment ($SELECTED_DE_NAME) was installed."
    print_warn "A system reboot might be beneficial but is not always strictly necessary."
fi

print_title "Setup Finished!"
