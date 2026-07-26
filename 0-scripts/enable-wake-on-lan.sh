#!/usr/bin/env bash
# Author: Roy Wiseman 2025-02
# enable-wake-on-lan.sh - Configure and use Wake-on-LAN (WoL) for this or other systems

set -euo pipefail

# ---- Configurable Defaults ----
IFACE=$(ip route | awk '/default/ {print $5; exit}')
MAC_ADDR=$(ip link show "$IFACE" | awk '/ether/ {print $2}')
BROADCAST="255.255.255.255"

# ---- Functions ----

show_help() {
cat <<EOF
🔧 Usage: enable-wake-on-lan.sh [OPTION]

Options:
  --on, --start          Enable Wake-on-LAN (magic packets) on this system
  --off, --stop          Disable Wake-on-LAN
  -s, --sleep, --sleep-now
                         Enable WoL and put this system to sleep now
  -w, --wake-now <ip|hostname>
                         Send a magic Wake-on-LAN packet to the last known MAC
  -h, --help             Show this help message

💡 Tips for waking up systems:
  - Send a WoL packet from another machine using this script or tools like `wakeonlan`
  - Use your router (many support WoL in their web interface)
  - Make sure BIOS/UEFI WoL is enabled (typically under Power Management)

⚠️ Most laptops do NOT support WoL from full power-off. Use sleep (S3/S4) instead.
EOF
}

pkg_install() {
    local pkgs=("$@")
    if command -v zypper &>/dev/null; then
        sudo zypper --non-interactive install --auto-agree-with-licenses -y "${pkgs[@]}"
    elif command -v apt-get &>/dev/null; then
        sudo apt-get update && sudo apt-get install -y "${pkgs[@]}"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "${pkgs[@]}"
    elif command -v yum &>/dev/null; then
        sudo yum install -y "${pkgs[@]}"
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm "${pkgs[@]}"
    elif command -v apk &>/dev/null; then
        sudo apk add "${pkgs[@]}"
    fi
}

enable_wol() {
  echo "🔎 Checking Wake-on-LAN compatibility on interface $IFACE..."

  if ! command -v ethtool >/dev/null; then
    echo "📦 Installing ethtool..."
    pkg_install ethtool
  fi

  echo "📝 Running: ethtool $IFACE"
  local ethtool_output
  if ! ethtool_output=$(sudo ethtool "$IFACE" 2>/dev/null); then
    echo "❌ Failed to run 'ethtool' on interface '$IFACE'. Is it valid?"
    exit 1
  fi

  echo "🔍 ethtool output:"
  echo "$ethtool_output" | grep -E 'Wake-on|Supports Wake-on' || echo "⚠️ No Wake-on-LAN lines found in ethtool output"

  local supports
  supports=$(echo "$ethtool_output" | grep 'Supports Wake-on' | awk '{print $3}')
  local current
  current=$(echo "$ethtool_output" | grep 'Wake-on' | tail -n1 | awk '{print $2}')

  if [[ "$supports" == *g* ]]; then
    echo "✅ Interface supports magic packet (g). Enabling..."
    sudo ethtool -s "$IFACE" wol g
    echo "🔁 New status:"
    sudo ethtool "$IFACE" | grep 'Wake-on'
  else
    echo "❌ Wake-on-LAN via magic packet (g) not supported on interface '$IFACE'"
  fi

  if grep -qi "battery" /sys/class/power_supply/*/type 2>/dev/null; then
    echo "⚠️ This appears to be a laptop. Wake-on-LAN won't work from full shutdown."
    echo "💤 Works only from:"
    echo "   • S3 (suspend-to-RAM)"
    echo "   • S4 (hibernate) — if BIOS supports it"
    echo "   ❌ Not from S5 (full shutdown) on most laptops"
  fi
}

disable_wol() {
  echo "🚫 Disabling Wake-on-LAN on interface $IFACE..."
  sudo ethtool -s "$IFACE" wol d
  echo "🔍 Current status:"
  sudo ethtool "$IFACE" | grep Wake-on
}

sleep_now() {
  enable_wol
  echo "😴 Sleeping now..."
  systemctl suspend
}

wake_now() {
  local target="$1"
  if ! command -v wakeonlan >/dev/null; then
    echo "📦 Installing 'wakeonlan' tool..."
    pkg_install wakeonlan
  fi

  echo "🌐 Resolving MAC of $target..."
  ping -c 1 "$target" >/dev/null || true
  arp_entry=$(ip neigh show "$target" | awk '{print $5}')
  if [[ -z "$arp_entry" ]]; then
    echo "❌ Failed to get MAC for $target. Try pinging it first from a session when it's awake."
    exit 1
  fi

  echo "📡 Sending magic packet to $arp_entry ($target)..."
  wakeonlan "$arp_entry"
}

# ---- Main ----

[[ $# -eq 0 ]] && show_help && exit 1

case "$1" in
  --on|--start)
    enable_wol
    ;;
  --off|--stop)
    disable_wol
    ;;
  -s|--sleep|--sleep-now)
    sleep_now
    ;;
  -w|--wake-now)
    [[ $# -ne 2 ]] && echo "❌ Missing target for --wake-now" && exit 1
    wake_now "$2"
    ;;
  -h|--help)
    show_help
    ;;
  *)
    echo "❌ Unknown option: $1"
    show_help
    exit 1
    ;;
esac

