#!/usr/bin/env bash
# Author: Roy Wiseman 2025-04

# --- Configuration ---
readonly COMPOSE_FILE="docker-media-servers.yaml"
readonly PROJECT_NAME="media_servers_pack" # Explicit project name for Docker Compose
MEDIA_FOLDER_PATH="" # Will be set by user input

# --- Important Note for User ---
# This script helps manage a set of media server containers for comparison.
# You MUST create a 'docker-media-servers.yaml' file with the service definitions.
# Key things to include in your YAML for each service:
#   - Correct image (e.g., linuxserver/jellyfin, linuxserver/plex, linuxserver/emby)
#   - Volume for configuration (matching HOST_DIRS below)
#   - Volume(s) for your media libraries (e.g., map subfolders from the media path you'll designate,
#     like ${MEDIA_FOLDER_PATH}/movies to /movies in the container)
#   - Unique host port mappings (e.g., Jellyfin on 8096, Emby on 8097, Plex on 32400)
#   - For Plex, use a PLEX_CLAIM token for initial setup.
# ---

# Service details for final information display
# Format: "container_name_in_yaml|Display Name|Host Config Paths|Access URL(s)|Notes"
# Notes will be updated to refer to the user-designated media folder.
readonly SERVICES_INFO_TEMPLATE=(
    "jellyfin|Jellyfin|~/.config/media_servers_pack/jellyfin|http://$(hostname -I | awk '{print $1}'):8096|Map media from your designated media folder (e.g., %MEDIA_FOLDER%/tvshows) in YAML. Default internal port 8096."
    "plex|Plex Media Server|~/.config/media_servers_pack/plex|http://$(hostname -I | awk '{print $1}'):32400/web|Claim server (use PLEX_CLAIM env var). Map /transcode. Map media from your designated media folder in YAML. Default port 32400."
    "emby|Emby Server|~/.config/media_servers_pack/emby|http://$(hostname -I | awk '{print $1}'):8097|Map media from your designated media folder in YAML. Default internal port 8096; map to host port 8097 in YAML to avoid Jellyfin conflict."
)
SERVICES_INFO=() # Will be populated after MEDIA_FOLDER_PATH is known

# Host directories for config/data
readonly HOST_DIRS=(
    "${HOME}/.config/media_servers_pack/jellyfin"
    "${HOME}/.config/media_servers_pack/plex"
    "${HOME}/.config/media_servers_pack/emby"
)

# --- Colors (Defined using printf for robustness) ---
COLOR_RESET=$(printf '\033[0m')
TITLE_BOX_COLOR=$(printf '\033[1;33m')
TAG_INFO_COLOR=$(printf '\033[1;37m')
TAG_SUCCESS_COLOR=$(printf '\033[0;32m')
TAG_WARN_COLOR=$(printf '\033[0;33m')
TAG_ERROR_COLOR=$(printf '\033[0;31m')
TAG_HEADING_COLOR=$(printf '\033[0;36m')
TAG_CMD_HASH_COLOR=$(printf '\033[0;37m')
TAG_CMD_TEXT_COLOR=$(printf '\033[0;32m')
TEXT_MSG_COLOR=$(printf '\033[0;37m')
TEXT_STRONG_WARN_COLOR=$(printf '\033[1;31m')

# --- Helper Functions ---
_print_tag_message() {
    local tag_color="$1"
    local tag_text="$2"
    local message="$3"
    printf "%b%s%b %b%s%b\n" "${tag_color}" "${tag_text}" "${COLOR_RESET}" "${TEXT_MSG_COLOR}" "${message}" "${COLOR_RESET}"
}

info() {    _print_tag_message "$TAG_INFO_COLOR"    "[INFO]   " "$1"; }
success() { _print_tag_message "$TAG_SUCCESS_COLOR" "[SUCCESS]" "$1"; }
warn() {    _print_tag_message "$TAG_WARN_COLOR"    "[WARNING]" "$1"; }
error() {   _print_tag_message "$TAG_ERROR_COLOR"    "[ERROR]  " "$1"; }
heading() { printf "\n%b>>>%b %b%s%b\n" "${TAG_HEADING_COLOR}" "${COLOR_RESET}" "${TEXT_MSG_COLOR}" "$1" "${COLOR_RESET}"; }

