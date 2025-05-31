#!/bin/bash
# Author: Roy Wiseman 2025-02

# Script to analyze a process by PID or search string
# Version: 1.2 (ss fix integrated)

# Colors for output
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'
C_WHITE='\033[0;37m'
C_BOLD='\033[1m'
C_RESET='\033[0m'

print_header() {
    echo -e "\n${C_BOLD}${C_BLUE}>>> $1${C_RESET}"
}

# Helper function to print the command being run
print_command() {
    local description="$1"
    local cmd_string="$2"
    echo -e "${C_GREEN}# $description: ${C_BOLD}$cmd_string${C_RESET}"
}

analyze_pid() {
    local pid="$1"
    local exe_target="" # Store the resolved executable path

    if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
        echo -e "${C_RED}Error: '$pid' is not a valid PID format.${C_RESET}"
        return 1
    fi
    if [ ! -d "/proc/$pid" ]; then
        echo -e "${C_RED}Error: Process with PID '$pid' does not exist.${C_RESET}"
        return 1
    fi

    echo -e "${C_BOLD}${C_GREEN}Analyzing Process ID (PID): $pid${C_RESET}"
    echo "--------------------------------------------------"

    # --- Process Command & Owner ---
    print_header "Process Information (from ps)"
    local ps_user
    local ps_cmd="ps -p \"$pid\" -o user:20,ppid,ni,%cpu,%mem,stat,etime,args --no-headers"
    print_command "Getting process details" "$ps_cmd"
    local ps_info
    ps_info=$(ps -p "$pid" -o user:20,ppid,ni,%cpu,%mem,stat,etime,args --no-headers)
    if [ -z "$ps_info" ]; then
        echo -e "${C_YELLOW}Could not retrieve basic process info for PID $pid. It might have terminated.${C_RESET}"
        local stat_cmd="stat -c '%U' \"/proc/$pid\""
        print_command "Attempting to get user via stat" "$stat_cmd"
        ps_user=$(stat -c '%U' "/proc/$pid" 2>/dev/null || echo "unknown")
    else
        echo -e "${C_CYAN}USER                  PPID  NI %CPU %MEM STAT  ELAPSED   COMMAND${C_RESET}" # Adjusted header for alignment
        echo "$ps_info"
        ps_user=$(echo "$ps_info" | awk '{print $1}')
    fi
    echo "Process User (from ps or stat): $ps_user"


    # --- Executable Path ---
    print_header "Executable Path"
    local exe_symlink_path="/proc/$pid/exe"
    if [ -L "$exe_symlink_path" ]; then
        local ls_cmd="sudo ls -ld \"$exe_symlink_path\""
        print_command "Getting symlink information" "$ls_cmd"
        sudo ls -ld "$exe_symlink_path" # Let ls print directly, including its own errors/formatting

        local readlink_cmd="sudo readlink -f \"$exe_symlink_path\""
        print_command "Resolving symlink target" "$readlink_cmd"
        exe_target=$(sudo readlink -f "$exe_symlink_path" 2>/dev/null)

        if [ -n "$exe_target" ]; then
            echo "Target:  $exe_target"
            if [[ "$exe_target" == *"(deleted)"* ]]; then
                echo -e "${C_YELLOW}Note: The executable appears to have been deleted from disk.${C_RESET}"
            fi
            if [[ "$exe_target" == /snap/* ]]; then
                echo -e "${C_GREEN}This process appears to be running from a Snap package.${C_RESET}"
                local snap_name
                snap_name=$(echo "$exe_target" | cut -d'/' -f3)
                local snap_info_cmd="snap info \"$snap_name\""
                if command -v snap >/dev/null && snap list "$snap_name" &>/dev/null; then # Check if snap exists before querying
                    print_command "Getting Snap package info" "$snap_info_cmd"
                    snap info "$snap_name"
                fi
            fi
        else
            echo -e "${C_YELLOW}Could not resolve target of $exe_symlink_path. (Often indicates a kernel thread or permission issue).${C_RESET}"
        fi
    else
        echo -e "${C_YELLOW}No symbolic link at $exe_symlink_path.${C_RESET}"
        local cmdline_content comm_name
        print_command "Reading command line from /proc" "cat \"/proc/$pid/cmdline\" | tr -d '\\0' | sed 's/$/ /'" # Added sed for trailing space for readability
        cmdline_content=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' | sed 's/ $//') # Use space separator, remove trailing
        print_command "Reading command name from /proc" "cat \"/proc/$pid/comm\""
        comm_name=$(cat "/proc/$pid/comm" 2>/dev/null)
        
        # More robust kernel thread check based on cmdline being empty and comm being [name]
        if [ -z "$cmdline_content" ] && [[ "$comm_name" == "["*"]" ]]; then
            echo -e "${C_GREEN}Confirmed: This is a kernel thread (command: $comm_name).${C_RESET}"
            exe_target="KERNEL_THREAD"
        else
            echo -e "${C_YELLOW}Further investigation needed if this is not a kernel thread (e.g., a very short-lived process or unusual setup).${C_RESET}"
            echo "Command line from /proc/$pid/cmdline: '$cmdline_content'"
            echo "Command name from /proc/$pid/comm: '$comm_name'"
        fi
    fi

    if [[ "$exe_target" == "KERNEL_THREAD" ]]; then
        echo -e "${C_MAGENTA}Skipping Systemd, CGroup, Network, Files, and Env checks for kernel thread.${C_RESET}"
    else
        # --- Systemd Service Status ---
        print_header "Systemd Service Status"
        local systemctl_cmd="sudo systemctl status \"$pid\""
        print_command "Checking systemd status for PID" "$systemctl_cmd"
        local systemctl_output
        systemctl_output=$(sudo systemctl status "$pid" 2>&1) # Capture stderr too
        local first_line_systemctl
        first_line_systemctl=$(echo "$systemctl_output" | head -n 1)

        if echo "$systemctl_output" | grep -qE "could not be found|Failed to get properties|Unit not found"; then # Added "Unit not found"
            echo -e "${C_YELLOW}PID $pid does not correspond to a systemd service unit directly.${C_RESET}"
        elif echo "$first_line_systemctl" | grep -q "^● $pid "; then # PID is part of a unit but not the main one listed first
            echo -e "${C_YELLOW}PID $pid is part of a service unit, but not its main PID (systemd provides generic process info):${C_RESET}"
            echo "$systemctl_output"
        elif [[ "$pid" == "1" ]] && echo "$first_line_systemctl" | grep -q "^● systemd"; then # Special case for PID 1
            echo "$systemctl_output"
        elif echo "$first_line_systemctl" | grep -q "^●.*\.service"; then # Starts with ● and .service, likely a service
            echo "$systemctl_output"
        else
            echo -e "${C_YELLOW}Systemd status for PID $pid is inconclusive or shows it's not a primary service PID.${C_RESET}"
            echo "$systemctl_output" | head -n 7 # Show a bit more for context
        fi

        # --- CGroups (useful for containers) ---
        print_header "Control Groups (CGroups)"
        local cgroup_path="/proc/$pid/cgroup"
        if [ -f "$cgroup_path" ]; then
            print_command "Reading cgroup info" "cat \"$cgroup_path\""
            local cgroup_content
            cgroup_content=$(cat "$cgroup_path")
            echo "$cgroup_content"
            if echo "$cgroup_content" | grep -qE '/docker/|/kubepods/|/lxc/|/machine\.slice/'; then
                echo -e "${C_GREEN}Process appears to be running inside a container or VM (based on cgroup path).${C_RESET}"
                if command -v docker &> /dev/null && echo "$cgroup_content" | grep -q '/docker/'; then
                    local docker_container_id
                    # Try to get full 64-char ID first
                    docker_container_id=$(echo "$cgroup_content" | grep -oP 'docker[/-]\K[0-9a-fA-F]{64}' | head -n 1)
                    if [ -z "$docker_container_id" ]; then
                         # Fallback to more general extraction if full ID not found or different format
                        docker_container_id=$(echo "$cgroup_content" | grep '/docker/' | head -n 1 | sed -e 's|.*/docker/||' -e 's|.*/docker-||' -e 's/\.scope$//' -e 's/\.service$//' | awk -F'.' '{print $1}')
                    fi

                    if [ -n "$docker_container_id" ]; then
                        print_header "Attempting Docker Inspect (deduced ID/Name: $docker_container_id)"
                        local docker_inspect_cmd="sudo docker inspect \"$docker_container_id\""
                        print_command "Inspecting Docker container" "$docker_inspect_cmd"
                        # Check if it's a known container ID (long or short) or name
                        if sudo docker ps -q --no-trunc | grep -q "^${docker_container_id:0:12}" || \
                           sudo docker ps -a --format '{{.Names}}' | grep -qw "^${docker_container_id}$" ; then
                            sudo docker inspect "$docker_container_id"
                        else
                            echo -e "${C_YELLOW}Deduced ID/Name '$docker_container_id' not found among running or all Docker containers. Skipping docker inspect.${C_RESET}"
                        fi
                    else
                        echo -e "${C_YELLOW}Could not deduce Docker container ID from cgroup info.${C_RESET}"
                    fi
                fi
            fi
        else
            echo -e "${C_YELLOW}Cannot read $cgroup_path.${C_RESET}"
        fi

        # --- Network Connections ---
        print_header "Network Connections (Listening TCP/UDP)"
        local found_ports=0
        if command -v ss >/dev/null; then
            # --- SS FIX INTEGRATED HERE ---
            local ss_listen_cmd="sudo ss -tulpn -p | grep \"pid=$pid[,)]\""
            print_command "Checking listening ports with ss and grep" "$ss_listen_cmd"
            local listening_ports
            # Capture stderr from ss to a variable to check if ss itself fails, grep won't see that
            listening_ports=$(sudo ss -tulpn -p 2>/dev/null | grep "pid=$pid[,)]")
            # --- END SS FIX ---
            if [ -n "$listening_ports" ]; then
                echo "Listening (ss -p | grep):"
                echo "$listening_ports"
                found_ports=1
            fi
        elif command -v lsof >/dev/null; then
            echo -e "${C_YELLOW}ss command not found, trying lsof (may be slower)...${C_RESET}"
            local lsof_listen_cmd="sudo lsof -nP -p \"$pid\" -iTCP -sTCP:LISTEN -iUDP"
            print_command "Checking listening ports with lsof" "$lsof_listen_cmd"
            local lsof_listen
            lsof_listen=$(sudo lsof -nP -p "$pid" -iTCP -sTCP:LISTEN -iUDP 2>/dev/null | grep -E "(LISTEN|UDP)")
            if [ -n "$lsof_listen" ]; then
                echo "Listening (lsof):"
                echo "$lsof_listen"
                found_ports=1
            fi
        else
             echo -e "${C_YELLOW}Neither 'ss' nor 'lsof' command found. Cannot display listening ports.${C_RESET}"
        fi
        if [ "$found_ports" -eq 0 ]; then
             echo "No listening TCP/UDP ports found for this process (or process is not listening, or sudo access issues with underlying tools)."
        fi

        print_header "Established Network Connections (TCP)"
        local found_established=0
        if command -v ss >/dev/null; then
            # --- SS FIX INTEGRATED HERE ---
            local ss_est_cmd="sudo ss -tpn -p state established | grep \"pid=$pid[,)]\""
            print_command "Checking established TCP connections with ss and grep" "$ss_est_cmd"
            local established_conns
            established_conns=$(sudo ss -tpn -p state established 2>/dev/null | grep "pid=$pid[,)]")
            # --- END SS FIX ---
            if [ -n "$established_conns" ]; then
                echo "Established (ss -p | grep):"
                echo "$established_conns"
                found_established=1
            fi
        elif command -v lsof >/dev/null; then
            echo -e "${C_YELLOW}ss command not found, trying lsof for established connections...${C_RESET}"
            local lsof_est_cmd="sudo lsof -nP -p \"$pid\" -iTCP -sTCP:ESTABLISHED"
            print_command "Checking established TCP connections with lsof" "$lsof_est_cmd"
            local lsof_established
            lsof_established=$(sudo lsof -nP -p "$pid" -iTCP -sTCP:ESTABLISHED 2>/dev/null)
            if [ -n "$lsof_established" ]; then
                echo "Established (lsof):"
                echo "$lsof_established"
                found_established=1
            fi
        fi
         if [ "$found_established" -eq 0 ]; then
            echo "No established TCP connections found for this process (or process has none, or sudo access issues)."
        fi

        # --- Open Files (Summary) ---
        print_header "Open Files Summary"
        if command -v lsof >/dev/null; then
            local lsof_count_cmd="sudo lsof -nP -p \"$pid\" | wc -l"
            print_command "Counting open files (approximate)" "$lsof_count_cmd (lsof can be slow)"
            local open_files_count
            open_files_count=$(sudo lsof -nP -p "$pid" 2>/dev/null | wc -l)
            local lsof_exit_status=$?

            if [ "$lsof_exit_status" -eq 0 ] && [ "$open_files_count" -gt 1 ]; then # lsof usually has at least 1 line (header)
                echo "Process has approximately $((open_files_count - 1)) open file descriptors (lsof output lines - 1 for header)."
                local lsof_sample_cmd="sudo lsof -nP -p \"$pid\" | head -n 10"
                print_command "Sample of open files (first 10 lines from lsof)" "$lsof_sample_cmd"
                sudo lsof -nP -p "$pid" 2>/dev/null | head -n 10
                echo "Use 'sudo lsof -nP -p $pid' for a full, unfiltered list." # Added -nP to suggested command
            elif [ "$lsof_exit_status" -ne 0 ]; then
                 echo -e "${C_RED}lsof command failed for PID $pid (Exit status: $lsof_exit_status).${C_RESET}"
            else # count is 0 or 1 (just header), or lsof succeeded but found nothing
                 echo "No open files found by lsof, process has very few, or process terminated during check."
            fi
        else
            echo -e "${C_YELLOW}'lsof' command not found. Cannot display open files summary.${C_RESET}"
        fi

        # --- Environment (first few variables) ---
        print_header "Environment Variables (Sample - first 5 valid-looking)"
        local environ_path="/proc/$pid/environ"
        if [ -e "$environ_path" ]; then # Check if file exists first
            local cat_env_cmd_base
            local env_strings
            local valid_env_output

            # Determine if sudo is needed to read the raw environ file
            if [ -r "$environ_path" ]; then
                cat_env_cmd_base="cat \"$environ_path\" | tr '\\0' '\\n'"
                # print_command "Reading all environment strings" "$cat_env_cmd_base" # Can be verbose
                env_strings=$(cat "$environ_path" 2>/dev/null | tr '\0' '\n')
            else
                cat_env_cmd_base="sudo cat \"$environ_path\" | tr '\\0' '\\n'"
                # print_command "Reading all environment strings (requires sudo)" "$cat_env_cmd_base" # Can be verbose
                env_strings=$(sudo cat "$environ_path" 2>/dev/null | tr '\0' '\n')
            fi

            if [ -n "$env_strings" ] || [ -z "$env_strings" ]; then # Process even if env_strings is empty to give feedback
                # Filter for lines containing '=' but not starting with '='.
                # This is a basic heuristic for KEY=VALUE.
                local filter_cmd_display="echo \"<strings>\" | grep '=' | grep -Ev '^=' | head -n 5"
                print_command "Filtering for KEY=VALUE format and taking first 5" "$filter_cmd_display"

                # Handle potentially empty env_strings before grep to avoid grep error on empty input if shell behaves that way
                if [ -n "$env_strings" ]; then
                    valid_env_output=$(echo "$env_strings" | grep '=' | grep -Ev '^=' | head -n 5)
                else
                    valid_env_output="" # Ensure it's empty if env_strings was empty
                fi

                if [ -n "$valid_env_output" ]; then
                    echo "$valid_env_output"
                    local full_list_cmd_base # For the "Use..." message
                    if [ -r "$environ_path" ]; then
                        full_list_cmd_base="cat $environ_path | tr '\\0' '\\n'"
                    else
                        full_list_cmd_base="sudo cat $environ_path | tr '\\0' '\\n'"
                    fi
                    echo "Use '$full_list_cmd_base | grep '=' | grep -Ev \"^=\"' for full list of valid-looking variables."
                else
                    echo -e "${C_YELLOW}No valid-looking (KEY=VALUE) environment variables found.${C_RESET}"
                    # Show the raw first string if no valid ones were found but some string existed
                    if [ -n "$env_strings" ]; then
                         local first_raw_string
                         first_raw_string=$(echo "$env_strings" | head -n 1)
                         echo -e "${C_MAGENTA}Raw first string from environ file: \"$first_raw_string\"${C_RESET}"
                    fi
                fi
            else
                # This case should ideally be caught by the file existence check or if env_strings remains truly unset
                echo -e "${C_YELLOW}Could not read environment variables, file is empty, or process is gone.${C_RESET}"
            fi
        else
            echo -e "${C_YELLOW}Environment file $environ_path does not exist. (Process likely terminated).${C_RESET}"
        fi
    fi

    echo "--------------------------------------------------"
    echo -e "${C_BOLD}${C_GREEN}Analysis for PID $pid complete.${C_RESET}"
}

find_and_analyze_string() {
    local search_string="$1"
    print_header "Searching for processes matching: '$search_string'"

    # Exclude this script itself and the grep command from ps output
    local self_pid="$$"
    local script_name_pattern
    script_name_pattern=$(basename "$0")
    # Need to be careful with grep -F and variable search_string if it contains meta-chars for grep -v E
    # Using awk for more robust exclusion
    local ps_pipeline_desc="ps aux (then awk to keep ssh but remove self_pid and ${0##*/} references)"
    print_command "Filtering processes with ps and awk" "$ps_pipeline_desc"
    
    local ps_output
    ps_output=$(ps aux | awk -v s="$search_string" -v self="$self_pid" -v script="$script_name_pattern" '
        BEGIN{IGNORECASE=1} # Case-insensitive search for the string
        $0 ~ s { # If line matches search_string
            # Exclude self, script name, typical grep, and this awk command itself
            if ($2 == self || $0 ~ script || $0 ~ "grep -F -- " || $0 ~ " awk -v s=") {
                next;
            }
            print; # Print matching line
        }')


    if [ -z "$ps_output" ]; then
        echo -e "${C_YELLOW}No running processes found matching '$search_string' (excluding this script/grep/awk).${C_RESET}"
        return
    fi

    local num_found
    num_found=$(echo "$ps_output" | wc -l)

    if [ "$num_found" -eq 1 ]; then
        local found_pid
        found_pid=$(echo "$ps_output" | awk '{print $2}')
        echo -e "${C_GREEN}One process found (PID: $found_pid). Analyzing...${C_RESET}"
        echo "Matched line: $ps_output"
        analyze_pid "$found_pid"
    else
        echo -e "${C_YELLOW}Multiple processes found matching '$search_string':${C_RESET}"
        echo -e "${C_CYAN}PID      USER            COMMAND${C_RESET}" # Adjusted header
        # Reformatted output for better alignment if command is long
        echo "$ps_output" | awk '{pid=$2; user=$1; cmd_start=11; cmd=""; for(i=cmd_start; i<=NF; i++) cmd=cmd $i " "; printf "%-8s %-15s %s\n", pid, user, cmd}'
        echo -e "${C_YELLOW}Please re-run the script with a specific PID from the list above.${C_RESET}"
    fi
}

# --- Main Script Logic ---
if [ $# -eq 0 ]; then
    echo -e "${C_BOLD}Usage:${C_RESET}"
    echo -e "  ${0##*/} <PID>"
    echo -e "  ${0##*/} \"<search_string>\" (quote search string if it contains spaces or special characters)"
    echo -e ""
    echo -e "${C_BOLD}Description:${C_RESET}"
    echo -e "  Analyzes a given Process ID (PID) or searches for processes by a string."
    echo -e "  Provides detailed information about the specified process by running a series of"
    echo -e "  investigative commands and displaying their output."
    echo -e ""
    echo -e "${C_BOLD}Analysis performed for a PID typically includes:${C_RESET}"
    echo -e "  - ${C_CYAN}Process Information:${C_RESET} User, PPID, CPU/Mem, status, command (from 'ps')."
    echo -e "  - ${C_CYAN}Executable Path:${C_RESET} Symlink and target of /proc/<PID>/exe ('ls', 'readlink')."
    echo -e "    - Checks if the executable is part of a Snap package ('snap info')."
    echo -e "    - Notes if the executable appears deleted."
    echo -e "    - Identifies kernel threads."
    echo -e "  - ${C_CYAN}Systemd Service Status:${C_RESET} Service unit details, if managed by systemd ('systemctl status')."
    echo -e "  - ${C_CYAN}Control Groups (CGroups):${C_RESET} cgroup paths from /proc/<PID>/cgroup ('cat')."
    echo -e "    - Checks for containerization indicators (Docker, LXC, etc.)."
    echo -e "    - Attempts 'docker inspect' if a Docker container ID is deduced."
    echo -e "  - ${C_CYAN}Network Connections:${C_RESET} Listening TCP/UDP ports and established TCP connections ('ss -p | grep' or 'lsof')."
    echo -e "  - ${C_CYAN}Open Files Summary:${C_RESET} Count and sample of open file descriptors ('lsof')."
    echo -e "  - ${C_CYAN}Environment Variables:${C_RESET} Sample from /proc/<PID>/environ ('cat', 'tr', 'head')."
    echo -e ""
    echo -e "${C_BOLD}Behavior for <search_string>:${C_RESET}"
    echo -e "  - Searches 'ps aux' output for command lines matching the string (uses 'awk')."
    echo -e "  - If one unique process is found (excluding self), it's analyzed as above."
    echo -e "  - If multiple processes are found, their PID, User, and Command are listed."
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${C_YELLOW}Warning: This script provides more complete information when run with sudo.${C_RESET}"
    echo -e "${C_YELLOW}Some details for processes not owned by you might be missing or incomplete.${C_RESET}"
fi

input="$1"

if [[ "$input" =~ ^[0-9]+$ ]]; then
    analyze_pid "$input"
else
    find_and_analyze_string "$input"
fi
