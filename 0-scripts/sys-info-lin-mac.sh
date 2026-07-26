#!/usr/bin/env bash
# Author: Roy Wiseman 2026-07
# Merged Cross-Platform System Inventory Tool (Linux & macOS)
set -euo pipefail

IS_MAC=false
if [[ "$(uname)" == "Darwin" ]]; then
    IS_MAC=true
fi

# ----------------------
# Root / Elevation handling
# ----------------------
if [[ "$IS_MAC" == "false" && $EUID -ne 0 ]]; then
    echo "This script needs root privileges on Linux. Re-running with sudo..."
    exec sudo bash "$0" "$@"
    exit $?
fi

# Determine output file location
if [[ "$IS_MAC" == "true" ]]; then
    INVOKER_REAL_HOME="$HOME"
    OUT_FILE="${INVOKER_REAL_HOME}/sys-info.txt"
else
    INVOKER_REAL_HOME=""
    TARGET_USER_FOR_OWNERSHIP="${SUDO_USER:-$(logname 2>/dev/null || echo "root")}"
    if [[ -n "$TARGET_USER_FOR_OWNERSHIP" && "$TARGET_USER_FOR_OWNERSHIP" != "root" ]]; then
        INVOKER_REAL_HOME=$(getent passwd "$TARGET_USER_FOR_OWNERSHIP" 2>/dev/null | cut -d: -f6 || true)
    fi
    if [[ -z "$INVOKER_REAL_HOME" || ! -d "$INVOKER_REAL_HOME" ]]; then
        INVOKER_REAL_HOME="$HOME"
    fi
    OUT_FILE="${INVOKER_REAL_HOME}/sys-info.txt"
fi

# ----------------------
# Dependency Checks (Linux only)
# ----------------------
if [[ "$IS_MAC" == "false" ]]; then
    pkg_install() {
        local package_name="$1"
        if command -v zypper &>/dev/null; then
            zypper refresh && zypper install -y "$package_name"
        elif command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y "$package_name"
        elif command -v dnf &>/dev/null; then
            dnf install -y "$package_name"
        elif command -v yum &>/dev/null; then
            yum install -y "$package_name"
        elif command -v pacman &>/dev/null; then
            pacman -Sy --noconfirm "$package_name"
        elif command -v apk &>/dev/null; then
            apk add "$package_name"
        else
            echo "Error: Could not detect supported package manager." >&2
            return 1
        fi
    }

    install_dependency() {
        local package_name="$1"
        local command_name="$2"
        if ! command -v "$command_name" &>/dev/null; then
            read -p "'$command_name' (from '$package_name') is not available. Install it? [Y/n] " yn
            if [[ $yn =~ ^[Yy]$ ]] || [[ -z $yn ]]; then
                echo "Installing $package_name..."
                pkg_install "$package_name" || {
                    echo "Failed to install $package_name. Exiting."
                    exit 1
                }
            else
                echo "'$command_name' is required by this script. Exiting."
                exit 1
            fi
        fi
    }

    install_dependency "dmidecode" "dmidecode"
    install_dependency "pciutils" "lspci"
    install_dependency "procps" "free"
    install_dependency "util-linux" "lscpu"
    install_dependency "util-linux" "df"
    install_dependency "util-linux" "uptime"
    install_dependency "coreutils" "nproc"
    install_dependency "upower" "upower"
    install_dependency "systemd" "systemd-detect-virt"
    install_dependency "systemd" "loginctl"
    install_dependency "iproute2" "ip"
fi

# ----------------------
# Helper functions
# ----------------------
print_aligned() {
    local label="$1"
    local value="${2:-(Unknown)}"
    printf "    %-22s %s\n" "$label:" "$value"
}

print_section() {
    echo
    echo "$1"
}

safe_cmd() {
    "$@" 2>/dev/null || echo ""
}

get_os_name() {
    if [[ "$IS_MAC" == "true" ]]; then
        echo "macOS $(sw_vers -productVersion) ($(sw_vers -productName))"
    elif command -v lsb_release &>/dev/null; then
        lsb_release -ds 2>/dev/null | tr -d '"'
    elif [[ -f /etc/os-release ]]; then
        ( . /etc/os-release && echo "${PRETTY_NAME:-$NAME}" )
    else
        uname -rs
    fi
}

