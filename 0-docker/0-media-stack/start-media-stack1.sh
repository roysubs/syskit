#!/bin/bash
# Author: Roy Wiseman, with Gemini "Robust Automation" Script 2025-09-15
# A unified script to correctly install, configure, and start the qBittorrent container.

# --- Configuration and Colors ---
RED='\e[0;31m'
YELLOW='\e[1;33m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
NC='\033[0m'

set -e # Exit immediately if a command exits with a non-zero status.

# --- Global Variables ---
CONFIG_PATH="$HOME/.config/media-stack/qbittorrent"
ENV_FILE=".env"
DOCKER_COMPOSE_FILE="docker-compose.yaml"

# --- Functions ---
check_dependencies() {
    echo -e "${BLUE}--- 1. Checking Dependencies ---${NC}"
    if ! command -v docker &> /dev/null; then echo -e "${RED}❌ Docker not found. Please install Docker.${NC}"; exit 1; fi
    if ! docker info &>/dev/null; then echo -e "${RED}❌ Docker daemon is not running. Please start Docker.${NC}"; exit 1; fi
    if ! command -v yq &> /dev/null; then echo -e "${RED}❌ 'yq' not found. Please install yq (e.g., sudo apt install yq).${NC}"; exit 1; fi
    echo "✅ All dependencies are met."
}

run_pre_flight_checks() {
    echo -e "\n${BLUE}--- 2. Running Pre-flight Checks ---${NC}"
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo -e "${RED}❌ docker-compose.yaml not found. Exiting.${NC}"; exit 1
    fi
    local container_name
    container_name=$(yq -r '.services.*.container_name' "$DOCKER_COMPOSE_FILE")
    if docker ps -a --format '{{.Names}}' | grep -wq "$container_name"; then
        echo -e "${RED}❌ Container \"$container_name\" already exists. Please run the stop script first.${NC}"
        exit 1
    fi
    echo "✅ No conflicting container names found."
}

gather_user_settings() {
    echo -e "\n${BLUE}--- 3. Gathering User Settings ---${NC}"
    PUID=$(id -u)
    PGID=$(id -g)
    TZ=$(timedatectl show --value -p Timezone)
    echo "Using PUID=$PUID, PGID=$PGID, TZ=$TZ"

    DEFAULT_MEDIA_PATH="$HOME/Downloads"
    read -e -p "Enter path for your media library [default: $DEFAULT_MEDIA_PATH]: " MEDIA_PATH_INPUT
    MEDIA_PATH="${MEDIA_PATH_INPUT:-$DEFAULT_MEDIA_PATH}"
    MEDIA_PATH="${MEDIA_PATH/#\~/$HOME}"
}

handle_vpn_choice_and_setup() {
    echo -e "\n${BLUE}--- 4. VPN Configuration ---${NC}"
    # This section remains unchanged.
    if grep -qi microsoft /proc/sys/kernel/osrelease; then
        echo -e "${YELLOW}WSL environment detected. VPN setup inside the container is not supported.${NC}"
        read -p "Continue with a non-VPN setup? (Y/n): " wsl_confirm
        if [[ "$wsl_confirm" =~ ^[Nn]$ ]]; then
            echo -e "${RED}❌ Aborting setup.${NC}"; exit 0
        fi
        USE_VPN="no"
    else
        read -p "Do you want to enable the WireGuard VPN? (Y/n): " vpn_confirm
        [[ "$vpn_confirm" =~ ^[Nn]$ ]] && USE_VPN="no" || USE_VPN="yes"
    fi

    echo "Creating config directories at ${CONFIG_PATH}..."
    mkdir -p "$CONFIG_PATH"

    if [ "$USE_VPN" = "yes" ]; then
        echo -e "\n--- Configuring WireGuard VPN ---"
        mkdir -p "${CONFIG_PATH}/wireguard"
        DEFAULT_WG_PATH="$HOME/wg0.conf"
        read -e -p "Enter FULL path to WireGuard config file [default: $DEFAULT_WG_PATH]: " WG_PATH_INPUT
        local wg_source_path="${WG_PATH_INPUT:-$DEFAULT_WG_PATH}"
        wg_source_path="${wg_source_path/#\~/$HOME}"

        if [ ! -f "$wg_source_path" ]; then
            echo -e "${RED}❌ WireGuard config not found at \"$wg_source_path\". Exiting.${NC}"; exit 1
        fi
        cp "$wg_source_path" "${CONFIG_PATH}/wireguard/wg0.conf"
        echo "✅ WireGuard config copied."
    fi
}

