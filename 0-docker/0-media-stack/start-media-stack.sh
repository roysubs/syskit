#!/bin/bash
# Author: Roy Wiseman 2025-05

RED='\e[0;31m'
YELLOW='\e[1;33m' # Added yellow for warnings/notes
NC='\033[0m'

set -e # Exit immediately if a command exits with a non-zero status.

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Installing...${NC}"
    if curl -fsSL https://get.docker.com | sh; then
        sudo usermod -aG docker "$USER"
        echo -e "${GREEN}Docker installed successfully. Please log out and back in to apply group changes or run 'newgrp docker'.${NC}"
        exit 1
    else
        echo -e "${RED}❌ Failed to install Docker.${NC}"
        exit 1
    fi
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
    exit 1
fi

# Ensure mikefarah/yq is installed for yaml parsing
if ! command -v yq &> /dev/null; then
    echo "yq command not found. Installing yq..."
    YQ_BINARY="yq_linux_amd64"
    case $(uname -m) in
        x86_64) YQ_BINARY="yq_linux_amd64";;
        aarch64) YQ_BINARY="yq_linux_arm64";;
        *) echo "Unsupported architecture for yq: $(uname -m). Please install yq manually."; exit 1;;
    esac

    if curl -L "https://github.com/mikefarah/yq/releases/latest/download/$YQ_BINARY" -o /usr/local/bin/yq; then
        sudo chmod +x /usr/local/bin/yq
        echo "yq installed successfully to /usr/local/bin."
    else
        echo "❌ Failed to download or install yq. Please install yq manually (e.g., via snap 'sudo snap install yq')."
        exit 1
    fi
fi

# --- BEGIN: WSL2 VPN Container Compatibility Check ---
IS_WSL=false
if grep -qE "(Microsoft|WSL)" /proc/version 2>/dev/null || uname -r | grep -q "microsoft-standard-WSL2" 2>/dev/null; then
    IS_WSL=true
fi

if [ "$IS_WSL" = true ]; then
    echo -e "${YELLOW}--------------------------------------------------------------------${NC}"
    echo -e "${YELLOW}⚠️ WARNING: WSL2 Environment Detected ⚠️${NC}"
    echo -e "${YELLOW}--------------------------------------------------------------------${NC}"
    echo -e "You appear to be running this script inside WSL2 (Windows Subsystem for Linux)."
    echo
    echo -e "${BOLD}Important limitations for VPN containers in WSL2:${NC}"
    echo -e "WSL2 uses a lightweight Linux kernel that limits the use of VPN containers."
    echo
    echo -e "1. ${CYAN}Kernel Module Loading:${NC} WSL2 does not fully support loading custom kernel modules"
    echo -e "   that some VPN containers require (e.g., 'iptable_mangle' for complex firewall rules)"
    echo -e "   You might be able to load some modules, but the container still fail to use them correctly."
    echo
    echo -e "2. ${CYAN}Privileged sysctl Changes:${NC} VPN containers often need to modify kernel parameters"
    echo -e "   (sysctls) for proper operation (e.g., 'net.ipv4.conf.all.src_valid_mark=1'). WSL2 restricts"
    echo -e "   many of these changes, even for privileged containers, leading to VPN connection failures."
    echo
    echo -e "${RED}Containers like container (and similar VPN gateway containers)"
    echo -e "are unlikely to establish a stable VPN connection within WSL2.${NC}"
    echo
    echo -e "${BOLD}Options:${NC}"
    echo -e "  a) ${GREEN}Run Docker on bare metal Linux (or a VM) for full VPN container functionality.${NC}"
    echo
    echo -e "  b) ${YELLOW}Run the container without VPN in WSL2 by disabling the option in docker-compose.yaml${NC}"
    echo -e "     For binhex/arch-qbittorrentvpn, that would mean changing the following line for the service:"
    echo -e "     'qbittorrentvpn' service:"
    echo
    echo -e "       From: ${CYAN}VPN_ENABLED=yes${NC}"
    echo -e "       To:   ${GREEN}VPN_ENABLED=no${NC}"
    echo
    echo -e "     ${BOLD}Note:${NC} Disabling the VPN will expose your qBittorrent traffic directly to your ISP."
    echo -e "     This could be ok, if, for example, you are running a VPN on the host OS."
    echo
    read -p "Do you want to continue with the script, in spite of these WSL2 limitations? (y/N): " wsl_confirm
    if [[ ! "$wsl_confirm" =~ ^[Yy]$ ]]; then
        echo "Exiting script."
        exit 1
    fi
    echo -e "${YELLOW}--------------------------------------------------------------------${NC}"
    echo # Newline for spacing
