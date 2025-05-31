#!/bin/bash
# Author: Roy Wiseman 2025-04

# consolidated-create-share-smb.sh: Enhanced script to create a Samba share step-by-step
# This script combines the best features from multiple versions.
# v2: Fixed regex quoting issue in share name validation.

# --- Configuration ---
SAMBA_CONF="/etc/samba/smb.conf"
LOG_FILE="$HOME/.config/consolidated-create-share-smb.log" # Changed log file name slightly
CONFIG_DIR=$(dirname "$LOG_FILE")

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Global Variables ---
ASSUME_YES="no" # Default, can be overridden by -y

# --- Helper Functions ---

# Ensure config directory exists for the log file
if ! mkdir -p "$CONFIG_DIR"; then
    echo -e "${RED}FATAL ERROR: Could not create log directory $CONFIG_DIR. Aborting.${NC}"
    # Attempt to log to a temporary location if primary log dir fails
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] FATAL ERROR: Could not create log directory $CONFIG_DIR." >> "/tmp/consolidated-create-share-smb-emergency.log"
    exit 1
fi

# Initialize log file with script start time
{
    echo "----------------------------------------------------------------------"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] --- Script execution started ---"
    echo "Script Name: $0"
    echo "Arguments: $*"
    echo "----------------------------------------------------------------------"
} >> "$LOG_FILE"


# Function to print a message to console and log it
log_message() {
    local type="$1" # e.g., INFO, WARN, ERROR, STEP, SUCCESS, USER_INPUT
    local message="$2"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=$BLUE # Default for INFO

    case "$type" in
        STEP) color=$YELLOW ;;
        WARN) color=$YELLOW ;;
        ERROR) color=$RED ;;
        SUCCESS) color=$GREEN ;;
        USER_INPUT) color=$BLUE ;; # Or a different color if preferred
    esac

    echo -e "${color}${type}:${NC} $message"
    echo "[$timestamp] ${type}: $message" >> "$LOG_FILE"
}

# Function to print a command to be executed, and log its intent.
log_command_intent() {
    local cmd_string="$1"
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "${GREEN}COMMAND INTENT:${NC} $cmd_string"
    echo "[$timestamp] COMMAND_INTENT: $cmd_string" >> "$LOG_FILE"
}

# Function to log actual execution of a command
log_command_execution() {
    local cmd_string="$1"
    local exit_code="$2"
    local output="$3" # Optional: command output
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    if [ "$exit_code" -eq 0 ]; then
        echo "[$timestamp] EXECUTED_SUCCESS: $cmd_string (Exit Code: $exit_code)" >> "$LOG_FILE"
        if [ -n "$output" ]; then
            echo "[$timestamp] CMD_OUTPUT_SUCCESS:\n$output" >> "$LOG_FILE"
        fi
    else
        echo "[$timestamp] EXECUTED_FAILURE: $cmd_string (Exit Code: $exit_code)" >> "$LOG_FILE"
        if [ -n "$output" ]; then
            echo "[$timestamp] CMD_OUTPUT_FAILURE:\n$output" >> "$LOG_FILE"
        fi
    fi
}


# Function to ask a yes/no question
# Returns 0 for yes, 1 for no.
ask_yes_no() {
    local question="$1"
    local reply
    if [ "$ASSUME_YES" = "yes" ]; then
        log_message "INFO" "Assuming 'yes' due to -y flag for: $question"
        return 0
    fi
    while true; do
        read -r -p "$(echo -e "${YELLOW}PROMPT:${NC} $question (y/n): ")" -n 1 reply
        echo "" # Newline
        log_message "USER_INPUT" "Prompt: '$question' User replied: '$reply'"
        case $reply in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo -e "${RED}Please answer yes (y) or no (n).${NC}";;
        esac
    done
}

# Function to check if a package is installed
package_installed() {
    # dpkg-query is more reliable than dpkg -s for scripting
    if command -v dpkg-query &> /dev/null; then
        dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
    elif command -v rpm &> /dev/null; then
        rpm -q "$1" &> /dev/null
    else
        log_message "WARN" "Cannot determine package status for '$1'. Unknown package manager."
        return 1 # Cannot determine, assume not installed or error
    fi
}

# Function to install Samba
install_samba() {
    log_message "STEP" "Checking and installing Samba packages..."
    if package_installed samba; then
        log_message "INFO" "Samba appears to be already installed."
        return 0
    fi

    log_message "INFO" "Samba not found."
    if ask_yes_no "Samba is not installed. Do you want to install it now?"; then
        local exit_code=1 # Default to failure
        local cmd_output
        if command -v apt-get &> /dev/null; then # Prefer apt-get for scripting over apt
            log_message "INFO" "Detected Debian/Ubuntu based system."
            log_command_intent "sudo apt-get update"
            cmd_output=$(sudo apt-get update 2>&1)
            exit_code=$?
            log_command_execution "sudo apt-get update" $exit_code "$cmd_output"
            if [ $exit_code -ne 0 ]; then
                log_message "ERROR" "'sudo apt-get update' failed. Please check your package manager. Output:\n$cmd_output"
                return 1
            fi

            log_command_intent "sudo apt-get install -y samba samba-common-bin acl"
            cmd_output=$(sudo apt-get install -y samba samba-common-bin acl 2>&1)
            exit_code=$?
            log_command_execution "sudo apt-get install -y samba samba-common-bin acl" $exit_code "$cmd_output"
        elif command -v yum &> /dev/null; then
            log_message "INFO" "Detected Red Hat/CentOS/Fedora based system (yum)."
            log_command_intent "sudo yum clean all" # Optional, but good practice
            cmd_output=$(sudo yum clean all 2>&1)
            # Don't fail script if 'yum clean all' fails, but log it
            log_command_execution "sudo yum clean all" $? "$cmd_output"

            log_command_intent "sudo yum install -y samba samba-common samba-client" # acl usually part of coreutils
            cmd_output=$(sudo yum install -y samba samba-common samba-client 2>&1)
            exit_code=$?
            log_command_execution "sudo yum install -y samba samba-common samba-client" $exit_code "$cmd_output"
        elif command -v dnf &> /dev/null; then
            log_message "INFO" "Detected Red Hat/Fedora based system (dnf)."
            # dnf clean all is similar to yum clean all
            log_command_intent "sudo dnf clean all"
            cmd_output=$(sudo dnf clean all 2>&1)
            log_command_execution "sudo dnf clean all" $? "$cmd_output"

            log_command_intent "sudo dnf install -y samba samba-common samba-client"
            cmd_output=$(sudo dnf install -y samba samba-common samba-client 2>&1)
            exit_code=$?
            log_command_execution "sudo dnf install -y samba samba-common samba-client" $exit_code "$cmd_output"
        else
            log_message "ERROR" "Unsupported distribution or package manager not found (apt-get, yum, dnf). Please install Samba manually."
            return 1
        fi

        if [ $exit_code -eq 0 ]; then
            log_message "SUCCESS" "Samba installed successfully."
        else
            log_message "ERROR" "Failed to install Samba. Please install it manually. Output:\n$cmd_output"
            return 1
        fi
    else
        log_message "WARN" "Samba installation skipped by user. Samba is required to create a share."
        return 1
    fi
    return 0
}

