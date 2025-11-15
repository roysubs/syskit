#!/bin/bash
# Author: Roy Wiseman, with Gemini "Robust Automation" Script 2025-09-15
# Refactored for complete Idempotency and State Management.

# --- Configuration and Colors ---
RED='\e[0;31m'
YELLOW='\e[1;33m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
NC='\033[0m'

# --- Global Variables ---
CONFIG_PATH="$HOME/.config/media-stack/qbittorrent"
ENV_FILE=".env"
DOCKER_COMPOSE_FILE="docker-compose.yaml"

# --- Functions ---

# Helper function to get the container name from the compose file
get_container_name() {
    yq -r '.services.*.container_name' "$DOCKER_COMPOSE_FILE" 2>/dev/null
}

check_dependencies() {
    echo -e "${BLUE}--- 1. Checking Dependencies ---${NC}"
    if ! command -v docker &> /dev/null; then echo -e "${RED}❌ Docker not found. Please install Docker.${NC}"; exit 1; fi
    if ! docker info &>/dev/null; then echo -e "${RED}❌ Docker daemon is not running. Please start Docker.${NC}"; exit 1; fi
    if ! command -v yq &> /dev/null; then echo -e "${RED}❌ 'yq' not found. Please install yq (e.g., sudo apt install yq).${NC}"; exit 1; fi
    echo "✅ All dependencies are met."
}

run_pre_flight_checks() {
    echo -e "\n${BLUE}--- 2. Running Pre-flight Checks (Idempotency Check) ---${NC}"
    
    if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
        echo -e "${RED}❌ docker-compose.yaml not found. Exiting.${NC}"; exit 1
    fi

    local container_name
    container_name=$(get_container_name)
    if [ -z "$container_name" ]; then
        echo -e "${RED}❌ Cannot determine container name from $DOCKER_COMPOSE_FILE. Exiting.${NC}"; exit 1
    fi

    # Check if the container exists (any state)
    if docker ps -a --format '{{.Names}}' | grep -wq "$container_name"; then
        local status
        status=$(docker inspect -f '{{.State.Status}}' "$container_name" 2>/dev/null)
        
        if [ "$status" == "running" ]; then
            echo -e "${GREEN}✅ Container \"$container_name\" is already running.${NC}"
            echo -e "${YELLOW}Skipping setup and jumping to password retrieval.${NC}"
            # Load existing variables for post-install step
            if [ -f "$ENV_FILE" ]; then
                export $(grep -E '^(MEDIA_PATH|CONFIG_PATH|VPN_ENABLED)=' "$ENV_FILE" | xargs)
            else
                echo -e "${RED}❌ Running container found, but $ENV_FILE is missing. Cannot proceed with instructions.${NC}"; exit 1
            fi
            post_install_instructions # Go directly to instructions and password retrieval
            exit 0
        else
            echo -e "${YELLOW}⚠️ Container \"$container_name\" exists but is $status. Removing existing container...${NC}"
            docker rm -f "$container_name" 2>/dev/null || true # Ignore error if removal fails
            echo "✅ Old container removed."
        fi
    fi
    echo "✅ Ready for fresh setup."
}

gather_user_settings() {
    echo -e "\n${BLUE}--- 3. Gathering User Settings ---${NC}"
    
    # Check if .env exists to skip user input (Idempotency for config)
    if [ -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}Found existing $ENV_FILE. Reusing stored configuration.${NC}"
        # Load variables for use in subsequent functions
        export $(grep -E '^(PUID|PGID|TZ|MEDIA_PATH|VPN_ENABLED)=' "$ENV_FILE" | xargs)
        if [ -z "$PUID" ]; then # Basic check if load failed
            echo -e "${RED}❌ Failed to load essential variables from $ENV_FILE. Starting clean.${NC}"
            rm "$ENV_FILE"
        else
            echo "✅ Configuration loaded (PUID=$PUID, PGID=$PGID, TZ=$TZ, MEDIA_PATH=$MEDIA_PATH)."
            return 0
        fi
    fi

    # Start fresh input if .env was not found or was invalid
    PUID=$(id -u)
    PGID=$(id -g)
    TZ=$(timedatectl show --value -p Timezone)
    echo "Using PUID=$PUID, PGID=$PGID, TZ=$TZ"

    DEFAULT_MEDIA_PATH="$HOME/Downloads"
    read -e -p "Enter path for your media library [default: $DEFAULT_MEDIA_PATH]: " MEDIA_PATH_INPUT
    MEDIA_PATH="${MEDIA_PATH_INPUT:-$DEFAULT_MEDIA_PATH}"
    MEDIA_PATH="${MEDIA_PATH/#\~/$HOME}"
    echo "Using MEDIA_PATH=$MEDIA_PATH"
}

