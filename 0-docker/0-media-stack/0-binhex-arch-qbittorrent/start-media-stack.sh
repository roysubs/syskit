#!/bin/bash
# Author: Roy Wiseman, with Gemini Refinement 2025-09-13

# --- Configuration and Colors ---
RED='\e[0;31m'
YELLOW='\e[1;33m'
GREEN='\e[0;32m'
BLUE='\e[0;34m'
NC='\033[0m'

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Global Variables ---
CONFIG_ROOT="$HOME/.config/media-stack"
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
        echo -e "${RED}❌ docker-compose.yaml not found in this directory. Exiting.${NC}"
        exit 1
    fi
    local container_names
    container_names=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
    for name in "${container_names[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -wq "$name"; then
            echo -e "${RED}❌ Container \"$name\" already exists. Please run the stop script first.${NC}"
            exit 1
        fi
    done
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
    # Use default if input is empty, and expand tilde to full home path
    MEDIA_PATH="${MEDIA_PATH_INPUT:-$DEFAULT_MEDIA_PATH}"
    MEDIA_PATH="${MEDIA_PATH/#\~/$HOME}"

    read -p "Do you want to enable the WireGuard VPN? (Y/n): " vpn_confirm
    if [[ "$vpn_confirm" =~ ^[Nn]$ ]]; then
        USE_VPN="no"
    else
        USE_VPN="yes"
    fi
}

setup_environment() {
    echo -e "\n${BLUE}--- 4. Setting up Environment ---${NC}"
    if [ ! -d "$MEDIA_PATH" ]; then
        read -p "Media path \"$MEDIA_PATH\" does not exist. Create it? (y/N): " create_dir
        if [[ "$create_dir" =~ ^[Yy]$ ]]; then
            mkdir -p "$MEDIA_PATH" || { echo "❌ Failed to create directory."; exit 1; }
        else
            echo "❌ Directory not found. Exiting."; exit 1
        fi
    fi

    echo "Creating config directories at $CONFIG_ROOT..."
    mkdir -p "${CONFIG_ROOT}/qbittorrentvpn/wireguard"

    echo "Setting ownership on media directory..."
    sudo chown -R "$PUID:$PGID" "$MEDIA_PATH"

    if [ "$USE_VPN" = "yes" ]; then
        echo -e "\n${BLUE}--- Configuring WireGuard VPN ---${NC}"
        echo "Setting VPN_PROV to 'custom' to use your local wg0.conf file."
        VPN_PROV="custom"

        DEFAULT_WG_PATH="$HOME/wg0.conf"
        read -e -p "Enter the FULL path to your WireGuard config file [default: $DEFAULT_WG_PATH]: " WG_PATH_INPUT
        local wg_source_path="${WG_PATH_INPUT:-$DEFAULT_WG_PATH}"
        wg_source_path="${wg_source_path/#\~/$HOME}"

        # This check ensures we only use a file from a specific path and fail securely.
        if [ ! -f "$wg_source_path" ]; then
            echo -e "${RED}❌ WireGuard config not found at \"$wg_source_path\". Exiting.${NC}"; exit 1
        fi

        # The binhex container expects the file to be named 'wg0.conf'.
        cp "$wg_source_path" "${CONFIG_ROOT}/qbittorrentvpn/wireguard/wg0.conf"
        echo "✅ WireGuard config copied successfully."
    else
        echo -e "\n${YELLOW}--- WARNING: VPN is DISABLED ---${NC}"
        sleep 2
    fi
}

create_env_file() {
    echo -e "\n${BLUE}--- 5. Creating .env file ---${NC}"
    read -e -p "Enter LAN network for local access (e.g., 192.168.1.0/24): " lan_network

    # Create the .env file
    {
        echo "TZ=$TZ"
        echo "PUID=$PUID"
        echo "PGID=$PGID"
        echo "MEDIA_PATH=$MEDIA_PATH"
        echo "CONFIG_ROOT=$CONFIG_ROOT"
        echo "VPN_LAN_NETWORK=$lan_network"
        echo "VPN_ENABLED=$USE_VPN"
        if [ "$USE_VPN" = "yes" ]; then
            echo "VPN_PROV=$VPN_PROV"
            # THIS IS THE CRITICAL FIX - Use VPN_CLIENT instead of VPN_TYPE
            echo "VPN_CLIENT=wireguard"
        fi
    } > "$ENV_FILE"

    echo "✅ .env file created."
    echo "--------------------"
    cat "$ENV_FILE"
    echo "--------------------"
}

launch_stack() {
    echo -e "\n${BLUE}--- 6. Launching Docker Stack ---${NC}"
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d
    echo -e "\n${GREEN}✅ Media stack launched successfully!${NC}"
}

post_install_instructions() {
    echo -e "\n${YELLOW}--- IMPORTANT: Final Manual Step ---${NC}"
    echo -e "To ensure your files download to the correct folder (${GREEN}${MEDIA_PATH}${YELLOW}), you MUST change one setting in qBittorrent:"
    echo -e "1. Log in to the Web UI at http://localhost:8080 (check logs for the temporary password if this is the first run)."
    echo -e "2. Go to ${GREEN}Tools -> Options -> Downloads${NC}."
    echo -e "3. In 'Default Save Path', change the existing path to exactly this:"
    echo -e "   ${GREEN}/data/downloads${NC}"
    echo -e "4. Click 'Save' at the bottom."
    echo -e "Your downloads will now go to the correct folder."
}

# --- Main Script Execution ---
main() {
    check_dependencies
    run_pre_flight_checks
    gather_user_settings
    setup_environment
    create_env_file
    launch_stack
    post_install_instructions
    echo -e "\nSetup complete."
}

# Run the main function
main "$@"


