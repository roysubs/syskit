#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi

# dns-rename.sh — Check and optionally update hostname + DNS (forward + reverse)
# Transparently shows all commands used.

set -euo pipefail

GREEN='\033[0;32m'
RESET='\033[0m'

echo
echo "🧭 Checking current forward and reverse DNS..."

# Get IP address (first non-loopback, non-docker)
if [[ "$(uname)" == "Darwin" ]]; then
    IFACE=$(route -n get 1.1.1.1 2>/dev/null | awk '/interface: /{print $2}')
    IP=$(ipconfig getifaddr "$IFACE" 2>/dev/null)
else
    IP=$(ip route get 1 | awk '{for(i=1;i<=NF;i++) if ($i=="src") print $(i+1)}' | head -n1)
fi

# Show forward DNS
echo
echo "🔍 Forward DNS (hostname for this machine):"
echo -e "${GREEN}hostname -f${RESET}"
hostname -f

# Show reverse DNS
echo
echo "🔁 Reverse DNS (hostname for IP address: $IP):"
echo -e "${GREEN}dig +short -x $IP${RESET}"
dig +short -x "$IP"

echo
read -rp "💬 Would you like to set both forward and reverse hostnames to a new name? [y/N] " reply
if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "❎ No changes made."
    exit 0
fi

read -rp "🆕 Enter new hostname (e.g. myhost.local or server01): " NEW_HOSTNAME

if [[ -z "$NEW_HOSTNAME" ]]; then
    echo "⚠️  Empty hostname. Aborting."
    exit 1
fi

# Set forward DNS (local hostname)
echo
echo "⚙️  Setting hostname to: $NEW_HOSTNAME"
if [[ "$(uname)" == "Darwin" ]]; then
    echo -e "${GREEN}sudo scutil --set HostName $NEW_HOSTNAME${RESET}"
    sudo scutil --set HostName "$NEW_HOSTNAME"
    echo -e "${GREEN}sudo scutil --set LocalHostName $NEW_HOSTNAME${RESET}"
    sudo scutil --set LocalHostName "$NEW_HOSTNAME"
    echo -e "${GREEN}sudo scutil --set ComputerName $NEW_HOSTNAME${RESET}"
    sudo scutil --set ComputerName "$NEW_HOSTNAME"
else
    echo -e "${GREEN}sudo hostnamectl set-hostname $NEW_HOSTNAME${RESET}"
    sudo hostnamectl set-hostname "$NEW_HOSTNAME"
fi

# Add reverse DNS via /etc/hosts if IP is local
if grep -q "$IP" /etc/hosts; then
    echo
    echo "🧹 Cleaning up old /etc/hosts entries for $IP"
    echo -e "${GREEN}sudo sed -i '/^$IP/d' /etc/hosts${RESET}"
    if [[ "$(uname)" == "Darwin" ]]; then
        sudo sed -i '' "/^$IP/d" /etc/hosts
    else
        sudo sed -i "/^$IP/d" /etc/hosts
    fi
fi

echo
echo "➕ Adding reverse DNS entry in /etc/hosts:"
echo -e "${GREEN}echo \"$IP $NEW_HOSTNAME\" | sudo tee -a /etc/hosts${RESET}"
echo "$IP $NEW_HOSTNAME" | sudo tee -a /etc/hosts > /dev/null

echo
echo "✅ Hostname updated!"
echo "🔁 Please log out and back in for shell prompts to reflect the new name."


