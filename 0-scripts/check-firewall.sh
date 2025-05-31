#!/bin/bash
# Author: Roy Wiseman 2025-01

# check-firewall.sh — Enhanced firewall checker for home users

print_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -h, --help     Show this help message
  -t, --tips     Show tips and common commands for all firewall tools

EOF
}

print_header() {
  echo "Checking for firewall status on your system..."
  echo "---------------------------------------------"
}

check_installed() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1
}

status_line() {
  printf "%-18s : %s\\n" "$1" "$2"
}

print_firewall_status() {
  ACTIVE_FIREWALLS=()
  echo ""
  echo "🔍 Checking active firewalls:"
  echo ""

  #### UFW
  if check_installed ufw; then
    ufw_status=$(ufw status 2>/dev/null)
    if echo "$ufw_status" | grep -q "Status: active"; then
      status_line "ufw" "🟢 Active"
      echo "$ufw_status" | sed 's/^/   /'
      ACTIVE_FIREWALLS+=("ufw")
    else
      status_line "ufw" "⚪ Installed (inactive)"
    fi
  fi

  #### firewalld
  if check_installed firewall-cmd; then
    if systemctl is-active firewalld &>/dev/null; then
      status_line "firewalld" "🟢 Active"
      firewall-cmd --list-all | sed 's/^/   /'
      ACTIVE_FIREWALLS+=("firewalld")
    else
      status_line "firewalld" "⚪ Installed (inactive)"
    fi
  fi

  #### iptables
  if check_installed iptables; then
    if iptables -L -n | grep -qvE "Chain INPUT \(policy ACCEPT\)|Chain FORWARD|Chain OUTPUT"; then
      status_line "iptables" "🟢 Active"
      iptables -L -n | sed 's/^/   /'
      ACTIVE_FIREWALLS+=("iptables")
    else
      status_line "iptables" "⚪ Installed (inactive)"
    fi
  fi

  #### nftables
  if check_installed nft; then
    if nft list ruleset 2>/dev/null | grep -q "table"; then
      status_line "nftables" "🟢 Active"
      nft list ruleset | sed 's/^/   /'
      ACTIVE_FIREWALLS+=("nftables")
    else
      status_line "nftables" "⚪ Installed (inactive)"
    fi
  fi

  #### CSF
  if check_installed csf; then
    if csf -l 2>/dev/null | grep -q "csf is running"; then
      status_line "csf" "🟢 Active"
      csf -l | sed 's/^/   /'
      ACTIVE_FIREWALLS+=("csf")
    else
      status_line "csf" "⚪ Installed (inactive)"
    fi
  fi

  #### ipset
  if check_installed ipset; then
    if ipset list 2>/dev/null | grep -q "Name:"; then
      status_line "ipset" "🟢 Active"
      ipset list | sed 's/^/   /'
      ACTIVE_FIREWALLS+=("ipset")
    else
      status_line "ipset" "⚪ Installed (inactive)"
    fi
  fi
}

print_tips() {
  echo ""
  echo "📌 Common commands for managing firewalls:"
  echo "-----------------------------------------"

  cat <<EOF
🔧 ufw (Uncomplicated Firewall)
   sudo ufw enable                 # Enable firewall
   sudo ufw disable                # Disable firewall
   sudo ufw status                 # Show status
   sudo ufw allow 22               # Allow port
   sudo ufw deny 22                # Deny port

🔧 firewalld
   sudo systemctl start firewalld  # Start service
   sudo firewall-cmd --state       # Check state
   sudo firewall-cmd --add-port=22/tcp --permanent
   sudo firewall-cmd --reload

🔧 iptables
   sudo iptables -L                # List rules
   sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT
   sudo iptables-save              # Save rules

🔧 nftables
   sudo nft list ruleset
   sudo nft add rule inet filter input tcp dport 22 accept

🔧 csf (ConfigServer Security & Firewall)
   sudo csf -e                     # Enable csf
   sudo csf -x                     # Disable csf
   sudo csf -l                     # List rules

🔧 ipset
   sudo ipset list
   sudo ipset create myset hash:ip
   sudo ipset add myset 192.168.0.1
EOF
}

# ========== Main ==========

case "$1" in
  -h|--help)
    print_usage
    exit 0
    ;;
  -t|--tips)
    print_header
    print_firewall_status
    print_tips
    echo -e "\nDone."
    exit 0
    ;;
esac

print_header
print_firewall_status

if [[ ${#ACTIVE_FIREWALLS[@]} -gt 0 ]]; then
  print_tips
fi

echo -e "\nDone."

