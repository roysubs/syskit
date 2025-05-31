#!/bin/bash
# Author: Roy Wiseman 2025-05

# Automatically elevate privileges with sudo if not running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Elevation required; rerunning as sudo..." 1>&2 # Print to stderr
    sudo "$0" "$@"; # Rerun the current script with sudo and pass all arguments
    exit 0 # Exit the current script after rerunning with sudo
fi

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Variables ---
# Common ports often used for web interfaces (HTTP/HTTPS and common alternates)
COMMON_WEB_PORTS="80 443 8000 8080 8443 3000 4533 9091 8888 4001 3333 9443 61208 5201" # Added ports from your example that weren't there

# Associative array to store Docker host port to container name mappings
declare -A docker_port_map # Declared globally

# Array to store potentially web services for later display (excluding standard 80/433 and Docker)
declare -a potential_web_services_list

# Array to store main output lines for sorting
declare -a main_output_lines


# --- Functions ---

# Check dependencies: lsof, curl, grep, sed, ps, and docker
check_dependencies() {
    echo "🔎 Checking for required commands: lsof, curl, grep, sed, ps, docker"
    if ! command -v lsof &> /dev/null; then
        echo "🚨 Error: 'lsof' command not found."
        echo "Please install it using: sudo apt update && sudo apt install lsof"
        exit 1
    fi
     if ! command -v curl &> /dev/null; then
        echo "🚨 Error: 'curl' command not found."
        echo "Please install it using: sudo apt update && sudo apt install curl"
        exit 1
    fi
     if ! command -v grep &> /dev/null; then
        echo "🚨 Error: 'grep' command not found. This is unexpected on a standard Debian system."
        exit 1
    fi
     if ! command -v sed &> /dev/null; then
        echo "🚨 Error: 'sed' command not found. This is unexpected on a standard Debian system."
        exit 1
    fi
     if ! command -v ps &> /dev/null; then # Added check for ps
        echo "🚨 Error: 'ps' command not found."
        echo "Please install it using: sudo apt update && sudo apt install ps"
        exit 1
    fi
     if ! command -v docker &> /dev/null; then # Added check for docker
        echo "⚠️ Warning: 'docker' command not found. Cannot identify services in Docker containers via port mapping."
        # Do not exit, continue without Docker checks
    fi
    echo "✅ Required commands found (some optional dependencies may be missing)."
    echo
}