# Function to check and manage Samba services (smbd, nmbd)
manage_samba_services() {
    log_message "STEP" "Checking Samba service status (smbd and nmbd)..."
    local services_ok=1 # Assume OK until a problem is found with an essential service
    local cmd_output
    local exit_code

    for service in smbd nmbd; do
        log_message "INFO" "Checking status of $service service..."
        local service_is_active=0
        local service_is_enabled_on_boot # Using this to avoid re-check if already known
        
        if command -v systemctl &> /dev/null; then
            if systemctl is-active --quiet "${service}.service"; then
                log_message "INFO" "$service service is active (running) via systemctl."
                service_is_active=1
                if systemctl is-enabled --quiet "${service}.service"; then
                    log_message "INFO" "$service service is enabled to start on boot."
                    service_is_enabled_on_boot=1
                else
                    log_message "WARN" "$service service is running but not enabled to start on boot."
                    service_is_enabled_on_boot=0
                    if ask_yes_no "Enable $service to start on boot?"; then
                        log_command_intent "sudo systemctl enable $service"
                        cmd_output=$(sudo systemctl enable "$service" 2>&1)
                        exit_code=$?
                        log_command_execution "sudo systemctl enable $service" $exit_code "$cmd_output"
                        if [ $exit_code -ne 0 ]; then log_message "ERROR" "Failed to enable $service. Output:\n$cmd_output"; fi
                    fi
                fi
            else 
                log_message "WARN" "$service service does not appear to be active (running) via systemctl."
                # services_ok will be set to 0 if smbd is not active and not started later
            fi
        elif command -v service &> /dev/null ; then # Fallback for older systems
            log_command_intent "sudo service $service status"
            cmd_output=$(sudo service "$service" status 2>&1) 
            if sudo service "$service" status &>/dev/null; then
                log_command_execution "sudo service $service status" 0 "$cmd_output"
                log_message "INFO" "$service service is active (running) via 'service' command."
                service_is_active=1
                log_message "WARN" "Cannot automatically check if $service is enabled on boot with 'service' command."
            else
                log_command_execution "sudo service $service status" $? "$cmd_output" 
                log_message "WARN" "$service service does not appear to be active (running) via 'service' command. Output:\n$cmd_output"
            fi
        else
            log_message "ERROR" "No systemctl or service command found to manage services."
            return 1 
        fi

        if [ "$service_is_active" -eq 0 ]; then
            if [ "$service" = "smbd" ]; then services_ok=0; fi # Mark essential service as not OK yet

            if ask_yes_no "$service service is not running. Attempt to start and enable it?"; then
                local started_successfully=0
                if command -v systemctl &> /dev/null; then
                    if [ "$service_is_enabled_on_boot" != "1" ]; then # Only enable if not already enabled or status unknown
                        log_command_intent "sudo systemctl enable $service"
                        cmd_output=$(sudo systemctl enable "$service" 2>&1)
                        exit_code=$?
                        log_command_execution "sudo systemctl enable $service" $exit_code "$cmd_output"
                        if [ $exit_code -ne 0 ]; then log_message "ERROR" "Failed to enable $service. Output:\n$cmd_output"; fi
                    fi

                    log_command_intent "sudo systemctl start $service"
                    cmd_output=$(sudo systemctl start "$service" 2>&1)
                    exit_code=$?
                    log_command_execution "sudo systemctl start $service" $exit_code "$cmd_output"
                    if systemctl is-active --quiet "${service}.service"; then started_successfully=1; fi
                elif command -v service &> /dev/null; then
                    log_message "WARN" "Attempting to start $service via 'service' command. Enabling on boot might need manual setup (e.g., update-rc.d, chkconfig)."
                    log_command_intent "sudo service $service start"
                    cmd_output=$(sudo service "$service" start 2>&1)
                    exit_code=$?
                    log_command_execution "sudo service $service start" $exit_code "$cmd_output"
                    if sudo service "$service" status &>/dev/null; then started_successfully=1; fi
                fi

                if [ "$started_successfully" -eq 1 ]; then
                    log_message "SUCCESS" "$service started successfully."
                    if [ "$service" = "smbd" ]; then services_ok=1; fi # Mark essential service as OK now
                else
                    log_message "ERROR" "Failed to start $service. Please check service logs. Output:\n$cmd_output"
                    if [ "$service" = "smbd" ]; then return 1; fi # Failed to start essential smbd
                fi
            else
                log_message "WARN" "User chose not to start/enable $service."
                if [ "$service" = "smbd" ]; then return 1; fi # User opted out of running essential smbd
            fi
        elif [ "$service" = "smbd" ] && [ "$service_is_active" -eq 1 ]; then
             services_ok=1 # Ensure smbd is confirmed as OK
        fi
    done

    if [ "$services_ok" -eq 0 ] && ! systemctl is-active --quiet "smbd.service"; then # Final check for smbd if loop finished
        log_message "ERROR" "Essential Samba service (smbd) is not active. Cannot proceed."
        return 1
    fi

    log_message "SUCCESS" "Samba services checked."
    return 0
}