get_last_boot() {
    if [[ "$IS_MAC" == "true" ]]; then
        local sec=$(sysctl -n kern.boottime 2>/dev/null | awk -F'sec = ' '{print $2}' | awk -F',' '{print $1}')
        if [[ -n "$sec" && "$sec" =~ ^[0-9]+$ ]]; then
            if date -d "@$sec" "+%Y-%m-%d %H:%M:%S" &>/dev/null; then
                date -d "@$sec" "+%Y-%m-%d %H:%M:%S"
            elif date -r "$sec" "+%Y-%m-%d %H:%M:%S" &>/dev/null; then
                date -r "$sec" "+%Y-%m-%d %H:%M:%S"
            else
                echo "Unknown"
            fi
        else
            echo "Unknown"
        fi
    elif uptime -s &>/dev/null; then
        uptime -s
    elif who -b 2>/dev/null | grep -q "boot"; then
        who -b 2>/dev/null | awk '{print $3, $4}'
    elif [[ -f /proc/uptime ]]; then
        date -d "@$(awk -v b="$(date +%s)" -v u="$(cut -d' ' -f1 /proc/uptime)" 'BEGIN{print int(b-u)}')" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 'Unknown'
    else
        echo 'Unknown'
    fi
}

get_uptime() {
    if [[ "$IS_MAC" == "true" ]]; then
        uptime | sed 's/.*up //' | sed 's/, [0-9]* user.*//'
    elif uptime -p &>/dev/null; then
        uptime -p | sed 's/up //g'
    elif [[ -f /proc/uptime ]]; then
        awk '{u=$1; d=int(u/86400); h=int((u%86400)/3600); m=int((u%3600)/60); 
              if (d > 0) printf "%d days, %d hours, %d minutes\n", d, h, m;
              else if (h > 0) printf "%d hours, %d minutes\n", h, m;
              else printf "%d minutes\n", m}' /proc/uptime
    else
        uptime 2>/dev/null | sed -E 's/.*up +([^,]+),.*/\1/' || echo 'Unknown'
    fi
}

get_hostname() {
    if command -v hostname &>/dev/null; then
        hostname
    elif command -v hostnamectl &>/dev/null; then
        hostnamectl hostname 2>/dev/null || uname -n
    else
        uname -n
    fi
}

# Redirect output to tee file
exec > >(tee "$OUT_FILE")

# ----------------------
# System Overview
# ----------------------
print_section "📋 System Overview"
print_aligned "Collected At" "$(date '+%Y-%m-%d %H:%M:%S')"
print_aligned "Last Boot Time" "$(get_last_boot)"
print_aligned "Uptime" "$(get_uptime)"

# ----------------------
# Hardware Information
# ----------------------
print_section "🖥️ Hardware Information"
print_aligned "Hostname" "$(get_hostname)"
print_aligned "Operating System" "$(get_os_name)"
print_aligned "Kernel Version" "$(uname -r)"
print_aligned "Architecture" "$(uname -m)"

if [[ "$IS_MAC" == "true" ]]; then
    print_aligned "Primary Owner" "$(whoami)"
    make_model=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ {print $2}' | xargs || echo "Apple Mac")
    print_aligned "Make/Model" "Apple $make_model"
    serial_num=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/ {print $2}' | xargs || echo "N/A")
    print_aligned "Serial Number" "$serial_num"
    print_aligned "Firmware/EFI" "Apple EFI/BootROM"