handle_vpn_choice_and_setup() {
    echo -e "\n${BLUE}--- 4. VPN Configuration ---${NC}"
    
    # Check if VPN_ENABLED is already set from .env file (Idempotency)
    if [ -n "$VPN_ENABLED" ]; then
        USE_VPN="$VPN_ENABLED"
        echo "Using stored VPN setting: $USE_VPN"
    else
        # Original VPN logic for fresh setup
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
        VPN_ENABLED="$USE_VPN" # Set it for the .env creation
    fi

    echo "Ensuring config directories at ${CONFIG_PATH}..."
    mkdir -p "$CONFIG_PATH"

    if [ "$USE_VPN" = "yes" ]; then
        echo -e "\n--- Configuring WireGuard VPN ---"
        mkdir -p "${CONFIG_PATH}/wireguard"
        local wg_config_target="${CONFIG_PATH}/wireguard/wg0.conf"

        if [ -f "$wg_config_target" ]; then
            echo "✅ WireGuard config already exists in the container config path. Skipping copy."
        else
            DEFAULT_WG_PATH="$HOME/wg0.conf"
            read -e -p "Enter FULL path to WireGuard config file [default: $DEFAULT_WG_PATH]: " WG_PATH_INPUT
            local wg_source_path="${WG_PATH_INPUT:-$DEFAULT_WG_PATH}"
            wg_source_path="${wg_source_path/#\~/$HOME}"

            if [ ! -f "$wg_source_path" ]; then
                echo -e "${RED}❌ WireGuard config not found at \"$wg_source_path\". Exiting.${NC}"; exit 1
            fi
            cp "$wg_source_path" "$wg_config_target"
            echo "✅ WireGuard config copied."
        fi
    fi
}

create_startup_script() {
    echo -e "\n${BLUE}--- 5. Creating Automation Script ---${NC}"
    local startup_dir="${CONFIG_PATH}/scripts/startup"
    local startup_script="${startup_dir}/set-all-paths.sh" # Renamed for clarity

    # Check if script exists and is identical (Simple Idempotency Check)
    # This is a weak check, but better than nothing for idempotent creation
    if [ -f "$startup_script" ]; then
        # Check size or hash against expected content if you wanted a strong check
        # For simplicity, we just assume existing is fine unless we want to force-write
        echo "✅ Automation script already exists. Skipping creation."
        return 0
    fi
    
    mkdir -p "$startup_dir"

    # The content creation part remains the same to ensure it's written if needed
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
    # Define the full, structured directory path on the host
    local host_media_library_path="$MEDIA_PATH/media-library"
    
    # Idempotent creation (mkdir -p is idempotent)
    echo "Ensuring media directory structure in '$MEDIA_PATH' exists..."
    mkdir -p \
        "$host_media_library_path/0-downloading" \
        "$host_media_library_path/0-torrents-incomplete" \
        "$host_media_library_path/0-torrents-complete" \
        "$host_media_library_path/movies" \
        "$host_media_library_path/tv"
    
    # Idempotent permission setting (chown -R is idempotent)
    echo "Setting ownership for user $PUID:$PGID on '$MEDIA_PATH'..."
    sudo chown -R "$PUID:$PGID" "$MEDIA_PATH"
    echo "✅ Host directories and permissions are ready."
}


