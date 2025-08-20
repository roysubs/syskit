#!/bin/bash

# host-announce.sh - Ensure this Linux host is discoverable by hostname

set -e

# --- CONFIG ---
DEFAULT_HOSTNAME="$(hostnamectl --static)"
IP_ADDR=$(hostname -I | awk '{print $1}')   # Get first non-loopback IP
RESOLVED_HOSTNAME=$(getent hosts "$IP_ADDR" | awk '{print $2}')
# ---------------

echo "🔍 Detected IP: $IP_ADDR"
echo "🔍 Current hostname: $DEFAULT_HOSTNAME"
echo "🔍 Hostname resolved from IP (PTR): ${RESOLVED_HOSTNAME:-<none>}"

# Function: Is hostname discoverable from IP (reverse lookup)?
function is_hostname_resolvable() {
    local ip="$1"
    local result
    result=$(getent hosts "$ip" | awk '{print $2}')
    [[ -n "$result" ]]
}

# --- Main Logic ---
if is_hostname_resolvable "$IP_ADDR"; then
    echo "✅ Hostname is already resolvable from IP: $RESOLVED_HOSTNAME"
    exit 0
fi

echo "⚠️  Hostname not resolvable via PTR record — setting up mDNS using avahi-daemon..."

# 1. Ensure hostnamectl has a valid hostname
if [[ -z "$DEFAULT_HOSTNAME" || "$DEFAULT_HOSTNAME" == "localhost" ]]; then
    read -rp "Enter a hostname to assign to this machine: " NEW_HOSTNAME
    sudo hostnamectl set-hostname "$NEW_HOSTNAME"
    echo "✅ Hostname set to: $NEW_HOSTNAME"
else
    echo "✅ Hostname already set: $DEFAULT_HOSTNAME"
fi

# 2. Install avahi-daemon if missing
if ! systemctl is-enabled --quiet avahi-daemon 2>/dev/null; then
    echo "📦 Installing and enabling avahi-daemon..."
    sudo apt-get update
    sudo apt-get install -y avahi-daemon
    sudo systemctl enable --now avahi-daemon
else
    echo "✅ avahi-daemon already installed and running."
fi

# 3. Check if samba is installed and might be advertising hostname
if systemctl is-active --quiet smbd || systemctl is-active --quiet nmbd; then
    echo "ℹ️  Samba appears to be running — it might be advertising the hostname via NetBIOS."
    echo "    This could explain why the hostname is visible from Windows."
fi

echo "✅ Setup complete. You should now be able to resolve this host by its name on the LAN."


