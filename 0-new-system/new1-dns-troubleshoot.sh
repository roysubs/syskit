#!/usr/bin/env bash

set -euo pipefail

GREEN='\033[0;32m'
RESET='\033[0m'

print_green() {
    echo -e "${GREEN}$1${RESET}"
}

# Get current hostname (forward resolution)
print_green "🔍 Checking forward DNS (hostname → IP)..."
hostname_output=$(hostname)
echo "Command: hostname"
echo "Result: $hostname_output"

echo

# Get IP of the current host
ip=$(hostname -I | awk '{print $1}')
print_green "🔍 Checking reverse DNS (IP → hostname)..."
echo "Command: dig -x $ip +short"
reverse_name=$(dig -x "$ip" +short)
echo "Result: $reverse_name"

# Display current status to user
echo -e "\nCurrent forward hostname: $hostname_output"
echo -e "Current reverse hostname: $reverse_name"
echo

# Ask if the user wants to rename the host
read -rp "Do you want to set a new hostname? (y/N): " confirm
if [[ "$confirm" =~ ^[Yy]$ ]]; then
    read -rp "Enter new hostname (no .local): " new_hostname

    if [[ -z "$new_hostname" ]]; then
        echo "No hostname entered. Aborting rename."
        exit 1
    fi

    print_green "Setting hostname to '$new_hostname'..."

    echo -e "\nCommand: sudo hostnamectl set-hostname $new_hostname"
    sudo hostnamectl set-hostname "$new_hostname"

    print_green "Updating /etc/hosts..."

    echo -e "\nCommand: sudo sed -i ..."
    sudo sed -i "/127.0.1.1/d" /etc/hosts
    echo "127.0.1.1   $new_hostname" | sudo tee -a /etc/hosts

    echo -e "\nHostname successfully updated to: $new_hostname"
    current_name="$new_hostname"
else
    current_name="$hostname_output"
fi

# Advise user if reverse lookup is still empty
echo
if [[ -z "$reverse_name" ]]; then
    print_green "⚠️ Note: Reverse DNS lookup returned no result."
    echo "This may be expected if the router or DNS server does not provide PTR records for LAN IPs."
    echo "Reverse DNS is mostly cosmetic in small LANs and may not populate automatically."
    echo
fi

# Troubleshooting and resolution tips for slow hostname resolution
print_green "\n💡 Troubleshooting Slow Hostname Resolution"
echo "If pinging '$current_name' is slow, but pinging the IP is fast, it likely indicates a DNS or name resolution issue."
echo "This often happens because Windows attempts various fallback methods (DNS, LLMNR, NetBIOS, mDNS), which may timeout."

echo
print_green "🧪 Recommended tests:"
echo "  - Run: nslookup $current_name"
echo "    → Checks if Windows can resolve it via DNS"
echo
print_green "  - Run: ping -4 $current_name"
echo "    → Forces IPv4, avoids any IPv6 delay"
echo
print_green "  - Run: Get-DnsClient (in PowerShell)"
echo "    → Shows how DNS suffixes are applied"

echo
print_green "🛠️ Fixes:"
echo "  1. Add to your Windows hosts file:"
echo "     C:\\Windows\\System32\\drivers\\etc\\hosts"
echo "       $ip   $current_name"
echo
print_green "  2. Avoid using '.local' hostnames unless you're using Bonjour/mDNS intentionally."
echo "     Rename the host using just a simple name like 'hp2', or something like 'hp2.lan'."
echo
print_green "  3. Ensure /etc/hosts on Linux includes:"
echo "       $ip   $current_name"
echo
print_green "  4. Disable unused Windows fallback mechanisms (NetBIOS, LLMNR) if delays persist."

echo
print_green "⏱️ Why this happens:"
echo "  - Windows tries DNS, then NetBIOS, then multicast/mDNS."
echo "  - If any of these are slow or misconfigured, resolution can take seconds."
echo "  - Setting things explicitly in hosts files ensures instant, local resolution."

echo
print_green "Done. Please test resolution and ping speeds from Windows to confirm."

