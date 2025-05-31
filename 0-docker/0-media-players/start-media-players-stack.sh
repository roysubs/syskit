#!/bin/bash
# Author: Roy Wiseman 2025-05

RED='\e[0;31m'
YELLOW='\e[1;33m'
GREEN='\e[0;32m'
NC='\033[0m' # No Color

# Optional: Uncomment if you have a custom Docker setup script
# if [ -f "./docker-setup-deb-variants.sh" ]; then "./docker-setup-deb-variants.sh"; fi

set -e # Exit immediately if a command exits with a non-zero status.

CONFIG_ROOT="$HOME/.config/media-players"
ENV_FILE=".env"
BASE_MEDIA="$HOME/Downloads" # This is the mount point target for containers
DOCKER_COMPOSE_FILE="docker-compose.yaml"

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

echo -e "${GREEN}--- Media Player Stack Setup Script ---${NC}"
echo

echo -e "${YELLOW}🔍 Parsing ${DOCKER_COMPOSE_FILE}...${NC}"
if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
    echo -e "${RED}‼️ Docker Compose file '$DOCKER_COMPOSE_FILE' not found! Please create it first.${NC}"
    echo -e "${YELLOW}A template has been provided. You should save it as ${DOCKER_COMPOSE_FILE} in the current directory.${NC}"
    exit 1
fi

CONTAINER_NAMES=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
IMAGES=($(yq -r '.services.*.image // "N/A"' "$DOCKER_COMPOSE_FILE")) # Use // "N/A" for robustness
# Adjusted port extraction to handle network_mode: host (which won't have 'ports') and various port definitions
PORTS=($(yq -r '.services.*.ports[]?' "$DOCKER_COMPOSE_FILE" 2>/dev/null | grep -o '^[0-9]*' | grep -E '^[0-9]+$' | sort -u))

if [ "${#CONTAINER_NAMES[@]}" -eq 0 ]; then
    echo -e "${RED}‼️ No services found in ${DOCKER_COMPOSE_FILE}. Please check the file.${NC}"
    exit 1
fi

if [ "${#CONTAINER_NAMES[@]}" -ne "${#IMAGES[@]}" ]; then
    echo -e "${YELLOW}‼️ Warning: Number of container names (${#CONTAINER_NAMES[@]}) vs images (${#IMAGES[@]}) mismatch. Review yq parsing if issues.${NC}" >&2
fi

echo
echo -e "${GREEN}Container names (with Image names) that will be used:${NC}"
for i in "${!CONTAINER_NAMES[@]}"; do
    name="${CONTAINER_NAMES[$i]}"
    image="${IMAGES[$i]:-N/A}"
    echo "- $name ($image)"
done

echo
echo -e "${GREEN}Host ports that will be exposed (from services not using network_mode: host):${NC}"
if [ "${#PORTS[@]}" -eq 0 ]; then
    echo "- No specific host ports found or all services primarily use network_mode: host."
else
    for port in "${PORTS[@]}"; do
        echo "- $port"
    done
fi
HOST_MODE_SERVICES=($(yq -r '.services | to_entries[] | select(.value.network_mode == "host") | .key' "$DOCKER_COMPOSE_FILE"))
if [ "${#HOST_MODE_SERVICES[@]}" -gt 0 ]; then
    echo -e "${YELLOW}Note: The following services are configured with 'network_mode: host' and will use the host's network directly:${NC}"
    for service in "${HOST_MODE_SERVICES[@]}"; do
        echo "- $service"
    done
fi
echo

echo -e "${YELLOW}🔎 Checking for existing conflicting container names...${NC}"
container_conflict_found=false
for name in "${CONTAINER_NAMES[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${name}$"; then # Exact match
        echo -e "${RED}❌ A container named \"$name\" already exists. Remove it with: ${YELLOW}docker rm -f $name${NC}"
        container_conflict_found=true
    fi
done
if [ "$container_conflict_found" = true ]; then
    echo -e "${RED}‼️ One or more container name conflicts found. Please resolve them before proceeding.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ No conflicting container names found.${NC}"

