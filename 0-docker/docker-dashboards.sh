#!/usr/bin/env bash
# Author: Roy Wiseman 2025-01

# --- Configuration ---
readonly COMPOSE_FILE="docker-dashboards.yaml"
readonly PROJECT_NAME="docker_dashboards" # Explicit project name for Docker Compose

# Service details for final information display
# Format: "container_name_in_yaml|Display Name|Host Config Paths|Access URL(s)|Notes"
# Ensure no leading/trailing invisible characters in these strings
readonly SERVICES_INFO=(
    "heimdall|Heimdall|~/.config/heimdall-docker|http://$(hostname -I | awk '{print $1}'):8080 (HTTP) or https://$(hostname -I | awk '{print $1}'):8443 (HTTPS)|Set PUID/PGID & TZ in YAML. First visit setup."
    "homer|Homer|~/.config/homer-docker/assets|http://$(hostname -I | awk '{print $1}'):8081|Create 'config.yml' in host assets folder. See Homer docs."
    "homarr|Homarr|~/.config/homarr-docker/configs, ~/.config/homarr-docker/icons|http://$(hostname -I | awk '{print $1}'):7575|Initial setup via web UI. Docker socket for widgets (optional)."
    "dashy|Dashy|~/.config/dashy-docker/user-data|http://$(hostname -I | awk '{print $1}'):4001|Place/edit 'conf.yml' in host user-data folder or use UI."
    "homepage|Homepage|~/.config/homepage-docker|http://$(hostname -I | awk '{print $1}'):3001|Create config YAMLs (services.yaml, etc.) in host config folder."
    "flame|Flame|~/.config/flame-docker/data|http://$(hostname -I | awk '{print $1}'):5005|Setup via web UI. Optional: set PASSWORD env var in YAML."
)

# Host directories for config/data (paths from your docker-dashboards.yaml)
readonly HOST_DIRS=(
    "${HOME}/.config/heimdall-docker"
    "${HOME}/.config/homer-docker/assets"
    "${HOME}/.config/homarr-docker/configs"
    "${HOME}/.config/homarr-docker/icons"
    "${HOME}/.config/dashy-docker/user-data"
    "${HOME}/.config/homepage-docker"
    "${HOME}/.config/flame-docker/data"
)

# --- Colors (Defined using printf for robustness, though direct assignment was likely fine) ---
# Using process substitution with printf to avoid subshell newlines if assignments were more complex.
# For simple ANSI, direct is usually okay, but this is belt-and-suspenders.
COLOR_RESET=$(printf '\033[0m')

# Title
TITLE_BOX_COLOR=$(printf '\033[1;33m')  # Bright Yellow

# Tags
TAG_INFO_COLOR=$(printf '\033[1;37m')    # Bold White
TAG_SUCCESS_COLOR=$(printf '\033[0;32m') # Green
TAG_WARN_COLOR=$(printf '\033[0;33m')    # Yellow
TAG_ERROR_COLOR=$(printf '\033[0;31m')   # Red
TAG_HEADING_COLOR=$(printf '\033[0;36m') # Cyan
TAG_CMD_HASH_COLOR=$(printf '\033[0;37m') # White for '#'
TAG_CMD_TEXT_COLOR=$(printf '\033[0;32m') # Green for command text

# Text - Message part
TEXT_MSG_COLOR=$(printf '\033[0;37m')       # Normal White (or terminal default)
TEXT_STRONG_WARN_COLOR=$(printf '\033[1;31m') # Bold Red for critical warnings


# --- Helper Functions ---
_print_tag_message() { # Internal helper
    local tag_color="$1"
    local tag_text="$2"
    local message="$3"
    # Using printf for the main message line for consistency
    printf "%b%s%b %b%s%b\n" "${tag_color}" "${tag_text}" "${COLOR_RESET}" "${TEXT_MSG_COLOR}" "${message}" "${COLOR_RESET}"
}

info() {    _print_tag_message "$TAG_INFO_COLOR"    "[INFO]   " "$1"; } # Adjusted spacing for alignment
success() { _print_tag_message "$TAG_SUCCESS_COLOR" "[SUCCESS]" "$1"; }
warn() {    _print_tag_message "$TAG_WARN_COLOR"    "[WARNING]" "$1"; }
error() {   _print_tag_message "$TAG_ERROR_COLOR"    "[ERROR]  " "$1"; } # Adjusted spacing for alignment

# Using printf for heading as well
heading() { printf "\n%b>>>%b %b%s%b\n" "${TAG_HEADING_COLOR}" "${COLOR_RESET}" "${TEXT_MSG_COLOR}" "$1" "${COLOR_RESET}"; }


