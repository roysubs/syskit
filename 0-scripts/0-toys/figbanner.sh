#!/bin/bash
# Author: Roy Wiseman 2025-05

# Function to create a RGB color bar gradient to test terminal color support
RGB() {
    awk 'BEGIN{
        s="          ";
        s=s s s s s s s s;
        for (colnum = 0; colnum<77; colnum++) {
            r = 255-(colnum*255/76);
            g = (colnum*510/76);
            b = (colnum*255/76);
            if (g>255) g = 510-g;
            printf "\033[48;2;%d;%d;%dm", r,g,b;
            printf "\033[38;2;%d;%d;%dm", 255-r,255-g,255-b;
            printf "%s\033[0m", substr(s,colnum+1,1);
        }
        printf " ";
    }'
    # Removed redundant detect_colors call from inside RGB function definition
}

# Detect terminal color capabilities
detect_colors() {
    local colors=0
    if [ -t 1 ]; then  # Check if stdout is a terminal
        if tput colors &>/dev/null; then
            colors=$(tput colors)
        fi
        if [ "$COLORTERM" = "truecolor" ] || [ "$COLORTERM" = "24bit" ]; then
            printf ": \e[1m24-bit True Color\e[0m (16.7 million colors)\n"
        elif [ "$colors" -ge 256 ]; then
            printf ": \e[1m8-bit\e[0m (256 colors)\n"
        elif [ "$colors" -ge 16 ]; then
            printf ": \e[1m4-bit\e[0m (16 colors)\n"
        elif [ "$colors" -ge 8 ]; then
            printf ": \e[1m3-bit\e[0m (8 colors)\n"
        else
            printf ": \e[1mBasic\e[0m ($(( colors )) colors)\n"
        fi
    else
        printf ": \e[1mNot detected\e[0m (not a terminal)\n"
    fi
}


# Function to detect system distribution/version
ver() {
    local RELEASE="Linux"
    [ -f /etc/os-release ] && RELEASE=$(grep -E "^PRETTY_NAME=" /etc/os-release | sed 's/PRETTY_NAME=//;s/"//g')
    [ -f /etc/redhat-release ] && RELEASE=$(cat /etc/redhat-release)
    [ -f /etc/lsb-release ] && RELEASE="$(grep DESCRIPTION /etc/lsb-release | sed 's/^.*=//g' | sed 's/\"//g')"
    [ -f /etc/debian_version ] && RELEASE="Debian $(cat /etc/debian_version)"
    [ -f /etc/alpine-release ] && RELEASE="Alpine $(cat /etc/alpine-release)"
    printf "\e[33m$RELEASE\e[00m: $(uname -msr)\n"
}

# Function to display system info
sys() {
    awk -F": " '
        FNR==NR { # Process /proc/cpuinfo first
            if (/^model name/) { mod=$2 }
            if (/^cpu MHz/) { mhz=$2 }
            if (/^cpu core/) { core=$2 }
            if (/^flags/) {
                virt="No Virtualisation";
                match($0,"svm");
                if (RSTART!=0) { virt="SVM-Virtualisation" };
                match($0,"vmx");
                if (RSTART!=0) { virt="VMX-Virtualisation" }
            }
            next # Move to the next line in the first file
        }
        # Process the output of free -mh second
        /Mem:/ {
            split($2,arr," ");
            tot=arr[1]; # Total memory
            free=arr[3] # Corrected: Use the 'free' column from free -mh
            used_calc = arr[2]; # Store 'used' for memory calculation
        }
        END {
            # Recalculating Used memory based on total and free from free -mh
            # The original script used $2 as total and $3 as used (which seems to be correct based on free -mh output)
            # Reverting the awk part back to align with original intent and free -mh output
            printf "%s, %.0fMHz, %s core(s), %s, %s Memory (%s Used)\n",
            mod, mhz, core, virt, tot, used_calc # Use used_calc from free -mh output
        }' /proc/cpuinfo <(free -mh | awk 'NR==2 {print $0}') # Pass only the second line of free -mh

    # Fix: Trim trailing whitespace from hostname -I output before adding comma
    local ips=$(hostname -I | sed 's/ *$//')
    local up=$(uptime)
    shopt -s extglob  # enable extended globbing
    up="${up##+( )} (1 min, 5 min, 15 min, ave per core)"

    # Only add comma if there are IPs
    if [ -n "$ips" ]; then
        printf "%s\n%s" "$ips" "$up"
    else
        printf "%s" "$up"
    fi
}