# Function to check firewall status
check_firewall() {
    log_message "STEP" "Checking Firewall Status..."
    local firewall_action_needed=0
    local ufw_status_output ufw_status firewalld_status_output firewalld_status
    local cmd_output exit_code

    # Define Samba ports
    local samba_ports_tcp="139,445"
    local samba_ports_udp="137,138"
    log_message "INFO" "Samba requires TCP ports $samba_ports_tcp and UDP ports $samba_ports_udp to be open."

    if command -v ufw &> /dev/null; then
        log_command_intent "sudo ufw status verbose"
        ufw_status_output=$(sudo ufw status verbose 2>&1)
        exit_code=$? # ufw status usually returns 0 even if inactive
        log_command_execution "sudo ufw status verbose" $exit_code "$ufw_status_output"
        # Display verbose status to user for their reference
        echo -e "${BLUE}UFW Status Output:${NC}\n$ufw_status_output"

        ufw_status=$(echo "$ufw_status_output" | grep -i '^Status:' | awk '{print $2}')
        log_message "INFO" "UFW status: $ufw_status"

        if [[ "$ufw_status" == "active" ]]; then
            # Check for 'samba' profile or individual ports
            if echo "$ufw_status_output" | grep -qE 'ALLOW IN.*Samba|ALLOW IN.*samba' || \
               (echo "$ufw_status_output" | grep -E '(^|[^0-9])137/udp($|[^0-9])' | grep -q 'ALLOW IN') && \
               (echo "$ufw_status_output" | grep -E '(^|[^0-9])138/udp($|[^0-9])' | grep -q 'ALLOW IN') && \
               (echo "$ufw_status_output" | grep -E '(^|[^0-9])139/tcp($|[^0-9])' | grep -q 'ALLOW IN') && \
               (echo "$ufw_status_output" | grep -E '(^|[^0-9])445/tcp($|[^0-9])' | grep -q 'ALLOW IN'); then
                log_message "SUCCESS" "UFW is active and Samba ports/profile appear to be allowed."
            else
                log_message "WARN" "UFW is active, but Samba ports/profile might be blocked or not explicitly allowed."
                firewall_action_needed=1
            fi
        else
            log_message "INFO" "UFW is installed but not active. Traffic might be unrestricted or managed by another firewall."
        fi
    elif command -v firewall-cmd &> /dev/null; then
        log_command_intent "sudo systemctl is-active firewalld"
        firewalld_status=$(sudo systemctl is-active firewalld 2>&1) # Capture output
        exit_code=$?
        log_command_execution "sudo systemctl is-active firewalld" $exit_code "$firewalld_status"
        log_message "INFO" "Firewalld service active status: $firewalld_status (exit code $exit_code)"

        if [[ "$firewalld_status" == "active" ]]; then
            log_message "INFO" "Checking firewalld rules for Samba..."
            log_command_intent "sudo firewall-cmd --list-all" # Shows current zone and services
            firewalld_status_output=$(sudo firewall-cmd --list-all 2>&1)
            exit_code=$?
            log_command_execution "sudo firewall-cmd --list-all" $exit_code "$firewalld_status_output"
            echo -e "${BLUE}Firewalld Current Configuration:${NC}\n$firewalld_status_output"


            # Check if samba service is allowed in any active zone.
            # This is a simplified check; a truly robust one would iterate active zones.
            log_command_intent "sudo firewall-cmd --query-service=samba --permanent"
            cmd_output=$(sudo firewall-cmd --query-service=samba --permanent 2>&1)
            exit_code=$? # Returns 0 if allowed, 1 if not (for --query-service)
            log_command_execution "sudo firewall-cmd --query-service=samba --permanent" $exit_code "$cmd_output"

            if [ $exit_code -eq 0 ]; then # 0 means "yes" or "true" for query
                log_message "SUCCESS" "Firewalld is active and Samba service appears to be permanently allowed in a zone."
                log_message "INFO" "Note: Ensure the zone where Samba is allowed is applied to your active network interface(s)."
            else
                log_message "WARN" "Firewalld is active, but Samba service is not listed as permanently allowed (or query failed)."
                firewall_action_needed=1
            fi
        else
            log_message "INFO" "Firewalld is installed but not active. Traffic might be unrestricted or managed by another firewall."
        fi
    else
        log_message "INFO" "Neither UFW nor Firewalld found. Firewall rules might be managed directly by iptables/nftables."
        log_message "WARN" "Please manually verify your iptables/nftables rules."
        log_command_intent "sudo iptables -L -v -n"
        cmd_output=$(sudo iptables -L -v -n 2>&1)
        log_command_execution "sudo iptables -L -v -n" $? "$cmd_output"
        echo -e "${BLUE}iptables rules:${NC}\n$cmd_output"

        if command -v nft &> /dev/null; then
            log_command_intent "sudo nft list ruleset"
            cmd_output=$(sudo nft list ruleset 2>&1)
            log_command_execution "sudo nft list ruleset" $? "$cmd_output"
            echo -e "${BLUE}nftables ruleset:${NC}\n$cmd_output"
        else
            log_message "INFO" "nft command not found, skipping nftables ruleset display."
        fi
    fi

    if [ "$firewall_action_needed" -eq 1 ]; then
        if ask_yes_no "Samba ports/service may be blocked. Would you like the script to attempt to open them?"; then
            if command -v ufw &> /dev/null && [[ "$ufw_status" == "active" ]]; then
                log_message "INFO" "Attempting to allow Samba through UFW..."
                log_command_intent "sudo ufw allow samba"
                cmd_output=$(sudo ufw allow samba 2>&1)
                exit_code=$?
                log_command_execution "sudo ufw allow samba" $exit_code "$cmd_output"
                if [ $exit_code -ne 0 ]; then log_message "ERROR" "Failed to execute 'ufw allow samba'. Output:\n$cmd_output"; else
                    log_command_intent "sudo ufw reload"
                    cmd_output=$(sudo ufw reload 2>&1)
                    exit_code=$?
                    log_command_execution "sudo ufw reload" $exit_code "$cmd_output"
                    if [ $exit_code -ne 0 ]; then log_message "ERROR" "Failed to reload UFW. Output:\n$cmd_output"; else
                        log_message "INFO" "UFW rules updated. Verifying..."
                        log_command_intent "sudo ufw status verbose"
                        cmd_output=$(sudo ufw status verbose 2>&1) # No exit code check, just display
                        log_command_execution "sudo ufw status verbose" 0 "$cmd_output"
                        echo -e "${BLUE}New UFW Status:${NC}\n$cmd_output"
                    fi
                fi
            elif command -v firewall-cmd &> /dev/null && [[ "$firewalld_status" == "active" ]]; then
                log_message "INFO" "Attempting to allow Samba service through Firewalld (permanently, in default/public zone)..."
                # Add to public zone by default. User might need to adjust if using a different zone.
                # Determine default zone, or use public as a fallback
                local default_zone
                default_zone=$(sudo firewall-cmd --get-default-zone 2>/dev/null) || default_zone="public"
                log_message "INFO" "Attempting to add samba service to zone: '$default_zone'"

                log_command_intent "sudo firewall-cmd --permanent --add-service=samba --zone=$default_zone"
                cmd_output=$(sudo firewall-cmd --permanent --add-service=samba --zone="$default_zone" 2>&1)
                exit_code=$?
                log_command_execution "sudo firewall-cmd --permanent --add-service=samba --zone=$default_zone" $exit_code "$cmd_output"

                if [ $exit_code -eq 0 ]; then
                    log_command_intent "sudo firewall-cmd --reload"
                    cmd_output=$(sudo firewall-cmd --reload 2>&1)
                    exit_code=$?
                    log_command_execution "sudo firewall-cmd --reload" $exit_code "$cmd_output"
                    if [ $exit_code -eq 0 ]; then
                        log_message "INFO" "Firewalld rules updated. Verifying..."
                        log_command_intent "sudo firewall-cmd --list-services --zone=$default_zone --permanent"
                        cmd_output=$(sudo firewall-cmd --list-services --zone="$default_zone" --permanent 2>&1)
                        log_command_execution "sudo firewall-cmd --list-services --zone=$default_zone --permanent" $? "$cmd_output"
                        echo -e "${BLUE}Permanent services in zone $default_zone:${NC}\n$cmd_output"
                    else
                        log_message "ERROR" "Failed to reload Firewalld. Output:\n$cmd_output"
                    fi
                else
                    log_message "ERROR" "Failed to add Samba service to Firewalld. Output:\n$cmd_output"
                fi
            else
                log_message "ERROR" "Could not automatically update firewall rules. No recognized active firewall manager (UFW/Firewalld) or it's inactive."
            fi
        else
            log_message "WARN" "User chose not to modify firewall rules. Please ensure Samba traffic is allowed manually."
        fi
    fi
    log_message "SUCCESS" "Firewall check completed."
    # This function does not return a failure code for the main script flow,
    # as firewall issues might be resolved manually by the user.
}