# Function to display and execute a command
run_cmd() {
    # Print command to stderr for visibility. Using printf.
    printf "%b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${*}" "${COLOR_RESET}" >&2
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
    echo "" # Explicit blank line

    warn "WARNING: You can now choose to remove the persistent configuration and data folders."
    warn "This action is IRREVERSIBLE and will delete all settings and user data for these services."

    local confirm1=""
    local confirm2=""

    printf "%bThe following directories and their contents will be PERMANENTLY DELETED:%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    for dir in "${HOST_DIRS[@]}"; do
        printf "%b  - %s%b\n" "${TEXT_STRONG_WARN_COLOR}" "${dir/\~/$HOME}" "${COLOR_RESET}"
    done
    echo "" # Explicit blank line

    # Using printf for prompts to avoid echo -e complexities with read -r -p
    printf "%bARE YOU ABSOLUTELY SURE? Type 'YES' to proceed to the final confirmation: %b" "${TEXT_STRONG_WARN_COLOR}" "${COLOR_RESET}"
    read -r confirm1

    if [[ "$confirm1" == "YES" ]]; then
        printf "%bFINAL CONFIRMATION: This is your last chance. Type 'YES' to delete all listed config and data folders: %b" "${TEXT_STRONG_WARN_COLOR}" "${COLOR_RESET}"
        read -r confirm2
        if [[ "$confirm2" == "YES" ]]; then
            info "Proceeding with deletion of configuration and data folders..."
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
    printf "%b=================================================%b\n" "${TITLE_BOX_COLOR}" "${COLOR_RESET}"
    printf "%b  Docker Dashboards Startup Script             %b\n" "${TITLE_BOX_COLOR}" "${COLOR_RESET}" # Adjusted spacing
    printf "%b=================================================%b\n" "${TITLE_BOX_COLOR}" "${COLOR_RESET}"
    printf "%bThis script will set up and manage various dashboard applications%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "%busing the Docker Compose file: %s%b\n" "${TEXT_MSG_COLOR}" "${COMPOSE_FILE}" "${COLOR_RESET}"
    printf "%bIt is designed to be idempotent.%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"

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
        expanded_dir="${dir/\~/$HOME}" # Bash expansion of ~
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

    # Create dummy config files (using printf for file content where simple)
    local homer_config_file="${HOME}/.config/homer-docker/assets/config.yml"
    if [[ ! -f "$homer_config_file" ]]; then
        info "Homer's config.yml not found. Creating a minimal placeholder at: $homer_config_file"
        printf "%s\n" \
            "# Homer Dashboard Configuration" \
            "# Get started by editing this file!" \
            "# Docs: https://github.com/bastienwirtz/homer/blob/main/docs/configuration.md" \
            "" \
            "title: \"My Homer Dashboard\"" \
            "subtitle: \"My awesome services\"" \
            "" \
            "# Optional:" \
            "# logo: \"assets/logo.png\"" \
            "# header: true" \
            "# footer: \"<p>Created with <span class='has-text-danger'>❤️</span></p>\"" \
            "" \
            "# Optional theming" \
            "# theme: default # or 'dark'" \
            "" \
            "# Optional custom internationalisation" \
            "# defaults:" \
            "#   language: en" \
            "" \
            "# Services" \
            "# services:" \
            "#   - name: \"My Group\"" \
            "#     icon: \"fas fa-layer-group\"" \
            "#     items:" \
            "#       - name: \"My First Service\"" \
            "#         logo: \"assets/tools/sample.png\"" \
            "#         subtitle: \"A sample service\"" \
            "#         tag: \"app\"" \
            "#         url: \"https://example.com/\"" \
            "#         target: \"_blank\" # optional html a tag target attribute" > "$homer_config_file"
        success "Created minimal config.yml for Homer. Please customize it."
    fi

    local homepage_config_dir="${HOME}/.config/homepage-docker"
    if [ ! -f "${homepage_config_dir}/services.yaml" ] && [ ! -f "${homepage_config_dir}/widgets.yaml" ] && [ ! -f "${homepage_config_dir}/settings.yaml" ]; then
        info "Homepage config files (services.yaml, widgets.yaml, settings.yaml) not found. Creating minimal placeholders."
        printf "%s\n" \
            "# Homepage Settings" \
            "# Refer to Homepage documentation: https://gethomepage.dev/latest/configs/settings/" \
            "title: My Dashboard" \
            "background: https://source.unsplash.com/random/1920x1080/?nature,water" > "${homepage_config_dir}/settings.yaml"
        printf "%s\n" \
            "# Homepage Services" \
            "# Refer to Homepage documentation: https://gethomepage.dev/latest/configs/services/" \
            "# - My Group:" \
            "#     - My First Service:" \
            "#         href: http://localhost/" \
            "#         description: My awesome service" > "${homepage_config_dir}/services.yaml"
        printf "%s\n" \
            "# Homepage Widgets" \
            "# Refer to Homepage documentation: https://gethomepage.dev/latest/widgets/" \
            "# - resources:" \
            "#     label: System" \
            "#     expanded: true" \
            "#     cpu: true" \
            "#     memory: true" > "${homepage_config_dir}/widgets.yaml"
        success "Created minimal config files for Homepage. Please customize them."
    fi

    local dashy_config_file="${HOME}/.config/dashy-docker/user-data/conf.yml"
    if [[ ! -f "$dashy_config_file" ]]; then
        info "Dashy's conf.yml not found at $dashy_config_file. Dashy will use defaults or can be configured via UI."
        info "If you prefer file-based config, create 'conf.yml' in that directory."
    fi

    # 3. Deploy/Update Services
    heading "Step 3: Starting/Updating Dashboard Services"
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
        warn " - Ensure PUID/PGID in '${COMPOSE_FILE}' are correct for your system if permission errors occur."
        warn " - Manually run (without -d for more logs): ${DOCKER_COMPOSE_CMD_ARRAY[*]} up --remove-orphans"
        exit 1
    fi

    # 4. Display Status of Managed Containers
    heading "Step 4: Current Status of Dashboard Services"
    info "Displaying status for containers in project '${PROJECT_NAME}':"
    printf "%b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "docker ps --filter \"label=com.docker.compose.project=${PROJECT_NAME}\" --format \"table {{.Names}}\\t{{truncate .ID 12}}\\t{{.Status}}\\t{{.Ports}}\"" "${COLOR_RESET}"
    docker ps --filter "label=com.docker.compose.project=${PROJECT_NAME}" --format "table {{.Names}}\t{{truncate .ID 12}}\t{{.Status}}\t{{.Ports}}"
    if [[ $? -ne 0 ]]; then
        warn "Could not retrieve specific container status using 'docker ps'. The '${DOCKER_COMPOSE_CMD_ARRAY[*]} ps' command might have more details."
    fi
    echo "" # Explicit blank line

    # 5. Display Access Information
    heading "Step 5: Access Information & Setup Notes"
    local primary_ip
    primary_ip=$(hostname -I | awk '{print $1}')
    if [[ -z "$primary_ip" ]]; then
        warn "Could not determine primary IP using 'hostname -I'. URLs will use 'localhost'."
        primary_ip="localhost" # Fallback
    else
        success "Services should be accessible via IP: $primary_ip (or 'localhost' if on the same machine)."
    fi

    for service_info_line in "${SERVICES_INFO[@]}"; do
        # Ensure IFS is local to the read command to prevent it from affecting other parts of the loop or script
        # However, in a 'for' loop, variables set by 'read' without 'local' are local to the loop iteration.
        # Setting IFS here will affect expansions later in this specific loop iteration if they rely on word splitting.
        # For safety, it can be localized if other expansions are sensitive, but here it's likely fine.
        IFS="|" read -r container_name display_name config_paths urls notes <<< "$service_info_line"

        echo "" # Newline before each service block (Intentional)
        printf "%b--- %s ---%b\n" "${TAG_HEADING_COLOR}" "${display_name}" "${COLOR_RESET}"

        local actual_status
        actual_status_raw=$(docker inspect --format "{{.State.Status}}" "${PROJECT_NAME}-${container_name}-1" 2>/dev/null || docker inspect --format "{{.State.Status}}" "$container_name" 2>/dev/null)
        
        # <<< REVISION: Attempt to sanitize actual_status from docker inspect >>>
        # This removes any ASCII control characters (like \r, \n, etc.)
        actual_status=$(echo -n "${actual_status_raw}" | tr -d '[:cntrl:]')

        local current_status_text=""  # This will hold "Running", "Exited...", etc.
        local current_status_color="" # This will hold the color for the status text

        if [[ -n "$actual_status" ]]; then
            if [[ "$actual_status" == "running" ]]; then
                # <<< IMPORTANT: Ensure this literal string "Running" has no hidden leading newlines >>>
                current_status_text="Running"
                current_status_color="${TAG_SUCCESS_COLOR}"
            elif [[ "$actual_status" == "exited" ]]; then
                # <<< IMPORTANT: Ensure this literal string has no hidden leading newlines >>>
                current_status_text="Exited - Check logs: docker logs ${PROJECT_NAME}-${container_name}-1 (or ${container_name})"
                current_status_color="${TAG_ERROR_COLOR}"
            else # e.g., created, restarting, paused
                current_status_text="${actual_status}" # Value from 'tr -d' above
                current_status_color="${TAG_WARN_COLOR}"
            fi
        else
            # <<< IMPORTANT: Ensure this literal string has no hidden leading newlines >>>
            current_status_text="Not Found (or error fetching status) - compose logs: ${DOCKER_COMPOSE_CMD_ARRAY[*]} logs ${container_name}"
            current_status_color="${TAG_ERROR_COLOR}"
        fi
        
        # --- Optional: Insert the debug block for 'current_status_text' here if problem persists ---
        # echo "DEBUG: Raw status text for ${display_name}: [${current_status_text}]"
        # echo -n "${current_status_text}" | od -c
        # ---

        local current_status_colored="${current_status_color}${current_status_text}${COLOR_RESET}"

        # <<< REVISION: Using printf for the status line for more precise control >>>
        # Format: "  Status:" (colored) then space then "current_status_colored" then newline
        # %b interprets escape sequences in the color variables. %s prints current_status_colored as a literal string.
        # If current_status_colored itself STARTS with \n (from current_status_text), it will still break.
        printf "%b  Status:%b %s\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}" "${current_status_colored}"

        local processed_urls=${urls//\$(hostname -I | awk '{print \$1}')/$primary_ip}
        printf "%b  Access URL(s): %b%s%b\n" "${TEXT_MSG_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${processed_urls}" "${COLOR_RESET}"

        local expanded_config_paths="${config_paths//\~/$HOME}"
        printf "%b  Host Config/Data Path(s): %s%b\n" "${TEXT_MSG_COLOR}" "${expanded_config_paths}" "${COLOR_RESET}"
        printf "%b  Notes: %s%b\n" "${TEXT_MSG_COLOR}" "${notes}" "${COLOR_RESET}"
    done
    printf "%b-------------------------------------------------%b\n" "${TAG_HEADING_COLOR}" "${COLOR_RESET}"
    echo "" # Explicit blank line

    success "Setup script complete! Your Docker Dashboards should be accessible."
    info "Some dashboards require initial configuration files or setup via their web UI (see notes above)."
    info "Try out the dashboards, then simply remove those you do not want"
    info "   ${TAG_CMD_TEXT_COLOR}docker stop heimdall; docker rm heimdall${COLOR_RESET}   # Use stop first instead of rm -f to prevent corrupting configs"
    info "   ${TAG_CMD_TEXT_COLOR}docker compose -f docker-dashboards.yaml up -d heimdall${COLOR_RESET}   # To create a new container"
    info "To remove all containers:   ${TAG_CMD_TEXT_COLOR}${0##*/} --remove${COLOR_RESET}   # Containers are destroyed, but the host configs will remain"

    # 6. Useful Commands Section
    heading "Step 6: Useful Docker & Compose Commands"
    info "Here are some commands you might find useful for managing this stack:"
    printf "%b  - List services and their status:%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "    %b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${DOCKER_COMPOSE_CMD_ARRAY[*]} ps" "${COLOR_RESET}"
    printf "%b  - Start/Update all services in the background:%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "    %b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${DOCKER_COMPOSE_CMD_ARRAY[*]} up -d" "${COLOR_RESET}"
    printf "%b  - Stop and remove containers & networks (configs on host remain):%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "    %b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${DOCKER_COMPOSE_CMD_ARRAY[*]} down" "${COLOR_RESET}"
    printf "%b  - View logs for a specific service (e.g., heimdall):%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "    %b# %b%s%b (or homer, homarr, etc.)\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${DOCKER_COMPOSE_CMD_ARRAY[*]} logs -f heimdall" "${COLOR_RESET}"
    printf "%b  - Restart or stop a specific service (e.g., heimdall):%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "    %b# %b%s%b\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "${DOCKER_COMPOSE_CMD_ARRAY[*]} restart heimdall" "${COLOR_RESET}"
    printf "%b  - Access a shell inside a container (e.g., heimdall, if image has 'sh'):%b\n" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    printf "    %b# %b%s%b (or use service name like heimdall)\n" "${TAG_CMD_HASH_COLOR}" "${TAG_CMD_TEXT_COLOR}" "docker exec -it ${PROJECT_NAME}-heimdall-1 sh" "${COLOR_RESET}"
    echo
}


# --- Main Script Logic ---
# Early exit if Docker itself is missing
if ! command_exists docker; then
    # Use _print_tag_message directly if error function might not be fully safe yet or for early errors
    printf "%b[ERROR]  %b %bDocker is not installed or not in PATH. Please install Docker first.%b\n" "${TAG_ERROR_COLOR}" "${COLOR_RESET}" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    exit 1
fi
if ! docker ps > /dev/null 2>&1; then # Check if Docker daemon is running
    printf "%b[ERROR]  %b %bDocker daemon is not running or accessible. Please start Docker.%b\n" "${TAG_ERROR_COLOR}" "${COLOR_RESET}" "${TEXT_MSG_COLOR}" "${COLOR_RESET}"
    exit 1
fi

initialize_docker_compose_cmd # Sets up DOCKER_COMPOSE_CMD_ARRAY or exits

if [[ "$1" == "--remove" ]]; then
    handle_stop
else
    main_startup
fi

exit 0
