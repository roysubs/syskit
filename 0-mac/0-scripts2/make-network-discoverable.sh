#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-02
# make-network-discoverable.sh — Make Linux system discoverable on local network (especially by Windows)


pkg_install() {
    if command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

set -euo pipefail

### User Prompt
read -rp "📛 Enter desired hostname for this system (no spaces): " new_hostname
if [[ -z "$new_hostname" ]]; then
  echo "❌ Hostname cannot be empty"
  exit 1
fi

echo "🔧 Setting hostname to '$new_hostname'..."
sudo hostnamectl set-hostname "$new_hostname"

### Update /etc/hosts for loopback resolution
echo "🔁 Updating /etc/hosts..."
sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/" /etc/hosts || true
if ! grep -q "127.0.1.1" /etc/hosts; then
  echo -e "127.0.1.1\t$new_hostname" | sudo tee -a /etc/hosts > /dev/null
fi

### Install Avahi
echo "📦 Installing avahi-daemon (mDNS responder)..."
sudo apt-get update -qq
pkg_install avahi-daemon avahi-utils libnss-mdns

echo "✅ Avahi installed"

### Ensure avahi-daemon is running
echo "🧩 Enabling and starting avahi-daemon..."
sudo systemctl enable avahi-daemon
sudo systemctl restart avahi-daemon

### Optional: Samba (for full Windows browsing)
read -rp "📁 Install Samba for file sharing and NetBIOS discovery? [y/N]: " samba_opt
if [[ "$samba_opt" =~ ^[Yy]$ ]]; then
  echo "📦 Installing Samba..."
  pkg_install samba smbclient
  sudo systemctl enable smbd
  sudo systemctl restart smbd
fi

### Firewall Config (if ufw is active)
if command -v ufw >/dev/null && sudo ufw status | grep -q "Status: active"; then
  echo "🌐 Configuring ufw firewall..."
  sudo ufw allow 5353/udp comment "mDNS for Avahi"
  [[ "$samba_opt" =~ ^[Yy]$ ]] && sudo ufw allow 'Samba'
fi

### Confirm success
echo ""
echo "🎉 Done! This Linux machine should now be discoverable as:"
echo "    🔸 ${new_hostname}.local      (mDNS)"
[[ "$samba_opt" =~ ^[Yy]$ ]] && echo "    🔸 ${new_hostname}             (NetBIOS / Windows name, if Samba enabled)"

### 🧪 Tests
echo ""
echo "🧪 Test it on another machine:"
echo "    - ping ${new_hostname}.local"
echo "    - smbclient -L //${new_hostname}/    (if Samba was enabled)"
echo ""
echo "💡 Windows systems need to have 'Function Discovery' services enabled for hostname resolution."