# Function to add and enable a Samba user
add_and_enable_samba_user() {
    local user="$1"
    local cmd_output exit_code
    log_message "STEP" "Managing Samba user '$user'..."

    # Check if the system user exists
    log_message "INFO" "Checking if system user '$user' exists..."
    if ! id "$user" &> /dev/null; then
        log_message "ERROR" "System user '$user' does not exist. Please create the system user first."
        return 1
    fi
    log_message "INFO" "System user '$user' exists."

    log_message "INFO" "Checking Samba user database for '$user'..."
    # pdbedit -L is noisy, -v can be even more so. Grep for the user.
    # We need to capture output to check flags.
    log_command_intent "sudo pdbedit -L -v" # Log intent for full list
    local samba_user_list_output
    samba_user_list_output=$(sudo pdbedit -L -v 2>&1) # Capture output, including potential errors
    exit_code=$? # Check if pdbedit itself ran successfully
    log_command_execution "sudo pdbedit -L -v" $exit_code # Don't log full output here, too verbose for general log
    if [ $exit_code -ne 0 ]; then
        log_message "ERROR" "Failed to list Samba users with pdbedit. Output:\n$samba_user_list_output"
        return 1
    fi

    local user_details
    user_details=$(echo "$samba_user_list_output" | grep "^${user}:")

    if [ -z "$user_details" ]; then
        log_message "WARN" "Samba user '$user' not found in Samba database."
        if ask_yes_no "Add '$user' to Samba? (You will be prompted for a new Samba password)"; then
            log_command_intent "sudo smbpasswd -a '$user'"
            # smbpasswd -a is interactive for password setting
            sudo smbpasswd -a "$user" # Let it run interactively
            exit_code=$? # Capture exit code directly after interactive command
            log_command_execution "sudo smbpasswd -a '$user'" $exit_code "Interactive command - output not captured here."
            if [ $exit_code -eq 0 ]; then
                log_message "SUCCESS" "Samba user '$user' added and enabled."
                return 0
            else
                log_message "ERROR" "Failed to add Samba user '$user'."
                return 1
            fi
        else
            log_message "WARN" "Samba user '$user' not added by choice. Authenticated access for this user will fail."
            return 1 # Critical if this user was intended for the share
        fi
    else
        log_message "INFO" "Samba user '$user' found in Samba database."
        echo -e "${BLUE}Samba User Details:${NC} $user_details" # Show the line from pdbedit to user

        # Check if user is disabled (flags like [UD], [D], [X])
        # Common disable flags: U (user), D (disabled account), X (expired password)
        # Regex to match flags indicating disabled or problematic state: e.g., contains 'D' or 'X' within brackets
        if echo "$user_details" | grep -qE '\[.*[DX].*\]'; then
            log_message "WARN" "Samba user '$user' appears to be disabled or account has issues (e.g., [D]isabled, e[X]pired)."
            if ask_yes_no "Attempt to enable Samba user '$user'?"; then
                log_command_intent "sudo smbpasswd -e '$user'"
                cmd_output=$(sudo smbpasswd -e "$user" 2>&1)
                exit_code=$?
                log_command_execution "sudo smbpasswd -e '$user'" $exit_code "$cmd_output"
                if [ $exit_code -eq 0 ]; then
                    log_message "SUCCESS" "Samba user '$user' enabled."
                else
                    log_message "ERROR" "Failed to enable Samba user '$user'. Output:\n$cmd_output"
                    return 1
                fi
            else
                log_message "WARN" "Samba user '$user' remains in its current state."
                return 1 # User chose not to enable a potentially problematic account
            fi
        else
            log_message "INFO" "Samba user '$user' appears to be enabled."
        fi

        if ask_yes_no "Samba user '$user' exists. Do you want to change/reset their Samba password?"; then
            log_command_intent "sudo smbpasswd '$user'"
            sudo smbpasswd "$user" # Interactive
            exit_code=$?
            log_command_execution "sudo smbpasswd '$user'" $exit_code "Interactive command - output not captured here."
            if [ $exit_code -eq 0 ]; then
                log_message "SUCCESS" "Samba password for '$user' updated."
            else
                log_message "ERROR" "Failed to change Samba password for '$user'."
                # Not returning 1 here as it's an optional step if user already exists and enabled
            fi
        fi
    fi
    log_message "SUCCESS" "Samba user '$user' management completed."
    return 0
}