echo -e "${YELLOW}🔎 Checking for running containers using images from this compose file...${NC}"
EXISTING_RUNNING_CONTAINERS=$(docker ps --format '{{.Names}} {{.Image}}')
CONFLICTING_IMAGES_FOUND=false
UNIQUE_IMAGES=($(echo "${IMAGES[@]}" | tr ' ' '\n' | grep -v "N/A" | sort -u))

if [ "${#UNIQUE_IMAGES[@]}" -gt 0 ]; then
    for img_pattern in "${UNIQUE_IMAGES[@]}"; do
        base_img_pattern=$(echo "$img_pattern" | cut -d: -f1) # Check both image:tag and image
        if echo "$EXISTING_RUNNING_CONTAINERS" | grep -Fq -- "$img_pattern" || \
           ([ "$base_img_pattern" != "$img_pattern" ] && echo "$EXISTING_RUNNING_CONTAINERS" | grep -Fq -- "$base_img_pattern"); then
            CONTAINERS_USING_IMAGE=$(echo "$EXISTING_RUNNING_CONTAINERS" | grep -E "($img_pattern|$base_img_pattern)" | awk '{print $1}')
            echo -e "⚠️  ${YELLOW}WARNING: Image pattern \"$img_pattern\" (or base \"$base_img_pattern\") is used by running container(s): ${CONTAINERS_USING_IMAGE}${NC}"
            CONFLICTING_IMAGES_FOUND=true
        fi
    done
fi
if [ "$CONFLICTING_IMAGES_FOUND" = true ]; then
    read -r -p "Continue anyway? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo -e "${RED}Exiting due to potential image conflicts.${NC}"; exit 1; }
fi
if [ "$CONFLICTING_IMAGES_FOUND" = false ]; then
    echo -e "${GREEN}✅ No running containers found using these exact images/base images.${NC}"
fi

echo -e "${YELLOW}🔎 Checking for port conflicts (for services not using network_mode: host)...${NC}"
port_conflict_found=false
for port in "${PORTS[@]}"; do
    if ss -tuln | grep -q ":$port " || netstat -tuln | grep -q ":$port "; then # Added netstat for wider compatibility
        echo -e "${RED}❌ Port $port is already in use. Please stop the service using it or change the ${DOCKER_COMPOSE_FILE}.${NC}"
        port_conflict_found=true
    fi
done
if [ "$port_conflict_found" = true ]; then
    echo -e "${RED}‼️ One or more port conflicts were found. Please resolve them before proceeding.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ No conflicting ports found for explicitly mapped ports.${NC}"
if [ "${#HOST_MODE_SERVICES[@]}" -gt 0 ]; then
    echo -e "${YELLOW}⚠️ Reminder: Services in 'network_mode: host' (${HOST_MODE_SERVICES[*]}) bypass Docker's port mapping. Ensure their default application ports do not conflict with existing services on your host.${NC}"
    echo -e "${YELLOW}   Common ports to check: Plex (32400/tcp), etc. Check service documentation.${NC}"
fi

echo -e "${GREEN}✅ Pre-flight checks passed. Proceeding with system setup...${NC}"
echo

if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Docker not found. Attempting to install...${NC}"
    if curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh; then
        sudo usermod -aG docker "$USER"
        echo -e "${GREEN}Docker installed successfully.${NC}"
        echo -e "${YELLOW}IMPORTANT: You MUST log out and back in, or run 'newgrp docker' in your current shell, to apply group changes before Docker will work without sudo for your user.${NC}"
        echo -e "${YELLOW}Re-run this script after doing so.${NC}"
        rm get-docker.sh
        exit 1
    else
        echo -e "${RED}❌ Failed to install Docker using get.docker.com script. Please install Docker manually.${NC}"
        rm -f get-docker.sh
        exit 1
    fi
else
    echo -e "${GREEN}Docker is already installed.${NC}"
fi