create_env_file() {
    echo -e "\n${BLUE}--- 7. Creating/Updating .env file ---${NC}"
    
    # Use the variables exported or set in previous functions
    {
        echo "TZ=$TZ"
        echo "PUID=$PUID"
        echo "PGID=$PGID"
        echo "MEDIA_PATH=$MEDIA_PATH"
        echo "CONFIG_PATH=$CONFIG_PATH"
        echo "VPN_ENABLED=$VPN_ENABLED" # Use the explicit variable name
    } > "$ENV_FILE"

    if [ "$VPN_ENABLED" = "yes" ]; then
        DEFAULT_LAN_NETWORK="192.168.1.0/24"
        
        # Check if LAN_NETWORK exists in an old .env to reuse (Idempotency)
        local LAN_NETWORK
        if grep -q "LAN_NETWORK" "$ENV_FILE" && [ "$(grep "LAN_NETWORK" "$ENV_FILE" | cut -d'=' -f2)" != "" ]; then
            LAN_NETWORK=$(grep "LAN_NETWORK" "$ENV_FILE" | cut -d'=' -f2)
            echo "Reusing LAN_NETWORK: $LAN_NETWORK"
        else
            read -e -p "Enter LAN network for local access [default: $DEFAULT_LAN_NETWORK]: " lan_network_input
            LAN_NETWORK="${lan_network_input:-$DEFAULT_LAN_NETWORK}"
        fi

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

    echo "✅ .env file created/updated."
    echo "--------------------"
    cat "$ENV_FILE"
    echo "--------------------"
}

launch_stack() {
    echo -e "\n${BLUE}--- 8. Launching Docker Stack ---${NC}"
    # This command is idempotent for starting/restarting a stack based on its state
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d || exit 1
    echo -e "\n${GREEN}✅ Media stack launched successfully!${NC}"
}

post_install_instructions() {
    echo -e "\n${YELLOW}--- Setup Complete ---${NC}"
    echo -e "Your qBittorrent instance is running and will be available shortly."
    echo -e "The download and media paths have been automatically set up inside: ${GREEN}${MEDIA_PATH}/media-library${NC}"
    echo -e "\nTo access the Web UI, go to: ${GREEN}http://localhost:8080${NC}"
    echo -e ""
    
    echo -e "\n${BLUE}--- Retrieving Temporary Password from Log ---${NC}"
    
    local log_file="${CONFIG_PATH}/supervisord.log"
    local max_attempts=12
    local attempt=1
    
    echo -e "Attempting to retrieve temporary password automatically (will check up to $max_attempts times)..."

    while [ $attempt -le $max_attempts ]; do
        if [ -f "$log_file" ]; then
            local password_line
            password_line=$(grep "temporary password" "$log_file")
            
            if [ -n "$password_line" ]; then
                echo -e "\n${GREEN}🔑 TEMPORARY PASSWORD FOUND (First login):${NC}"
                echo -e "${YELLOW}$password_line${NC}"
                break
            fi
        fi
        
        if [ $attempt -lt $max_attempts ]; then
            echo "Attempt $attempt/$max_attempts: Password not found yet. Waiting 5 seconds..."
            sleep 5
        fi
        attempt=$((attempt + 1))
    done

    if [ $attempt -gt $max_attempts ]; then
        echo -e "${RED}❌ Password not found after several attempts.${NC}"
        echo -e "${YELLOW}Please run the following command manually in a few moments:${NC}"
        echo -e "${GREEN}cat ${CONFIG_PATH}/supervisord.log | grep \"temporary password\"${NC}"
    fi

    if [ "$VPN_ENABLED" = "no" ]; then
        echo -e "\n${RED}WARNING: This setup is NOT using a VPN and is not secure for downloading torrents.${NC}"
    fi
}

# --- Main Script Execution ---
main() {
    check_dependencies
    
    # Load default PUID/PGID/TZ here in case pre-flight jumps straight to post-install
    PUID=$(id -u)
    PGID=$(id -g)
    TZ=$(timedatectl show --value -p Timezone)
    
    run_pre_flight_checks # This might exit 0 if container is already running
    
    gather_user_settings
    handle_vpn_choice_and_setup
    
    # Use 'set -e' for the critical setup and launch steps
    # to ensure consistency if a command fails unexpectedly
    set -e
    create_startup_script
    setup_media_directories
    create_env_file
    launch_stack
    set +e # Turn off 'set -e' before post-install to prevent grep failures from exiting the script
    
    post_install_instructions
    echo -e "\n"
}

main "$@"