# Function to configure the Samba share
configure_share() {
    local share_name="$1"
    local share_path="$2"
    local writable="$3" # "yes" or "no"
    local guest_ok="$4" # "yes" or "no"
    local valid_users="$5" # comma-separated string or empty
    local cmd_output exit_code

    log_message "STEP" "Configuring Samba Share '$share_name'..."
    log_message "INFO" "Share Details: Path='$share_path', Writable='$writable', GuestOK='$guest_ok', ValidUsers='$valid_users'"

    # Ensure the directory exists
    log_message "INFO" "Checking share directory: '$share_path'..."
    if [ ! -d "$share_path" ]; then
        log_message "WARN" "Directory '$share_path' does not exist."
        if ask_yes_no "Create directory '$share_path'?"; then
            log_command_intent "sudo mkdir -p '$share_path'"
            cmd_output=$(sudo mkdir -p "$share_path" 2>&1)
            exit_code=$?
            log_command_execution "sudo mkdir -p '$share_path'" $exit_code "$cmd_output"
            if [ $exit_code -ne 0 ]; then
                log_message "ERROR" "Failed to create directory '$share_path'. Aborting. Output:\n$cmd_output"
                return 1
            fi
            log_message "SUCCESS" "Directory '$share_path' created."
        else
            log_message "ERROR" "Share directory '$share_path' does not exist and creation was skipped. Aborting."
            return 1
        fi
    else
        log_message "INFO" "Directory '$share_path' already exists."
    fi

    # --- Check and Set Directory Permissions ---
    log_message "INFO" "Checking permissions for '$share_path'..."
    log_command_intent "ls -ld '$share_path'"
    local current_perms_details
    current_perms_details=$(ls -ld "$share_path" 2>&1)
    exit_code=$?
    log_command_execution "ls -ld '$share_path'" $exit_code "$current_perms_details"
    echo -e "${BLUE}Current directory details:${NC} $current_perms_details"

    local current_permissions current_owner current_group
    # stat can fail if path was just created by another user and sudo mkdir, then current user can't stat.
    # Try to stat as sudo if direct stat fails.
    current_permissions=$(stat -c "%a" "$share_path" 2>/dev/null) || current_permissions=$(sudo stat -c "%a" "$share_path" 2>/dev/null)
    current_owner=$(stat -c "%U" "$share_path" 2>/dev/null) || current_owner=$(sudo stat -c "%U" "$share_path" 2>/dev/null)
    current_group=$(stat -c "%G" "$share_path" 2>/dev/null) || current_group=$(sudo stat -c "%G" "$share_path" 2>/dev/null)

    if [ -z "$current_permissions" ]; then
        log_message "ERROR" "Could not determine current permissions for '$share_path'. Skipping permission adjustment."
    else
        log_message "INFO" "Parsed - Current permissions: $current_permissions, Owner: $current_owner, Group: $current_group"

        local set_perms_cmd=""
        local set_owner_cmd=""
        local perm_explanation=""
        local suggested_owner=""
        local suggested_group=""
        local suggested_perms=""

        if [ "$guest_ok" = "yes" ]; then
            perm_explanation="For guest access, the 'guest account' (often 'nobody' or 'smbguest') needs appropriate access via 'others' permissions on the filesystem, or Samba's 'force user' must be used."
            suggested_owner="nobody"
            # nogroup might not exist on all systems, or guest might be mapped to a different group.
            # Check if 'nogroup' exists, otherwise use 'nobody' as group too.
            if getent group nogroup >/dev/null; then
                suggested_group="nogroup"
            else
                suggested_group="nobody" # Fallback
                log_message "WARN" "Group 'nogroup' not found, will suggest user 'nobody' for group ownership for guest share."
            fi

            if [ "$writable" = "yes" ]; then
                perm_explanation+=" Recommended for guest writable: Owner '$suggested_owner:$suggested_group', Permissions '0777' (world rwx - very open, use with caution!) or '1777' (sticky bit + world rwx). Alternatively, use 'force user' in smb.conf."
                suggested_perms="0777" # Or 1777 for sticky bit
            else # Guest read-only
                perm_explanation+=" Recommended for guest read-only: Owner '$suggested_owner:$suggested_group', Permissions '0755' (world rx)."
                suggested_perms="0755"
            fi
            set_owner_cmd="sudo chown -R '$suggested_owner:$suggested_group' '$share_path'"
            set_perms_cmd="sudo chmod -R '$suggested_perms' '$share_path'"

        elif [ -n "$valid_users" ]; then
            local first_user
            first_user=$(echo "$valid_users" | cut -d',' -f1 | tr -d ' ') # Get first user, remove spaces
            if ! id "$first_user" &>/dev/null; then
                 log_message "ERROR" "Primary user '$first_user' for permissions does not exist. Skipping permission setup."
            else
                local first_user_group
                first_user_group=$(id -gn "$first_user" 2>/dev/null) || first_user_group=$first_user # Fallback

                perm_explanation="For authenticated access by '$valid_users', the user(s) need appropriate filesystem rights. "
                suggested_owner="$first_user"
                suggested_group="$first_user_group"

                if [ "$writable" = "yes" ]; then
                    perm_explanation+="Recommended: Owner '$first_user:$first_user_group', Permissions '0770' (user rwx, group rwx, others no access). Ensure all valid users are in group '$first_user_group' if group write is desired. For multi-user write, consider 'chmod g+s' (setgid) on the directory and 'force group' in smb.conf."
                    suggested_perms="0770"
                    # For multi-user write, consider '2770' (setgid) and ensuring users are in the group.
                else # Read-only for valid users
                    perm_explanation+="Recommended: Owner '$first_user:$first_user_group', Permissions '0750' (user rwx, group rx, others no access)."
                    suggested_perms="0750"
                fi
                set_owner_cmd="sudo chown -R '$suggested_owner:$suggested_group' '$share_path'"
                set_perms_cmd="sudo chmod -R '$suggested_perms' '$share_path'"
            fi
        else
            log_message "WARN" "No guest access and no specific valid users. File system permissions will heavily dictate access based on how users connect and global Samba settings (e.g., 'force user'). Manual permission review is critical."
            perm_explanation="Permissions are highly dependent on your global Samba config and how users connect."
        fi

        log_message "INFO" "$perm_explanation"
        if [[ -n "$set_owner_cmd" || -n "$set_perms_cmd" ]]; then
            if ask_yes_no "Attempt to set recommended ownership/permissions as described above?"; then
                if [ -n "$set_owner_cmd" ]; then
                    log_command_intent "$set_owner_cmd"
                    cmd_output=$(eval "$set_owner_cmd" 2>&1) # eval to handle variables in command string
                    exit_code=$?
                    log_command_execution "$set_owner_cmd" $exit_code "$cmd_output"
                    if [ $exit_code -ne 0 ]; then log_message "ERROR" "Failed to set ownership. Output:\n$cmd_output"; fi
                fi
                if [ -n "$set_perms_cmd" ]; then
                    log_command_intent "$set_perms_cmd"
                    cmd_output=$(eval "$set_perms_cmd" 2>&1)
                    exit_code=$?
                    log_command_execution "$set_perms_cmd" $exit_code "$cmd_output"
                    if [ $exit_code -ne 0 ]; then log_message "ERROR" "Failed to set permissions. Output:\n$cmd_output"; fi
                fi
                # Only log success if both commands were intended and at least one ran (or would have run)
                if [ $? -eq 0 ]; then # Check last command's status, or overall logic
                    log_message "SUCCESS" "Ownership/permissions update process completed for '$share_path'."
                    log_message "INFO" "Verifying new permissions:"
                    log_command_intent "ls -ld '$share_path'"
                    cmd_output=$(ls -ld "$share_path" 2>&1)
                    log_command_execution "ls -ld '$share_path'" $? "$cmd_output"
                    echo -e "${BLUE}New directory details:${NC} $cmd_output"
                fi
            else
                log_message "WARN" "Permissions not automatically set. Please ensure they are correct manually."
            fi
        fi
    fi # End of if [ -z "$current_permissions" ]

    # Add the share definition to smb.conf
    log_message "INFO" "Preparing to append share configuration to $SAMBA_CONF."

    # Construct the configuration block
    local temp_conf_block_file
    if ! temp_conf_block_file=$(mktemp); then
        log_message "ERROR" "Failed to create temporary file for Samba config block. Aborting share configuration."
        return 1
    fi
    # Ensure temp file is cleaned up on script exit or error
    trap 'rm -f "$temp_conf_block_file"' EXIT

    cat <<EOF > "$temp_conf_block_file"

; --- Share '$share_name' created by $0 on $(date) ---
[$share_name]
    comment = Samba share for $share_path
    path = $share_path
    browseable = yes
    # Ensure directory and file operations respect standard Unix permissions by default
    # unless overridden by specific Samba settings like 'force user', 'force group', etc.
    # These masks are applied AFTER standard Unix permissions.
    # 0664 for files means owner/group can rw, others r.
    # 0775 for dirs means owner/group can rwx, others rx.
    create mask = 0664
    directory mask = 0775
EOF

    if [ "$writable" = "yes" ]; then
        echo "    read only = no" >> "$temp_conf_block_file"
        # writable = yes is implied by read only = no, but can be explicit
        echo "    writable = yes" >> "$temp_conf_block_file"
    else
        echo "    read only = yes" >> "$temp_conf_block_file"
        echo "    writable = no" >> "$temp_conf_block_file"
    fi

    if [ "$guest_ok" = "yes" ]; then
        echo "    guest ok = yes" >> "$temp_conf_block_file"
        # Common guest account. Ensure this system user exists and has no login shell.
        # This can also be set globally in smb.conf.
        echo "    guest account = nobody" >> "$temp_conf_block_file"
        # If guest writable, you might need to force the user for created files
        # if filesystem permissions are restrictive for 'nobody'.
        # if [ "$writable" = "yes" ]; then
        # echo " force user = nobody" >> "$temp_conf_block_file"
        # fi
    else
        echo "    guest ok = no" >> "$temp_conf_block_file"
    fi

    if [ -n "$valid_users" ]; then
        # Ensure users are comma-separated, no leading/trailing spaces per user
        local formatted_valid_users
        formatted_valid_users=$(echo "$valid_users" | tr -s ' ' | sed 's/ *, */,/g' | sed 's/^,//;s/,$//')
        echo "    valid users = $formatted_valid_users" >> "$temp_conf_block_file"
        if [ "$writable" = "yes" ]; then
            echo "    write list = $formatted_valid_users" >> "$temp_conf_block_file"
            # If multiple users and group write is desired via filesystem group permissions:
            local first_user_for_group
            first_user_for_group=$(echo "$formatted_valid_users" | cut -d',' -f1)
            if id "$first_user_for_group" &>/dev/null; then
                local group_to_force
                group_to_force=$(id -gn "$first_user_for_group" 2>/dev/null)
                if [ -n "$group_to_force" ]; then
                    echo "    force group = +$group_to_force" >> "$temp_conf_block_file" # '+' makes sure primary group of user is not changed
                    log_message "INFO" "Added 'force group = +$group_to_force'. Ensure all valid users are members of this group for consistent write access if using group permissions on the filesystem. Consider setting 'inherit permissions = yes'."
                fi
            fi
        fi
    fi
    # Add a final line to ensure separation if other shares follow
    echo "; --- End of Share '$share_name' configuration ---" >> "$temp_conf_block_file"
    echo "" >> "$temp_conf_block_file"


    log_message "INFO" "The following configuration block will be appended to $SAMBA_CONF:"
    # Use cat -n to show line numbers for easier review by user
    echo -e "${BLUE}--- Configuration Block to Append ---${NC}"
    cat -n "$temp_conf_block_file"
    echo -e "${BLUE}--- End of Configuration Block ---${NC}"

    if ask_yes_no "Proceed with appending this configuration to $SAMBA_CONF?"; then
        # Backup smb.conf before modification
        local SAMBA_CONF_BACKUP
        SAMBA_CONF_BACKUP="${SAMBA_CONF}.$(date +%Y%m%d%H%M%S).bak"
        log_message "INFO" "Backing up current Samba configuration to $SAMBA_CONF_BACKUP"
        log_command_intent "sudo cp '$SAMBA_CONF' '$SAMBA_CONF_BACKUP'"
        cmd_output=$(sudo cp "$SAMBA_CONF" "$SAMBA_CONF_BACKUP" 2>&1)
        exit_code=$?
        log_command_execution "sudo cp '$SAMBA_CONF' '$SAMBA_CONF_BACKUP'" $exit_code "$cmd_output"
        if [ $exit_code -ne 0 ]; then
            log_message "ERROR" "Failed to backup $SAMBA_CONF. Aborting share configuration to prevent data loss. Output:\n$cmd_output"
            rm -f "$temp_conf_block_file" # Ensure trap cleanup happens if exit isn't immediate
            return 1
        fi

        log_command_intent "sudo tee -a '$SAMBA_CONF' < '$temp_conf_block_file'"
        # The actual content is in temp_conf_block_file, tee appends it.
        # We don't want tee's stdout (which is the content itself) to go to the console here.
        cmd_output=$(sudo tee -a "$SAMBA_CONF" < "$temp_conf_block_file" > /dev/null 2>&1)
        exit_code=$?
        # Log the execution, but not the content of the block as output (it's already logged)
        log_command_execution "sudo tee -a '$SAMBA_CONF' < '$temp_conf_block_file'" $exit_code "$cmd_output"
        # rm -f "$temp_conf_block_file" # Trap will handle this

        if [ $exit_code -eq 0 ]; then
            log_message "SUCCESS" "Samba configuration for '$share_name' appended to $SAMBA_CONF."
        else
            log_message "ERROR" "Failed to append configuration to $SAMBA_CONF. Output:\n$cmd_output"
            log_message "INFO" "Original configuration is backed up at $SAMBA_CONF_BACKUP. You may need to restore it manually: sudo cp '$SAMBA_CONF_BACKUP' '$SAMBA_CONF'"
            return 1
        fi
    else
        log_message "WARN" "Configuration not appended to $SAMBA_CONF by user choice."
        # rm -f "$temp_conf_block_file" # Trap will handle this
        return 1 # If not configured, share won't work as intended by this script run
    fi
    return 0
}