if ! docker compose version &>/dev/null; then
    echo -e "${YELLOW}Docker Compose plugin not found. Attempting to install...${NC}"
    DOCKER_CONFIG_PLUGIN_PATH=${DOCKER_CONFIG:-$HOME/.docker}/cli-plugins
    mkdir -p "$DOCKER_CONFIG_PLUGIN_PATH" || { echo -e "${RED}❌ Failed to create Docker config directory: $DOCKER_CONFIG_PLUGIN_PATH${NC}"; exit 1; }
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$LATEST_COMPOSE_VERSION" ]; then
        echo -e "${YELLOW}Could not fetch latest Docker Compose version from GitHub, using a recent default (e.g., v2.27.1). Please check manually if this fails.${NC}"
        # Fallback to a known version or let the user handle it if specific version is critical
        LATEST_COMPOSE_VERSION="v2.27.1" # Example fixed version
    fi
    echo "Attempting to download Docker Compose ${LATEST_COMPOSE_VERSION} for $(uname -m)..."
    if sudo curl -SL "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
      -o "$DOCKER_CONFIG_PLUGIN_PATH/docker-compose"; then
        sudo chmod +x "$DOCKER_CONFIG_PLUGIN_PATH/docker-compose" || { echo -e "${RED}❌ Failed to set execute permissions on docker-compose plugin.${NC}"; exit 1; }
        echo -e "${GREEN}Docker Compose plugin installed successfully to $DOCKER_CONFIG_PLUGIN_PATH/docker-compose.${NC}"
        echo -e "${YELLOW}You might need to re-login or open a new terminal for 'docker compose' to be found if it was just installed.${NC}"
    else
        echo -e "${RED}❌ Failed to download Docker Compose plugin. Please install it manually from Docker's official documentation.${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Docker Compose plugin is already installed.${NC}"
fi
echo

