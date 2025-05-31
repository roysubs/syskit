#!/usr/bin/env bash
# Author: Roy Wiseman 2025-04

# --- Configuration ---
readonly COMPOSE_FILE="docker-managers.yaml"
readonly PROJECT_NAME="docker_managers" # Explicit project name for Docker Compose

# Service details for final information display
# Format: "service_name_in_yaml|Display Name|Host Config Paths|Access URL(s) (uses direct hostname -I)|Notes"
readonly SERVICES_INFO=(
    "portainer|Portainer|~/.config/portainer-docker|http://$(hostname -I | awk '{print $1}'):9000 (HTTP) and https://$(hostname -I | awk '{print $1}'):9443 (HTTPS)|Create an admin user on first visit."
    "yacht|Yacht|~/.config/yacht-docker|http://$(hostname -I | awk '{print $1}'):8001 (Yacht's container port is 8000)|\033[0;33mIMPORTANT!!! 'admin@yacht.local' and 'pass' for first login!!!\033[0m"
    "dockge|Dockge|Data: ~/.config/dockge-docker/data, Stacks: ~/dockge_compose_stacks|http://$(hostname -I | awk '{print $1}'):5001|Create an admin user on first visit."
    "dozzle|Dozzle Log Viewer|N/A (uses Docker socket directly)|http://$(hostname -I | awk '{print $1}'):8081|Real-time Docker log viewer. Accesses Docker socket via /var/run/docker.sock."
    "watchtower|Watchtower (Auto Updater)|N/A (uses Docker socket directly)|N/A (background service)|Automatically updates other containers. Check logs: docker logs watchtower. Uses /var/run/docker.sock."
    "diun|Diun (Image Update Notifier)|~/.config/diun-docker (for diun.yml & data)|http://$(hostname -I | awk '{print $1}'):8082 (Web UI)|Notifies of Docker image updates. Create 'diun.yml' in its config path to set providers (e.g., Docker) & notifiers (e.g., Gotify, Email)."
)

# Host directories for config/data (paths from your docker-managers.yaml)
readonly HOST_DIRS=(
    "${HOME}/.config/portainer-docker"
    "${HOME}/.config/yacht-docker"
    "${HOME}/.config/dockge-docker/data" # Dockge's internal data
    "${HOME}/dockge_compose_stacks"      # Directory for Dockge's managed compose files
    "${HOME}/.config/diun-docker"        # Diun's configuration and data
)

# --- Colors ---
COLOR_RESET='\033[0m'

# Title
TITLE_BOX_COLOR='\033[1;33m'  # Bright Yellow

# Tags
TAG_INFO_COLOR='\033[1;37m'    # Bold White
TAG_SUCCESS_COLOR='\033[0;32m' # Green
TAG_WARN_COLOR='\033[0;33m'    # Yellow
TAG_ERROR_COLOR='\033[0;31m'   # Red
TAG_HEADING_COLOR='\033[0;36m' # Cyan
TAG_CMD_HASH_COLOR='\033[0;37m' # White for '#'
TAG_CMD_TEXT_COLOR='\033[0;32m' # Green for command text

# Text - Message part
TEXT_MSG_COLOR='\033[0;37m'       # Normal White (or terminal default)
TEXT_STRONG_WARN_COLOR='\033[1;31m' # Bold Red for critical warnings

# --- Helper Functions ---
_print_tag_message() { # Internal helper
    local tag_color="$1"
    local tag_text="$2"
    local message="$3"
    echo -e "${tag_color}${tag_text}${COLOR_RESET}${TEXT_MSG_COLOR} ${message}${COLOR_RESET}"
}

info() {    _print_tag_message "$TAG_INFO_COLOR"    "[INFO]   " "$1"; }
success() { _print_tag_message "$TAG_SUCCESS_COLOR" "[SUCCESS]"  "$1"; }
warn() {    _print_tag_message "$TAG_WARN_COLOR"    "[WARNING]"  "$1"; }
error() {   _print_tag_message "$TAG_ERROR_COLOR"    "[ERROR]  "  "$1"; }
heading() { echo -e "\n${TAG_HEADING_COLOR}>>>${COLOR_RESET}${TEXT_MSG_COLOR} ${1}${COLOR_RESET}"; }

