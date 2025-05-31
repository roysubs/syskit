#!/usr/bin/env bash
# Author: Roy Wiseman 2025-05

# --- Configuration ---
readonly COMPOSE_FILE="docker-books.yaml"
readonly PROJECT_NAME="docker_books" # Explicit project name for Docker Compose
readonly ENV_FILE=".env"             # For storing PRIMARY_IP

# Service details for final information display
# Format: "service_name_in_yaml|Display Name|Host Config Paths|Access URL(s) (uses direct hostname -I)|Notes"
readonly SERVICES_INFO=(
    "calibre_web|Calibre-web|~/.config/calibre-web-docker/config (config), ~/.config/calibre-web-docker/books (library)|http://$(hostname -I | awk '{print $1}' || echo 'localhost'):8083|Point to Calibre library in /books. Default user/pass: admin/admin123 after initial setup."
    "kavita|Kavita|~/.config/kavita-docker/config (config), ~/.config/kavita-docker/series (media), ~/.config/kavita-docker/covers (cache)|http://$(hostname -I | awk '{print $1}' || echo 'localhost'):5000|Digital library. Add media to 'series' dir. Create admin on first visit."
    "wallabag|Wallabag|~/.config/wallabag-docker/data (database/config), ~/.config/wallabag-docker/images (article images)|http://$(hostname -I | awk '{print $1}' || echo 'localhost'):8084|Save web pages. Default login may vary (e.g. wallabag/wallabag) or create new user on first setup."
    "freshrss|FreshRSS|~/.config/freshrss-docker (config & data)|http://$(hostname -I | awk '{print $1}' || echo 'localhost'):8085|RSS feed aggregator. Setup on first visit."
    "mealie|Mealie|~/.config/mealie-docker/data (config & data)|http://$(hostname -I | awk '{print $1}' || echo 'localhost'):9090|Recipe manager. Default: changeme@example.com / MyPassword. CHANGE IT after first login!"
    "stirling_pdf|Stirling PDF|~/.config/stirling-pdf-docker/config (settings), ~/.config/stirling-pdf-docker/tessdata (OCR data)|http://$(hostname -I | awk '{print $1}' || echo 'localhost'):8086|Web-based PDF tool. Place OCR language files in tessdata."
    "dokuwiki|DokuWiki|~/.config/dokuwiki-docker (config & data)|http://$(hostname -I | awk '{print $1}' || echo 'localhost'):8087|Wiki software. Complete setup and create admin user on first visit."
    "bookstack|BookStack|~/.config/bookstack-docker (config & data)|http://$(hostname -I | awk '{print $1}' || echo 'localhost'):8088|Information platform. Default: admin@admin.com / password. CHANGE IT!"
)

# Host directories for config/data (paths from your docker-books.yaml)
readonly HOST_DIRS=(
    "${HOME}/.config/calibre-web-docker/config"
    "${HOME}/.config/calibre-web-docker/books"
    "${HOME}/.config/kavita-docker/config"
    "${HOME}/.config/kavita-docker/series"
    "${HOME}/.config/kavita-docker/covers"
    "${HOME}/.config/wallabag-docker/data"
    "${HOME}/.config/wallabag-docker/images"
    "${HOME}/.config/freshrss-docker"
    "${HOME}/.config/mealie-docker/data"
    "${HOME}/.config/stirling-pdf-docker/config"
    "${HOME}/.config/stirling-pdf-docker/tessdata"
    "${HOME}/.config/dokuwiki-docker"
    "${HOME}/.config/bookstack-docker"
)

# --- Colors ---
COLOR_RESET='\033[0m'
TITLE_BOX_COLOR='\033[1;33m'  # Bright Yellow
TAG_INFO_COLOR='\033[1;37m'    # Bold White
TAG_SUCCESS_COLOR='\033[0;32m' # Green
TAG_WARN_COLOR='\033[0;33m'    # Yellow
TAG_ERROR_COLOR='\033[0;31m'   # Red
TAG_HEADING_COLOR='\033[0;36m' # Cyan
TAG_CMD_HASH_COLOR='\033[0;37m' # White for '#'
TAG_CMD_TEXT_COLOR='\033[0;32m' # Green for command text
TEXT_MSG_COLOR='\033[0;37m'      # Normal White
TEXT_STRONG_WARN_COLOR='\033[1;31m' # Bold Red

# --- Helper Functions ---
_print_tag_message() {
    local tag_color="$1"
    local tag_text="$2"
    local message="$3"
    echo -e "${tag_color}${tag_text}${COLOR_RESET}${TEXT_MSG_COLOR} ${message}${COLOR_RESET}"
}
info() {    _print_tag_message "$TAG_INFO_COLOR"    "[INFO]   " "$1"; }
success() { _print_tag_message "$TAG_SUCCESS_COLOR" "[SUCCESS]" "$1"; }
warn() {    _print_tag_message "$TAG_WARN_COLOR"    "[WARNING]" "$1"; }
error() {   _print_tag_message "$TAG_ERROR_COLOR"    "[ERROR]  " "$1"; }
heading() { echo -e "\n${TAG_HEADING_COLOR}>>>${COLOR_RESET}${TEXT_MSG_COLOR} ${1}${COLOR_RESET}"; }

