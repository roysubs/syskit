#!/bin/bash
# Author: Roy Wiseman 2025-03

# --- Color Definitions ---
NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m' # Bright White
B_YELLOW='\033[1;33m'
B_GREEN='\033[1;32m'
B_RED='\033[1;31m'

# --- Symbols ---
ERROR_X="${B_RED}❌${NC}"

# --- Global Configuration Variables (will be prompted) ---
BASE_HOSTNAME=""
LETSENCRYPT_EMAIL=""
DOCKER_NETWORK="bridge"
COMPOSE_CONFIG_BASE_DIR="./docker-compose-configs"
ENABLE_TRAEFIK_INTEGRATION="no" # Default to no Traefik labels

# --- Application Data Array (Shortened for this example, full list would be here) ---
declare -a apps_data=(
    # Media Suite: Servers, Players, Downloaders & Management
    "plex:32400:Media Suite:A popular media server for organizing and streaming your personal video, music, and photo collections."
    "sonarr:8885:Media Suite:A PVR for Usenet and BitTorrent users that monitors multiple RSS feeds for new episodes of your favorite shows."
    "radarr:8886:Media Suite:An independent fork of Sonarr reworked for automatically downloading movies via Usenet and BitTorrent."
    # ... (Your full list of apps would go here) ...

    # Network Services & Security
    "traefik:8907:Network Services & Security:Reverse proxy and load balancer (dashboard on this port, HTTP/S on 80/443)."
    "pi-hole:8001:Network Services & Security:A DNS sinkhole (admin UI from compose; DNS on 53)."
    # ...

    # System, Container & Database Management
    "portainer:9000:System & Container Management:Lightweight management UI for Docker."
    # ...

    # Dashboards & Monitoring
    "heimdall:80:Dashboards & Monitoring:Application dashboard (default port, Traefik handles public)."
    # ... (etc.) ...
)


# --- Helper Functions (get_user_paths_and_tz, execute_docker_command, check_docker_installed, is_port_available are same as before) ---
# (Assuming these helper functions are defined as in the previous version)
get_user_paths_and_tz() {
    local app_name_sanitized="$1"
    local needs_data_path="$2" 
    local needs_media_path="$3"

    default_config_path="/opt/${app_name_sanitized}/config"
    default_data_path="/srv/${app_name_sanitized}/data"
    default_media_path="/srv/media/${app_name_sanitized}" # More specific for media

    read -e -p "$(echo -e ${CYAN}"Enter path for ${app_name_sanitized} config [${default_config_path}]: "${NC})" app_config_path
    app_config_path=${app_config_path:-$default_config_path}

    if [[ "$needs_data_path" == "yes" ]]; then
        read -e -p "$(echo -e ${CYAN}"Enter path for ${app_name_sanitized} data [${default_data_path}]: "${NC})" app_data_path
        app_data_path=${app_data_path:-$default_data_path}
    fi
    if [[ "$needs_media_path" == "yes" ]]; then
        read -e -p "$(echo -e ${CYAN}"Enter path for ${app_name_sanitized} media files (e.g., movies, TV shows, music) [${default_media_path}]: "${NC})" app_media_path
        app_media_path=${app_media_path:-$default_media_path}
    fi

    default_tz=$(cat /etc/timezone 2>/dev/null || timedatectl show --property=Timezone --value 2>/dev/null || echo "America/New_York")
    read -p "$(echo -e ${CYAN}"Enter your TimeZone [${default_tz}]: "${NC})" app_tz
    app_tz=${app_tz:-$default_tz}

    _APP_CONFIG_PATH="$app_config_path"
    _APP_DATA_PATH="$app_data_path"
    _APP_MEDIA_PATH="$app_media_path"
    _APP_TZ="$app_tz"
    _PUID=$(id -u)
    _PGID=$(id -g)
}