# Check if user is in docker group, vital after installation
if ! groups "$USER" | grep -q '\bdocker\b'; then
    echo -e "${YELLOW}WARNING: User $USER is not yet part of the 'docker' group.${NC}"
    echo -e "${YELLOW}Docker commands might require 'sudo' or fail. If Docker was just installed, please log out and log back in, or run 'newgrp docker' then re-run this script.${NC}"
    read -r -p "Continue with script execution? (Some Docker commands might fail) (y/N): " confirm_docker_group
    if [[ ! "$confirm_docker_group" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi


# Try to guess Timezone, otherwise default to Etc/UTC
TZ_GUESS=$(cat /etc/timezone 2>/dev/null || timedatectl show --value -p Timezone 2>/dev/null)
DEFAULT_TZ=${TZ_GUESS:-"Etc/UTC"}
read -r -p "Enter your TimeZone (e.g., America/New_York, Europe/London) [default: $DEFAULT_TZ]: " INPUT_TZ
TZ=${INPUT_TZ:-$DEFAULT_TZ}
PUID=$(id -u)
PGID=$(id -g)
echo "Using UID=$PUID, GID=$PGID, TimeZone=$TZ"
echo

echo -e "${GREEN}--- Media Directory Setup ---${NC}"
DEFAULT_SOURCE_PATH="/mnt/storage/media" # Example default, adjust if you have a common one
echo -e "The containers will see media from ${YELLOW}${BASE_MEDIA}${NC}."
echo -e "You need to provide the ${YELLOW}actual path on your host machine${NC} where your media files are (or will be) stored."
echo -e "This script will then attempt to bind-mount your actual path to ${YELLOW}${BASE_MEDIA}${NC}."
read -r -p "Enter path to your ACTUAL media source location (e.g., /srv/mymedia, /mnt/hdd1/media) [default: $DEFAULT_SOURCE_PATH]: " SOURCE_PATH_INPUT
SOURCE_PATH="${SOURCE_PATH_INPUT:-$DEFAULT_SOURCE_PATH}"
SOURCE_PATH=$(realpath "$SOURCE_PATH") # Resolve to absolute path
echo "Using source path for media: $SOURCE_PATH (will be mounted to $BASE_MEDIA for containers)"

if [ ! -d "$SOURCE_PATH" ]; then
    echo -e "${YELLOW}Source path \"$SOURCE_PATH\" does not exist. Creating with sudo...${NC}"
    sudo mkdir -p "$SOURCE_PATH" || { echo -e "${RED}❌ Error creating source path: $SOURCE_PATH. Check permissions.${NC}"; exit 1; }
    sudo chown "$PUID:$PGID" "$SOURCE_PATH" # Own the root of the source path
    echo -e "${GREEN}Created source path: $SOURCE_PATH${NC}"
fi
if [ ! -d "$BASE_MEDIA" ]; then
    echo -e "${YELLOW}Target mount point $BASE_MEDIA does not exist. Creating with sudo...${NC}"
    sudo mkdir -p "$BASE_MEDIA" || { echo -e "${RED}❌ Error creating mount point: $BASE_MEDIA. Check permissions.${NC}"; exit 1; }
    echo -e "${GREEN}Created mount point: $BASE_MEDIA${NC}"
fi

# Handle mounting $SOURCE_PATH to $BASE_MEDIA
if mountpoint -q "$BASE_MEDIA"; then
    MOUNTED_SOURCE=$(findmnt -n -o SOURCE --target "$BASE_MEDIA" | sed 's/\[.*\]//') # Remove opts like [/.../]
    REAL_MOUNTED_SOURCE=$(realpath "$MOUNTED_SOURCE" 2>/dev/null || echo "$MOUNTED_SOURCE")
    REAL_SOURCE_PATH=$(realpath "$SOURCE_PATH")

    if [ "$REAL_MOUNTED_SOURCE" == "$REAL_SOURCE_PATH" ]; then
        echo -e "${GREEN}$BASE_MEDIA is already correctly mounted from $SOURCE_PATH.${NC}"
    else
        echo -e "${YELLOW}Warning: $BASE_MEDIA is mounted from '$MOUNTED_SOURCE' (resolves to '$REAL_MOUNTED_SOURCE'), not '$SOURCE_PATH' (resolves to '$REAL_SOURCE_PATH').${NC}"
        read -r -p "Attempt to unmount '$BASE_MEDIA' and remount '$SOURCE_PATH' to it? (y/N): " remount_confirm
        if [[ "$remount_confirm" =~ ^[Yy]$ ]]; then
            echo "Attempting to unmount $BASE_MEDIA..."
            sudo umount "$BASE_MEDIA" || { echo -e "${RED}❌ Failed to unmount $BASE_MEDIA. It might be in use. Please check manually.${NC}"; exit 1; }
            echo "Mounting $SOURCE_PATH to $BASE_MEDIA with sudo..."
            if sudo mount --bind "$SOURCE_PATH" "$BASE_MEDIA"; then
                echo -e "${GREEN}Successfully mounted $SOURCE_PATH to $BASE_MEDIA.${NC}"
            else
                echo -e "${RED}❌ Error mounting $SOURCE_PATH to $BASE_MEDIA. Check permissions and paths.${NC}"
                exit 1
            fi
        else
            echo -e "${YELLOW}Skipping remount. Please ensure $BASE_MEDIA points to your intended media for containers.${NC}"
        fi
    fi
else
    echo "Mounting $SOURCE_PATH to $BASE_MEDIA with sudo..."
    if sudo mount --bind "$SOURCE_PATH" "$BASE_MEDIA"; then
        echo -e "${GREEN}Successfully mounted $SOURCE_PATH to $BASE_MEDIA.${NC}"
    else
        echo -e "${RED}❌ Error mounting $SOURCE_PATH to $BASE_MEDIA. Check permissions and ensure path '$SOURCE_PATH' exists and '$BASE_MEDIA' is available.${NC}"
        exit 1
    fi
fi

echo "Ensuring required media subdirectories exist under $SOURCE_PATH (will be visible at $BASE_MEDIA/... for containers)..."
MEDIA_SUBDIRS=("movies" "tv" "music" "photos" "books" "audiobooks" "other" "downloads") # Common subdirs
for subdir_name in "${MEDIA_SUBDIRS[@]}"; do
    full_subdir_path="$SOURCE_PATH/$subdir_name" # Create in the actual source path
    if [ ! -d "$full_subdir_path" ]; then
        echo "Creating directory: $full_subdir_path"
        sudo mkdir -p "$full_subdir_path" || { echo -e "${RED}❌ Error creating media subdirectory: $full_subdir_path.${NC}"; exit 1; }
        sudo chown "$PUID:$PGID" "$full_subdir_path"
        sudo chmod 775 "$full_subdir_path" # rwxrwxr-x
    else
        echo "Directory $full_subdir_path (visible as $BASE_MEDIA/$subdir_name in containers) already exists."
        # Optionally, ensure ownership and permissions on existing dirs
        # sudo chown -R "$PUID:$PGID" "$full_subdir_path"
        # sudo chmod -R u+rwX,g+rwX,o+rX "$full_subdir_path"
    fi
done

echo "Creating necessary config directories under ${CONFIG_ROOT}..."
# Using service names from Docker Compose file for config subdirectories
SERVICE_NAMES_FOR_CONFIG=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
for service_name in "${SERVICE_NAMES_FOR_CONFIG[@]}"; do
    conf_subdir="${CONFIG_ROOT}/${service_name}"
    mkdir -p "$conf_subdir" || { echo -e "${RED}❌ Error creating config directory: $conf_subdir${NC}"; exit 1; }
done
echo -e "${GREEN}✅ Config directories created/ensured under ${CONFIG_ROOT}.${NC}"

echo "Setting ownership on config root ${CONFIG_ROOT} to $PUID:$PGID..."
# No sudo here if CONFIG_ROOT is in $HOME, otherwise sudo needed.
# $HOME is usually owned by user, so subdirs should be too.
# However, if script is run as root initially, $HOME/.config might become root owned.
# Using sudo to be safe, but it's better if $CONFIG_ROOT is user-creatable.
if [ "$(stat -c '%U' "$(dirname "$CONFIG_ROOT")")" == "root" ] && [ ! -w "$(dirname "$CONFIG_ROOT")" ]; then
    echo -e "${YELLOW}Parent of $CONFIG_ROOT might require sudo for ownership change.${NC}"
    sudo chown -R "$PUID:$PGID" "$CONFIG_ROOT" || echo -e "${YELLOW}Warning: Could not chown $CONFIG_ROOT. Permissions issues might occur in containers.${NC}"
else
    chown -R "$PUID:$PGID" "$CONFIG_ROOT" || sudo chown -R "$PUID:$PGID" "$CONFIG_ROOT" || echo -e "${YELLOW}Warning: Could not chown $CONFIG_ROOT. Permissions issues might occur in containers.${NC}"
fi
echo

echo -e "${GREEN}--- Environment File Setup ---${NC}"
read -r -p "Enter PLEX_CLAIM token (optional, get from plex.tv/claim, leave blank to skip): " PLEX_CLAIM_TOKEN
read -r -p "Enter JELLYFIN_SERVER_URL for Jellyfin (optional, e.g., http://your_ip:8096 or https://your.domain.com, leave blank): " JELLYFIN_URL_INPUT

echo "Creating/Updating .env file at $ENV_FILE..."
# Resolve CONFIG_ROOT and BASE_MEDIA to absolute paths for .env
ABS_CONFIG_ROOT=$(realpath "$CONFIG_ROOT")
ABS_BASE_MEDIA=$(realpath "$BASE_MEDIA") # Should already be absolute, but just in case
{
    echo "TZ=${TZ}"
    echo "PUID=${PUID}"
    echo "PGID=${PGID}"
    echo "CONFIG_ROOT=${ABS_CONFIG_ROOT}"
    echo "BASE_MEDIA=${ABS_BASE_MEDIA}"
    echo "PLEX_CLAIM=${PLEX_CLAIM_TOKEN}"
    echo "JELLYFIN_SERVER_URL=${JELLYFIN_URL_INPUT}"
} > "$ENV_FILE"
echo ".env file created/updated with the following content:"
cat "$ENV_FILE"
echo

echo -e "${GREEN}Attempting to launch the Docker stack with 'docker compose -f \"$DOCKER_COMPOSE_FILE\" --env-file \"$ENV_FILE\" up -d'...${NC}"
if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then
    echo -e "${GREEN}✅ Docker media player stack launched successfully!${NC}"
else
    echo -e "${RED}❌ Failed to launch Docker stack. Check logs above and run 'docker compose -f \"$DOCKER_COMPOSE_FILE\" logs' for more details.${NC}"
    exit 1
fi

echo -e "${GREEN}Attempting to launch the Docker stack with 'docker compose -f \"$DOCKER_COMPOSE_FILE\" --env-file \"$ENV_FILE\" up -d'...${NC}"
if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then
    echo -e "${GREEN}✅ Docker media player stack launched successfully!${NC}"
else
    echo -e "${RED}❌ Failed to launch Docker stack. Check logs above and run 'docker compose -f \"$DOCKER_COMPOSE_FILE\" logs' for more details.${NC}"
    exit 1
fi

echo
echo -e "${GREEN}✅ Media player stack setup complete!${NC}"
echo
echo "--- Application Access URLs (Approximate) ---"
echo "Wait a few minutes for services to initialize fully."
echo "(If accessing from another device on your network, replace 'localhost' or '127.0.0.1' with this machine's IP address)"

for service_name in "${CONTAINER_NAMES[@]}"; do
    display_name="$(tr '[:lower:]' '[:upper:]' <<< ${service_name:0:1})${service_name:1}"
    network_mode=$(yq -r ".services.\"$service_name\".network_mode // \"default\"" "$DOCKER_COMPOSE_FILE")
    
    if [ "$network_mode" == "host" ]; then
        default_port_info=""
        case "$service_name" in
            plex) default_port_info=" (Plex WebUI: http://localhost:32400/web)" ;;
            *) default_port_info=" (Port is directly on host; check service documentation for default port)" ;;
        esac
        echo -e "- ${display_name}: ${YELLOW}Uses host network${NC}${default_port_info}"
    else
        # Try to get the first port mapping
        port_mapping=$(yq -r ".services.\"$service_name\".ports[0]?" "$DOCKER_COMPOSE_FILE")
        if [ -n "$port_mapping" ] && [ "$port_mapping" != "null" ]; then
            host_port=$(echo "$port_mapping" | cut -d: -f1 | grep -o '^[0-9]*')
            if [[ "$host_port" =~ ^[0-9]+$ ]]; then
                echo "- ${display_name}: http://localhost:${host_port}"
            else
                 echo "- ${display_name}: Port mapping ('$port_mapping') found, but host port unclear."
            fi
        else
            # Service might not expose a primary web port (e.g. headless kodi's main access is via other clients/webUI on specific port)
             # Check for specific known ports if no general mapping is useful for a primary URL
            case "$service_name" in
                kodi-headless) echo "- ${display_name} (WebUI): http://localhost:8088" ;; # From kodi-headless port mapping
                *) echo "- ${display_name}: No simple primary port mapping found. Check compose file for specific ports." ;;
            esac
        fi
    fi
done

echo
echo "To manage individual services (e.g., plex):"
echo -e "  Stop:     ${YELLOW}docker compose -f \"$DOCKER_COMPOSE_FILE\" stop plex${NC}"
echo -e "  Start:    ${YELLOW}docker compose -f \"$DOCKER_COMPOSE_FILE\" up -d plex${NC}"
echo -e "  Restart:  ${YELLOW}docker compose -f \"$DOCKER_COMPOSE_FILE\" restart plex${NC}"
echo -e "  Logs:     ${YELLOW}docker compose -f \"$DOCKER_COMPOSE_FILE\" logs plex${NC}"
echo -e "  All Logs: ${YELLOW}docker compose -f \"$DOCKER_COMPOSE_FILE\" logs${NC}"
echo -e "  Down (stop & remove containers): ${YELLOW}docker compose -f \"$DOCKER_COMPOSE_FILE\" down${NC}"
echo
echo -e "${GREEN}Setup finished. Enjoy your media!${NC}"
