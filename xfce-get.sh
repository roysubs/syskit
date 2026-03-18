#!/bin/bash

################################################################################
# XFCE & DASHBOARD COMMAND CENTER (Debian 2026 Edition)
#
# DESCRIPTION:
#   A fully idempotent script to start/stop a minimal XFCE desktop and a
#   Conky system monitor. Optimized for 8GB RAM systems.
#
# FEATURES:
#   - Smart Updates: Only runs 'apt update' if the cache is > 7 days old.
#   - Zero Bloat: Installs only essential XFCE components.
#   - RAM Focused: Reclaims ~800MB-1GB RAM when stopped.
#   - Modern Monitoring: Uses smartctl for HDD temps (replacing hddtemp).
#
# USAGE:
#   ./xfce-get.sh        -> Launch GUI and Dashboard
#   ./xfce-get.sh -stop  -> Kill everything and free RAM
################################################################################

# --- Configuration ---
VNC_DISPLAY=1
VNC_PORT=590$VNC_DISPLAY
VNC_RES="1280x720"
VNC_PWD_FILE="$HOME/.vnc/passwd"
CONKY_CONF="$HOME/.config/conky/conky.conf"
UPDATE_THRESHOLD=604800 # 7 days in seconds

# --- Helper Functions ---

print_ram() {
    local label=$1
    local used=$(free -m | awk '/Mem:/ { print $3 }')
    echo ">>> $label: ${used}MB RAM used."
}

smart_update() {
    local cache="/var/cache/apt/pkgcache.bin"
    local now=$(date +%s)
    if [ ! -f "$cache" ] || [ $((now - $(stat -c %Y "$cache"))) -gt $UPDATE_THRESHOLD ]; then
        echo "[!] Apt cache stale. Updating..."
        sudo apt update
    else
        echo "[i] Apt cache is fresh. Skipping update."
    fi
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

stop_all() {
    echo "--- Shutting down GUI and Reclaiming RAM ---"
    local start_ram=$(free -m | awk '/Mem:/ { print $3 }')

    # Kill VNC, Conky, and XFCE background ghosts
    vncserver -kill :$VNC_DISPLAY > /dev/null 2>&1
    pkill conky > /dev/null 2>&1
    pkill -u $USER -f "xfce4|thunar|xfconfd|gvfs|dbus-daemon|at-spi"
    
    # Cleanup stale lock files
    rm -f /tmp/.X11-unix/X$VNC_DISPLAY 2>/dev/null
    rm -f ~/.vnc/*.pid 2>/dev/null

    local end_ram=$(free -m | awk '/Mem:/ { print $3 }')
    echo "DONE: Freed $((start_ram - end_ram))MB. Current usage: ${end_ram}MB."
}

generate_conky_config() {
    mkdir -p "$(dirname "$CONKY_CONF")"
    
    # Auto-detect the primary network interface
    local net_if=$(ip -o -4 route show to default | awk '{print $5}' | head -n1)
    [ -z "$net_if" ] && net_if="enp2s0" # Default to what we saw in your screenshot

    cat <<EOF > "$CONKY_CONF"
conky.config = {
    alignment = 'top_right',
    background = false,
    double_buffer = true,
    font = 'DejaVu Sans Mono:size=10',
    gap_x = 30, gap_y = 60,
    own_window = true,
    own_window_type = 'desktop',
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_argb_value = 0,
    update_interval = 2.0,
    use_xft = true,
    default_color = 'white',
}
conky.text = [[
\${color #00FF00}SYSTEM \${hr 2}
\${color}Node: \${alignr}\${nodename}
\${color}IP ($net_if): \${alignr}\${addr $net_if}
\${color}Uptime: \${alignr}\${uptime}
\${color}CPU Load: \${alignr}\${cpu cpu0}%
\${color}CPU Temp: \${alignr}\${hwmon 0 temp 1}°C
\${color}RAM: \${alignr}\${mem}/\${memmax} (\${memperc}%)

\${color #00FF00}STORAGE DETECTED \${hr 2}
EOF

    # DYNAMICALLY DETECT DRIVES + TEMPS
    lsblk -rn -o MOUNTPOINT,KNAME,SIZE | grep -E '^/' | while read -r mount dev size; do
        # Strip partition numbers for smartctl (e.g. sdb2 -> sdb)
        local base_dev=$(echo "$dev" | sed 's/[0-9]*$//')
        
        # Determine the most robust temp extraction command
        # We try to use the absolute path and handle both 194 (SATA Temp) and 190 (Airflow Temp/Older SATA)
        local temp_cmd="/usr/sbin/smartctl -A /dev/$base_dev | awk '\$1 == \"194\" || \$1 == \"190\" {print \$10}' | grep -oE '[0-9]+' | head -n1"

        cat <<EOF >> "$CONKY_CONF"
\${color}Drive: $mount ($size)
\${fs_used_perc $mount}% \${alignr}\${fs_used $mount}/\${fs_size $mount}
\${fs_bar 6 $mount}
\${color grey}Temp: \${alignr}\${execi 60 $temp_cmd}°C
EOF
    done

    echo "]]" >> "$CONKY_CONF"
}

# --- Main Execution ---

if [[ "$1" == "-stop" ]]; then
    stop_all
    exit 0
fi

echo "--- Starting XFCE On-Demand Session ---"
print_ram "BASELINE"

# 1. Smart Install Logic
PKGS="xfce4 xfce4-terminal thunar xfce4-session tigervnc-standalone-server tigervnc-common dbus-x11 x11-xserver-utils conky-all smartmontools lm-sensors"
TO_INSTALL=""
for p in $PKGS; do ! is_installed "$p" && TO_INSTALL+="$p "; done

if [ -n "$TO_INSTALL" ]; then
    smart_update
    sudo apt install -y --no-install-recommends $TO_INSTALL
fi

# Tweak smartctl so conky can read temps without sudo (must be outside install block)
if is_installed "smartmontools"; then
    echo "[i] Ensuring smartctl has SUID permissions for dashboard..."
    sudo chmod u+s /usr/sbin/smartctl 2>/dev/null
fi

# 2. VNC and Dashboard Setup
if [ ! -f "$VNC_PWD_FILE" ]; then
    echo "[!] Setting VNC password..."
    vncpasswd
fi

mkdir -p ~/.vnc
cat <<EOF > ~/.vnc/xstartup
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
if [ -z "\$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval \$(dbus-launch --sh-syntax --exit-with-session)
fi
# Start Dashboard then XFCE
conky -c "$CONKY_CONF" &
exec xfce4-session
EOF
chmod +x ~/.vnc/xstartup

# 3. Launch
generate_conky_config
vncserver -kill :$VNC_DISPLAY > /dev/null 2>&1
vncserver :$VNC_DISPLAY -geometry $VNC_RES -localhost no

print_ram "POST-START"
IP=$(hostname -I | awk '{print $1}')
echo "================================================================"
echo " CONNECT TO: ${IP}:${VNC_PORT}"
echo " TIGERVNC VIEWER IS BEST FOR RESIZING SUPPORT"
echo " RUN './xfce-get.sh -stop' TO RECLAIM RAM"
echo "================================================================"