execute_docker_command() {
    local cmd_type="$1" 
    local image_name="$2" 
    local full_command="$3"
    
    local network_arg_auto=""
    # Auto-add network if DOCKER_NETWORK is set and not bridge, AND not already in command
    if [[ -n "$DOCKER_NETWORK" && "$DOCKER_NETWORK" != "bridge" && ! "$full_command" == *"--network"* ]]; then
        network_arg_auto="--network \"$DOCKER_NETWORK\""
        # Simple prepend, functions should ideally manage this better if complex logic is needed
        if [[ "$full_command" == "docker run"* ]]; then
             full_command=$(echo "$full_command" | sed "s/docker run /docker run $network_arg_auto /")
        else
             full_command="$network_arg_auto $full_command"
        fi
    fi


    if [[ "$cmd_type" == "pull" ]]; then
        echo -e "${WHITE}# ${GREEN}docker pull \"$image_name\"${NC}"
        if docker pull "$image_name"; then
            echo -e "${GREEN}Image $image_name pulled successfully.${NC}"
            return 0
        else
            echo -e "${RED}Failed to pull image $image_name.${NC}"
            return 1
        fi
    elif [[ "$cmd_type" == "run" ]]; then
        echo -e "${WHITE}# ${B_GREEN}${full_command}${NC}" 
        if eval "$full_command"; then 
            return 0
        else
            return 1
        fi
    fi
}

check_docker_installed() {
    if ! command -v docker &> /dev/null; then
        echo -e "${ERROR_X} Docker could not be found. Please install Docker to continue."
        exit 1
    fi
    if ! docker info &> /dev/null; then
        echo -e "${ERROR_X} Docker daemon is not running. Please start Docker to continue."
        exit 1
    fi
    # Removed the "Docker is installed" message here to reduce startup noise, it's implied if no error.
}

is_port_available() {
    local port_to_check="$1"
    if [[ "$port_to_check" == "0" ]]; then 
        return 0 
    fi
    if ss -tulnp | grep -q ":${port_to_check}\b"; then
        return 1 
    else
        return 0 
    fi
}