# Function to test Samba configuration
test_samba_config() {
    log_message "STEP" "Testing Samba Configuration..."
    log_command_intent "testparm -s '$SAMBA_CONF'"
    # testparm output can be verbose, capture and log, then print
    local testparm_output
    testparm_output=$(testparm -s "$SAMBA_CONF" 2>&1) # Capture stdout and stderr
    local exit_code=$?
    log_command_execution "testparm -s '$SAMBA_CONF'" $exit_code "$testparm_output" # Log full output

    echo -e "${BLUE}--- testparm output ---${NC}"
    echo "$testparm_output"
    echo -e "${BLUE}--- end of testparm output ---${NC}"

    if [ $exit_code -eq 0 ]; then
        # testparm returns 0 even for some warnings, check output for "Loaded services file OK"
        if echo "$testparm_output" | grep -q "Loaded services file OK."; then
            log_message "SUCCESS" "Samba configuration test (testparm) passed."
            return 0
        else
            log_message "WARN" "testparm reported success (exit code 0) but 'Loaded services file OK.' not found. Please review output carefully."
            # Potentially still okay, but warrants a warning.
            return 0 # Treat as success for script flow, but user should check.
        fi
    else
        log_message "ERROR" "Samba configuration has errors (testparm failed). Please check $SAMBA_CONF and the output above."
        return 1
    fi
}

# Function to restart Samba services
restart_samba_services() {
    log_message "STEP" "Restarting Samba Services..."
    local all_restarts_ok=1 # Assume OK initially
    local smbd_restarted_ok=0
    local cmd_output exit_code

    for service in smbd nmbd; do 
        log_message "INFO" "Attempting to restart $service..."
        local service_exists=0
        local restart_attempted_for_this_service=0

        if command -v systemctl &> /dev/null; then
            if systemctl list-units --full -all | grep -qF "${service}.service"; then # Use -F for fixed string
                service_exists=1
            else
                log_message "INFO" "Service ${service}.service not found by systemctl. Skipping restart for it."
                if [ "$service" = "smbd" ]; then all_restarts_ok=0; fi # smbd is essential
                continue
            fi
            
            restart_attempted_for_this_service=1
            log_command_intent "sudo systemctl restart $service"
            cmd_output=$(sudo systemctl restart "$service" 2>&1)
            exit_code=$?
            log_command_execution "sudo systemctl restart $service" $exit_code "$cmd_output"
            if [ $exit_code -eq 0 ]; then
                log_message "SUCCESS" "$service restarted successfully via systemctl."
                if [ "$service" = "smbd" ]; then smbd_restarted_ok=1; fi
            else
                log_message "ERROR" "Failed to restart $service via systemctl. Output:\n$cmd_output"
                if [ "$service" = "smbd" ]; then all_restarts_ok=0; fi 
            fi
        elif command -v service &> /dev/null; then 
            # Cannot easily check if service exists with 'service' command before trying
            service_exists=1 # Assume it might exist for service command
            restart_attempted_for_this_service=1
            log_command_intent "sudo service $service restart"
            cmd_output=$(sudo service "$service" restart 2>&1)
            exit_code=$?
            log_command_execution "sudo service $service restart" $exit_code "$cmd_output"
            if [ $exit_code -eq 0 ]; then
                log_message "SUCCESS" "$service restarted successfully via service command."
                if [ "$service" = "smbd" ]; then smbd_restarted_ok=1; fi
            else
                log_message "ERROR" "Failed to restart $service via service command. Output:\n$cmd_output"
                if [ "$service" = "smbd" ]; then all_restarts_ok=0; fi
            fi
        else
            log_message "ERROR" "Cannot determine how to restart Samba services (no systemctl or service command found)."
            return 1 # Critical failure for restarting
        fi
    done

    if [ "$smbd_restarted_ok" -eq 1 ]; then
        log_message "SUCCESS" "Essential Samba service (smbd) restarted successfully."
        if [ "$all_restarts_ok" -eq 0 ]; then # If smbd was ok, but nmbd (if attempted) failed
             log_message "WARN" "Note: Not all Samba-related services may have restarted correctly (e.g., nmbd). Check logs if issues persist."
        fi
        return 0
    else
        log_message "ERROR" "Failed to restart essential Samba service (smbd). Please check service logs and restart manually."
        return 1
    fi
}

