#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-05

# Ensure script is run as sudo

pkg_install() {
    if command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

if [[ $EUID -ne 0 ]]; then
  echo "Please run this script using sudo."
  exit 1
fi

# Determine the calling user's home directory and username
USER_HOME=$(eval echo ~$SUDO_USER)
USER_NAME=$SUDO_USER
VNC_XSTARTUP="$USER_HOME/.vnc/xstartup"

# List of supported desktop environments with descriptions
declare -A DESKTOP_ENVS=(
  ["GNOME"]="Appeals to users who value a modern, full-featured desktop environment."
  ["XFCE"]="Lightweight and highly customizable, perfect for low-resource systems."
  ["LXQt"]="A lightweight Qt-based desktop with a modern look and feel."
  ["LXDE"]="Simple and resource-friendly, suitable for older hardware."
  ["MATE"]="Traditional desktop experience with updated technologies."
  ["Budgie"]="Sleek and modern desktop focused on simplicity and elegance."
  ["KDE"]="Highly customizable and visually stunning, with numerous features."
  ["Cinnamon"]="Traditional yet modern desktop from the Linux Mint project."
  ["Pantheon"]="A minimalist and beautiful desktop environment inspired by macOS."
  ["Deepin"]="Polished and visually appealing desktop from the Deepin project."
  ["Openbox"]="Minimal and highly configurable window manager."
  ["i3"]="Keyboard-driven tiling window manager for power users."
  ["Fluxbox"]="Lightweight and fast, perfect for minimal setups."
  ["Enlightenment"]="Innovative and visually unique lightweight desktop."
  ["Sugar"]="Educational desktop designed for children, emphasizing simplicity."
)

# Function to display usage instructions
display_usage() {
  echo "Usage: ./swith-desktop-environment.sh <Desktop Environment>"
  echo
  echo "Install a new Desktop Environments."
  echo "Also update VNC and XRDP to default to the new Desktop Environment."
  echo
  echo "Available Desktop Environments:"
  for DE in "${!DESKTOP_ENVS[@]}"; do
    echo "  $DE - ${DESKTOP_ENVS[$DE]}"
  done
  echo
  exit 0
}

# Function to configure the VNC startup file
configure_vnc() {
  local session_cmd=$1
  echo "Configuring VNC for $DESKTOP_ENV..."
  cat <<EOF > "$VNC_XSTARTUP"
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
$session_cmd
[ -x /etc/vnc/xstartup ] && exec /etc/vnc/xstartup
[ -r $USER_HOME/.Xresources ] && xrdb $USER_HOME/.Xresources
x-window-manager &
EOF
  chmod +x "$VNC_XSTARTUP"
  echo "VNC configuration updated at $VNC_XSTARTUP"
}

# Function to configure XRDP (if installed)
configure_xrdp() {
  local session_cmd=$1
  if systemctl is-active --quiet xrdp; then
    echo "Configuring XRDP to use $DESKTOP_ENV..."
    XRDP_FILE="/etc/xrdp/startwm.sh"
    if [[ -f $XRDP_FILE ]]; then
      # Backup the existing configuration
      cp "$XRDP_FILE" "${XRDP_FILE}.bak"
      echo "Backed up existing XRDP configuration to ${XRDP_FILE}.bak"
      
      # Update the XRDP configuration
      cat <<EOF > "$XRDP_FILE"
#!/bin/sh
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
$session_cmd
EOF
      chmod +x "$XRDP_FILE"
      echo "XRDP configuration updated to use $DESKTOP_ENV."
    else
      echo "XRDP configuration file not found at $XRDP_FILE. Skipping XRDP configuration."
    fi
  else
    echo "XRDP is not active or installed. Skipping XRDP configuration."
  fi
}

# Main logic
if [[ $# -eq 0 ]]; then
  display_usage
fi

DESKTOP_ENV=$1
SESSION_CMD=""

# Map desktop environments to their session commands and installation commands
case $DESKTOP_ENV in
  GNOME)
    pkg_install task-gnome-desktop dbus-x11
    SESSION_CMD="/usr/bin/gnome-session"
    ;;
  XFCE)
    pkg_install task-xfce-desktop dbus-x11
    SESSION_CMD="/usr/bin/startxfce4"
    ;;
  LXQt)
    pkg_install task-lxqt-desktop dbus-x11
    SESSION_CMD="/usr/bin/startlxqt"
    ;;
  LXDE)
    pkg_install task-lxde-desktop dbus-x11
    SESSION_CMD="/usr/bin/startlxde"
    ;;
  MATE)
    pkg_install task-mate-desktop dbus-x11
    SESSION_CMD="/usr/bin/mate-session"
    ;;
  Budgie)
    pkg_install budgie-desktop dbus-x11
    SESSION_CMD="/usr/bin/budgie-session"
    ;;
  KDE)
    pkg_install task-kde-desktop dbus-x11
    SESSION_CMD="/usr/bin/startplasma-x11"
    ;;
  Cinnamon)
    pkg_install task-cinnamon-desktop dbus-x11
    SESSION_CMD="/usr/bin/cinnamon-session"
    ;;
  Pantheon)
    pkg_install pantheon
    SESSION_CMD="/usr/bin/pantheon-session"
    ;;
  Deepin)
    pkg_install dde
    SESSION_CMD="/usr/bin/startdde"
    ;;
  Openbox)
    pkg_install openbox
    SESSION_CMD="/usr/bin/openbox-session"
    ;;
  i3)
    pkg_install i3
    SESSION_CMD="/usr/bin/i3"
    ;;
  Fluxbox)
    pkg_install fluxbox
    SESSION_CMD="/usr/bin/startfluxbox"
    ;;
  Enlightenment)
    pkg_install enlightenment
    SESSION_CMD="/usr/bin/enlightenment_start"
    ;;
  Sugar)
    pkg_install sucrose
    SESSION_CMD="/usr/bin/sugar"
    ;;
  *)
    echo "Invalid Desktop Environment: $DESKTOP_ENV"
    display_usage
    ;;
esac

# Configure the VNC startup file and XRDP if applicable
configure_vnc "$SESSION_CMD"
configure_xrdp "$SESSION_CMD"

# Update the default desktop environment
echo "Switching default desktop manager..."
update-alternatives --set x-session-manager "$SESSION_CMD"
echo "Configuration complete. Please reboot for changes to take effect."