fi

CONFIG_ROOT="$HOME/.config/media-stack"
ENV_FILE=".env"
BASE_MEDIA="/mnt/media" # This is the mount point, seen by containers as the root of media
DOCKER_COMPOSE_FILE="docker-compose.yaml" # Updated Docker Compose filename

echo "🔍 Parsing ${DOCKER_COMPOSE_FILE}..."

CONTAINER_NAMES=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
IMAGES=($(yq -r '.services.*.image' "$DOCKER_COMPOSE_FILE"))
PORTS=($(yq -r '.services.*.ports[]?' "$DOCKER_COMPOSE_FILE" | cut -d: -f1 | grep -E '^[0-9]+$' | sort -u))

if [ "${#CONTAINER_NAMES[@]}" -ne "${#IMAGES[@]}" ]; then
    echo "‼️ Warning: The number of extracted container names (${#CONTAINER_NAMES[@]}) does not match the number of images (${#IMAGES[@]}). Output might be misaligned." >&2
fi

echo
echo "Container names (with Image names) that will be used:"
for i in "${!CONTAINER_NAMES[@]}"; do
    name="${CONTAINER_NAMES[$i]}"
    image="${IMAGES[$i]:-N/A (Image not found)}"
    echo "- $name ($image)"
done

echo ""
echo "Ports that will be used:"
if [ "${#PORTS[@]}" -eq 0 ]; then
    echo "- No host ports exposed"
else
    for port in "${PORTS[@]}"; do
        echo "- $port"
    done
fi
echo ""

display_urls() {
    echo "--- Application Access URLs ---"
    echo "(Note: You can replace the IP address with 'localhost' if local, or by the Tailscale address if remote)"
    echo

    for service_name in "${CONTAINER_NAMES[@]}"; do
        # Query for the first port mapping for the current service.
        # yq's '.services.<service_name>.ports[0]?' attempts to get the first port definition.
        # The '?' ensures it returns 'null' (as a string) if 'ports' is missing or empty, instead of erroring.
        port_mapping=$(yq -r ".services.\"$service_name\".ports[0]?" "$DOCKER_COMPOSE_FILE")

        # Check if port_mapping is not empty and not the literal string "null"
        if [ -n "$port_mapping" ] && [ "$port_mapping" != "null" ]; then
            # Extract the host port (the part before the first colon)
            host_port=$(echo "$port_mapping" | cut -d: -f1)
            # Ensure host_port is a valid number.
            # This also filters out cases where port_mapping might be more complex than "HOST:CONTAINER"
            # or if cut -d: -f1 results in a non-numeric string.
            if [[ "$host_port" =~ ^[0-9]+$ ]]; then
                display_name=$service_name
                # display_name="$(tr '[:lower:]' '[:upper:]' <<< ${service_name:0:1})${service_name:1}" # Could prettify/capitalise here
                echo "- ${display_name}: http://$(hostname -I | awk '{print $1}'):${host_port}"
            fi
        fi
    done
    echo
}

echo "🔎 Checking for existing containers that could conflict..."
container_conflict_found=false
for name in "${CONTAINER_NAMES[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -wq "$name"; then
        echo -e "❌ A container named \"$name\" already exists. Remove it with: ${YELLOW}docker rm -f $name${NC}"
        container_conflict_found=true
    fi
done
if [ "$container_conflict_found" = true ]; then
    echo
    echo -e "${RED}‼️ ${NC}One or more container name conflicts were found. Please resolve them before proceeding."
    echo
    echo -e "${YELLOW}It is possible that the full stack is running; you can test it at the following URLs:${NC}"
    echo
    display_urls
    exit 1
fi
echo "✅ No conflicting container names found."

echo "🔎 Checking for running containers using images from this compose file..."
EXISTING_RUNNING_CONTAINERS=$(docker ps --format '{{.Names}} {{.Image}}')
CONFLICTING_IMAGES=()
FILTERED_IMAGES=()
for img in "${IMAGES[@]}"; do
    if [[ "$img" != "none" && "$img" != "" ]]; then
        FILTERED_IMAGES+=("$img")
    fi
