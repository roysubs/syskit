#!/bin/bash
# Author: Roy Wiseman, with Gemini Review 2025-09-13

# --- Configuration and Colors ---
RED='\e[0;31m'
YELLOW='\e[1;33m'
GREEN='\e[0;32m'
NC='\033[0m'

set -e # Exit immediately if a command exits with a non-zero status.

# --- Global Variables ---
CONFIG_ROOT="$HOME/.config/media-stack"
ENV_FILE=".env"
DOCKER_COMPOSE_FILE="docker-compose.yaml"

# --- Functions ---

check_dependencies() {
    echo "--- 1. Checking Dependencies ---"
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}❌ Docker not found. Please install Docker before running this script.${NC}"
        exit 1
    fi
    if ! docker info &>/dev/null; then
        echo -e "${RED}❌ Docker daemon is not running. Please start the Docker service.${NC}"
        exit 1
    fi
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}❌ 'yq' not found. Please install it (e.g., 'sudo snap install yq').${NC}"
        exit 1
    fi
    echo "✅ All dependencies are met."
}

run_pre_flight_checks() {
    echo -e "\n--- 2. Running Pre-flight Checks ---"
    
    # Parse container names and ports for checks
    local container_names
    container_names=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
    
    # Check for existing container names
    for name in "${container_names[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -wq "$name"; then
            echo -e "${RED}❌ A container named \"$name\" already exists. Please remove it first (e.g., './stop-and-remove-media-stack.sh').${NC}"
            exit 1
        fi
    done
    echo "✅ No conflicting container names found."
    
    # Check for port conflicts
    local ports
    ports=($(yq -r '.services.*.ports[]?' "$DOCKER_COMPOSE_FILE" | cut -d: -f1 | grep -E '^[0-9]+$' | sort -u))
    for port in "${ports[@]}"; do
        if ss -tuln | grep -q ":$port "; then
            echo -e "${RED}❌ Port $port is already in use. Please stop the service using it.${NC}"
            exit 1
        fi
    done
    echo "✅ No conflicting ports are in use."
}

gather_user_settings() {
    echo -e "\n--- 3. Gathering User Settings ---"
    
    # Get PUID/PGID/Timezone
    PUID=$(id -u)
    PGID=$(id -g)
    TZ=$(timedatectl show --value -p Timezone)
    echo "Using PUID=$PUID, PGID=$PGID, TZ=$TZ"
    
    # Get Media Path
    DEFAULT_MEDIA_PATH="$HOME/Downloads"
    read -e -p "Enter the path for your media library [default: $DEFAULT_MEDIA_PATH]: " MEDIA_PATH_INPUT
    MEDIA_PATH="${MEDIA_PATH_INPUT:-$DEFAULT_MEDIA_PATH}"
    MEDIA_PATH="${MEDIA_PATH/#\~/$HOME}" # Expand ~
    
    # Get VPN Choice
    read -p "Do you want to enable the VPN for qBittorrent? (Y/n): " vpn_confirm
    if [[ "$vpn_confirm" =~ ^[Nn]$ ]]; then
        USE_VPN="no"
    else
        USE_VPN="yes"
    fi
}