# Function to display and execute a command
run_cmd() {
    echo -e "${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${*}${COLOR_RESET}" >&2 # Print command to stderr for visibility
    "$@"
    return $?
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Docker Compose Command Helper ---
DOCKER_COMPOSE_CMD_ARRAY=() # Will hold the command and its base arguments

initialize_docker_compose_cmd() {
    if command_exists docker && docker compose version > /dev/null 2>&1; then
        DOCKER_COMPOSE_CMD_ARRAY=("docker" "compose")
    elif command_exists docker-compose; then
        DOCKER_COMPOSE_CMD_ARRAY=("docker-compose")
    else
        error "Docker Compose is not installed. Please install it (V2 'docker compose' recommended): https://docs.docker.com/compose/install/"
        exit 1
    fi
    DOCKER_COMPOSE_CMD_ARRAY+=("-f" "${COMPOSE_FILE}" "-p" "${PROJECT_NAME}")
    # No success message here, will be part of Step 1 output
}


# --- Stop and Cleanup Functionality ---
handle_stop() {
    heading "Stop and Cleanup Mode"
    info "This will shut down the services defined in '${COMPOSE_FILE}'."

    if ! run_cmd "${DOCKER_COMPOSE_CMD_ARRAY[@]}" "down"; then
        error "Failed to shut down the Docker Compose stack. Please check messages above."
    else
        success "Docker Compose stack '${PROJECT_NAME}' shut down successfully."
    fi
    echo ""

    warn "WARNING: You can now choose to remove the persistent configuration and data folders."
    warn "This action is IRREVERSIBLE and will delete all settings, templates, and user data for these services."

    local confirm1=""
    local confirm2=""

    echo -e "${TEXT_MSG_COLOR}The following directories and their contents will be PERMANENTLY DELETED:${COLOR_RESET}"
    for dir in "${HOST_DIRS[@]}"; do
        echo -e "${TEXT_STRONG_WARN_COLOR}  - ${dir/\~/$HOME}${COLOR_RESET}"
    done
    echo ""

    read -r -p "$(echo -e "${TEXT_STRONG_WARN_COLOR}ARE YOU ABSOLUTELY SURE? Type 'YES' to proceed to the final confirmation: ${COLOR_RESET}")" confirm1

    if [[ "$confirm1" == "YES" ]]; then
        read -r -p "$(echo -e "${TEXT_STRONG_WARN_COLOR}FINAL CONFIRMATION: This is your last chance. Type 'YES' to delete all listed config and data folders: ${COLOR_RESET}")" confirm2
        if [[ "$confirm2" == "YES" ]]; then
            info "Proceeding with deletion of configuration and data folders..."
            for dir in "${HOST_DIRS[@]}"; do
                expanded_dir="${dir/\~/$HOME}"
                if [[ -d "$expanded_dir" ]]; then
                    if run_cmd sudo rm -rf "$expanded_dir"; then
                        success "Successfully deleted: $expanded_dir"
                    else
                        error "Failed to delete: $expanded_dir. Please check permissions or remove manually."
                    fi
                else
                    warn "Directory not found (already deleted?): $expanded_dir"
                fi
            done
            success "Cleanup of configuration and data folders complete."
        else
            info "Cleanup aborted. Configuration folders were NOT deleted."
        fi
    else
        info "Cleanup aborted. Configuration folders were NOT deleted."
    fi
    exit 0
}

# --- Main Startup Script ---
main_startup() {
    echo -e "${TITLE_BOX_COLOR}=================================================${COLOR_RESET}"
    echo -e "${TITLE_BOX_COLOR}  Docker Managers Startup Script                 ${COLOR_RESET}"
    echo -e "${TITLE_BOX_COLOR}=================================================${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}This script will set up and manage Portainer, Yacht, Dockge, Dozzle, Watchtower, and Diun" # Updated
    echo -e "using the Docker Compose file: ${COMPOSE_FILE}"
    echo -e "It is designed to be idempotent.${COLOR_RESET}"

    # 1. Prerequisites Check
    heading "Step 1: Checking Prerequisites"
    success "Docker is installed and accessible (checked via Docker Compose init)." 
    success "Docker Compose found (${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} will be used)."


    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Docker Compose file '${COMPOSE_FILE}' not found in the current directory!"
        error "Please ensure it exists and contains the service definitions."
        exit 1
    fi
    success "Compose file '${COMPOSE_FILE}' found."

    # 2. Ensure Host Directories Exist
    heading "Step 2: Ensuring Host Directories for Persistent Data"
    for dir in "${HOST_DIRS[@]}"; do
        expanded_dir="${dir/\~/$HOME}"
        if [[ ! -d "$expanded_dir" ]]; then
            info "Attempting to create directory: $expanded_dir"
            if run_cmd mkdir -p "$expanded_dir"; then
                success "Directory created/ensured: $expanded_dir"
            else
                error "Failed to create directory: $expanded_dir"
                error "Please check permissions or create it manually."
                exit 1
            fi
        else
            success "Directory already exists: $expanded_dir"
        fi
    done

    # 3. Deploy/Update Services
    heading "Step 3: Starting/Updating Docker Management Services"
    info "This will use Docker Compose to bring services up or update them if needed."
    info "If services are already running and up-to-date, this command will make no changes."
    info "Please wait, this may take a moment if images need to be pulled..."

    if run_cmd "${DOCKER_COMPOSE_CMD_ARRAY[@]}" "up" "-d" "--remove-orphans"; then
        success "Docker Compose 'up' command completed successfully."
    else
        error "Docker Compose 'up' command failed. See output above for details."
        warn "Troubleshooting tips:"
        warn " - Check for port conflicts if services fail to start."
        warn " - Ensure Docker has enough resources."
        warn " - Manually run (without -d for more logs): ${DOCKER_COMPOSE_CMD_ARRAY[@]} up --remove-orphans"
        exit 1
    fi

    # 4. Display Status of Managed Containers
    heading "Step 4: Current Status of Docker Management Services"
    info "Displaying status for containers in project '${PROJECT_NAME}':"
    echo -e "${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}docker ps --filter \"label=com.docker.compose.project=${PROJECT_NAME}\" --format \"table {{.Names}}\\\t{{truncate .ID 12}}\\\t{{.Status}}\\\t{{.Ports}}\"${COLOR_RESET}"
    docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "table {{.Names}}\t{{truncate .ID 12}}\t{{.Status}}\t{{.Ports}}"
    if [[ $? -ne 0 ]]; then
        warn "Could not retrieve specific container status using 'docker ps'. The 'docker compose ps' command might have more details."
    fi
    echo ""

    # 5. Display Access Information
    heading "Step 5: Access Information & Setup Notes"
    local primary_ip
    primary_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$primary_ip" ]]; then
        warn "Could not determine primary IP using 'hostname -I'. URLs will use 'localhost'."
        primary_ip="localhost"
    else
        success "Services should be accessible via IP: $primary_ip (or 'localhost' if on the same machine)."
    fi


    for service_info_line in "${SERVICES_INFO[@]}"; do
        IFS="|" read -r service_yaml_name display_name config_paths urls notes <<< "$service_info_line"

        echo "" # Newline before each service block
        echo -e "${TAG_HEADING_COLOR}--- ${display_name} ---${COLOR_RESET}"

        local container_name_to_check="$service_yaml_name" 
        local actual_status
        local container_id
        container_id=$(docker compose -p "${PROJECT_NAME}" ps -q "${service_yaml_name}" 2>/dev/null)
        
        if [[ -n "$container_id" ]]; then
             actual_status=$(docker inspect --format "{{.State.Status}}" "$container_id" 2>/dev/null)
        else
            actual_status="" 
        fi

        local current_status="${TAG_WARN_COLOR}Unknown${COLOR_RESET}" 

        if [[ -n "$actual_status" ]]; then
            if [[ "$actual_status" == "running" ]]; then
                current_status="${TAG_SUCCESS_COLOR}Running${COLOR_RESET}"
            elif [[ "$actual_status" == "exited" ]]; then
                current_status="${TAG_ERROR_COLOR}Exited - Check logs: docker compose -p ${PROJECT_NAME} logs ${service_yaml_name}${COLOR_RESET}"
            else 
                current_status="${TAG_WARN_COLOR}${actual_status}${COLOR_RESET}"
            fi
        else
            actual_status_fallback=$(docker inspect --format "{{.State.Status}}" "${service_yaml_name}" 2>/dev/null)
            if [[ -n "$actual_status_fallback" ]]; then
                 if [[ "$actual_status_fallback" == "running" ]]; then
                    current_status="${TAG_SUCCESS_COLOR}Running${COLOR_RESET}"
                elif [[ "$actual_status_fallback" == "exited" ]]; then
                    current_status="${TAG_ERROR_COLOR}Exited - Check logs: docker logs ${service_yaml_name}${COLOR_RESET}"
                else
                    current_status="${TAG_WARN_COLOR}${actual_status_fallback}${COLOR_RESET}"
                fi
            else
                 current_status="${TAG_ERROR_COLOR}Not Found (or error fetching status)${COLOR_RESET}"
            fi
        fi
        echo -e "${TEXT_MSG_COLOR}  Status:${COLOR_RESET} ${current_status}"

        echo -e "${TEXT_MSG_COLOR}  Access URL(s): ${TAG_CMD_TEXT_COLOR}${urls}${COLOR_RESET}"

        if [[ "$config_paths" != "N/A"* ]]; then 
            expanded_config_paths="${config_paths//\~/$HOME}"
            echo -e "${TEXT_MSG_COLOR}  Host Config/Data Path(s): ${expanded_config_paths}${COLOR_RESET}"
        fi
        echo -e "${TEXT_MSG_COLOR}  Notes: ${notes}${COLOR_RESET}"
    done
    echo -e "${TAG_HEADING_COLOR}-------------------------------------------------${COLOR_RESET}"
    echo ""

    success "Setup script complete! Your Docker managers should be accessible."
    info "You can quickly remove (down and optionally delete config files) with:  ./${0##*/} --remove"
    info "Portainer V1 Templates also load into Yacht (go to the template section and add these URLs):"
    info "  SelfhostedPro: https://raw.githubusercontent.com/SelfhostedPro/selfhosted_templates/yacht/Template/template.json"
    info "  Technorabilia: https://raw.githubusercontent.com/technorabilia/portainer-templates/main/lsio/templates/technorabilia-lsio-templates.json"
    info "  Lissy93: https://raw.githubusercontent.com/Lissy93/portainer-templates/main/templates.json"
    echo
    info "If any containers are not required, simply remove as follows for a single container name"
    info "   ${TAG_CMD_TEXT_COLOR}docker stop <name>; docker rm <name>; docker image prune${COLOR_RESET}"
    info "Using 'stop' instead of 'rm -f' cleanly removes the container (configs will be intact)."
    info "   ${TAG_CMD_TEXT_COLOR}docker compose -f docker-dashboards.yaml up -d heimdall${COLOR_RESET}   # To create a new container"
    info "To remove all containers:   ${TAG_CMD_TEXT_COLOR}${0##*/} --remove${COLOR_RESET}"
    info "All containers in the yaml are completely removed, but the host configs will remain"

    # 6. Useful Commands Section
    heading "Step 6: Useful Docker & Compose Commands"
    info "Here are some commands you might find useful for managing this stack:"
    echo -e "${TEXT_MSG_COLOR}  - List services and their status:${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} -f \"${COMPOSE_FILE}\" -p \"${PROJECT_NAME}\" ps${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}  - Start/Update all services in the background:${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} -f \"${COMPOSE_FILE}\" -p \"${PROJECT_NAME}\" up -d${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}  - Stop and remove containers & networks (configs on host remain):${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} -f \"${COMPOSE_FILE}\" -p \"${PROJECT_NAME}\" down${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}  - View logs for a specific service (e.g., portainer):${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} -f \"${COMPOSE_FILE}\" -p \"${PROJECT_NAME}\" logs -f portainer${COLOR_RESET} (or yacht, dockge, dozzle, watchtower, diun)" # Updated
    echo -e "${TEXT_MSG_COLOR}  - Restart a specific service (e.g., portainer):${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} -f \"${COMPOSE_FILE}\" -p \"${PROJECT_NAME}\" restart portainer${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}  - Access a shell inside a container (e.g., portainer):${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} -f \"${COMPOSE_FILE}\" -p \"${PROJECT_NAME}\" exec portainer sh${COLOR_RESET}"
    echo ""

}

# --- Main Script Logic ---
if ! command_exists docker; then
    _print_tag_message "$TAG_ERROR_COLOR" "[ERROR]  " "Docker is not installed or not in PATH. Please install Docker first."
    exit 1
fi
if ! docker ps > /dev/null 2>&1; then 
    _print_tag_message "$TAG_ERROR_COLOR" "[ERROR]  " "Docker daemon is not running or accessible. Please start Docker."
    exit 1
fi

initialize_docker_compose_cmd 

if [[ "$1" == "--remove" ]]; then
    handle_stop
else
    main_startup
fi

exit 0