# Populate the docker_port_map associative array by parsing `docker ps` output
populate_docker_port_map() {
    # Check if docker command is available
    if ! command -v docker &> /dev/null; then
        return # Skip if docker is not installed
    fi

    echo "🐳 Populating Docker port mappings..."
    local docker_ps_output_lines=() # Temporary array to hold lines
    # Use mapfile or readarray to read lines efficiently without a subshell for the pipe
    # Use ### as a separator (less likely to conflict than :::)
    # Redirect stderr to /dev/null in case user is not in docker group etc.
    mapfile -t docker_ps_output_lines < <(docker ps --format "{{.Names}}###{{.Ports}}" --no-trunc 2>/dev/null)

    if [ ${#docker_ps_output_lines[@]} -eq 0 ]; then
        echo "ℹ️ No running Docker containers with exposed ports found."
        echo
        return
    fi # Corrected: was a stray }

    # Process each line from the array (each line is one container)
    # This loop runs in the main shell context of the function, so array modifications persist
    for line in "${docker_ps_output_lines[@]}"; do
        # Use ### as the field separator
        local container_name=$(echo "$line" | awk -F '###' '{print $1}')
        local port_mappings=$(echo "$line" | awk -F '###' '{print $2}')

        # Split port_mappings string by comma, replacing with newline, then loop through each mapping
        local cleaned_mappings=$(echo "$port_mappings" | sed -E 's/,[[:space:]]*/\n/g' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//') # Split and trim

        # Process each cleaned mapping line by line using a here-string <<< to avoid a subshell
        while IFS= read -r mapping_line; do

            # --- Technique for Parsing Mapping (using grep -oP) ---
            # Parse each mapping line to find the host port using grep -oP
            # We are interested in the HOST_PORT when it exists in the format like IP:HOST_PORT->...
            local extracted_port=$(grep -oP ':\K([0-9]+)(?=->)' <<< "$mapping_line")

            # Check if grep successfully extracted a port number
            if [ -n "$extracted_port" ]; then
                local host_port="$extracted_port"
                # Store the mapping: host_port -> container_name
                # This assignment is now happening in the main function shell context,
                # correctly modifying the global docker_port_map
                docker_port_map[$host_port]="$container_name"
            fi
             # Mappings like "3001/tcp" or those without "->" will not match the grep pattern,
             # so $extracted_port will be empty, and they will be correctly ignored for host port mapping.
            # --- End of Technique ---

        done <<< "$cleaned_mappings" # Use here-string to process mappings without a subshell


    done # End of for line loop (processing docker ps output lines)

     echo "✅ Docker port mappings populated."
     echo
}

# Attempt to connect to a port via HTTP/S and get the Server header
# Includes an initial quick check (-m 1) to fail faster on non-responsive ports
# Tries secure HTTPS, then insecure HTTPS, then HTTP (with -m 3 timeouts)
# Args: $1 = IP Address/Hostname, $2 = Port
get_web_service_header() {
    local address="$1"
    local port="$2"
    local header=""
    local curl_target="$address"
    local temp_verbose_output=$(mktemp) # Use a temporary file for verbose output
    local quick_check_success=false # Flag for the initial quick check

    # Use localhost if the address is a wildcard or loopback
    if [[ "$address" == "0.0.0.0" || "$address" == "[::]" || "$address" == "127.0.0.1" || "$address" == "::1" || "$address" == "*" ]]; then
        curl_target="localhost"
    fi

    # --- Initial Quick Check (1-second timeout) ---
    # Try HTTP first for the quick check as it's often the most basic
    # Use --fail-with-body to ensure it fails on HTTP errors unless -f is used,
    # but -s suppresses progress so it just tests connection/initial response.
    # Redirect stdout/stderr to /dev/null
    if curl -s -f -L -m 1 --output /dev/null "http://$curl_target:$port" &> /dev/null; then
        quick_check_success=true
    # If HTTP failed, try HTTPS with --insecure for quick check
    # Redirect stdout/stderr to /dev/null
    elif curl -s -f -L -m 1 --output /dev/null --insecure "https://$curl_target:$port" &> /dev/null; then
        quick_check_success=true
    fi

    # If both quick checks failed, assume it's not a quick HTTP/S responder and return early
    if [ "$quick_check_success" == "false" ]; then
        rm -f "$temp_verbose_output" # Clean up the temp file
        echo "No HTTP/S response"
        return
    fi

    # --- If Quick Check Passed, Proceed with Detailed Checks (3-second timeouts) ---

    # Try HTTPS first (secure)
    if curl -s -L -m 3 -v --output /dev/null "https://$curl_target:$port" 2> "$temp_verbose_output"; then
         header=$(grep -i '^< Server:' "$temp_verbose_output" | head -n 1 | sed 's/^< Server: //i' | tr -d '\r' | tr '\n' ' ')
    fi

    # If no header found, try HTTPS (insecure fallback for cert issues)
    if [ -z "$header" ]; then
       if curl -s -L -m 3 -v --output /dev/null --insecure "https://$curl_target:$port" 2> "$temp_verbose_output"; then
           header=$(grep -i '^< Server:' "$temp_verbose_output" | head -n 1 | sed -E 's/^< Server: //i' | tr -d '\r' | tr '\n' ' ')
       fi
    fi

    # If no header found, try HTTP
     if [ -z "$header" ]; then
        if curl -s -L -m 3 -v --output /dev/null "http://$curl_target:$port" 2> "$temp_verbose_output"; then
             header=$(grep -i '^< Server:' "$temp_verbose_output" | head -n 1 | sed -E 's/^< Server: //i' | tr -d '\r' | tr '\n' ' ')
        fi
    fi

    # Clean up temporary file
    rm -f "$temp_verbose_output"

    if [ -n "$header" ]; then
        echo "$header"
    else
        # If header still empty, but quick check passed, it means it responded but not with a standard header
        echo "No Server header found"
    fi
}

# Attempt to connect via HTTP/S and extract the page title
# Includes an initial quick check (-m 1) to fail faster on non-responsive ports
# Tries secure HTTPS, then insecure HTTPS, then HTTP (with -m 3 timeouts)
# Args: $1 = IP Address/Hostname, $2 = Port
get_page_title() {
    local address="$1"
    local port="$2"
    local title=""
    local curl_target="$address"
    local temp_html_file=$(mktemp) # Use a temporary file to capture curl output
    local quick_check_success=false # Flag for the initial quick check


    # Use localhost if the address is a wildcard or loopback
    if [[ "$address" == "0.0.0.0" || "$address" == "[::]" || "$address" == "127.0.0.1" || "$address" == "::1" || "$address" == "*" ]]; then
        curl_target="localhost"
    fi

     # --- Initial Quick Check (1-second timeout) ---
    # Try HTTP first for the quick check as it's often the most basic
    # Use --fail-with-body to ensure it fails on HTTP errors unless -f is used,
    # but -s suppresses progress so it just tests connection/initial response.
     # Redirect stdout/stderr to /dev/null
    if curl -s -f -L -m 1 --output /dev/null "http://$curl_target:$port" &> /dev/null; then
        quick_check_success=true
    # If HTTP failed, try HTTPS with --insecure for quick check
    # Redirect stdout/stderr to /dev/null
    elif curl -s -f -L -m 1 --output /dev/null --insecure "https://$curl_target:$port" &> /dev/null; then
        quick_check_success=true
    fi

    # If both quick checks failed, assume it's not a quick HTTP/S responder and return early
    if [ "$quick_check_success" == "false" ]; then
        rm -f "$temp_html_file" # Clean up the temp file
        echo "No HTTP/S response"
        return
    fi


    # --- If Quick Check Passed, Proceed with Detailed Checks (3-second timeouts) ---

    # Try HTTPS first (secure)
    if curl -s -L -m 3 --output "$temp_html_file" "https://$curl_target:$port" 2>/dev/null; then
        # More robust sed to extract content between title tags after grep
        title=$(grep -i '<title>' "$temp_html_file" | head -n 1 | sed -E 's/.*<title>(.*)<\/title>.*/\1/i' | tr -d '\r' | tr '\n' ' ')
    fi

    # If no title found, try HTTPS (insecure fallback for cert issues)
    if [ -z "$title" ]; then
       if curl -s -L -m 3 --output "$temp_html_file" --insecure "https://$curl_target:$port" 2>/dev/null; then
           # More robust sed to extract content between title tags after grep
           title=$(grep -i '<title>' "$temp_html_file" | head -n 1 | sed -E 's/.*<title>(.*)<\/title>.*/\1/i' | tr -d '\r' | tr '\n' ' ')
       fi
    fi

    # If no title found, try HTTP
     if [ -z "$title" ]; then
        if curl -s -L -m 3 --output "$temp_html_file" "http://$curl_target:$port" 2>/dev/null; then
            # More robust sed to extract content between title tags after grep
            title=$(grep -i '<title>' "$temp_html_file" | head -n 1 | sed -E 's/.*<title>(.*)<\/title>.*/\1/i' | tr -d '\r' | tr '\n' ' ')
        fi
    fi

    # Clean up temporary file
    rm -f "$temp_html_file"

    if [ -n "$title" ]; then
        # Limit title length for display, only add "..." if truncated
        local single_line_title=$(echo "$title") # Ensure it's treated as a single string
        if [ "${#single_line_title}" -gt 50 ]; then
            echo "${single_line_title:0:50}..."
        else
            echo "$single_line_title" # Print full title if <= 50 chars
        fi
    else
         # If title still empty, but quick check passed, it means it responded but no title tag
        echo "No <title> tag found"
    fi # Corrected: Added missing closing 'fi'
}


# Find and list services listening on TCP ports, checking Server header and Page Title
find_listening_services() {
    echo "🔎 Searching for services listening on TCP ports..."
    echo "   (Checking Docker port mappings and then HTTP/S info)"
    echo

    # Use lsof as before, filter for LISTEN, and extract command, PID, and address:port.
    local lsof_output=$(sudo lsof -iTCP -P -n | grep LISTEN)

    if [ -z "$lsof_output" ]; then
        echo "✅ No services found listening on TCP ports."
        echo
        # Return early as there's nothing to list or categorize
        return
    fi

    # Capture the processed lines from lsof into a temporary array without a subshell for modification
    local processed_lsof_entries=()
    # Read output from the awk command into the array
    mapfile -t processed_lsof_entries < <(echo "$lsof_output" | awk 'NR>1 { command=$1; pid=$2; name=$9; sub(/ \(LISTEN\)$/, "", name); print command, pid, name }')


    if [ ${#processed_lsof_entries[@]} -eq 0 ]; then
        echo "✅ No services found listening on TCP ports (after initial processing)." # Should not happen if lsof_output is not empty
        echo
        return
    fi

    # Header will be printed after sorting

    # Reset the potential web services list (now stores port, command, pid, address_port, service_info, details_page_title)
    potential_web_services_list=()
    # Reset the main output lines array
    main_output_lines=()


    # Process each line from the processed lsof array (runs in the main function shell context)
    for entry_line in "${processed_lsof_entries[@]}"; do
        # --- Debugging Start ---
        # echo "DEBUG: Processing lsof array entry: $entry_line" >&2
        # --- Debugging End ---

        # Split the entry_line back into fields based on space separation from awk
        local command=$(echo "$entry_line" | awk '{print $1}')
        local pid=$(echo "$entry_line" | awk '{print $2}')
        local address_port=$(echo "$entry_line" | awk '{print $3}') # This is the combined address:port

        # Extract just the port number
        local port=$(echo "$address_port" | awk -F: '{ print $NF }')
        # Extract just the address part
        local address=$(echo "$address_port" | sed 's/:.*//')

        local display_service_info="-" # Variables for final display, default to "-"
        local display_details_page_title="-"

        local container_name=""

        # --- Check for Docker Mapping and Prioritize ---
        # Ensure port is a number before lookup in the map
        if [[ "$port" =~ ^[0-9]+$ ]]; then
                 # Check if the port exists in the docker_port_map and if the mapped value is not empty
                 if [ -n "${docker_port_map[$port]}" ]; then
                     # Port is a number AND found in the Docker map
                     container_name="${docker_port_map[$port]}"
                     display_service_info="Docker Container:"
                     display_details_page_title="$container_name"
                 fi # Corrected: Removed stray closing braces
        fi # Corrected: Removed stray closing braces


        # --- If NOT Docker Mapped, Check for Web Service Info ---
        # Only perform web checks if container_name was NOT set by the Docker check
        if [ -z "$container_name" ]; then
            local is_web_port="false"
            # Check if it's a number AND a common web port (or 80/443)
            if [[ "$port" =~ ^[0-9]+$ ]]; then
                if [ "$port" -eq 80 ] || [ "$port" -eq 443 ]; then
                    is_web_port="true"
                elif echo "$COMMON_WEB_PORTS" | grep -w "$port" &> /dev/null; then
                     is_web_port="true"
                fi
            fi

            if [ "$is_web_port" == "true" ]; then
                 # It's a web port, get HTTP/S info
                 display_service_info=$(get_web_service_header "$address" "$port")
                 display_details_page_title=$(get_page_title "$address" "$port")

                 # Store this entry for later if it's a potentially web port (excluding 80/433)
                 # Docker mapped ports are already excluded by the [ -z "$container_name" ] check above
                 if [ "$port" -ne 80 ] && [ "$port" -ne 443 ]; then
                     potential_web_services_list+=("$port|$command|$pid|$address_port|$display_service_info|$display_details_page_title")
                 fi
            fi
            # If not a web port and not Docker, display_service_info and display_details_page_title remain "-" (initialized value)
        fi

        # Store the processed line in the array for later sorting, using | as delimiter
        # This line should be fine and is NOT line 390 in the correct script
        main_output_lines+=("$port|$command|$pid|$address_port|$display_service_info|$display_details_page_title")

    done # End of for loop processing processed lsof entries

    # --- Print Sorted Main Table ---
    echo "-----------------------------------------------------------------------------------------------------------"
    printf "%-20s %-10s %-25s %-25s %s\n" "COMMAND" "PID" "LISTEN ADDRESS:PORT" "SERVICE INFO" "DETAILS / PAGE TITLE"
    echo "-----------------------------------------------------------------------------------------------------------"

    # Sort the collected lines numerically by the first field (port) using '|' as delimiter
    # Then loop through the sorted output and print the original fields
    printf "%s\n" "${main_output_lines[@]}" | sort -n -t'|' -k1 | while IFS='|' read -r port_sorted command_sorted pid_sorted address_port_sorted service_info_sorted details_page_title_sorted; do
    # Print the row using the sorted fields
    printf "%-20s %-10s %-25s %-25s %s\n" "$command_sorted" "$pid_sorted" "$address_port_sorted" "$service_info_sorted" "$details_page_title_sorted"
    done
    echo "-----------------------------------------------------------------------------------------------------------"

    # Updated Explanation
    echo "ℹ️ Explanation:"
    echo "  - COMMAND: The (potentially truncated) name of the process. Use the PID with 'ps' to get the full command."
    echo "  - PID: The Process ID of the service."
    echo "  - LISTEN ADDRESS:PORT: The IP address and port the service is listening on."
    # Clarified IPv6 format in explanation
    echo "    - '0.0.0.0' or '[::]' means listening on all available network interfaces (accessible externally)."
    echo "    - '127.0.0.1' or '::1' means listening only on the local machine (not accessible externally)."
    # Corrected: Escaped the backtick in the IPv6 example string
    echo "    - IPv6 addresses like [fe80::...]' will show the address in brackets followed by the port."
    echo "  - SERVICE INFO / DETAILS / PAGE TITLE:"
    echo "    - If the port is mapped from a running Docker container, this shows 'Docker Container:' and the container name."
    echo "    - For non-Docker processes on potential web ports, this shows HTTP 'Server' header and HTML '<title>' tag if detected (truncated)."
    echo "    - Otherwise, it shows '-'."
    echo "  - 'No HTTP/S response': The port did not respond like a standard HTTP/S web service."
    echo "  - 'No Server header found': Connected, but no standard HTTP 'Server' header was in the response."
    echo "  - 'No <title> tag found': Connected and got a response, but no HTML '<title>' tag was found (common for APIs or dynamic content)."
    echo
    echo "💡 How to Investigate Further:"
    echo "  - For non-web ports or those with limited info: Consult documentation for the COMMAND/process."
    echo "  - To see the full command line (for non-Docker or host processes): Use 'ps -p <PID> -o command --no-headers'."
    echo "  - To investigate Docker containers: Use 'docker inspect <container_id>' or 'docker top <container_id>'."
    echo "  - Tools like 'nmap -sV <IP> -p <port>' can sometimes identify services that don't respond conventionally to simple probes."

    echo "Search complete."
} # This '}' closes the find_listening_services function

# --- Main Script Execution ---

# Auto-elevate handled by the block after shebang

check_dependencies
populate_docker_port_map # Run this after checking dependencies
find_listening_services # This populates the potential_web_services_list and main_output_lines arrays

# After the main output, display the filtered list if not empty
# This list now only includes non-Docker potential web services (excluding 80/433)
if [ ${#potential_web_services_list[@]} -gt 0 ]; then
    echo
    # Adjusted header - Matches the main table header
    echo "--- Potential Non-Docker Web Services (Sorted by Port) ---"
    echo "-----------------------------------------------------------------------------------------------------------"
    printf "%-20s %-10s %-25s %-25s %s\n" "COMMAND" "PID" "LISTEN ADDRESS:PORT" "SERVICE INFO" "DETAILS / PAGE TITLE"
    echo "-----------------------------------------------------------------------------------------------------------"

    # Sort the array numerically by the first field (port) using '|' as delimiter
    # Then loop through the sorted output and print the original fields
    printf "%s\n" "${potential_web_services_list[@]}" | sort -n -t'|' -k1 | while IFS='|' read -r port command pid address_port service_info details_page_title; do
         # Print the row
         printf "%-20s %-10s %-25s %-25s %s\n" "$command" "$pid" "$address_port" "$service_info" "$details_page_title"
    done
    echo "-----------------------------------------------------------------------------------------------------------"
fi

echo "Script finished."