run_cmd() {
    printf "%b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${*}" "${COLOR_RESET}" >&2
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

# --- Stop and Cleanup Functionality ---
handle_stop() {
    heading "Stop and Cleanup Mode for Media Servers Pack"
    info "This will shut down the services defined in '${COMPOSE_FILE}'."

    if ! run_cmd "${DOCKER_COMPOSE_CMD_ARRAY[@]}" "down"; then
        error "Failed to shut down the Docker Compose stack. Please check messages above."
    else
        success "Docker Compose stack '${PROJECT_NAME}' shut down successfully."
    fi
    echo ""

    warn "WARNING: You can now choose to remove the persistent configuration folders."
    warn "This action is IRREVERSIBLE and will delete all settings for these media servers."
    warn "(Your actual media library files will NOT be touched by this script's cleanup)."

    local confirm1=""
    local confirm2=""

    printf "%bThe following configuration directories and their contents will be PERMANENTLY DELETED:%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    for dir in "${HOST_DIRS[@]}"; do
        printf "%b  - %s%b\n" "${TEXT_STRONG_WARN_COLOR}" "${dir/\~/$HOME}" "${COLOR_RESET}"
    done
    echo ""

    printf "%bARE YOU ABSOLUTELY SURE? Type 'YES' to proceed to the final confirmation: %b" "${TEXT_STRONG_WARN_COLOR}" "${COLOR_RESET}"
    read -r confirm1

    if [[ "$confirm1" == "YES" ]]; then
        printf "%bFINAL CONFIRMATION: Type 'YES' to delete all listed configuration folders: %b" "${TEXT_STRONG_WARN_COLOR}" "${COLOR_RESET}"
        read -r confirm2
        if [[ "$confirm2" == "YES" ]]; then
            info "Proceeding with deletion of configuration folders..."
            for dir in "${HOST_DIRS[@]}"; do
                expanded_dir="${dir/\~/$HOME}"
                if [[ -d "$expanded_dir" ]]; then
                    if run_cmd rm -rf "$expanded_dir"; then
                        success "Successfully deleted: $expanded_dir"
                    else
                        error "Failed to delete: $expanded_dir. Please check permissions or remove manually."
                    fi
                else
                    warn "Directory not found (already deleted?): $expanded_dir"
                fi
            done
            success "Cleanup of configuration folders complete."
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
    printf "%b=================================================%b\n" "${TITLE_BOX_COLOR}" "${COLOR_RESET}"
    printf "%b  Docker Media Servers Pack Startup Script     %b\n" "${TITLE_BOX_COLOR}" "${COLOR_RESET}"
    printf "%b=================================================%b\n" "${TITLE_BOX_COLOR}" "${COLOR_RESET}"
    printf "%bThis script will help you set up and compare Jellyfin, Plex, and Emby%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "%busing the Docker Compose file: %s%b\n" "${TEXT_MSG_COLOR}" "${COMPOSE_FILE}" "${COLOR_RESET}"
    printf "%bIt is designed to be idempotent for starting/stopping containers.%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    echo ""
    info "Please ensure you have created '${COMPOSE_FILE}' with service definitions,"
    info "including mappings for your media libraries and unique host ports."
    info "The script will now ask for your main media folder location to remind you."
    echo ""

    # --- Get Media Folder Path from User (New) ---
    heading "Step 0.5: Designating Your Host Media Folder (for your YAML setup)"
    local default_media_folder="${HOME}/Downloads"
    local user_media_folder_input=""
    printf "%bPlease specify the main folder on your host system where your media%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "%b(movies, TV shows, music, etc.) is located or will be located.%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "%bThis script will NOT create this folder or manage its contents directly.%b\n" "${TAG_WARN_COLOR}" "${COLOR_RESET}"
    printf "%bIt will be used in informational messages to remind you how to map volumes%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "%bin your separate '%s' file.%b\n" "${TEXT_MSG_COLOR}" "${COMPOSE_FILE}" "${COLOR_RESET}"
    read -r -p "$(printf "%bEnter full path to your media folder [default: %s]: %b" "${TEXT_MSG_COLOR}" "${default_media_folder}" "${COLOR_RESET}")" user_media_folder_input
    MEDIA_FOLDER_PATH="${user_media_folder_input:-$default_media_folder}" # Use default if input is empty
    
    # Expand tilde if present
    if [[ "${MEDIA_FOLDER_PATH}" == "~" ]]; then
        MEDIA_FOLDER_PATH="${HOME}"
    elif [[ "${MEDIA_FOLDER_PATH}" == "~/"* ]]; then
        MEDIA_FOLDER_PATH="${HOME}/${MEDIA_FOLDER_PATH#\~/}"
    fi

    # Basic check if path is absolute (starts with /)
    if [[ ! "${MEDIA_FOLDER_PATH}" = /* ]]; then
        warn "The path entered does not appear to be absolute: ${MEDIA_FOLDER_PATH}"
        warn "Please ensure you use absolute paths for Docker volume mappings in your YAML."
    fi

    success "Media folder designated for reference: ${MEDIA_FOLDER_PATH}"
    info "In your '${COMPOSE_FILE}', you should map subfolders like:"
    info "  e.g., host '${MEDIA_FOLDER_PATH}/movies' to '/movies' (or similar) inside each container."
    info "  e.g., host '${MEDIA_FOLDER_PATH}/tv_shows' to '/tvshows' (or similar) inside each container."
    echo ""

    # Populate SERVICES_INFO with the MEDIA_FOLDER_PATH placeholder replaced
    for template_info_line in "${SERVICES_INFO_TEMPLATE[@]}"; do
        SERVICES_INFO+=("${template_info_line//%MEDIA_FOLDER%/$MEDIA_FOLDER_PATH}")
    done

    # 1. Prerequisites Check
    heading "Step 1: Checking Prerequisites"
    success "Docker is installed and accessible (checked via Docker Compose init)."
    success "Docker Compose found (${DOCKER_COMPOSE_CMD_ARRAY[0]} ${DOCKER_COMPOSE_CMD_ARRAY[1]:-} will be used)."

    if [[ ! -f "$COMPOSE_FILE" ]]; then
        error "Docker Compose file '${COMPOSE_FILE}' not found in the current directory!"
        error "Please create it with definitions for Jellyfin, Plex, and Emby."
        error "Example service snippets can be found on Docker Hub or linuxserver.io."
        error "Crucially, ensure you map your media from subfolders of '${MEDIA_FOLDER_PATH}'"
        error "and resolve any port conflicts (e.g., map Emby's internal 8096 to host 8097)."
        exit 1
    fi
    success "Compose file '${COMPOSE_FILE}' found."

    # 2. Ensure Host Directories Exist for Configuration
    heading "Step 2: Ensuring Host Directories for Persistent Configuration"
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
    heading "Step 3: Starting/Updating Media Server Services"
    info "This will use Docker Compose to bring services up or update them if needed."
    info "If services are already running and up-to-date, this command will make no changes."
    warn "Ensure your '${COMPOSE_FILE}' is correctly configured with image names, PUID/PGID,"
    warn "unique host ports, and volume mappings for BOTH config AND your media libraries"
    warn "(e.g., using subfolders of '${MEDIA_FOLDER_PATH}' like '${MEDIA_FOLDER_PATH}/movies')."
    info "Please wait, this may take a moment if images need to be pulled or media is scanned on first start..."

    if run_cmd "${DOCKER_COMPOSE_CMD_ARRAY[@]}" "up" "-d" "--remove-orphans"; then
        success "Docker Compose 'up' command completed successfully."
        info "Containers should now be starting. It might take a few moments for them to be fully operational."
    else
        error "Docker Compose 'up' command failed. See output above for details."
        warn "Common issues leading to 'Not Found' statuses or startup failures:"
        warn " - Incorrect image names in '${COMPOSE_FILE}'."
        warn " - Volume mapping errors: Ensure paths to your media libraries (e.g., '${MEDIA_FOLDER_PATH}/movies') are correct and accessible."
        warn " - Port conflicts: Make sure Jellyfin (e.g., 8096) and Emby (e.g., 8097) use different host ports."
        warn " - PUID/PGID environment variables not set or incorrect for your media file permissions."
        warn " - For Plex: Server claim token (`PLEX_CLAIM`) missing or expired for initial setup."
        warn " - Insufficient system resources (CPU/RAM)."
        warn "To debug, run without -d for more logs: ${DOCKER_COMPOSE_CMD_ARRAY[*]} up --remove-orphans"
        # Do not exit here, allow status check to proceed to show "Not Found" if they failed.
    fi
    echo ""
    info "Allow a minute for services to initialize before checking status or access URLs."
    echo ""

    # 4. Display Status of Managed Containers
    heading "Step 4: Current Status of Media Server Services"
    info "Displaying status for containers in project '${PROJECT_NAME}':"
    # (This docker ps command is just for a quick overview)
    printf "%b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "docker ps --filter \"label=com.docker.compose.project=${PROJECT_NAME}\" --format \"table {{.Names}}\\t{{truncate .ID 12}}\\t{{.Status}}\\t{{.Ports}}\"" "${COLOR_RESET}"
    docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "table {{.Names}}\t{{truncate .ID 12}}\t{{.Status}}\t{{.Ports}}"
    if [[ $? -ne 0 ]]; then
        warn "Could not retrieve specific container status using 'docker ps'."
    fi
    echo ""

    # 5. Display Access Information & Detailed Status
    heading "Step 5: Access Information & Detailed Status"
    local primary_ip
    primary_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$primary_ip" ]]; then
        warn "Could not determine primary IP using 'hostname -I'. URLs will use 'localhost'."
        primary_ip="localhost" # Fallback
    else
        success "Services should be accessible via IP: $primary_ip (or 'localhost' if on the same machine)."
    fi

    for service_info_line in "${SERVICES_INFO[@]}"; do
        IFS="|" read -r container_name display_name config_paths urls notes <<< "$service_info_line"

        echo "" # Newline before each service block
        printf "%b--- %s ---%b\n" "${TAG_HEADING_COLOR}" "${display_name}" "${COLOR_RESET}"

        local actual_status_raw
        # Check both common Compose naming conventions
        actual_status_raw=$(docker inspect --format "{{.State.Status}}" "${PROJECT_NAME}-${container_name}-1" 2>/dev/null || docker inspect --format "{{.State.Status}}" "$container_name" 2>/dev/null)
        local actual_status
        actual_status=$(echo -n "${actual_status_raw}" | tr -d '[:cntrl:]') # Sanitize

        local current_status_text=""
        local current_status_color=""

        if [[ -n "$actual_status" ]]; then
            if [[ "$actual_status" == "running" ]]; then
                current_status_text="Running"
                current_status_color="${TAG_SUCCESS_COLOR}"
            elif [[ "$actual_status" == "exited" ]];then
                current_status_text="Exited - Check logs: ${DOCKER_COMPOSE_CMD_ARRAY[*]} logs ${container_name}"
                current_status_color="${TAG_ERROR_COLOR}"
            else # e.g., created, restarting, paused, dead
                current_status_text="${actual_status}" # Show the actual status like 'restarting'
                current_status_color="${TAG_WARN_COLOR}"
            fi
        else
            current_status_text="Not Found (or error fetching status) - If just started, wait a moment. Else, check compose logs: ${DOCKER_COMPOSE_CMD_ARRAY[*]} logs ${container_name}"
            current_status_color="${TAG_ERROR_COLOR}"
        fi
        
        local current_status_colored="${current_status_color}${current_status_text}${COLOR_RESET}"
        # Using printf for the status line
        printf "%b  Status:%b %s\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}" "${current_status_colored}"

        local processed_urls=${urls//\$(hostname -I | awk '{print \$1}')/$primary_ip}
        printf "%b  Access URL(s): %b%s%b\n" "${TEXT_MSG_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${processed_urls}" "${COLOR_RESET}"

        local expanded_config_paths="${config_paths//\~/$HOME}"
        printf "%b  Host Config/Data Path(s): %s%b\n" "${TEXT_MSG_COLOR}" "${expanded_config_paths}" "${COLOR_RESET}"
        printf "%b  Notes: %s%b\n" "${TEXT_MSG_COLOR}" "${notes}" "${COLOR_RESET}"
    done
    printf "%b-------------------------------------------------%b\n" "${TAG_HEADING_COLOR}" "${COLOR_RESET}"
    echo ""

    success "Setup script complete! Your Media Servers should be starting up."
    info "Remember to configure libraries and any first-time setup steps in each media server's web UI."
    echo ""

    # --- Post-Setup Advice (New) ---
    heading "Step 7: Next Steps - Comparing and Pruning Your Media Servers"
    warn "Running all three media servers (Jellyfin, Plex, Emby) simultaneously can be resource-intensive,"
    warn "especially during library scans or if transcoding occurs. This setup is intended for you to"
    warn "test each one, explore their features, and decide which best fits your needs."
    echo ""
    info "Once you've chosen your preferred media server, it's recommended to stop and remove the ones"
    info "you no longer wish to use to free up system resources and disk space."
    echo ""
    printf "%bTo stop and remove a specific service (e.g., 'plex'):%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "  %b# %b%s down plex%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${DOCKER_COMPOSE_CMD_ARRAY[*]}" "${COLOR_RESET}"
    printf "%b(Replace 'plex' with 'jellyfin' or 'emby' as needed).%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    echo ""
    info "The 'down' command stops and removes the container. Your configuration files"
    info "(in ~/.config/media_servers_pack/*) will remain unless you use this script's --remove option with full cleanup."
    info "Your actual media library files are never touched by these 'down' or cleanup commands."
    echo ""
    printf "%bTo reclaim disk space from unused Docker images after removing containers:%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "  %b# %bdocker image prune -a -f%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${COLOR_RESET}"
    info "(This removes all unused images, not just for this pack. Use with care or prune specific images.)"
    echo ""

    # --- Specific Note for Plex Claiming (New) ---
    heading "Step 8: Important Note for Plex Users - Server Claiming"
    info "If you're setting up Plex for the first time with this script:"
    info "1. Plex needs to be 'claimed' by your Plex account to be fully functional and manageable."
    info "2. For easiest setup, especially headless, you should include a `PLEX_CLAIM` environment"
    info "   variable in your '${COMPOSE_FILE}' for the Plex service on its first run."
    info "3. How to get a claim token:"
    printf "%b     a. Open your web browser and go to: %bhttps://plex.tv/claim%b\n" "${TEXT_MSG_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${COLOR_RESET}"
    info "     b. Log in with your Plex account."
    info "     c. You'll be given a claim token string (e.g., claim-xxxxxxxxxxxxxxxxxxxx)."
    info "     d. Copy this token and add it to your Plex service definition in '${COMPOSE_FILE}':"
    info "        environment:"
    info "          - PLEX_CLAIM=YOUR_COPIED_TOKEN_HERE"
    info "4. Start Plex. It should automatically claim itself."
    info "5. This token is usually only needed for the very first setup. Once claimed, you can often"
    info "   remove the PLEX_CLAIM variable from your '${COMPOSE_FILE}' for subsequent restarts."
    info "If you didn't use a claim token and can't access server settings, you might need to"
    info "recreate the Plex container with a fresh config and a new claim token."
    echo ""

    # Useful Commands Section (can remain largely the same)
    heading "Step 9: Useful Docker & Compose Commands"
    info "Here are some commands you might find useful for managing this stack:"
    printf "%b  - List services and their status:%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "    %b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${DOCKER_COMPOSE_CMD_ARRAY[*]} ps" "${COLOR_RESET}"
    printf "%b  - View logs for a specific service (e.g., jellyfin):%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "    %b# %b%s%b (or plex, emby, etc.)\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${DOCKER_COMPOSE_CMD_ARRAY[*]} logs -f jellyfin" "${COLOR_RESET}"
    echo ""
}


# --- Main Script Logic ---
if ! command_exists docker; then
    printf "%b[ERROR]  %b %bDocker is not installed or not in PATH. Please install Docker first.%b\n" "${TAG_ERROR_COLOR}" "${COLOR_RESET}" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    exit 1
fi
if ! docker ps > /dev/null 2>&1; then
    printf "%b[ERROR]  %b %bDocker daemon is not running or accessible. Please start Docker.%b\n" "${TAG_ERROR_COLOR}" "${COLOR_RESET}" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    exit 1
fi

initialize_docker_compose_cmd

if [[ "$1" == "--remove" ]]; then
    handle_stop
else
    main_startup
fi

exit 0
