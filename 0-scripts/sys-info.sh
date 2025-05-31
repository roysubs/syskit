#!/usr/bin/env bash
# Author: Roy Wiseman 2025-04
set -euo pipefail

# Section 1: Ensure script is run as root. If not, re-execute with sudo.
if [[ $EUID -ne 0 ]]; then
    echo "This script needs root privileges. Re-running with sudo..."
    exec sudo bash "$0" "$@"
    exit $?
fi

# Section 2: Script is now running as root. Determine where to save the output file.
INVOKER_REAL_HOME=""
TARGET_USER_FOR_OWNERSHIP=""

if [[ -n "${SUDO_USER:-}" ]]; then
    TARGET_USER_FOR_OWNERSHIP="$SUDO_USER"
    INVOKER_REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [[ -z "$INVOKER_REAL_HOME" ]] || ! [[ -d "$INVOKER_REAL_HOME" ]]; then
        echo "Warning: Could not determine home directory for user '$SUDO_USER' from getent. Trying alternative or defaulting to /tmp." >&2
        INVOKER_REAL_HOME_ALT=$(eval echo "~$SUDO_USER" 2>/dev/null || true)
        if [[ -n "$INVOKER_REAL_HOME_ALT" ]] && [[ -d "$INVOKER_REAL_HOME_ALT" ]]; then
            INVOKER_REAL_HOME="$INVOKER_REAL_HOME_ALT"
        else
            INVOKER_REAL_HOME=""
        fi
    fi
else
    ORIGINAL_LOGGED_IN_USER=$(logname 2>/dev/null || true)
    if [[ -n "$ORIGINAL_LOGGED_IN_USER" ]] && [[ "$ORIGINAL_LOGGED_IN_USER" != "root" ]]; then
        TARGET_USER_FOR_OWNERSHIP="$ORIGINAL_LOGGED_IN_USER"
        INVOKER_REAL_HOME=$(getent passwd "$ORIGINAL_LOGGED_IN_USER" | cut -d: -f6)
        if [[ -z "$INVOKER_REAL_HOME" ]] || ! [[ -d "$INVOKER_REAL_HOME" ]]; then
             echo "Warning: Could not determine home directory for logged-in user '$ORIGINAL_LOGGED_IN_USER'. Will default to root's home or /tmp." >&2
             INVOKER_REAL_HOME=""
        fi
    fi
fi

if [[ -z "$INVOKER_REAL_HOME" ]] || ! [[ -d "$INVOKER_REAL_HOME" ]]; then
    if [[ -n "$TARGET_USER_FOR_OWNERSHIP" ]] && [[ "$TARGET_USER_FOR_OWNERSHIP" != "root" ]]; then
        echo "Warning: Home directory for '$TARGET_USER_FOR_OWNERSHIP' is invalid or not found ('${INVOKER_REAL_HOME:-not set}'). Outputting to /tmp." >&2
        OUT_FILE="/tmp/sys-info-${TARGET_USER_FOR_OWNERSHIP}-$(date +%Y%m%d-%H%M%S).txt"
    else
        TARGET_USER_FOR_OWNERSHIP="root"
        INVOKER_REAL_HOME="$HOME"
        OUT_FILE="${INVOKER_REAL_HOME}/sys-info.txt"
        # echo "Info: Outputting to root's home directory: $OUT_FILE" >&2 # Less verbose
    fi
else
    OUT_FILE="${INVOKER_REAL_HOME}/sys-info.txt"
fi

if [[ -z "$TARGET_USER_FOR_OWNERSHIP" ]]; then
    TARGET_USER_FOR_OWNERSHIP="root"
fi

OUT_DIR=$(dirname "$OUT_FILE")
if [[ ! -d "$OUT_DIR" ]]; then
    mkdir -p "$OUT_DIR"
    if [[ "$TARGET_USER_FOR_OWNERSHIP" != "root" ]] && id "$TARGET_USER_FOR_OWNERSHIP" &>/dev/null; then
        chown "$TARGET_USER_FOR_OWNERSHIP":"$(id -g "$TARGET_USER_FOR_OWNERSHIP")" "$OUT_DIR" || \
            echo "Warning: Failed to chown $OUT_DIR to $TARGET_USER_FOR_OWNERSHIP." >&2
    fi
fi