# Alternative system function for Alpine Linux
type apk &> /dev/null && sys() {
    awk -F": " '
        FNR==NR { # Process /proc/cpuinfo first
            if (/^model name/) { mod=$2 }
            if (/^cpu MHz/) { mhz=$2 }
            if (/^cpu core/) { core=$2 }
            if (/^flags/) {
                virt="No Virtualisation";
                match($0,"svm");
                if (RSTART!=0) { virt="SVM-Virtualisation" };
                match($0,"vmx");
                if (RSTART!=0) { virt="VMX-Virtualisation" }
            }
            next # Move to the next line in the first file
        }
        # Process the output of free -mh second
        /Mem:/ {
             split($2,arr," "); # Assuming the second field of free -mh is the total memory
             tot=arr[1]; # Total
             free=arr[3] # Free
             used_calc = arr[2]; # Used
        }
        END {
            printf "%s, %.0fMHz, %s core(s), %s, %s Memory (%s Used)\n",
            mod, mhz, core, virt, tot, used_calc
        }' /proc/cpuinfo <(free -mh | awk 'NR==2 {print $0}')

    # Alpine uses ifconfig, need to adapt the IP extraction and comma logic
    local ips=$(ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | sed 'H;1h;$!d;x;y/\n/,/g')
    local up=$(uptime)

    # Only add comma if there are non-localhost IPs
    if [ -n "$(echo "$ips" | sed 's/,//g' | xargs)" ]; then # Check if the comma-separated string is not just empty or commas/spaces
        printf "%s, %s\n" "$ips" "$up"
    else
         # If no IPs were found (other than localhost filtered out), just print uptime
         printf "%s\n" "$up"
    fi
}

# Function to display figlet date and time
type figlet &> /dev/null && fignow() {
    printf "\e[33m$(figlet -w -t -f /usr/share/figlet/small.flf $(date +"%a, %d %b, wk%V"))"

    if [ -f /usr/share/figlet/univers.flf ]; then
        local opts="-f /usr/share/figlet/univers.flf"
    else
        local opts="-f /usr/share/figlet/big.flf"
    fi

    printf "\n\e[94m$(figlet -t $opts $(date +"%H:%M"))\e[00m\n"
}

# Function to display interactive clock with system info
type figlet &> /dev/null && figclock() {
    while [ 1 ]; do
        clear
        printf "\e[33m"
        df -kh 2> /dev/null
        printf "\e[31m\n"
        top -n 1 -b | head -11
        printf "\e[33m$(figlet -w -t -f small $(date +"%b %d, week %V"))\n"

        font=$(figrandom 2>/dev/null || echo "big")
        printf "Font: %s\n\e[94m%s\e[00m\n" "$font" "$(figlet -w -t -f "$font" $(date +"%H:%M:%S"))" # Fixed printf format here
        printf "\e[35m5 second intervals, Ctrl-C to quit.\e[00m"

        sleep 3
    done
}

# Random module to show weather information
weather() {
    if type curl >/dev/null 2>&1; then
        printf "\e[36mWeather: \e[0m"
        curl -s "wttr.in/$(curl -s ipinfo.io/city 2>/dev/null)?format=3" 2>/dev/null || echo "Weather service unavailable"
        printf "\n"
    fi
}

# Docker containers status module
docker_info() {
    if type docker >/dev/null 2>&1; then
        # Get running containers count
        local running=$(docker ps -q 2>/dev/null | wc -l)

        # Get stopped containers count
        local stopped=$(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l)

        # Get images count
        local images=$(docker images -q 2>/dev/null | wc -l)

        # Calculate container sizes
        local running_size="0"
        if [ "$running" -gt 0 ]; then
            running_size=$(docker ps --format '{{.Size}}' 2>/dev/null | awk '{
                # Remove characters like G, M, k, B from the end for calculation
                size = $1;
                unit = substr(size, length(size), 1);
                value = substr(size, 1, length(size)-1);
                # Convert everything to GB for summation
                if (unit == "B") { sum += value / 1024 / 1024 / 1024; }
                else if (unit == "k") { sum += value / 1024 / 1024; }
                else if (unit == "M") { sum += value / 1024; }
                else if (unit == "G") { sum += value; }
                # If no unit, assume bytes or handle appropriately
                else { sum += value; }
            } END { printf "%.1fGB", sum }')
        fi

        # Calculate total image size
        local image_size="0"
        if [ "$images" -gt 0 ]; then
            image_size=$(docker images --format "{{.Size}}" 2>/dev/null | awk '{
                # Remove characters like GB, MB, kB, B from the size string
                size_str = $0;
                gsub(/GB|MB|kB|B/, "", size_str);

                value = size_str;

                # Convert to GB based on the original unit
                if (index($0, "MB") > 0) { sum += value / 1024; }
                else if (index($0, "GB") > 0) { sum += value; }
                else if (index($0, "kB") > 0) { sum += value / 1024 / 1024; }
                 else if (index($0, "B") > 0) { sum += value / 1024 / 1024 / 1024; } # Bytes
                else { sum += value; }
            } END { printf "%.1fGB", sum }')
        fi

        printf "\e[35mDocker: \e[0m%s Running Container" "$running" # Use %s for variables
        [ "$running" -ne 1 ] && printf "s"
        [ "$running" -gt 0 ] && printf " (%s)" "$running_size" # Use %s for variables

        printf ", %s Stopped" "$stopped" # Use %s for variables
        [ "$stopped" -ne 1 ] && printf " Containers"
        [ "$stopped" -eq 1 ] && printf " Container"

        printf ", %s Image" "$images" # Use %s for variables
        [ "$images" -ne 1 ] && printf "s"
        [ "$images" -gt 0 ] && printf " (%s)" "$image_size" # Use %s for variables
        printf "\n"
    fi
}