done
if [ "${#FILTERED_IMAGES[@]}" -gt 0 ]; then
    for img in "${FILTERED_IMAGES[@]}"; do
        if echo "$EXISTING_RUNNING_CONTAINERS" | grep -Fw -- "$img" > /dev/null; then
            CONTAINERS_USING_IMAGE=$(echo "$EXISTING_RUNNING_CONTAINERS" | grep -Fw -- "$img" | awk '{print $1}')
            echo -e "⚠️  WARNING: Image \"$img\" is already used by running container(s): ${YELLOW}$CONTAINERS_USING_IMAGE${NC}"
            CONFLICTING_IMAGES+=("$img")
        fi
    done
fi
if [ "${#CONFLICTING_IMAGES[@]}" -gt 0 ]; then
    read -p "Continue anyway? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi
if [ "${#CONFLICTING_IMAGES[@]}" -eq 0 ]; then
    echo "✅ No running containers found using these images."
fi

echo "🔎 Checking for port conflicts..."
port_conflict_found=false
for port in "${PORTS[@]}"; do
    if ss -tuln | grep -q ":$port "; then
        echo -e "❌ Port $port is already in use. Please stop the service using it or change the docker-compose config."
        port_conflict_found=true
    fi
done
if [ "$port_conflict_found" = true ]; then
    echo "‼️ One or more port conflicts were found. Please resolve them before proceeding."
    exit 1
fi
echo "✅ No conflicting ports found."

echo "✅ All conflict checks passed. Proceeding with system checks and setup..."

if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    if curl -fsSL https://get.docker.com | sh; then
        sudo usermod -aG docker "$USER"
        echo "Docker installed successfully. Please log out and back in to apply group changes or run 'newgrp docker'."
        exit 1
    else
        echo "❌ Failed to install Docker."
        exit 1
    fi
else
    echo "Docker is already installed."
fi

if ! docker compose version &>/dev/null; then
    echo "Docker Compose plugin not found. Installing..."
    DOCKER_CONFIG_PATH=${DOCKER_CONFIG:-$HOME/.docker} # Renamed variable to avoid conflict
    mkdir -p "$DOCKER_CONFIG_PATH/cli-plugins" || { echo "❌ Failed to create Docker config directory."; exit 1; }
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_COMPOSE_VERSION" ]; then # Fallback if API fails
        echo "Could not fetch latest Docker Compose version, using a recent default."
        LATEST_COMPOSE_VERSION="v2.27.1" # Or your preferred fixed version
    fi
    if curl -SL "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
      -o "$DOCKER_CONFIG_PATH/cli-plugins/docker-compose"; then
        chmod +x "$DOCKER_CONFIG_PATH/cli-plugins/docker-compose" || { echo "❌ Failed to set execute permissions on docker-compose plugin."; exit 1; }
        echo "Docker Compose plugin installed successfully."
    else
        echo "❌ Failed to download Docker Compose plugin."
        exit 1
    fi
fi

TZ=$(timedatectl show --value -p Timezone)
PUID=$(id -u)
PGID=$(id -g)
echo "Using UID=$PUID and GID=$PGID, TimeZone=$TZ"

echo "--- Media Directory Setup ---"
DEFAULT_MEDIA_PATH="~/Downloads"
read -e -p "Enter path to your actual media location (e.g. /srv/mymedia, /mnt/media etc) [default: $DEFAULT_MEDIA_PATH]: " MEDIA_PATH_INPUT   # -e tab completion
MEDIA_PATH="${MEDIA_PATH_INPUT:-$DEFAULT_MEDIA_PATH}"
if [[ "${MEDIA_PATH:0:1}" == "~" ]] && [ -n "$HOME" ]; then
    MEDIA_PATH="${MEDIA_PATH/#\~/$HOME}"
fi
MEDIA_PATH="${MEDIA_PATH%/}"   # Trim a trailing "/", if input is like "~/Downloads/"

if [ ! -d "$MEDIA_PATH" ]; then
    echo "Media path \"$MEDIA_PATH\" does not exist."
    echo "❌ Error: Required directory for media not found. Exiting."
    exit 1
fi

