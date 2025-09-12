#!/bin/bash
# Author: Roy Wiseman 2025-05
#
# Essentially a "Swiss Army knife" for finding a computer's local IP address. It's complex because there isn't one single, universal
# command that works reliably on every type of system (like different versions of Linux, macOS, or minimalist server installs).
# 
# It works like a waterfall, trying the most reliable methods first and falling back to other options if the previous one fails to find
# the primary IPv4 address your machine uses on the local network. It does this by attempting a series of checks in a specific order:
#
# - The Quickest Method (hostname -I): This is the first attempt. On many modern Linux systems, this command directly prints the
# machine's IP address(es). It's fast and simple, but the hostname command might not be installed or might list IPs for inactive
# connections (like a disconnected Ethernet port), so the script can't rely on it alone.
#
# - The Smartest Method (ip route get 1.1.1.1): This is a very clever trick for Linux. It asks the system, "Which network interface and
# IP address would you use to send a packet to the public DNS server at 1.1.1.1?" The answer reliably reveals the IP address of the
# primary, active internet-facing connection. This is often the most accurate method.
#
# - The Brute-Force Method (ip addr show <interface>): If the first two methods fail, the script starts guessing. It has a predefined
# list of common network interface names (eth0 for Ethernet, wlan0 for Wi-Fi, etc.) and checks them one by one to see if any have an IP
# address assigned.
# 
# - The macOS Fallback (ifconfig): This entire section exists because macOS doesn't use the same modern networking commands as Linux
# (like ip addr). It uses an older tool called ifconfig. This part of the script runs only if it detects it's on a Mac (uname == "Darwin").
#
# - The Last Resort (localhost): If every single one of the above methods fails to find an IP, the script gives up and prints localhost
# (which corresponds to the IP 127.0.0.1) so that it always provides some output.
#
# - This multi-layered approach makes the script robust and portable, but if you only ever plan to use it on one type of machine,
# it could be made much simpler.

# --- Script Setup ---
VERBOSE=0

# --- Functions ---

# Displays the help message and exits.
show_help() {
    cat << EOF
A robust script to find the primary local IP address of the machine.

USAGE:
  $(basename "$0") [FLAG]

FLAGS:
  -h, --help      Display this help message and exit.
  -v, --verbose   Print step-by-step diagnostic messages.

METHODOLOGY:
The script attempts several methods in a specific order, designed from most to least
reliable, to ensure the best chance of success across different systems (Linux/macOS).
It stops and prints the IP as soon as one method succeeds.

1. hostname -I
   - Command: hostname -I | awk '{print \$1}'
   - Why First: This is a fast and direct method on many modern Linux systems.

2. ip route
   - Command: ip route get 1.1.1.1 | awk '{print \$7}'
   - Why Second: This is a highly reliable Linux method that determines which IP is
     used for outbound traffic, accurately reflecting the primary active connection.

3. Interface Scan
   - Command: ip addr show <interface> | grep "inet" ...
   - Why Third: If the above fail, the script brute-forces a list of common
     interface names (eth0, wlan0, en0, etc.) to find an active IP.

4. macOS Fallback (ifconfig)
   - Command: ifconfig <interface> | grep "inet" ...
   - Why Last: This is a compatibility check for macOS, which uses the older
     'ifconfig' command instead of 'ip'.

If all methods fail, the script will return 'localhost'.
EOF
}

# Helper for logging verbose messages to standard error.
log() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "-> $1" >&2
    fi
}

# Checks if a command exists.
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Main function to find the host IP.
get_host_ip() {
    local ip=""
    
    # Method 1: hostname -I
    log "Checking method: hostname -I"
    if command_exists hostname && hostname -I > /dev/null 2>&1; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    if [[ -n "$ip" ]]; then
        log "SUCCESS: Found IP using 'hostname -I'"
        echo "$ip"
        return
    fi

    # Method 2: ip route
    log "Checking method: ip route"
    if [[ -z "$ip" ]]; then
        if command_exists ip; then
            ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}') 2>/dev/null
        fi
    fi
    if [[ -n "$ip" ]]; then
        log "SUCCESS: Found IP using 'ip route'"
        echo "$ip"
        return
    fi
    
    # Method 3: Interface Scan
    log "Checking common interfaces..."
    if [[ -z "$ip" ]]; then
        if command_exists ip; then
            local interfaces=("eth0" "wlan0" "en0" "eno1" "ens33" "enp0s3")
            for iface in "${interfaces[@]}"; do
                log "  - Checking interface: $iface"
                if ip addr show "$iface" 2>/dev/null | grep -q "inet\b"; then
                    ip=$(ip addr show "$iface" | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
                    if [[ -n "$ip" ]]; then
                        log "SUCCESS: Found IP on interface '$iface'"
                        echo "$ip"
                        return
                    fi
                fi
            done
        fi
    fi

    # Method 4: macOS Fallback
    log "Checking macOS methods..."
    if [[ -z "$ip" && "$(uname)" == "Darwin" ]]; then
        if command_exists ifconfig; then
            local mac_interfaces=("en0" "en1")
            for iface in "${mac_interfaces[@]}"; do
                 log "  - Checking interface: $iface"
                if ifconfig "$iface" 2>/dev/null | grep -q "inet\b"; then
                    ip=$(ifconfig "$iface" | grep "inet\b" | awk '{print $2}')
                    if [[ -n "$ip" ]]; then
                        log "SUCCESS: Found IP on macOS interface '$iface'"
                        echo "$ip"
                        return
                    fi
                fi
            done
        fi
    fi

    log "FAIL: All methods failed to find a valid IP."
    echo "localhost" # Default fallback
}


# --- Argument Parsing & Execution ---
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    show_help
    exit 0
elif [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    VERBOSE=1
fi

get_host_ip