else
    domain_name=$(get_hostname -d 2>/dev/null || safe_cmd dnsdomainname 2>/dev/null || true)
    print_aligned "Domain" "${domain_name:-(none)}"
    print_aligned "Primary Owner" "${SUDO_USER:-$(whoami)}"
    
    sys_make_raw=$(safe_cmd dmidecode -s system-manufacturer)
    sys_model_raw=$(safe_cmd dmidecode -s system-product-name)
    sys_make=$(echo "$sys_make_raw" | grep -vE "To Be Filled|Not Applicable|Default string|System Manufacturer" || echo "$sys_make_raw")
    sys_model=$(echo "$sys_model_raw" | grep -vE "To Be Filled|Not Applicable|Default string|System Product Name" || echo "$sys_model_raw")
    if [[ "$sys_make_raw" =~ (To Be Filled|Not Applicable|Default string|System Manufacturer) ]]; then sys_make=""; fi
    if [[ "$sys_model_raw" =~ (To Be Filled|Not Applicable|Default string|System Product Name) ]]; then sys_model=""; fi

    if [[ "$sys_make" == "$sys_model" ]] && [[ -n "$sys_make" ]]; then
        print_aligned "Make/Model" "$sys_make"
    elif [[ -n "$sys_make" ]] && [[ -n "$sys_model" ]]; then
        print_aligned "Make/Model" "$sys_make $sys_model"
    elif [[ -n "$sys_make" ]]; then
        print_aligned "Make/Model" "$sys_make"
    elif [[ -n "$sys_model" ]]; then
        print_aligned "Make/Model" "$sys_model"
    else
        print_aligned "Make/Model"
    fi

    serial_num_raw=$(safe_cmd dmidecode -s system-serial-number)
    serial_num=$(echo "$serial_num_raw" | grep -vE "Not Applicable|None|To Be Filled|Default string" || echo "$serial_num_raw")
    if [[ "$serial_num_raw" =~ (Not Applicable|None|To Be Filled|Default string) ]]; then serial_num=""; fi
    print_aligned "Serial Number" "${serial_num}"
    print_aligned "BIOS Version" "$(safe_cmd dmidecode -s bios-version)"
fi

# ----------------------
# CPU Information
# ----------------------
print_section "⚙️ CPU Information"
if [[ "$IS_MAC" == "true" ]]; then
    print_aligned "CPU Model" "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model 2>/dev/null)"
    print_aligned "Physical Cores" "$(sysctl -n hw.physicalcpu 2>/dev/null)"
    print_aligned "Logical Processors" "$(sysctl -n hw.logicalcpu 2>/dev/null)"
else
    cpu_model=$(lscpu | awk -F: '/Model name/ {print $2}' | xargs || true)
    print_aligned "CPU Model" "${cpu_model:-Unknown}"
    print_aligned "Sockets" "$(lscpu | awk -F: '/Socket\(s\)/ {print $2}' | xargs || echo '1')"
    print_aligned "Core(s) per socket" "$(lscpu | awk -F: '/Core\(s\) per socket/ {print $2}' | xargs || echo '1')"
    print_aligned "Thread(s) per core" "$(lscpu | awk -F: '/Thread\(s\) per core/ {print $2}' | xargs || echo '1')"
    print_aligned "Total Physical Cores" "$(lscpu | awk -F: '/CPU\(s\)/ {print $2}' | xargs || echo '1')"
    print_aligned "Total Logical Processors" "$(nproc 2>/dev/null || echo '1')"
fi

# ----------------------
# Memory Information
# ----------------------
print_section "🧠 Memory Information"
if [[ "$IS_MAC" == "true" ]]; then
    total_mem_gb=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1024 / 1024 / 1024 ))
    print_aligned "Total Memory" "${total_mem_gb} GB"
    free_pages=$(vm_stat 2>/dev/null | awk '/Pages free/ {print $3}' | tr -d '.' || echo 0)
    free_mem_mb=$(( free_pages * 4096 / 1024 / 1024 ))
    print_aligned "Free Memory (Approx)" "${free_mem_mb} MB"
else
    print_aligned "Total Memory" "$(free -h | awk '/Mem:/ {print $2}')"
    print_aligned "Used Memory" "$(free -h | awk '/Mem:/ {print $3}')"
    print_aligned "Free Memory" "$(free -h | awk '/Mem:/ {print $4}')"
    print_aligned "Available Memory" "$(free -h | awk '/Mem:/ {print $7}')"

    echo
    echo "  RAM Module Details (from dmidecode):"
    dmi_ram=$(dmidecode -t memory 2>/dev/null || true)
    if [[ -n "$dmi_ram" ]]; then
        echo "$dmi_ram" | awk '/Memory Device/,/^$/ {
            if ($0 ~ /Locator: / && $0 !~ /Bank/) loc=$2;
            if ($0 ~ /Size: /) size=$2 " " $3;
            if ($0 ~ /Type: / && $0 !~ /Detail/) type=$2;
            if ($0 ~ /Speed: / && $0 !~ /Configured/) speed=$2 " " $3;
            if ($0 ~ /Manufacturer: /) mfr=$2;
            if ($0 ~ /Part Number: /) part=$2;
            if ($0 ~ /Serial Number: /) serial=$2;
        } END {
            if (size != "" && size !~ /No Module Installed/) {
                printf "    Slot %s (%s, %s, PN: %s, Type: %s, Speed: %s)\n", loc, size, serial, part, type, speed;
            }
        }'
    fi