create_startup_script() {
    echo -e "\n${BLUE}--- 5. Creating Automation Script ---${NC}"
    local startup_dir="${CONFIG_PATH}/scripts/startup"
    local startup_script="${startup_dir}/set-all-paths.sh" # Renamed for clarity
    mkdir -p "$startup_dir"

    # This new, robust script runs inside the container to set all paths correctly.
    cat > "$startup_script" << 'EOF'
#!/bin/bash
CONF_FILE="/config/qBittorrent/config/qBittorrent.conf"
ATTEMPTS=0
MAX_ATTEMPTS=6 # Wait up to 30 seconds

echo "[startup_script] Waiting for qBittorrent config file..."
while [ ! -f "$CONF_FILE" ]; do
    if [ $ATTEMPTS -ge $MAX_ATTEMPTS ]; then
        echo "[startup_script] ERROR: Config file not found after 30 seconds. Aborting."
        exit 1
    fi
    sleep 5
    ATTEMPTS=$((ATTEMPTS+1))
done
echo "[startup_script] Config file found. Ensuring all media paths are correct..."

# --- Define desired paths within the container ---
CONTAINER_MEDIA_LIBRARY_PATH="/data/media-library"
CONTAINER_TEMP_DOWNLOAD_PATH="/data/media-library/0-downloading"
CONTAINER_INCOMPLETE_TORRENTS_PATH="/data/media-library/0-torrents-incomplete"
CONTAINER_COMPLETE_TORRENTS_PATH="/data/media-library/0-torrents-complete"
# ---

# Helper function to find a section and add/update a key
update_setting() {
    local section=$1
    local key=$2
    local value=$3
    local full_line="$key=$value"
    local escaped_key=$(echo "$key" | sed 's/\\/\\\\/g')
    local escaped_line=$(echo "$full_line" | sed 's/\\/\\\\/g; s/\//\\\//g') # Escape slashes for sed

    # Check if the key exists, and if so, update it
    if grep -q "^$escaped_key=" "$CONF_FILE"; then
        sed -i "s#^$escaped_key=.*#$escaped_line#" "$CONF_FILE"
        echo "[startup_script] Updated: $key"
    # If not, add it under the correct section header
    else
        sed -i "/^\[$section\]/a $escaped_line" "$CONF_FILE"
        echo "[startup_script] Added: $key"
    fi
}

update_setting "Preferences" "Downloads\\DefaultSavePath" "$CONTAINER_MEDIA_LIBRARY_PATH"
update_setting "BitTorrent" "Session\\DefaultSavePath" "$CONTAINER_MEDIA_LIBRARY_PATH"
update_setting "BitTorrent" "Session\\TempPath" "$CONTAINER_TEMP_DOWNLOAD_PATH"
update_setting "BitTorrent" "Session\\TorrentExportDirectory" "$CONTAINER_INCOMPLETE_TORRENTS_PATH"
update_setting "BitTorrent" "Session\\FinishedTorrentExportDirectory" "$CONTAINER_COMPLETE_TORRENTS_PATH"
update_setting "BitTorrent" "Session\\TempPathEnabled" "true"

echo "[startup_script] All paths have been verified and set."
EOF
    chmod +x "$startup_script"
    echo "✅ Automation script for all save paths created."
}

