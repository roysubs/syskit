# Author: Roy Wiseman 2025-05
get_host_ip() {
    local ip=""
    # Try common Linux methods first
    if command_exists hostname && hostname -I > /dev/null 2>&1; then
        ip=$(hostname -I | awk '{print $1}')
    fi

    # If IP is still empty, try 'ip route get'
    if [[ -z "$ip" ]]; then
        if command_exists ip; then
            ip=$(ip route get 1.1.1.1 | awk '{print $7; exit}') 2>/dev/null
        fi
    fi

    # Fallback to specific interfaces if the above fails
    if [[ -z "$ip" ]]; then
        if command_exists ip; then # Ensure 'ip' command exists before trying to use it for interfaces
            local interfaces=("eth0" "wlan0" "en0" "eno1" "ens33" "enp0s3") # Added more common interface names
            for iface in "${interfaces[@]}"; do
                # Check if interface exists and has an inet address
                if ip addr show "$iface" 2>/dev/null | grep -q "inet\b"; then
                    ip=$(ip addr show "$iface" | grep "inet\b" | awk '{print $2}' | cut -d/ -f1)
                    if [[ -n "$ip" ]]; then break; fi
                fi
            done
        fi
    fi

    # Fallback for macOS if 'ip' command isn't aliased or available, or if still no IP
    if [[ -z "$ip" && "$(uname)" == "Darwin" ]]; then
        if command_exists ifconfig; then
            local mac_interfaces=("en0" "en1")
            for iface in "${mac_interfaces[@]}"; do
                if ifconfig "$iface" 2>/dev/null | grep -q "inet\b"; then
                    ip=$(ifconfig "$iface" | grep "inet\b" | awk '{print $2}')
                    if [[ -n "$ip" ]]; then break; fi
                fi
            done
        fi
    fi

    if [[ -n "$ip" ]]; then
        echo "$ip"
    else
        echo "localhost" # Default fallback
    fi
}

get_host_ip