setup_environment() {
    echo -e "\n--- 4. Setting up Environment ---"

    # Validate and create Media Path
    if [ ! -d "$MEDIA_PATH" ]; then
        echo "Media path \"$MEDIA_PATH\" does not exist."
        read -p "Do you want to create it? (y/N): " create_dir_confirm
        if [[ "$create_dir_confirm" =~ ^[Yy]$ ]]; then
            mkdir -p "$MEDIA_PATH" || { echo "❌ Failed to create directory."; exit 1; }
            echo "✅ Directory '$MEDIA_PATH' created."
        else
            echo "❌ Required directory not found. Exiting."
            exit 1
        fi
    fi

    # Create config directories
    echo "Creating necessary config directories..."
    CONFIG_SUBDIRS=("${CONFIG_ROOT}/qbittorrentvpn/wireguard" "${CONFIG_ROOT}/qbittorrentvpn/openvpn" "${CONFIG_ROOT}/radarr" "${CONFIG_ROOT}/lidarr" "${CONFIG_ROOT}/prowlarr")
    for dir in "${CONFIG_SUBDIRS[@]}"; do
        mkdir -p "$dir" || { echo "❌ Error creating config directory: $dir"; exit 1; }
    done
    echo "✅ Config directories created."

    # Set ownership on media path
    echo "Setting ownership on media directory..."
    if ! sudo chown -R "$PUID:$PGID" "$MEDIA_PATH"; then
        echo "❌ Error setting ownership on $MEDIA_PATH. Make sure you have sudo permissions."
        exit 1
    fi
    echo "✅ Media directory permissions set."

    # Handle VPN Configuration
    if [ "$USE_VPN" = "yes" ]; then
        echo -e "\n--- Configuring WireGuard VPN ---"
        DEFAULT_WG_PATH="$HOME/wg0.conf"
        read -e -p "Enter the FULL path to your WireGuard config file [default: $DEFAULT_WG_PATH]: " WG_PATH_INPUT
        local wg_source_path="${WG_PATH_INPUT:-$DEFAULT_WG_PATH}"
        wg_source_path="${wg_source_path/#\~/$HOME}"
        
        if [ ! -f "$wg_source_path" ]; then
            echo -e "${RED}❌ WireGuard config file not found at '$wg_source_path'. Exiting.${NC}"
            exit 1
        fi
        
        cp "$wg_source_path" "${CONFIG_ROOT}/qbittorrentvpn/wireguard/wg0.conf" || { echo "❌ Error copying WireGuard config file"; exit 1; }
        echo "✅ WireGuard configuration file copied successfully."
    else
        echo -e "\n${YELLOW}--------------------------------------------------------------------${NC}"
        echo -e "${YELLOW}⚠️ WARNING: VPN DISABLED ⚠️${NC}"
        echo -e "${RED}Your qBittorrent activity may be visible to your ISP.${NC}"
        echo -e "${YELLOW}--------------------------------------------------------------------${NC}"
        sleep 3
    fi
}

create_env_file() {
    echo -e "\n--- 5. Creating .env file ---"
    
    # Get LAN network for bypass
    read -e -p "Enter LAN network(s) for local access (e.g., 192.168.1.0/24) [press Enter for none]: " lan_network
    
    # Build .env content
    {
        echo "TZ=$TZ"
        echo "PUID=$PUID"
        echo "PGID=$PGID"
        echo "MEDIA_PATH=$MEDIA_PATH"
        echo "CONFIG_ROOT=$CONFIG_ROOT"
        echo "VPN_LAN_NETWORK=$lan_network"
        echo "VPN_ENABLED=$USE_VPN"
        if [ "$USE_VPN" = "yes" ]; then
            echo "VPN_TYPE=wireguard"
        fi
    } > "$ENV_FILE"

    echo "✅ .env file created with the following content:"
    echo -e "${GREEN}--------------------"
    cat "$ENV_FILE"
    echo -e "--------------------${NC}"
}

launch_stack() {
    echo -e "\n--- 6. Launching Docker Stack ---"
    if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then
        echo -e "\n${GREEN}✅ Media stack launched successfully!${NC}"
    else
        echo -e "\n${RED}❌ Failed to launch Docker stack. Check logs above for errors.${NC}"
        exit 1
    fi
}

display_urls() {
    echo -e "\n--- Application Access URLs ---"
    local container_names
    container_names=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
    local host_ip
    host_ip=$(hostname -I | awk '{print $1}')

    for service_name in "${container_names[@]}"; do
        local port_mapping
        port_mapping=$(yq -r ".services.\"$service_name\".ports[0]?" "$DOCKER_COMPOSE_FILE")
        if [ -n "$port_mapping" ] && [ "$port_mapping" != "null" ]; then
            local host_port
            host_port=$(echo "$port_mapping" | cut -d: -f1)
            if [[ "$host_port" =~ ^[0-9]+$ ]]; then
                echo "- ${service_name}: http://${host_ip}:${host_port}"
            fi
        fi
    done
}

# --- Main Script Execution ---
main() {
    check_dependencies
    run_pre_flight_checks
    gather_user_settings
    setup_environment
    create_env_file
    launch_stack
    display_urls
    echo -e "\nSetup complete."
}

main "$@"