if id "$TARGET_USER_FOR_OWNERSHIP" &>/dev/null; then
    touch "$OUT_FILE"
    chown "$TARGET_USER_FOR_OWNERSHIP":"$(id -g "$TARGET_USER_FOR_OWNERSHIP")" "$OUT_FILE" || \
        echo "Warning: Failed to chown $OUT_FILE to $TARGET_USER_FOR_OWNERSHIP." >&2
else
    echo "Warning: Target user '$TARGET_USER_FOR_OWNERSHIP' for file ownership does not exist. File will be owned by root." >&2
    if ! [[ -w "$OUT_FILE" && -f "$OUT_FILE" ]]; then
        touch "$OUT_FILE"
    fi
fi

# ----------------------
# Dependency Checks & Installation
# ----------------------
install_dependency() {
    local package_name="$1"
    local command_name="$2"
    if ! command -v "$command_name" &>/dev/null; then
        read -p "'$command_name' (from '$package_name') is not available. Install it? [Y/n] " yn
        if [[ $yn =~ ^[Yy]$ ]] || [[ -z $yn ]]; then
            echo "Installing $package_name..."
            apt-get update && apt-get install -y "$package_name" || {
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
install_dependency "procps" "free" # procps provides free, ps, top, uptime, etc.
install_dependency "util-linux" "lscpu" # util-linux provides lscpu, df, mount etc.
# uptime is often in procps, but let's ensure util-linux for 'df' as well.
install_dependency "util-linux" "df"
install_dependency "util-linux" "uptime"
install_dependency "lsb-release" "lsb_release"
install_dependency "coreutils" "nproc" # coreutils provides nproc, date, etc.
install_dependency "upower" "upower"
install_dependency "systemd" "systemd-detect-virt"
install_dependency "systemd" "loginctl"
install_dependency "iproute2" "ip" # for ip command

# ----------------------
# Helper functions
# ----------------------
print_aligned() {
    local label="$1"
    local value="${2:-(Unknown)}"
    printf "    %-22s %s\n" "$label:" "$value"
}

print_multiline_aligned() {
    local label="$1"
    shift
    local first_value="${1:-(Unknown)}"
    shift
    printf "    %-22s %s\n" "$label:" "$first_value"
    for line in "$@"; do
        printf "    %-22s %s\n" "" "$line"
    done
}

print_section() {
    echo
    echo "$1"
}

safe_cmd() {
    "$@" 2>/dev/null || echo ""
}

# ----------------------
# Begin Output Redirection
# ----------------------
exec > >(tee "$OUT_FILE")

# ----------------------
# System Overview
# ----------------------
print_section "📋 System Overview"
print_aligned "Collected At" "$(date '+%Y-%m-%d %H:%M:%S')"
print_aligned "Last Boot Time" "$(uptime -s || echo 'Unknown')"
print_aligned "Uptime" "$(uptime -p | sed 's/up //g' || echo 'Unknown')"

# ----------------------
# Hardware Information
# ----------------------
print_section "🖥️ Hardware Information"
print_aligned "Hostname" "$(hostname)"
print_aligned "Operating System" "$(lsb_release -ds 2>/dev/null || uname -rs)"
print_aligned "Kernel Version" "$(uname -r)"
print_aligned "Architecture" "$(uname -m)"
domain_name=$(hostname -d 2>/dev/null || safe_cmd dnsdomainname)
print_aligned "Domain" "${domain_name:-(none)}"

owner_for_display="${SUDO_USER:-}"
if [[ -z "$owner_for_display" ]]; then
    current_logname=$(logname 2>/dev/null || true)
    if [[ -n "$current_logname" ]]; then
        owner_for_display="$current_logname"
    else
        owner_for_display="$(whoami)"
    fi
fi
print_aligned "Primary Owner" "$owner_for_display"

sys_make_raw=$(safe_cmd dmidecode -s system-manufacturer)
sys_model_raw=$(safe_cmd dmidecode -s system-product-name)
sys_make=$(echo "$sys_make_raw" | grep -vE "To Be Filled|Not Applicable|Default string|System Manufacturer" || echo "$sys_make_raw")
sys_model=$(echo "$sys_model_raw" | grep -vE "To Be Filled|Not Applicable|Default string|System Product Name" || echo "$sys_model_raw")

# If grep made them empty because they *only* contained filtered strings, use empty.
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
    print_aligned "Make/Model" # Relies on (Unknown) default from print_aligned
fi

serial_num_raw=$(safe_cmd dmidecode -s system-serial-number)
serial_num=$(echo "$serial_num_raw" | grep -vE "Not Applicable|None|To Be Filled|Default string" || echo "$serial_num_raw")
if [[ "$serial_num_raw" =~ (Not Applicable|None|To Be Filled|Default string) ]]; then serial_num=""; fi
print_aligned "Serial Number" "${serial_num}"

print_aligned "BIOS Version" "$(safe_cmd dmidecode -s bios-version)"

mb_mfr_raw=$(safe_cmd dmidecode -s baseboard-manufacturer)
mb_prod_raw=$(safe_cmd dmidecode -s baseboard-product-name)
mb_mfr=$(echo "$mb_mfr_raw" | grep -vE "Not Applicable|To Be Filled|Default string" || echo "$mb_mfr_raw")
mb_prod=$(echo "$mb_prod_raw" | grep -vE "Not Applicable|To Be Filled|Default string" || echo "$mb_prod_raw")
if [[ "$mb_mfr_raw" =~ (Not Applicable|To Be Filled|Default string) ]]; then mb_mfr=""; fi
if [[ "$mb_prod_raw" =~ (Not Applicable|To Be Filled|Default string) ]]; then mb_prod=""; fi

mb_display=""
if [[ -n "$mb_mfr" ]] && [[ "$mb_mfr" == "$mb_prod" ]]; then
    mb_display="$mb_mfr"
elif [[ -n "$mb_mfr" ]] && [[ -n "$mb_prod" ]]; then
    mb_display="$mb_mfr $mb_prod"
elif [[ -n "$mb_mfr" ]]; then
    mb_display="$mb_mfr"
elif [[ -n "$mb_prod" ]]; then
    mb_display="$mb_prod"
fi
print_aligned "Motherboard" "${mb_display}"


# ----------------------
# CPU Information
# ----------------------
print_section "⚙️ CPU Information"
cpu_model=$(lscpu | awk -F: '/Model name/ {gsub(/^[ \t]+/, "", $2); print $2; exit}' || echo "Unknown CPU Model")
sockets=$(lscpu | awk -F: '/^Socket\(s\)/ {print $2}' | xargs)
cores_per_socket=$(lscpu | awk -F: '/^Core\(s\) per socket/ {print $2}' | xargs)
threads_per_core=$(lscpu | awk -F: '/Thread\(s\) per core/ {print $2}' | xargs)
total_physical_cores=$((sockets * cores_per_socket))
total_logical_processors=$(nproc)
numa_nodes=$(lscpu | awk -F: '/^NUMA node\(s\)/ {print $2}' | xargs)

print_aligned "CPU Model" "$cpu_model"
print_aligned "Sockets" "$sockets"
print_aligned "Core(s) per socket" "$cores_per_socket"
print_aligned "Thread(s) per core" "$threads_per_core"
print_aligned "Total Physical Cores" "$total_physical_cores"
print_aligned "Total Logical Processors" "$total_logical_processors"
print_aligned "NUMA Node(s)" "$numa_nodes"


# ----------------------
# Memory Information
# ----------------------
print_section "🧠 Memory Information"
print_aligned "Total Memory" "$(free -h | awk '/^Mem:/ {print $2}')"
print_aligned "Used Memory" "$(free -h | awk '/^Mem:/ {print $3}')"
print_aligned "Free Memory" "$(free -h | awk '/^Mem:/ {print $4}')"
if free -h | awk '/^Mem:/ {print $7}' &>/dev/null; then # Check if "available" field exists
    print_aligned "Available Memory" "$(free -h | awk '/^Mem:/ {print $7}')"
fi
echo # Add a blank line for spacing

if command -v dmidecode &>/dev/null; then
    if [[ $EUID -ne 0 ]]; then
        echo "  Information: Run as root to see detailed RAM stick/slot information (needs dmidecode)."
    else
        echo "  RAM Module Details (from dmidecode):"
        
        # Use awk to parse dmidecode output for Memory Devices (Type 17)
        # Each record (Memory Device block) is separated by blank lines.
        # Fields within a record are on separate lines.
        parsed_ram_info=$(sudo dmidecode -t memory | awk '
            # Function to trim leading/trailing whitespace
            function trim(s) {
                sub(/^[\s\t]+/, "", s);
                sub(/[\s\t]+$/, "", s);
                return s;
            }

            BEGIN { 
                RS = "\n\n"; # Records are separated by blank lines
                FS = "\n";   # Fields within a record are separated by newlines
            }

            # Process only "Memory Device" blocks
            /Memory Device/ {
                # Initialize fields for each device
                size = "N/A"; manufacturer = "N/A"; part_number = "N/A";
                type = "N/A"; speed = "N/A"; locator = "N/A";
                is_empty_flag = 0;

                for (i=1; i<=NF; i++) {
                    current_line = $i;
                    # Trim current_line for reliable matching
                    current_line = trim(current_line);

                    if (current_line ~ /^Size: No Module Installed$/) { 
                        is_empty_flag = 1; 
                        size = "Empty"; # Specific value for empty
                    } else if (current_line ~ /^Size: /) { 
                        size = current_line; sub(/^Size: /, "", size); 
                    }
                    
                    if (current_line ~ /^Manufacturer: /) { manufacturer = current_line; sub(/^Manufacturer: /, "", manufacturer); }
                    if (current_line ~ /^Part Number: /) { part_number = current_line; sub(/^Part Number: /, "", part_number); }
                    if (current_line ~ /^Type: /) { type = current_line; sub(/^Type: /, "", type); }
                    if (current_line ~ /^Speed: /) { speed = current_line; sub(/^Speed: /, "", speed); }
                    if (current_line ~ /^Locator: /) { locator = current_line; sub(/^Locator: /, "", locator); }
                }

                # Normalize common "Not Specified" or "Unknown" values from dmidecode for consistency
                if (manufacturer == "" || manufacturer == "Not Specified") manufacturer = "N/A";
                if (part_number == "" || part_number == "Not Specified") part_number = "N/A";
                if (type == "" || type == "Unknown" || type == "Not Specified") type = "N/A";
                if (speed == "" || speed == "Unknown" || speed == "Not Specified" || speed == "0 MT/s") speed = "N/A"; # 0 MT/s can mean unknown or not running
                if (locator == "" || locator == "Not Specified") locator = "N/A";
                if (size == "" || size == "Not Specified") size = "N/A"; # Should be "Empty" or a value if populated

                # Output CSV-like format: tag,locator,size,manufacturer,part_number,type,speed
                if (is_empty_flag) {
                    print "empty_slot," locator "," type; # For empty slots, type is what dmidecode says (often "Unknown")
                } else {
                    # Only print if size is not N/A (i.e., its a populated slot)
                    if (size != "N/A" && size != "Empty") {
                         print "populated_slot," locator "," size "," manufacturer "," part_number "," type "," speed;
                    }
                }
            }
        ')

        if [[ -z "$parsed_ram_info" ]]; then
            echo "    Could not parse detailed RAM information from dmidecode, or no memory devices reported."
        else
            populated_slots_count=0
            empty_slots_count=0
            populated_ram_details=""
            empty_ram_details=""
            declare -A installed_ram_types # Associative array to store types of installed RAM

            # Read through parsed info
            while IFS=',' read -r tag p_locator p_size p_manufacturer p_part_number p_type p_speed; do
                if [[ "$tag" == "populated_slot" ]]; then
                    populated_slots_count=$((populated_slots_count + 1))
                    detail_line="    Slot ${p_locator} ("
                    detail_line+="${p_size}"
                    if [[ "$p_manufacturer" != "N/A" ]]; then detail_line+=", ${p_manufacturer}"; fi
                    if [[ "$p_part_number" != "N/A" ]]; then detail_line+=", PN: ${p_part_number}"; fi
                    if [[ "$p_type" != "N/A" ]]; then
                        detail_line+=", Type: ${p_type}"
                        # Store type if it's specific (not N/A or Unknown)
                        if [[ "$p_type" != "N/A" && "$p_type" != "Unknown" ]]; then
                            installed_ram_types["$p_type"]=1
                        fi
                    fi
                    if [[ "$p_speed" != "N/A" ]]; then detail_line+=", Speed: ${p_speed}"; fi
                    detail_line+=")"
                    populated_ram_details+="${detail_line}\n"
                elif [[ "$tag" == "empty_slot" ]]; then
                    empty_slots_count=$((empty_slots_count + 1))
                    # For empty slots, p_size is the type field from awk
                    empty_ram_details+="    Slot ${p_locator} (Empty, Compatible Type: ${p_size})\n" # p_size here is actually the type from dmidecode for empty slot
                fi
            done <<< "$parsed_ram_info" # Use here-string

            if [[ $populated_slots_count -gt 0 ]]; then
                echo "  Populated RAM Modules:"
                printf "%b" "$populated_ram_details"
            else
                echo "  No populated RAM modules found by dmidecode (or details not parsable)."
            fi

            # Infer technology for empty slots if dmidecode reported "Unknown"
            inferred_empty_type="Unknown"
            if [[ ${#installed_ram_types[@]} -eq 1 ]]; then # If all populated RAM is of the same specific type
                for ram_type in "${!installed_ram_types[@]}"; do inferred_empty_type="$ram_type"; done
            elif [[ ${#installed_ram_types[@]} -gt 1 ]]; then
                types_list=$(printf "%s/" "${!installed_ram_types[@]}")
                inferred_empty_type="Mixed (e.g., ${types_list%/})" # e.g. DDR4/DDR5
            fi # Otherwise, it remains "Unknown" or whatever dmidecode said initially.

            if [[ $empty_slots_count -gt 0 ]]; then
                echo "  Empty RAM Slots:"
                # Re-iterate for empty slots to apply inferred type if needed
                 while IFS=',' read -r tag p_locator p_type_from_dmi; do # p_type_from_dmi is the 3rd field for empty_slot
                    if [[ "$tag" == "empty_slot" ]]; then
                        current_empty_tech="$p_type_from_dmi"
                        if [[ "$current_empty_tech" == "N/A" || "$current_empty_tech" == "Unknown" ]]; then
                            current_empty_tech="$inferred_empty_type (inferred)"
                        fi
                        printf "    Slot %s (Empty, Approx. Technology: %s)\n" "$p_locator" "$current_empty_tech"
                    fi
                done <<< "$parsed_ram_info"
            else
                echo "  No empty RAM slots found (or all slots appear populated)."
            fi
            echo # Blank line
            print_aligned "Detected Populated RAM Sticks" "$populated_slots_count"
            print_aligned "Detected Empty RAM Slots" "$empty_slots_count"
        fi
    fi
else
    echo "  Warning: dmidecode command not found. Cannot display detailed RAM stick/slot information."
fi

# ----------------------
# Display Information
# ----------------------
print_section "🖼️ Display Information"
gpu_cards=()
gpu_drivers=()
pci_ids=$( (lspci -nn | grep -i 'VGA compatible controller\|3D controller' | awk '{print $1}') || true )

if [ -n "$pci_ids" ]; then
    for id in $pci_ids; do
        card_desc_full=$( (lspci -vs "$id" | grep -E "^\S+.*\[[0-9a-f]{4}:[0-9a-f]{4}\]" | head -n1) || true )
        card_desc=$(echo "$card_desc_full" | sed -e "s/^\S\+\s\+//" -e "s/ (rev [0-9a-f][0-9a-f])//" -e "s/Corporation //" | awk -F'[' '{print $1}' | xargs)
        vendor_device=$(echo "$card_desc_full" | awk -F'[' '{print $2}' | cut -d']' -f1)

        if [ -z "$card_desc" ] && [ -n "$card_desc_full" ]; then # Only fallback if initial parse of card_desc_full failed
             # This fallback might not be needed if the first lspci -vs attempt is robust
             true # Placeholder, original fallback was fine if lspci -s is guarded
        elif [ -z "$card_desc" ]; then # If card_desc_full was empty from start or first parse failed
            card_desc_full=$(lspci -s "$id" || true) # Guarded lspci -s
            card_desc=$(echo "$card_desc_full" | sed -e "s/^\S\+\s\+//" -e "s/ (rev [0-9a-f][0-9a-f])//" -e "s/Corporation //" | awk -F'[' '{print $1}' | xargs)
            vendor_device=$(echo "$card_desc_full" | awk -F'[' '{print $2}' | cut -d']' -f1)
        fi

        display_text="$card_desc"
        if [[ -n "$vendor_device" ]]; then
            display_text+=" [$vendor_device]"
        fi

        if [[ -n "$card_desc" ]] && ! [[ "$card_desc" =~ "Unknown device" ]]; then
             if ! [[ " ${gpu_cards[*]} " =~ " ${display_text} " ]]; then # Avoid duplicates
                gpu_cards+=("$display_text")
            fi
        fi
        
        driver=$(lspci -ks "$id" | grep "Kernel driver in use:" | awk '{print $NF}' || true)
        if [ -n "$driver" ]; then
            if ! [[ " ${gpu_drivers[*]} " =~ " ${driver} " ]]; then # Avoid duplicates
                gpu_drivers+=("$driver")
            fi
        fi
    done
fi

if [ ${#gpu_drivers[@]} -eq 0 ]; then # Fallback if no drivers found via lspci -ks
    lsmod_drivers_output=$(lsmod | awk '/nvidia|amdgpu|i915|nouveau|radeon|vmwgfx/ {print $1}' | sort -u || true)
    if [ -n "$lsmod_drivers_output" ]; then
        while IFS= read -r drv; do
            if ! [[ " ${gpu_drivers[*]} " =~ " ${drv} " ]]; then # Avoid duplicates with already found ones
                 gpu_drivers+=("$drv (from lsmod)")
            fi
        done <<< "$lsmod_drivers_output"
    fi
fi

if [ ${#gpu_cards[@]} -gt 0 ]; then
    print_multiline_aligned "Display Card(s)" "${gpu_cards[@]}"
else
    print_aligned "Display Card(s)" "Unknown or N/A"
fi

if [ ${#gpu_drivers[@]} -gt 0 ]; then
    print_multiline_aligned "Display Driver(s)" "${gpu_drivers[@]}"
else
    print_aligned "Display Driver(s)" "Not found or N/A"
fi

session_id=$(loginctl list-sessions --no-legend | awk '/seat0/ {print $1; exit}' || true)
if [[ -n "$session_id" ]]; then
    session_type=$(loginctl show-session "$session_id" -p Type --value 2>/dev/null || echo "Unknown")
    desktop_env=$(loginctl show-session "$session_id" -p Desktop --value 2>/dev/null || echo "")
    print_aligned "Session Type" "$session_type"
    if [[ -n "$desktop_env" ]] && [[ "$desktop_env" != "-" ]]; then
      print_aligned "Desktop Environment" "$desktop_env"
    elif [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
      print_aligned "Desktop Environment" "${XDG_CURRENT_DESKTOP:-}"
    fi
else
    print_aligned "Active Session" "No active graphical session found via loginctl"
fi

X_SERVER=$(ps -e | grep -E 'xfce|mate|gnome|kde|cinnamon|lxde|openbox|fluxbox|i3')
echo "Display processes: $X_SERVER"


# ----------------------
# Storage Information
# ----------------------
print_section "💾 Storage Information"
echo "    Filesystem          Type   Size  Used Avail Use% Mounted on"
# Run df and capture its raw output, including stderr for debugging if needed (for manual run)
# The `2>/dev/null || true` makes it robust in script
df_raw_output=$(df -hT --output=source,fstype,size,used,avail,pcent,target \
                -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null || true)

# Check if df_raw_output has more than just a header line (or is not empty)
# A simple check: count lines. If > 1, there's data.
if [[ $(echo "$df_raw_output" | wc -l) -gt 1 ]]; then
    echo "$df_raw_output" | \
        awk 'NR==1 {next} {gsub(/\/dev\//, "", $1); printf "    %-19s %-6s %5s %5s %5s %4s %s\n", $1, $2, $3, $4, $5, $6, $7}'
else
    echo "    No persistent disk usage information found or applicable disks excluded."
fi


# ----------------------
# Network Information
# ----------------------
print_section "🌐 Network Information"
echo "    Interface  IP Address           MAC Address"
ip_br_addr_output=$(ip -br addr show 2>/dev/null || true)
if [[ -n "$ip_br_addr_output" ]]; then
    echo "$ip_br_addr_output" | awk '
    $1 != "lo" && NF >= 2 { # Basic check: not loopback and has at least iface and state
        iface = $1;
        state = $2;
        mac_addr = "N/A";
        ipv4_addr = "N/A";
        
        # Field 3 is MAC if it looks like one, otherwise IPs start at field 3
        # A MAC address has 5 colons.
        # Example with MAC: eth0 UP 00:11:22:33:44:55 192.168.1.2/24 ...
        # Example w/o MAC:  wg0  UP 10.0.0.1/24 ...
        
        ip_start_field = 3; # Default assumption: IPs start at field 3
        if (NF >=3 && $3 ~ /^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$/) {
            mac_addr = $3;
            ip_start_field = 4; # If field 3 was MAC, IPs start at field 4
        }

        # Find the first IPv4 address
        for (i = ip_start_field; i <= NF; i++) {
            if ($i ~ /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\//) {
                split($i, addr_parts, "/");
                ipv4_addr = addr_parts[1];
                break; 
            }
        }
        printf "    %-10s %-20s %s\n", iface, ipv4_addr, mac_addr;
    }'
else
    echo "    No active network interfaces found or \'ip\' command issue."
fi


# ----------------------
# System Configuration
# ----------------------
print_section "⚙️ System Configuration"
battery_path=$(upower -e | grep battery | head -n1 || true)
if [[ -n "$battery_path" ]]; then
    battery_percentage=$(upower -i "$battery_path" 2>/dev/null | awk -F': ' '/percentage/ {print $2}' | xargs || echo "N/A")
    battery_state=$(upower -i "$battery_path" 2>/dev/null | awk -F': ' '/state/ {print $2}' | xargs || echo "N/A")
    print_aligned "Battery" "${battery_percentage} (${battery_state})"
else
    print_aligned "Battery" "Not present or N/A"
fi

virt_type=$(systemd-detect-virt 2>/dev/null || echo "None detected")
print_aligned "Virtualization" "${virt_type}"

# ----------------------
# Software & Repositories
# ----------------------
print_section "📦 Software & Repositories"
echo "    APT Repository URLs (Suite, URL, Components):"
grep_output=$(grep -rhE '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null || true)
if [[ -n "$grep_output" ]]; then
    echo "$grep_output" | \
    awk '{
        url = $2; 
        suite = $3; 
        components = ""; 
        for (i=4; i<=NF; i++) components = components " " $i; 
        sub(/^[ \t]+/, "", components); 
        printf "        %-25s %s (%s)\n", suite, url, components
    }' | sort -u
else
    echo "        No repositories found or non-APT system."
fi

# ----------------------
# Mounted Remote Shares
# ----------------------
print_section "📡 Remote Shares (Mounted)"
mount_output=$(mount | grep -E 'type (nfs|cifs|smb3|sshfs)' || true)
if [[ -n "$mount_output" ]]; then
    echo "$mount_output" | awk '{printf "    %-30s on %-25s type %s (%s)\n", $1, $3, $5, $6}'
else
    echo "    (none)"
fi

# ----------------------
# NFS Exports (if configured)
# ----------------------
if [[ -f /etc/exports ]] && [[ -s /etc/exports ]]; then
    print_section "📂 NFS Exports (Configured)"
    grep -vE '^\s*#|^\s*$' /etc/exports | awk '{print "    " $0}' || echo "    (No active exports or error reading)"
else
    print_section "📂 NFS Exports (Configured)"
    echo "    (/etc/exports not found or empty)"
fi

# ----------------------
# Samba Shares (if configured)
# ----------------------
if command -v testparm &>/dev/null && [[ -f /etc/samba/smb.conf ]]; then
    print_section "🗂️ Samba Shares (Configured)"
    # Corrected testparm command:
    # 1. Use 'testparm -s' to dump all service definitions.
    # 2. Extract section names (without brackets) using grep -Po.
    # 3. Filter out 'global', 'homes', and 'printers' sections.
    # 4. Format the output similarly to the elif branch.
    testparm_output=$(testparm -s 2>/dev/null | grep -Po '^\[\K[^]]+(?=\])' | grep -vE '^(global|homes|printers)$' | sed 's/^/   [ /; s/$/ ]/' || true)
    if [[ -n "$testparm_output" ]]; then
        echo "$testparm_output"
    else
        echo "   (No custom shares defined or error reading smb.conf with testparm)" # Modified message for clarity
    fi
elif [[ -f /etc/samba/smb.conf ]]; then
    print_section "🗂️ Samba Shares (Configured)"
    # This part remains the same
    samba_shares=$(grep -Po '^\s*\[\K[^]]+(?=\])' /etc/samba/smb.conf | grep -vE 'global|homes|printers' | sed 's/^/   [ /; s/$/ ]/' || true)
    if [[ -n "$samba_shares" ]]; then
        echo "$samba_shares"
    else
        echo "   (No custom shares found in smb.conf, or 'testparm' not available)" # Modified message for clarity
    fi
else
    print_section "🗂️ Samba Shares (Configured)" # Note: title says "Configured" even if not found. Consider "Samba Status".
    echo "   (Samba not configured or smb.conf not found)"
fi

echo
echo "System information has been saved to: $OUT_FILE"

exit 0
