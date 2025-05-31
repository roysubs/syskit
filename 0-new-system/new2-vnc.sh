#!/bin/bash
# Author: Roy Wiseman 2025-05

# Configure VNC server (TightVNC)
# Setup ~/.vnc/xstartup and passwords
# This page solved all of my problems with VNC setup:
# https://bytexd.com/how-to-install-configure-vnc-on-debian/

# Define output file for passwords
SCRIPT_NAME=$(basename "$0")
PASSWORD_FILE="~/.vnc/${SCRIPT_NAME%.sh}-passwords.txt"
touch $PASSWORD_FILE
> "$PASSWORD_FILE"   # Clear the contents of this file
DESKTOP_PACKAGE="task-mate-desktop"      # task-xfce-desktop
DESKTOP_BINARY="/usr/bin/mate-session"   # /usr/bin/startxfce4

# Update the system
echo "Updating the system..."
sudo apt update && sudo apt upgrade -y
# Install necessary packages
echo "Install TightVNC server & Desktop..."
sudo apt install -y $DESKTOP_PACKAGE dbus-x11 tightvncserver expect

# Automate TightVNC vncpasswd entry
# Passwords must be 6-8 in length, any more than 8 is truncated
# Automate the vncpasswd process for both passwords
VNC_PASSWORD="11111111"
VIEW_ONLY_PASSWORD="00000000"
expect <<EOF
spawn vncpasswd
expect "Password:"
send "$VNC_PASSWORD\r"
expect "Verify:"
send "$VNC_PASSWORD\r"
expect "Would you like to enter a view-only password (y/n)?"
send "y\r"
expect "Password:"
send "$VIEW_ONLY_PASSWORD\r"
expect "Verify:"
send "$VIEW_ONLY_PASSWORD\r"
expect eof
EOF

echo "VNC passwords set, storing plaintext in $PASSWORD_FILE."
touch $PASSWORD_FILE
echo "VNC Password: $VNC_PASSWORD" >> "$PASSWORD_FILE"
echo "View-only Password: $VIEW_ONLY_PASSWORD" >> "$PASSWORD_FILE"

# Kill TightVNC session and backup xstartup
vncserver -kill :1
if [ -f ~/.vnc/xstartup ]; then
  cp ~/.vnc/xstartup ~/.vnc/xstartup-$(date +'%Y-%m-%d_%H-%M-%S').bak
fi

# Unset session manager variable to avoid conflicts
#   unset SESSION_MANAGER
# Unset D-Bus session address to prevent errors
#   unset DBUS_SESSION_BUS_ADDRESS
# Start MATE desktop session
#   /usr/bin/mate-session
# Execute system-wide xstartup script if it's executable
#   [ -x /etc/vnc/xstartup ] && exec /etc/vnc/xstartup
# Load user X resources if the file exists
#   [ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources

# Configure .vnc/xstartup
xstartup="#!/bin/sh
# Start up the standard system desktop
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
$DESKTOP_BINARY
[ -x /etc/vnc/xstartup ] && exec /etc/vnc/xstartup
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources
x-window-manager &
"
echo "$xstartup" > ~/.vnc/xstartup
chmod +x ~/.vnc/xstartup
vncserver

echo "VNC is set up. Access the system with a VNC client by IP or hostname:"
echo "   server_hostname:1"
echo "   server_ip:1"
echo

# Configure ufw firewall if installed
echo "Configuring firewall..."
if ! command -v ufw &> /dev/null; then
    echo "UFW not found, skipping..."
    # sudo apt install -y ufw
else
    sudo ufw allow ssh
    # sudo ufw allow 3389/tcp  # XRDP
    sudo ufw allow 5901/tcp  # VNC
    sudo ufw enable
fi

echo "

On Linux server:
==========
vncserver -kill :1
vncserver

Message from 'vncserver' should be something like:

##########
# New 'X' desktop is myhostname:1
#
# Starting applications specified in /home/boss/.vnc/xstartup
# Log file is /home/boss/.vnc/myhostname.log
##########

It may not be possibly to connect by hostname, use ip in that case instead

On Windows system:
==========

The 'vncserver' output tells you exactly what to enter into the VNC Viewer on Windows:
    myhostname:1
    192.168.1.100:1

TightVNC Viewer is very simple and creates a good display resolution without tweaking.
UltraVNC has a good autosize option, and tons of options.

Full access password: $VNC_PASSWORD
View only password:   $VIEW_ONLY_PASSWORD

"