run_cmd() {
    echo -e "${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${*}${COLOR_RESET}" >&2
    "$@"
    return $?
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# --- Docker Compose Command Helper ---
DOCKER_COMPOSE_CMD_ARRAY=()

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
}

# --- Environment File Setup ---
setup_env_file() {
    heading "Preparing Environment Configuration"
    local current_primary_ip
    current_primary_ip=$(hostname -I | awk '{print $1}')

    if [[ -z "$current_primary_ip" ]]; then
        warn "Could not determine primary IP using 'hostname -I'. Using 'localhost' for APP_URL configurations in .env file."
        warn "This might affect external accessibility for services like Bookstack and Wallabag if not overridden."
        current_primary_ip="localhost"
    fi

    # Check if .env file exists and if PRIMARY_IP needs update
    local old_ip=""
    if [[ -f "$ENV_FILE" ]]; then
        old_ip=$(grep '^PRIMARY_IP=' "$ENV_FILE" | cut -d'=' -f2)
    fi

    if [[ "$old_ip" != "$current_primary_ip" || ! -f "$ENV_FILE" ]]; then
        info "Updating ${ENV_FILE} with PRIMARY_IP=${current_primary_ip}"
        echo "PRIMARY_IP=${current_primary_ip}" > "$ENV_FILE"
        success "${ENV_FILE} created/updated."
    else
        success "${ENV_FILE} already up-to-date (PRIMARY_IP=${current_primary_ip})."
    fi
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
    warn "This action is IRREVERSIBLE and will delete all settings and user data for these services."

    local confirm1=""
    local confirm2=""

    echo -e "${TEXT_MSG_COLOR}The following directories and their contents will be PERMANENTLY DELETED:${COLOR_RESET}"
    for dir in "${HOST_DIRS[@]}"; do
        echo -e "${TEXT_STRONG_WARN_COLOR}  - ${dir/\~/$HOME}${COLOR_RESET}"
    done
    echo ""

    read -r -p "$(echo -e "${TEXT_STRONG_WARN_COLOR}ARE YOU ABSOLUTELY SURE? Type 'YES' to proceed: ${COLOR_RESET}")" confirm1

    if [[ "$confirm1" == "YES" ]]; then
        read -r -p "$(echo -e "${TEXT_STRONG_WARN_COLOR}FINAL CONFIRMATION: Type 'YES' to delete listed folders: ${COLOR_RESET}")" confirm2
        if [[ "$confirm2" == "YES" ]]; then
            info "Proceeding with deletion of configuration and data folders..."
            for dir in "${HOST_DIRS[@]}"; do
                expanded_dir="${dir/\~/$HOME}"
                if [[ -d "$expanded_dir" ]]; then
                    if run_cmd sudo rm -rf "$expanded_dir"; then
                        success "Successfully deleted: $expanded_dir"
                    else
                        error "Failed to delete: $expanded_dir. Check permissions or remove manually."
                    fi
                else
                    warn "Directory not found (already deleted?): $expanded_dir"
                fi
            done
            if [[ -f "$ENV_FILE" ]]; then
                if run_cmd rm -f "$ENV_FILE"; then
                    success "Successfully deleted: $ENV_FILE"
                else
                    error "Failed to delete: $ENV_FILE. Please remove manually."
                fi
            fi
            success "Cleanup of configuration, data folders, and .env file complete."
        else
            info "Cleanup aborted. Folders were NOT deleted."
        fi
    else
        info "Cleanup aborted. Folders were NOT deleted."
    fi
    exit 0
}