# System load indicator with color coding
system_load() {
    local load=$(cat /proc/loadavg | cut -d' ' -f1)
    local cores=$(grep -c ^processor /proc/cpuinfo)
    local load_per_core="N/A"
    if [ "$cores" -gt 0 ]; then
      load_per_core=$(awk "BEGIN {printf \"%.2f\", $load / $cores}")
    fi

    printf "Load: "
    if [ -n "$load_per_core" ] && [ "$load_per_core" != "N/A" ]; then
      # Use printf with format specifiers for variables
      if (( $(echo "$load_per_core < 0.7" | bc -l) )); then
          printf "\e[32m%s\e[0m" "$load"  # Green for low load
      elif (( $(echo "$load_per_core < 1.0" | bc -l) )); then
          printf "\e[33m%s\e[0m" "$load"  # Yellow for medium load
      else
          printf "\e[31m%s\e[0m" "$load"  # Red for high load
      fi
      printf " (%s/core)\n" "$load_per_core"
    else
      printf "%s (N/A / core)\n" "$load" # Handle case where load_per_core couldn't be calculated
    fi
}


# Function to display disk usage summary
# Function to display disk usage summary
disk_status() {
    printf "\e[33mDisk Usage: \e[0m"

    # Get partition list from lsblk, skip empty lines and filter real partitions
    local partitions
    partitions=$(lsblk -o NAME,MOUNTPOINT,SIZE,FSUSE% -n -r |
        grep -vE 'loop|ram|squashfs|^$' |
        awk 'NF >= 3 {print}')

    local output=""
    local root_part=""

    while IFS= read -r line; do
        local name mount size usage

        name=$(awk '{print $1}' <<< "$line")
        mount=$(awk '{print $2}' <<< "$line")
        size=$(awk '{print $3}' <<< "$line")
        usage=$(awk '{print $4}' <<< "$line")

        # Skip if size is 1K (e.g. sda2 protective partitions)
        [[ "$size" == "1K" ]] && continue

        # Skip if not a partition (assume partition names end in digit, e.g. sda1)
        [[ ! "$name" =~ [0-9]$ ]] && continue

        # Format: only show mountpoint for root (/), hide others
        if [[ "$mount" == "/" ]]; then
            root_part="${name}(${mount}) ${size} (${usage})"
        else
            # Don't show "(mount)" for non-root
            local formatted="${name} ${size} (${usage})"
            output+="${output:+, }$formatted"
        fi
    done <<< "$partitions"

    # Print in desired order: root first
    if [[ -n "$root_part" ]]; then
        printf "%s" "$root_part"
        [[ -n "$output" ]] && printf ", %s" "$output"
    else
        printf "%s" "$output"
    fi

    printf "\n"
}

# Function to display main login banner
login_banner() {
    # Define the modules to show (set to 1 to enable, 0 to disable)
    SHOW_COLOR_BAR=${SHOW_COLOR_BAR:-1}
    SHOW_SYSTEM_INFO=${SHOW_SYSTEM_INFO:-1}
    SHOW_WEATHER=${SHOW_WEATHER:-0} # Set to 1 to enable weather
    SHOW_DOCKER=${SHOW_DOCKER:-0} # Set to 1 to enable docker info
    SHOW_LOAD=${SHOW_LOAD:-1}
    SHOW_DISK=${SHOW_DISK:-1}

    # Display the banner with enabled modules
    printf "\n"
    [ "$SHOW_COLOR_BAR" = "1" ] && RGB
    detect_colors   # Shows the colors supported by terminal

    [ "$SHOW_SYSTEM_INFO" = "1" ] && printf "%s : %s\n%s\n" "$(ver)" "$(date +"%Y-%m-%d, %H:%M:%S, %A, Week %V")" "$(sys)" # Use %s for variables
    [ "$SHOW_WEATHER" = "1" ] && weather
    [ "$SHOW_DOCKER" = "1" ] && docker_info
#    [ "$SHOW_LOAD" = "1" ] && system_load
    [ "$SHOW_DISK" = "1" ] && disk_status

    # Show figlet banner if available
    type figlet >/dev/null 2>&1 && fignow
}

# Only display login banner if not in a tmux session
[ -z "$TMUX" ] && login_banner

# Uncomment to always start tmux at login (but skip when already in tmux)
# [ -z "$TMUX" ] && export TERM=xterm-256color && exec tmux

# Uncomment to prompt for tmux startup
# if [ -z "$TMUX" ]; then
#     read -p "Run tmux? (y/n) " -n 1 -r
#     echo
#     if [[ $REPLY =~ ^[Yy]$ ]]; then
#         exec tmux new-session -A -s main
#     fi
# fi