setup_media_directories() {
    echo -e "\n${BLUE}--- 6. Setting up Media Directories ---${NC}"
    # Define and create the full, structured directory path on the host
    local host_media_library_path="$MEDIA_PATH/media-library"
    
    echo "Creating media directory structure in '$MEDIA_PATH'..."
    mkdir -p \
        "$host_media_library_path/0-downloading" \
        "$host_media_library_path/0-torrents-incomplete" \
        "$host_media_library_path/0-torrents-complete" \
        "$host_media_library_path/movies" \
        "$host_media_library_path/tv"
    
    echo "Setting ownership for user $PUID:$PGID on '$MEDIA_PATH'..."
    # The -R flag ensures all newly created subdirectories get the correct permissions
    sudo chown -R "$PUID:$PGID" "$MEDIA_PATH"
    echo "✅ Host directories and permissions are ready."
}


create_env_file() {
    echo -e "\n${BLUE}--- 7. Creating .env file ---${NC}"
    {
        echo "TZ=$TZ"
        echo "PUID=$PUID"
        echo "PGID=$PGID"
        echo "MEDIA_PATH=$MEDIA_PATH"
        echo "CONFIG_PATH=$CONFIG_PATH"
        echo "VPN_ENABLED=$USE_VPN"
    } > "$ENV_FILE"

    if [ "$USE_VPN" = "yes" ]; then
        DEFAULT_LAN_NETWORK="192.168.1.0/24"
        read -e -p "Enter LAN network for local access [default: $DEFAULT_LAN_NETWORK]: " lan_network_input
        LAN_NETWORK="${lan_network_input:-$DEFAULT_LAN_NETWORK}"
        {
            echo "VPN_CLIENT=wireguard"
            echo "VPN_PROV=custom"
            echo "LAN_NETWORK=$LAN_NETWORK"
        } >> "$ENV_FILE"
    else
        {
            echo "VPN_CLIENT="
            echo "VPN_PROV="
            echo "LAN_NETWORK="
        } >> "$ENV_FILE"
    fi

    echo "✅ .env file created."
    echo "--------------------"
    cat "$ENV_FILE"
    echo "--------------------"
}

launch_stack() {
    echo -e "\n${BLUE}--- 8. Launching Docker Stack ---${NC}"
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d
    echo -e "\n${GREEN}✅ Media stack launched successfully!${NC}"
}

post_install_instructions() {
    echo -e "\n${YELLOW}--- Setup Complete ---${NC}"
    echo -e "Your qBittorrent instance is running and will be available shortly."
    echo -e "The download and media paths have been automatically set up inside: ${GREEN}${MEDIA_PATH}/media-library${NC}"
    echo -e "\nTo access the Web UI, go to: ${GREEN}http://localhost:8080${NC}"
    echo -e ""
    echo -e "${YELLOW}To find the temporary password for the first login, run:${NC}"
    echo -e "${GREEN}cat ${CONFIG_PATH}/supervisord.log | grep \"temporary password\"${NC}"

    echo -e "\n${BLUE}Attempting to retrieve temporary password automatically (please wait)...${NC}"
    sleep 10 # Give the container time to start and generate the log
    if [ -f "${CONFIG_PATH}/supervisord.log" ]; then
        grep "temporary password" "${CONFIG_PATH}/supervisord.log" || echo -e "${YELLOW}Password not found yet. Please run the command above manually in a few moments.${NC}"
    else
        echo -e "${RED}Log file not found yet. Please run the command above manually in a few moments.${NC}"
    fi

    if [ "$USE_VPN" = "no" ]; then
        echo -e "\n${RED}WARNING: This setup is NOT using a VPN and is not secure for downloading torrents.${NC}"
    fi
}

# --- Main Script Execution ---
main() {
    check_dependencies
    run_pre_flight_checks
    gather_user_settings
    handle_vpn_choice_and_setup
    create_startup_script
    setup_media_directories # Updated function name
    create_env_file
    launch_stack
    post_install_instructions
    echo -e "\n"
}

main "$@"