echo "Ensuring required media subdirectories exist under $MEDIA_PATH..."
# Subdirectories for Radarr, Lidarr, downloads etc.
# These will be created inside $MEDIA_PATH and thus appear under $BASE_MEDIA after bind mount.
SUBDIRS=("$MEDIA_PATH/downloads" "$MEDIA_PATH/movies" "$MEDIA_PATH/tv" "$MEDIA_PATH/music" "$MEDIA_PATH/books" "$MEDIA_PATH/audiobooks")
for subdir in "${SUBDIRS[@]}"; do
    if sudo mkdir -p "$subdir"; then
        echo "Created/Ensured directory: $subdir"
    else
        echo "❌ Error creating necessary media subdirectory: $subdir."
        echo "Please check permissions for the user $USER (or root if using sudo) on $MEDIA_PATH."
        exit 1
    fi
done

echo "Creating necessary config directories under ${CONFIG_ROOT}..."
# Config dirs for qbittorrentvpn (which includes wireguard), radarr, lidarr, prowlarr
CONFIG_SUBDIRS=("${CONFIG_ROOT}/qbittorrentvpn/wireguard" "${CONFIG_ROOT}/radarr" "${CONFIG_ROOT}/lidarr" "${CONFIG_ROOT}/prowlarr" "${CONFIG_ROOT}/raradd" "${CONFIG_ROOT}/readarr" "${CONFIG_ROOT}/bazarr")
for conf_subdir in "${CONFIG_SUBDIRS[@]}"; do
    # Use -p for mkdir to create parent directories as needed
    mkdir -p "$conf_subdir" || { echo "❌ Error creating config directory: $conf_subdir"; exit 1; }
done
echo "✅ Config directories created."


echo "Setting ownership on $MEDIA_PATH to $PUID:$PGID..."
if ! sudo chown -R "$PUID:$PGID" "$MEDIA_PATH"; then
    echo "❌ Error setting ownership on $MEDIA_PATH. Make sure you have appropriate permissions."
    exit 1
fi

echo
echo "--- WireGuard VPN Configuration ---"
echo -e "The qBittorrent+VPN container (${YELLOW}dyonr/qbittorrentvpn${NC} in your compose file) requires a WireGuard configuration file."
echo -e "You need to obtain this WireGuard configuration file (usually ending in ${YELLOW}.conf${NC}) from your VPN provider."
echo -e "This typically involves:"
echo -e "  1. Logging into your VPN provider's website."
echo -e "  2. Navigating to a 'Manual Setup', 'Router Setup', or 'WireGuard Configuration' section."
echo -e "  3. Generating or downloading the ${YELLOW}.conf${NC} file."
echo

DEFAULT_CONFIG_FILE_PATH="$HOME/wg0.conf" # Example default path
WIREGUARD_SOURCE_CONFIG_FILE_PATH=""
while true; do
    read -e -p "Enter the FULL path to your WireGuard configuration file (e.g., /path/to/your/wg0.conf) [default: $DEFAULT_CONFIG_FILE_PATH]: " CONFIG_FILE_PATH_INPUT
    WIREGUARD_SOURCE_CONFIG_FILE_PATH="${CONFIG_FILE_PATH_INPUT:-$DEFAULT_CONFIG_FILE_PATH}"
    if [[ "${WIREGUARD_SOURCE_CONFIG_FILE_PATH:0:1}" == "~" ]] && [ -n "$HOME" ]; then
        WIREGUARD_SOURCE_CONFIG_FILE_PATH="${WIREGUARD_SOURCE_CONFIG_FILE_PATH/#\~/$HOME}"
    fi
    WIREGUARD_SOURCE_CONFIG_FILE_PATH="${WIREGUARD_SOURCE_CONFIG_FILE_PATH%/}"   # Trim a trailing "/", if input is like "~/Downloads/"
    if [ -f "$WIREGUARD_SOURCE_CONFIG_FILE_PATH" ]; then
        echo "✅ WireGuard configuration file found at: $WIREGUARD_SOURCE_CONFIG_FILE_PATH"
        break
    else
        echo "❌ File not found at '$WIREGUARD_SOURCE_CONFIG_FILE_PATH'. Please enter a valid path."
    fi
done

# Define the target directory and filename for the qbittorrentvpn container
TARGET_WG_CONF_DIR="${CONFIG_ROOT}/qbittorrentvpn/wireguard"
TARGET_WG_CONF_FILE="${TARGET_WG_CONF_DIR}/wg0.conf" # Most containers expect wg0.conf