# --- Main Startup Script ---
main_startup() {
    echo -e "${TITLE_BOX_COLOR}=================================================${COLOR_RESET}"
    echo -e "${TITLE_BOX_COLOR}     Docker Books & Content Startup Script       ${COLOR_RESET}"
    echo -e "${TITLE_BOX_COLOR}=================================================${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}This script will set up and manage various book and content organization services"
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

    # 1b. Setup .env file
    setup_env_file

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
    heading "Step 3: Starting/Updating Docker Book Services"
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
    heading "Step 4: Current Status of Docker Book Services"
    info "Displaying status for containers in project '${PROJECT_NAME}':"
    echo -e "${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}docker ps --filter \"label=com.docker.compose.project=${PROJECT_NAME}\" --format \"table {{.Names}}\t{{truncate .ID 12}}\t{{.Status}}\t{{.Ports}}\"${COLOR_RESET}"
    docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "table {{.Names}}\t{{truncate .ID 12}}\t{{.Status}}\t{{.Ports}}"
    if [[ $? -ne 0 ]]; then
        warn "Could not retrieve specific container status using 'docker ps'. 'docker compose ps' might have details."
    fi
    echo ""

    # 5. Display Access Information
    heading "Step 5: Access Information & Setup Notes"
    local primary_ip_display
    primary_ip_display=$(hostname -I | awk '{print $1}')
    if [[ -z "$primary_ip_display" ]]; then
        warn "Could not determine primary IP using 'hostname -I'. URLs below will use 'localhost'."
        primary_ip_display="localhost"
    else
        success "Services should be accessible via IP: $primary_ip_display (or 'localhost' if on the same machine)."
    fi
    info "Remember to check the PUID/PGID settings in '${COMPOSE_FILE}' for linuxserver.io images."


    for service_info_line in "${SERVICES_INFO[@]}"; do
        IFS="|" read -r service_yaml_name display_name config_paths urls notes <<< "$service_info_line"

        echo ""
        echo -e "${TAG_HEADING_COLOR}--- ${display_name} ---${COLOR_RESET}"

        local container_id
        container_id=$(docker compose -p "${PROJECT_NAME}" ps -q "${service_yaml_name}" 2>/dev/null)
        local actual_status=""
        local current_status="${TAG_WARN_COLOR}Unknown${COLOR_RESET}"

        if [[ -n "$container_id" ]]; then
            actual_status=$(docker inspect --format "{{.State.Status}}" "$container_id" 2>/dev/null)
        fi

        if [[ -n "$actual_status" ]]; then
            if [[ "$actual_status" == "running" ]]; then
                current_status="${TAG_SUCCESS_COLOR}Running${COLOR_RESET}"
            elif [[ "$actual_status" == "exited" ]]; then
                current_status="${TAG_ERROR_COLOR}Exited - Check logs: ${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} -p ${PROJECT_NAME} logs ${service_yaml_name}${COLOR_RESET}"
            else
                current_status="${TAG_WARN_COLOR}${actual_status}${COLOR_RESET}"
            fi
        else
             # Fallback for cases where compose ps -q might fail but container exists by service name
            actual_status_fallback=$(docker inspect --format "{{.State.Status}}" "${PROJECT_NAME}-${service_yaml_name}-1" 2>/dev/null || docker inspect --format "{{.State.Status}}" "${service_yaml_name}" 2>/dev/null)
            if [[ -n "$actual_status_fallback" ]]; then
                if [[ "$actual_status_fallback" == "running" ]]; then
                    current_status="${TAG_SUCCESS_COLOR}Running${COLOR_RESET}"
                elif [[ "$actual_status_fallback" == "exited" ]]; then
                    current_status="${TAG_ERROR_COLOR}Exited - Check logs for ${service_yaml_name}${COLOR_RESET}"
                else
                    current_status="${TAG_WARN_COLOR}${actual_status_fallback}${COLOR_RESET}"
                fi
            else
                current_status="${TAG_ERROR_COLOR}Not Found (or error fetching status)${COLOR_RESET}"
            fi
        fi
        echo -e "${TEXT_MSG_COLOR}  Status:${COLOR_RESET} ${current_status}"

        # Substitute primary_ip_display into the URLs for display
        display_urls="${urls//\$(hostname -I | awk '{print \$1}' || echo 'localhost')/$primary_ip_display}"
        echo -e "${TEXT_MSG_COLOR}  Access URL(s): ${TAG_CMD_TEXT_COLOR}${display_urls}${COLOR_RESET}"

        if [[ "$config_paths" != "N/A"* ]]; then
            expanded_config_paths="${config_paths//\~/$HOME}"
            echo -e "${TEXT_MSG_COLOR}  Host Config/Data Path(s): ${expanded_config_paths}${COLOR_RESET}"
        fi
        echo -e "${TEXT_MSG_COLOR}  Notes: ${notes}${COLOR_RESET}"
    done
    echo -e "${TAG_HEADING_COLOR}-------------------------------------------------${COLOR_RESET}"
    echo ""

    success "Setup script complete! Your Docker book services should be accessible."
    info "You can quickly stop services and optionally remove data with: ./${0##*/} --remove"
    info "If any containers are not required, comment them out in '${COMPOSE_FILE}' and run this script again,"
    info "or use: ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[@]} down <service_name>${COLOR_RESET} followed by ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[@]} up -d --remove-orphans${COLOR_RESET}"
    echo

    # 6. Useful Commands Section
    heading "Step 6: Useful Docker & Compose Commands"
    info "Here are some commands you might find useful for managing this stack:"
    echo -e "${TEXT_MSG_COLOR}  - List services and their status:${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[@]} ps${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}  - Start/Update all services in the background:${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[@]} up -d${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}  - Stop and remove containers & networks (configs on host remain):${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[@]} down${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}  - View logs for a specific service (e.g., calibre_web):${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[@]} logs -f calibre_web${COLOR_RESET} (or kavita, wallabag, etc.)"
    echo -e "${TEXT_MSG_COLOR}  - Restart a specific service (e.g., calibre_web):${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[@]} restart calibre_web${COLOR_RESET}"
    echo -e "${TEXT_MSG_COLOR}  - Access a shell inside a container (e.g., calibre_web):${COLOR_RESET}"
    echo -e "    ${TAG_CMD_HASH_COLOR}# ${TAG_CMD_TEXT_COLOR}${DOCKER_COMPOSE_CMD_ARRAY[@]} exec calibre_web sh${COLOR_RESET} (or bash)"
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