prompt_global_configs() {
    echo -e "${B_YELLOW}Global Configuration Setup:${NC}"

    echo -e "\n${B_WHITE}About Traefik (Reverse Proxy):${NC}"
    echo -e "${WHITE}Traefik can simplify accessing your services with custom domain names (e.g., sonarr.yourdomain.com)${NC}"
    echo -e "${WHITE}and can automatically manage HTTPS/SSL certificates for you. It uses Docker labels for configuration.${NC}"
    read -p "$(echo -e ${CYAN}"Do you want to include Traefik integration labels in Docker commands? [y/N]: "${NC})" enable_traefik_choice
    ENABLE_TRAEFIK_INTEGRATION=$(echo "$enable_traefik_choice" | tr '[:upper:]' '[:lower:]')

    if [[ "$ENABLE_TRAEFIK_INTEGRATION" == "y" ]]; then
        read -e -p "$(echo -e ${CYAN}"Enter a base hostname (e.g., yourdomain.com, for rules like app.\${BASE_HOSTNAME}) [$(hostname -f 2>/dev/null || echo server.local)]: "${NC})" temp_base_hostname
        BASE_HOSTNAME=${temp_base_hostname:-$(hostname -f 2>/dev/null || echo server.local)}

        read -e -p "$(echo -e ${CYAN}"Enter your email address for Let's Encrypt (for SSL certs via Traefik): "${NC})" LETSENCRYPT_EMAIL
        echo -e "${YELLOW}Note: Traefik itself needs to be installed and configured separately for these labels to be effective.${NC}"
    else
        echo -e "${YELLOW}Traefik integration labels will NOT be added to Docker commands.${NC}"
        # BASE_HOSTNAME might still be useful for some app's own --hostname setting, so we can still ask for it with a different context.
        read -e -p "$(echo -e ${CYAN}"Enter a general hostname for your server (some apps might use this, e.g., server.local) [$(hostname -f 2>/dev/null || echo server.local)]: "${NC})" temp_base_hostname
        BASE_HOSTNAME=${temp_base_hostname:-$(hostname -f 2>/dev/null || echo server.local)}
    fi

    read -e -p "$(echo -e ${CYAN}"Enter Docker network name for containers (e.g., docker_infra_net, leave blank for 'bridge') [bridge]: "${NC})" temp_docker_network
    DOCKER_NETWORK=${temp_docker_network:-bridge}
    if [[ -n "$temp_docker_network" && "$DOCKER_NETWORK" != "bridge" ]]; then
        if ! docker network inspect "$DOCKER_NETWORK" &>/dev/null; then
            echo -e "${YELLOW}Warning: Docker network '$DOCKER_NETWORK' does not exist. Create it with 'docker network create $DOCKER_NETWORK' if needed.${NC}"
        fi
    fi

    read -e -p "$(echo -e ${CYAN}"Enter base directory for Docker Compose style relative configs (e.g., for Traefik's .yml files) [./docker-compose-configs]: "${NC})" temp_compose_config_base_dir
    COMPOSE_CONFIG_BASE_DIR=${temp_compose_config_base_dir:-./docker-compose-configs}
    mkdir -p "$COMPOSE_CONFIG_BASE_DIR"
    echo ""
}

# --- Installation Functions ---
# Example of modifying an existing function:
install_sonarr() {
    local app_name="$1"
    local host_port="$2"
    local container_port="8989"
    local image_name="lscr.io/linuxserver/sonarr:latest"

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    get_user_paths_and_tz "sonarr" "yes" "yes"
    local app_config_path="$_APP_CONFIG_PATH"
    local app_downloads_path="$_APP_DATA_PATH" # Downloads
    local app_tv_path="$_APP_MEDIA_PATH"     # TV shows
    local app_tz="$_APP_TZ"
    local app_puid="$_PUID"
    local app_pgid="$_PGID"

    mkdir -p "$app_config_path" "$app_downloads_path" "$app_tv_path"

    execute_docker_command "pull" "$image_name" || return 1

    local network_arg=$([[ -n "$DOCKER_NETWORK" && "$DOCKER_NETWORK" != "bridge" ]] && echo "--network \"$DOCKER_NETWORK\"" || echo "")
    
    local docker_cmd="docker run -d \
        --name $app_name \
        $network_arg \
        -e PUID=\"$app_puid\" \
        -e PGID=\"$app_pgid\" \
        -e TZ=\"$app_tz\" \
        -p $host_port:$container_port \
        -v \"$app_config_path:/config\" \
        -v \"$app_tv_path:/tv\" \
        -v \"$app_downloads_path:/downloads\" "

    if [[ "$ENABLE_TRAEFIK_INTEGRATION" == "y" ]]; then
        docker_cmd+=" --label \"traefik.enable=true\" \
        --label \"traefik.http.routers.sonarr.rule=Host(\\\`sonarr.$BASE_HOSTNAME\\\`)\" \
        --label \"traefik.http.routers.sonarr.entrypoints=websecure\" \
        --label \"traefik.http.routers.sonarr.tls.certresolver=myresolver\" \
        --label \"traefik.http.services.sonarr.loadbalancer.server.port=$container_port\" "
    fi
    
    docker_cmd+=" --restart unless-stopped \
        $image_name"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}

install_traefik() {
    local app_name="traefik" 
    local host_port="$2" # Dashboard port, e.g., 8907
    local container_dashboard_port="8080"
    local image_name="traefik:v2.9.5" 

    echo -e "${PURPLE}Preparing to install $app_name...${NC}"
    
    local traefik_config_dir="$COMPOSE_CONFIG_BASE_DIR/traefik"
    local traefik_letsencrypt_dir="$traefik_config_dir/letsencrypt"
    local traefik_yml_path="$traefik_config_dir/traefik.yml"
    local traefik_dynamic_config_yml_path="$traefik_config_dir/config.yml"

    echo -e "${CYAN}Ensure the following paths are set up correctly and files exist where needed:${NC}"
    echo -e "  Docker Socket: /var/run/docker.sock (host) -> /var/run/docker.sock (container)"
    echo -e "  Let's Encrypt Store: ${WHITE}$traefik_letsencrypt_dir${NC} (host) -> /letsencrypt (container)"
    echo -e "  Static Config: ${WHITE}$traefik_yml_path${NC} (host, ${B_RED}YOU MUST CREATE THIS${NC}) -> /traefik.yml (container, read-only)"
    echo -e "  Dynamic Config Dir: ${WHITE}$traefik_dynamic_config_yml_path${NC} (host, ${B_RED}YOU MUST CREATE THIS${NC} if referenced in traefik.yml) -> /config.yml (container, read-only)"
    echo ""
    read -p "$(echo -e ${CYAN}"Confirm base directory for Traefik configs is '${WHITE}$traefik_config_dir${NC}' and you will create needed .yml files? [y/N]: "${NC})" confirm_paths
    confirm_paths_lower=$(echo "$confirm_paths" | tr '[:upper:]' '[:lower:]')
    if [[ "$confirm_paths_lower" != "y" ]]; then
        echo -e "${RED}Aborting $app_name installation. Config paths not confirmed.${NC}"
        return 1
    fi

    mkdir -p "$traefik_letsencrypt_dir" 

    execute_docker_command "pull" "$image_name" || return 1

    # Traefik is often best on the host network for simplicity with ports 80/443,
    # or on a dedicated network. The compose used 'bridge'.
    # For this explicit install, using the global DOCKER_NETWORK or bridge.
    local network_arg=$([[ -n "$DOCKER_NETWORK" && "$DOCKER_NETWORK" != "bridge" ]] && echo "--network \"$DOCKER_NETWORK\"" || echo "--network bridge")
    
    local traefik_cli_args="--providers.docker=true \
        --providers.docker.exposedbydefault=false \
        --entrypoints.web.address=:80 \
        --entrypoints.websecure.address=:443 \
        --api.dashboard=true \
        --log.level=INFO "
    
    if [[ "$ENABLE_TRAEFIK_INTEGRATION" == "y" && -n "$LETSENCRYPT_EMAIL" ]]; then
        # This basic resolver setup should ideally be in traefik.yml for more control
        traefik_cli_args+=" --certificatesresolvers.myresolver.acme.email=\"$LETSENCRYPT_EMAIL\" \
        --certificatesresolvers.myresolver.acme.storage=/letsencrypt/acme.json \
        --certificatesresolvers.myresolver.acme.httpchallenge.entrypoint=web "
    fi
        
    local docker_cmd="docker run -d \
        --name traefik \
        $network_arg \
        -p 80:80 \
        -p $host_port:$container_dashboard_port \
        -p 443:443 \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -v \"$traefik_letsencrypt_dir:/letsencrypt\" \
        -v \"$traefik_yml_path:/traefik.yml:ro\" \
        -v \"$traefik_dynamic_config_yml_path:/config.yml:ro\" \
        --label \"traefik.enable=true\" \
        --label \"traefik.http.middlewares.redirect-to-https.redirectscheme.scheme=https\" \
        --label \"traefik.http.routers.redirs.rule=hostregexp(\\\`{host:.+}\\\`)\" \
        --label \"traefik.http.routers.redirs.entrypoints=web\" \
        --label \"traefik.http.routers.redirs.middlewares=redirect-to-https\" \
        --dns 8.8.8.8 \
        --restart always \
        $image_name \
        $traefik_cli_args"

    if execute_docker_command "run" "" "$docker_cmd"; then
        echo -e "${B_GREEN}$app_name installed successfully.${NC}"
        echo -e "${YELLOW}Ensure your '$traefik_yml_path' and '$traefik_dynamic_config_yml_path' (if used) are correctly configured!${NC}"
        if [[ "$ENABLE_TRAEFIK_INTEGRATION" == "y" && -n "$LETSENCRYPT_EMAIL" ]]; then
           echo -e "${YELLOW}A basic Let's Encrypt resolver 'myresolver' was configured via CLI. For more advanced setups, define it in your traefik.yml.${NC}"
        fi
    else
        echo -e "${ERROR_X} Failed to install $app_name."
        return 1
    fi
}


# --- Placeholder function (ensure it respects ENABLE_TRAEFIK_INTEGRATION) ---
install_generic_placeholder() {
    local app_name="$1"
    local host_port="$2"
    local app_name_lower=$(echo "$app_name" | tr '[:upper:]' '[:lower:]' | sed 's/-//g')
    local suggested_image="lscr.io/linuxserver/$app_name_lower:latest" 

    echo -e "${B_YELLOW}INSTALLING $app_name (PLACEHOLDER)${NC}"
    # ... (rest of the placeholder messages) ...
    get_user_paths_and_tz "$app_name_lower" "yes" "no" 
    # ... (assign PUID, PGID, TZ) ...

    local network_arg_placeholder=$([[ -n "$DOCKER_NETWORK" && "$DOCKER_NETWORK" != "bridge" ]] && echo "--network \"$DOCKER_NETWORK\" \\\\" || echo "")
    local traefik_labels_placeholder=""
    if [[ "$ENABLE_TRAEFIK_INTEGRATION" == "y" ]]; then
        traefik_labels_placeholder="--label \"traefik.enable=true\" \\\\\n        --label \"traefik.http.routers.$app_name_lower.rule=Host(\\\`$app_name_lower.$BASE_HOSTNAME\\\`)\" \\\\\n        --label \"traefik.http.routers.$app_name_lower.entrypoints=websecure\" \\\\\n        --label \"traefik.http.routers.$app_name_lower.tls.certresolver=myresolver\" \\\\\n        --label \"traefik.http.services.$app_name_lower.loadbalancer.server.port=80\" \\\\" # Assuming 80, needs to be specific
    fi
    
    local placeholder_cmd="docker run -d \\\\
        --name \"$app_name\" \\\\
        $network_arg_placeholder
        -p \"$host_port:80\" \\\\ 
        -e PUID=\$_PUID -e PGID=\$_PGID \\\\
        -e TZ=\$_APP_TZ \\\\
        -v \"\$_APP_CONFIG_PATH:/config\" \\\\ 
        -v \"\$_APP_DATA_PATH:/data\" \\\\   
        $traefik_labels_placeholder
        --restart unless-stopped \\\\
        $suggested_image"
    # ... (echo placeholder cmd) ...
    return 1 
}


create_install_functions() {
    local app_name
    for app_entry in "${apps_data[@]}"; do
        app_name=$(echo "$app_entry" | cut -d: -f1)
        local func_name="install_$(echo "$app_name" | tr '-' '_' | tr '[:upper:]' '[:lower:]')"

        if ! type "$func_name" &>/dev/null; then
            eval "
            ${func_name}() {
                install_generic_placeholder \"\$1\" \"\$2\"
            }
            "
        fi
    done
}

# --- Main Script Logic ---
check_docker_installed
prompt_global_configs # New prompt for global settings
create_install_functions


echo -e "${B_GREEN}Welcome to the Docker Container Installer!${NC}"
if [[ "$ENABLE_TRAEFIK_INTEGRATION" == "y" ]]; then
    echo -e "Traefik Integration: ${GREEN}ENABLED${NC}. Using Base Hostname: ${WHITE}$BASE_HOSTNAME${NC}, Email for Traefik: ${WHITE}$LETSENCRYPT_EMAIL${NC}"
else
    echo -e "Traefik Integration: ${RED}DISABLED${NC}. Using General Hostname: ${WHITE}$BASE_HOSTNAME${NC}."
fi
echo -e "Default Docker Network: ${WHITE}$DOCKER_NETWORK${NC}, Compose Config Base: ${WHITE}$COMPOSE_CONFIG_BASE_DIR${NC}"
echo ""

# (The rest of the main loop for categories and apps remains the same as your previous version)
# ... (Category listing, app processing loop) ...

# Example of how the main loop calls the install function:
# Inside the app processing loop:
# func_to_call="install_$(echo "$app_name" | tr '-' '_' | tr '[:upper:]' '[:lower:]')"
# if type "$func_to_call" &>/dev/null; then
#     "$func_to_call" "$app_name" "$host_port" # It's up to the install func to use global vars like ENABLE_TRAEFIK_INTEGRATION
# else
# ...
# fi
# (Main loop from previous version should be here)
# Extract categories and count apps
declare -A category_counts
declare -a sorted_categories

for app_entry in "${apps_data[@]}"; do
    category=$(echo "$app_entry" | cut -d: -f3)
    category_counts["$category"]=$(( ${category_counts["$category"]} + 1 ))
done

# Sort categories
IFS=$'\n' sorted_categories=($(sort <<<"${!category_counts[*]}"))
unset IFS

echo -e "${WHITE}Available application categories:${NC}"
for category_name in "${sorted_categories[@]}"; do
    count=${category_counts["$category_name"]}
    echo -e "- ${B_YELLOW}$category_name${NC} ($count app(s))"
done
echo ""
read -p "$(echo -e ${CYAN}"Press any key to continue... "${NC})" -n 1 -s
echo -e "\n"


# Loop through categories
for category_name in "${sorted_categories[@]}"; do
    echo -e "${B_YELLOW}Category: $category_name${NC}"
    echo -e "${WHITE}Host port number is in brackets beside App Name${NC}"
    
    declare -a apps_in_category
    for app_entry in "${apps_data[@]}"; do
        current_category=$(echo "$app_entry" | cut -d: -f3)
        if [[ "$current_category" == "$category_name" ]]; then
            app_name_list=$(echo "$app_entry" | cut -d: -f1) # Renamed to avoid conflict
            host_port_list=$(echo "$app_entry" | cut -d: -f2) # Renamed
            description_list=$(echo "$app_entry" | cut -d: -f4) # Renamed
            echo -e "- ${WHITE}$app_name_list${NC} ($host_port_list): $description_list"
            apps_in_category+=("$app_entry") 
        fi
    done
    echo ""

    read -p "$(echo -e ${CYAN}"Do you want to process applications in the '$category_name' category? [y/N]: "${NC})" process_category_choice
    process_category_choice_lower=$(echo "$process_category_choice" | tr '[:upper:]' '[:lower:]')

    if [[ "$process_category_choice_lower" != "y" ]]; then
        echo -e "${YELLOW}Skipping category '$category_name'.${NC}"
        echo -e "\n"
        continue
    fi
    echo ""

    # Process apps in the chosen category
    for app_entry_to_install in "${apps_in_category[@]}"; do
        app_name_install=$(echo "$app_entry_to_install" | cut -d: -f1) # Renamed
        host_port_install=$(echo "$app_entry_to_install" | cut -d: -f2) # Renamed
        
        echo -e "${CYAN}Processing App: ${WHITE}$app_name_install${NC} (Attempting Host Port: ${WHITE}$host_port_install${NC})"

        if is_port_available "$host_port_install"; then
            echo -e "${GREEN}Host port $host_port_install appears to be available.${NC}"
            read -p "$(echo -e ${CYAN}"Do you want to install $app_name_install? [y/N]: "${NC})" install_choice
            install_choice_lower=$(echo "$install_choice" | tr '[:upper:]' '[:lower:]')

            if [[ "$install_choice_lower" == "y" ]]; then
                func_to_call="install_$(echo "$app_name_install" | tr '-' '_' | tr '[:upper:]' '[:lower:]')"
                if type "$func_to_call" &>/dev/null; then
                    "$func_to_call" "$app_name_install" "$host_port_install" 
                else
                    echo -e "${ERROR_X} Installation function ${RED}$func_to_call${NC} not found for $app_name_install."
                fi
            else
                echo -e "${YELLOW}Skipping installation of $app_name_install.${NC}"
            fi
        else
            echo -e "${ERROR_X} Host port ${RED}$host_port_install${NC} is NOT available. Skipping $app_name_install."
        fi
        echo "" 
    done
    echo -e "${B_GREEN}Finished processing category '$category_name'.${NC}"
    echo -e "\n"
done

echo -e "${B_GREEN}All categories processed. Script finished.${NC}"