# Ensure the target directory exists (mkdir -p in config setup should have handled qbittorrentvpn/wireguard)
mkdir -p "$TARGET_WG_CONF_DIR" || { echo "❌ Error ensuring WireGuard target config directory exists: $TARGET_WG_CONF_DIR"; exit 1; }

cp "$WIREGUARD_SOURCE_CONFIG_FILE_PATH" "$TARGET_WG_CONF_FILE" || { echo "❌ Error copying WireGuard config file to $TARGET_WG_CONF_FILE"; exit 1; }
echo "✅ WireGuard configuration file copied to $TARGET_WG_CONF_FILE"
echo "This file will be used by the qbittorrentvpn container."

# --- BEGIN: New section for VPN_LAN_NETWORK ---
echo
echo "--- VPN LAN Network Configuration ---"
echo "The VPN container needs to know your local LAN network(s) to allow access"
echo "from devices on your network and potentially other networks like Tailscale."
echo "This is typically in CIDR notation (e.g., 192.168.1.0/24)."
echo "You can specify multiple networks separated by commas (e.g., 192.168.1.0/24,100.64.0.0/10)."

DETECTED_LAN_SUGGESTION=""
# Try to get the primary IP and form a /24 suggestion
PRIMARY_IP=$(hostname -I 2>/dev/null | awk '{print $1}') # Suppress stderr for hostname -I if it fails (e.g. no network)
if [ -n "$PRIMARY_IP" ]; then
    # Construct a /24 network suggestion from the primary IP
    DETECTED_LAN_SUGGESTION="$(echo "$PRIMARY_IP" | awk -F. '{print $1"."$2"."$3".0/24"}')"
else
    DETECTED_LAN_SUGGESTION="192.168.1.0/24" # Fallback default if IP detection fails
fi
# As you previously used Tailscale, let's include it in the default suggestion.
DEFAULT_VPN_LAN_NETWORK_VALUE="${DETECTED_LAN_SUGGESTION},100.64.0.0/10"
read -e -p "Enter your LAN network(s) for VPN bypass [default: ${DEFAULT_VPN_LAN_NETWORK_VALUE}]: " VPN_LAN_NETWORK_INPUT
VPN_LAN_NETWORK_VALUE="${VPN_LAN_NETWORK_INPUT:-$DEFAULT_VPN_LAN_NETWORK_VALUE}"

if [ -z "$VPN_LAN_NETWORK_VALUE" ]; then
    echo -e "${RED}❌ Error: VPN_LAN_NETWORK cannot be empty. Exiting.${NC}"
    exit 1
fi
echo "Using VPN_LAN_NETWORK: $VPN_LAN_NETWORK_VALUE"

echo
echo "Creating .env file..."
env_content=""
env_content+="TZ=$TZ"$'\n'
env_content+="PUID=$PUID"$'\n'
env_content+="PGID=$PGID"$'\n'
env_content+="MEDIA_PATH=$MEDIA_PATH"$'\n'
env_content+="CONFIG_ROOT=${CONFIG_ROOT}"$'\n' # Ensures compose file can use this
env_content+="VPN_LAN_NETWORK=${VPN_LAN_NETWORK_VALUE}"$'\n'
# Add any other global environment variables if needed by multiple services in compose
echo "$env_content" > "$ENV_FILE"
echo ".env file created with the following content:"
cat "$ENV_FILE"
echo

echo "Launching the Docker stack with 'docker compose up -d'..."
if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then
    echo "✅ Docker stack launched successfully!"
else
    echo "❌ Failed to launch Docker stack."
    exit 1
fi

echo
echo "✅ Media stack setup complete!"
echo
echo "To manage individual services (e.g., radarr):"
echo -e "  Stop:    ${YELLOW}docker compose stop radarr${NC}"
echo -e "  Start:   ${YELLOW}docker compose up -d radarr${NC}"
echo -e "  Restart: ${YELLOW}docker compose restart radarr${NC}"
echo -e "  Logs:    ${YELLOW}docker compose logs radarr${NC}"
echo
echo "qbittorrentvpn WebUI has username 'admin' and password 'adminadmin' by default."
echo "I normally set the other media components to the same for convenience."
echo

echo
echo "The following services should be accessible at these URLs:"
echo
display_urls
echo