# --- Main Script ---
main() {
    # Ensure trap is set for the main script execution for temp file cleanup
    trap 'rm -f "$temp_conf_block_file" 2>/dev/null' EXIT SIGINT SIGTERM

    echo -e "${YELLOW}--- Samba Share Creation Script ---${NC}"
    echo "This script will guide you through setting up a Samba share."
    echo -e "All actions and commands will be logged to: ${GREEN}$LOG_FILE${NC}"
    echo "You will be prompted for confirmation for major changes unless -y is used."
    echo "Use the -y flag to automatically answer 'yes' to all prompts (use with caution)."
    echo "Press Ctrl+C at any time to abort."
    echo "-----------------------------------"
    # sleep 2 # Give user a moment to read

    # Check for root privileges early, but most commands use sudo anyway
    if [ "$(id -u)" -ne 0 ]; then
        log_message "WARN" "This script performs actions requiring root privileges (sudo)."
        log_message "WARN" "You may be prompted for your sudo password multiple times."
        # Validate sudo timestamp or prompt for password
        if ! sudo -v; then
            log_message "ERROR" "Sudo credentials failed or not provided. Aborting."
            exit 1
        fi
        log_message "INFO" "Sudo credentials appear to be valid."
    else
        log_message "INFO" "Script is running as root."
    fi


    # Parse command-line options
    SHARE_PATH=""
    SHARE_NAME=""
    WRITABLE="no" # read-only by default
    GUEST_OK="no"
    VALID_USERS="" # Comma-separated list

    # ASSUME_YES is global, ensure it's correctly set by -y if provided
    # No need to reset it here as it's handled by the getopts loop or default global value

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -p|--path) SHARE_PATH="$2"; shift ;;
            -n|--name) SHARE_NAME="$2"; shift ;;
            -w|--writable) WRITABLE="yes" ;;
            -g|--guest) GUEST_OK="yes" ;;
            -u|--users) VALID_USERS="$2"; shift ;;
            -y|--yes) ASSUME_YES="yes"; log_message "INFO" "'-y' flag detected. Will assume 'yes' for prompts." ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  -p, --path <path>         : Absolute path to the directory to share (required)"
                echo "  -n, --name <name>         : Name of the Samba share (defaults to the last part of the path)"
                echo "  -w, --writable            : Allow writing to the share (default is read-only)"
                echo "  -g, --guest               : Allow guest access without a password"
                echo "  -u, --users <user1,...>   : Comma-separated list of valid system users for authenticated access"
                echo "  -y, --yes                 : Automatically answer yes to prompts (use with caution)"
                echo "  -h, --help                : Show this help message"
                exit 0
                ;;
            *) log_message "ERROR" "Unknown parameter passed: $1. Use -h or --help for usage."; exit 1 ;;
        esac
        shift
    done

    # Validate required options
    if [ -z "$SHARE_PATH" ]; then
        log_message "ERROR" "Share path is required. Use -p or --path."
        echo "Use -h or --help for usage information."
        exit 1
    fi
    # Ensure SHARE_PATH is absolute
    if [[ "$SHARE_PATH" != /* ]]; then
        log_message "ERROR" "Share path must be an absolute path (e.g., /srv/myshare)."
        exit 1
    fi


    # Set default share name if not provided
    if [ -z "$SHARE_NAME" ]; then
        SHARE_NAME=$(basename "$SHARE_PATH")
        log_message "INFO" "Share name not provided, using '$SHARE_NAME' derived from the path."
    fi
    # Validate share name (Samba has restrictions, e.g. no / \ etc. and length)
    # Corrected line: Quote the regex pattern.
    # The pattern [/\\[\\]:|<>*?"] matches common problematic characters.
    if [[ "$SHARE_NAME" =~ "[/\\[\\]:|<>*?\"]" || ${#SHARE_NAME} -gt 80 ]]; then # Basic check
        log_message "ERROR" "Invalid share name '$SHARE_NAME'. Avoid special characters like / \\ [ ] : | < > * ? \" and keep it reasonably short (max 80 chars)."
        exit 1
    fi


    # Check for conflicting options
    if [ "$GUEST_OK" = "yes" ] && [ -n "$VALID_USERS" ]; then
        log_message "ERROR" "Cannot have both guest access (-g) and specific valid users (-u) defined. Choose one."
        exit 1
    fi
    if [ "$GUEST_OK" = "no" ] && [ -z "$VALID_USERS" ]; then
        log_message "WARN" "No guest access (-g) and no specific users (-u) defined. Access will depend on global Samba settings (e.g. 'security = user' implies authentication) and file permissions. This might lead to unexpected access behavior."
    fi


    # --- Pre-configuration Steps ---
    log_message "STEP" "Starting pre-configuration checks..."

    if ! install_samba; then
        log_message "ERROR" "Samba installation failed or was skipped. Cannot proceed."
        exit 1
    fi

    if ! manage_samba_services; then
        log_message "ERROR" "Samba services (smbd/nmbd) are not running or could not be started/enabled. Cannot proceed."
        exit 1
    fi

    check_firewall # This function will log its own success/failure but script continues unless user aborts within

    if [ -n "$VALID_USERS" ]; then
        log_message "STEP" "Processing specified Samba users: $VALID_USERS"
        IFS=',' read -r -a USERS_ARRAY <<< "$VALID_USERS" # -r to prevent backslash interpretation
        local all_users_ok=1
        for user_to_check in "${USERS_ARRAY[@]}"; do
            # Trim whitespace from user_to_check
            user_to_check_trimmed=$(echo "$user_to_check" | xargs) # xargs trims leading/trailing whitespace
            if [ -z "$user_to_check_trimmed" ]; then continue; fi # Skip empty user entries

            if ! add_and_enable_samba_user "$user_to_check_trimmed"; then
                log_message "ERROR" "Failed to setup Samba user '$user_to_check_trimmed'. This user may not have access."
                all_users_ok=0
                # Decide if script should abort if one user fails. For now, continue but warn.
            fi
        done
        if [ "$all_users_ok" -eq 0 ]; then
            log_message "WARN" "One or more specified Samba users could not be fully configured. The share might not work as expected for them."
            if ! ask_yes_no "Continue with share configuration despite user setup issues?"; then
                log_message "INFO" "Aborting due to user request after Samba user setup issues."
                exit 1
            fi
        fi
        log_message "SUCCESS" "Specified Samba users processed."
    fi


    # --- Configuration Steps ---
    log_message "STEP" "Starting main configuration steps..."

    if ! configure_share "$SHARE_NAME" "$SHARE_PATH" "$WRITABLE" "$GUEST_OK" "$VALID_USERS"; then
        log_message "ERROR" "Failed to configure the Samba share in $SAMBA_CONF or set directory permissions. Aborting."
        exit 1
    fi

    if ! test_samba_config; then
        log_message "ERROR" "Samba configuration test (testparm) failed. Please review $SAMBA_CONF and fix errors."
        if ! ask_yes_no "testparm failed. Attempt to restart Samba anyway (NOT RECOMMENDED)?"; then
            log_message "INFO" "Aborting due to testparm failure and user choice."
            exit 1
        fi
        log_message "WARN" "Proceeding with Samba restart despite testparm failure, as per user request."
    fi

    if ! restart_samba_services; then
        log_message "ERROR" "Failed to restart Samba services. The new share may not be active. Please check service logs and restart manually."
        # Don't exit here, still provide summary and connection info
    fi

    # --- Post-configuration Information ---
    log_message "STEP" "Share Creation Summary & Connection Info"
    echo -e "\n${YELLOW}--- Share Creation Summary ---${NC}"
    echo -e "Samba share ${GREEN}'$SHARE_NAME'${NC} for path ${GREEN}'$SHARE_PATH'${NC} has been configured."
    echo "Access Type:"
    if [ "$GUEST_OK" = "yes" ]; then
        echo -e "  ${GREEN}Guest access is enabled.${NC}"
        echo -e "  ${YELLOW}WARNING:${NC} Guest access, especially if writable with open permissions (e.g., 0777 on filesystem), can be a security risk. Ensure 'guest account' in smb.conf is appropriately restricted."
    elif [ -n "$VALID_USERS" ]; then
        echo -e "  Access is restricted to users: ${GREEN}$VALID_USERS${NC} (requires Samba password for each user)."
    else
        echo -e "  ${YELLOW}Access is not explicitly defined for guests or specific users.${NC}"
        echo "  Access will depend on global Samba settings (e.g., 'security = user') and filesystem permissions."
    fi
    echo -e "Writable (in Samba config): ${GREEN}$WRITABLE${NC} (Filesystem permissions also apply)"

    # Get server IP for connection examples
    local SERVER_IP SERVER_HOSTNAME
    SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}') # Get primary IP
    SERVER_HOSTNAME=$(hostname -s 2>/dev/null) # Short hostname
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="<server_ip_address>" # Fallback
        log_message "WARN" "Could not automatically determine server IP address."
    fi
    if [ -z "$SERVER_HOSTNAME" ]; then
        SERVER_HOSTNAME="<server_hostname>"
        log_message "WARN" "Could not automatically determine server hostname."
    fi


    echo -e "\n${YELLOW}--- How to Connect ---${NC}"
    echo "Replace placeholders like ${GREEN}<YourSambaUsername>${NC}, ${GREEN}<YourSambaPassword>${NC}, ${GREEN}/mnt/local_mount_point${NC} as needed."
    echo ""
    echo -e "${BLUE}From Windows Explorer:${NC}"
    echo -e "  \\\\${GREEN}$SERVER_IP\\$SHARE_NAME${NC}"
    echo -e "  or (if NetBIOS name resolution works): \\\\${GREEN}$SERVER_HOSTNAME\\$SHARE_NAME${NC}"
    echo ""
    echo -e "${BLUE}From Windows Command Prompt (net use):${NC}"
    echo -e "  Example (map as drive Z:):"
    if [ -n "$VALID_USERS" ]; then
        local first_example_user
        first_example_user=$(echo "$VALID_USERS" | cut -d',' -f1 | xargs)
        echo -e "  net use Z: \\\\${GREEN}$SERVER_IP\\$SHARE_NAME${NC} /user:${GREEN}$first_example_user${NC} *"
        echo "  (Enter password for '$first_example_user' when prompted. Or replace '*' with the password directly - less secure)"
    elif [ "$GUEST_OK" = "yes" ]; then
        echo -e "  net use Z: \\\\${GREEN}$SERVER_IP\\$SHARE_NAME${NC}"
        echo "  (Should connect as guest if server allows anonymous login for the share)"
    else # security = user, but no specific users defined in this share block
        echo -e "  net use Z: \\\\${GREEN}$SERVER_IP\\$SHARE_NAME${NC} /user:${GREEN}<YourSambaUsername>${NC} *"
        echo "  (You will need to provide credentials for a valid system user known to Samba)"
    fi
    echo ""
    echo -e "${BLUE}From Linux (mount command - run as root or with sudo):${NC}"
    echo -e "  1. Create a mount point: sudo mkdir -p ${GREEN}/mnt/$SHARE_NAME${NC} (or your preferred location)"
    local mount_options="uid=$(id -u),gid=$(id -g)" # Mount as current user
    if [ "$writable" = "yes" ]; then
        mount_options+=",rw"
    else
        mount_options+=",ro"
    fi

    if [ -n "$VALID_USERS" ]; then
        local first_example_user
        first_example_user=$(echo "$VALID_USERS" | cut -d',' -f1 | xargs)
        echo -e "  2. Mount command (authenticated):"
        echo -e "     sudo mount -t cifs //${GREEN}$SERVER_IP/$SHARE_NAME${NC} ${GREEN}/mnt/$SHARE_NAME${NC} -o username=${GREEN}$first_example_user${NC},password=${GREEN}<YourSambaPassword>${NC},$mount_options"
        echo -e "     (Consider using a credentials file for security: 'man mount.cifs', option 'credentials=/path/to/file')"
    elif [ "$GUEST_OK" = "yes" ]; then
        echo -e "  2. Mount command (for guest access):"
        echo -e "     sudo mount -t cifs //${GREEN}$SERVER_IP/$SHARE_NAME${NC} ${GREEN}/mnt/$SHARE_NAME${NC} -o guest,$mount_options"
    else # security = user, but no specific users defined in this share block
        echo -e "  2. Mount command (general authenticated):"
        echo -e "     sudo mount -t cifs //${GREEN}$SERVER_IP/$SHARE_NAME${NC} ${GREEN}/mnt/$SHARE_NAME${NC} -o username=${GREEN}<YourSambaUsername>${NC},$mount_options"
        echo -e "     (You will need to provide credentials for a valid system user known to Samba)"
    fi
    echo ""
    echo -e "${BLUE}From Linux File Manager (e.g., Nautilus, Dolphin, Thunar):${NC}"
    echo -e "  Enter this in the address bar:"
    echo -e "  smb://${GREEN}$SERVER_IP/$SHARE_NAME${NC}"
    echo -e "  or (if name resolution works): smb://${GREEN}$SERVER_HOSTNAME/$SHARE_NAME${NC}"
    echo "  You may be prompted for username and password if the share is not guest accessible."

    echo -e "\n${YELLOW}--- Important Notes & Troubleshooting ---${NC}"
    echo "1.  ${BLUE}Firewall:${NC} This script attempted to check/configure UFW/Firewalld. If connection fails, double-check that UDP ports 137, 138 and TCP ports 139, 445 are open on the server for your client's network."
    echo "2.  ${BLUE}SELinux/AppArmor:${NC} If enabled, these security modules might block Samba. You may need to set appropriate contexts/policies (e.g., 'sudo chcon -R -t samba_share_t '$SHARE_PATH'' for SELinux, or AppArmor profiles). This script does NOT configure these."
    echo "3.  ${BLUE}File Permissions:${NC} The script attempted to set permissions. Complex scenarios might need manual 'chown', 'chmod', or ACL adjustments on '$SHARE_PATH'. Samba's 'force user', 'force group', 'create mask', 'directory mask', and 'inherit permissions' settings can also affect effective permissions."
    echo "4.  ${BLUE}Samba Users:${NC} For authenticated access, system users must exist and be added to Samba with 'sudo smbpasswd -a username'. Their Samba passwords may differ from their system passwords."
    echo "5.  ${BLUE}Samba Logs:${NC} Check Samba logs for errors if connections fail. Common locations:"
    echo "    - /var/log/samba/log.smbd"
    echo "    - /var/log/samba/log.nmbd"
    echo "    - /var/log/samba/log.<client_hostname_or_ip>"
    echo "    Use 'sudo journalctl -u smbd -u nmbd -f' on systemd systems or 'sudo tail -f /var/log/samba/log.*' to monitor."
    echo "6.  ${BLUE}Windows Credentials:${NC} Windows can aggressively cache credentials. If you change passwords or access types, you might need to clear cached credentials in Windows Credential Manager or restart the 'Workstation' service on the Windows client (or reboot client)."
    echo "7.  ${BLUE}Testparm:${NC} Review the output of 'testparm -s $SAMBA_CONF' for any warnings or misconfigurations not caught by this script."
    echo "8.  ${BLUE}Global smb.conf settings:${NC} Settings in the [global] section of $SAMBA_CONF (like 'security', 'map to guest', 'guest account') significantly impact share behavior."

    echo -e "\n${GREEN}--- Script Finished ---${NC}"
    log_message "INFO" "Script execution finished successfully."
    # Clean up trap explicitly at the end of successful execution if desired, though EXIT trap handles it.
    trap - EXIT SIGINT SIGTERM 
    exit 0
}

# Global variable for temp file, to be cleaned by trap
temp_conf_block_file="" 

# Call main function with all script arguments
main "$@"