fi

# ----------------------
# Display Information
# ----------------------
print_section "🖼️ Display Information"
if [[ "$IS_MAC" == "true" ]]; then
    disp_card=$(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model|Metal Support/ {print $2}' | xargs | head -n1 || echo "Apple Display")
    print_aligned "Display Card(s)" "$disp_card"
    print_aligned "Display Driver(s)" "macOS Quartz Extreme / Metal"
else
    disp_card=$(lspci | awk '/VGA|3D/ {print $0}' | head -n1 || echo "Unknown")
    print_aligned "Display Card(s)" "$disp_card"
    disp_driver=$(lspci -k 2>/dev/null | awk '/VGA|3D/,/Kernel driver in use/ {if (/Kernel driver in use/) print $5}' | head -n1 || echo "Unknown")
    print_aligned "Display Driver(s)" "$disp_driver"
fi

# ----------------------
# Storage Information
# ----------------------
print_section "💾 Storage Information"
echo "    Filesystem          Type   Size  Used Avail Use% Mounted on"
df_raw_output=$(df -hT -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null || df -h 2>/dev/null || true)
if [[ $(echo "$df_raw_output" | wc -l) -gt 1 ]]; then
    echo "$df_raw_output" | awk 'NR==1 {next} {printf "    %-19s %-6s %5s %5s %5s %4s %s\n", $1, $2, $3, $4, $5, $6, $7}'
else
    echo "    No persistent disk usage information found."
fi

# ----------------------
# Network Information
# ----------------------
print_section "🌐 Network Information"
echo "    Interface  IP Address           MAC Address"
if [[ "$IS_MAC" == "true" ]]; then
    ifconfig 2>/dev/null | awk '
    /^[a-z0-9]+:/ {iface=$1; sub(/:/, "", iface)}
    /ether/ {mac=$2}
    /inet / && !/127\.0\.0\.1/ {ip=$2; printf "    %-10s %-20s %s\n", iface, ip, mac}
    '
else
    ip_br_addr_output=$(ip -br addr show 2>/dev/null || true)
    if [[ -n "$ip_br_addr_output" ]]; then
        echo "$ip_br_addr_output" | awk '
        $1 != "lo" && NF >= 2 {
            iface = $1;
            mac_addr = "N/A";
            ipv4_addr = "N/A";
            ip_start_field = 3;
            if (NF >=3 && $3 ~ /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/) {
                mac_addr = $3;
                ip_start_field = 4;
            }
            for (i = ip_start_field; i <= NF; i++) {
                if ($i ~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\//) {
                    split($i, addr_parts, "/");
                    ipv4_addr = addr_parts[1];
                    break;
                }
            }
            printf "    %-10s %-20s %s\n", iface, ipv4_addr, mac_addr;
        }'
    fi
fi

# ----------------------
# Software & Repositories
# ----------------------
print_section "📦 Software & Repositories"
if [[ "$IS_MAC" == "true" ]]; then
    if command -v brew &>/dev/null; then
        print_aligned "Package Manager" "Homebrew ($(brew --prefix))"
    else
        print_aligned "Package Manager" "Native macOS (No Homebrew detected)"
    fi
else
    if command -v zypper &>/dev/null; then
        echo "    Zypper Repositories (Alias, Name, Enabled, URL):"
        zypper lr -u 2>/dev/null | awk -F'|' 'NR>4 && NF>=6 {gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $3); gsub(/^[ \t]+|[ \t]+$/, "", $4); gsub(/^[ \t]+|[ \t]+$/, "", $7); if ($4~/[Yy]es/ || $4=="1") printf "        %-20s %-30s %s\n", $2, $3, $7}' || echo "        No Zypper repos found."
    elif command -v apt-get &>/dev/null; then
        echo "    APT Repository URLs (Suite, URL, Components):"
        grep_output=$(grep -rhE '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true)
        if [[ -n "$grep_output" ]]; then
            echo "$grep_output" | awk '{url=$2; suite=$3; components=""; for (i=4; i<=NF; i++) components=components " " $i; sub(/^[ \t]+/, "", components); printf "        %-25s %s (%s)\n", suite, url, components}' | sort -u
        else
            echo "        No APT repositories found."
        fi
    fi
fi

echo
echo "System information has been saved to: $OUT_FILE"

exit 0
