#!/bin/bash
# Author: Roy Wiseman 2025-01

RED='\e[0;31m'
NC='\033[0m'

# Check if docker is installed:
if [ -f "docker-setup-deb-variants.sh" ]; then "./docker-setup-deb-variants.sh"; fi

set -e # Exit immediately if a command exits with a non-zero status. Note: We'll handle specific exits for conflicts.

CONFIG_ROOT="$HOME/.config/media-stack"
ENV_FILE=".env"
BASE_MEDIA="/mnt/media" # This is the mount point, seen by containers as the root of media
DOCKER_COMPOSE_FILE="docker-compose-wireguard.yaml"

# Ensure mikefarah/yq is installed
if ! command -v yq &>/dev/null || ! yq --version 2>&1 | grep -q "mikefarah/yq"; then
    echo "Installing mikefarah/yq..."
    YQ_ARCH=$(uname -m)
    case "${YQ_ARCH}" in
        x86_64) YQ_BINARY="yq_linux_amd64";;
        aarch64) YQ_BINARY="yq_linux_arm64";;
        *) echo "Unsupported arch: ${YQ_ARCH}"; exit 1;;
    esac
    sudo curl -L "https://github.com/mikefarah/yq/releases/latest/download/${YQ_BINARY}" -o /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq || { echo "Failed to install yq."; exit 1; }
    echo "yq installed."
else
    echo "mikefarah/yq already installed."
fi

echo "🔍 Parsing docker-compose.yaml..."

# Extract container names, image names, and host posts (host port always the first part of port bindings) that will be used
# Note: Using --raw-output (-r) with yq is often safer for shell processing
CONTAINER_NAMES=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))
IMAGES=($(yq -r '.services.*.image' "$DOCKER_COMPOSE_FILE"))
PORTS=($(yq -r '.services.*.ports[]?' "$DOCKER_COMPOSE_FILE" | cut -d: -f1 | grep -E '^[0-9]+$' | sort -u))

# Check if the number of container names and images match
if [ "${#CONTAINER_NAMES[@]}" -ne "${#IMAGES[@]}" ]; then
    echo "‼️ Warning: The number of extracted container names (${#CONTAINER_NAMES[@]}) does not match the number of images (${#IMAGES[@]}). Output might be misaligned." >&2
fi

echo
echo "Container names (with Image names) that will be used:"
# Loop using an index to pair container names and images
for i in "${!CONTAINER_NAMES[@]}"; do
    # Get the container name at index i
    name="${CONTAINER_NAMES[$i]}"
    # Get the corresponding image name at index i (if it exists)
    # Use array indirection and check index validity
    image="${IMAGES[$i]:-N/A (Image not found)}" # Provide a default if image is missing for some reason
    echo "- $name ($image)"
done

echo "" # Add a blank line for separation

echo "Ports that will be used:"
if [ "${#PORTS[@]}" -eq 0 ]; then
    echo "- No host ports exposed"
else
    # Loop through ports
    for port in "${PORTS[@]}"; do
        echo "- $port"
    done
fi

echo "" # Add a blank line for separation

# Check for container name conflicts
echo "🔎 Checking for existing containers that could conflict..."
container_conflict_found=false # Initialize a flag for container names

for name in "${CONTAINER_NAMES[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -wq "$name"; then
        echo "❌ A container named \"$name\" already exists. Remove it with:"
        echo "    docker rm -f $name"
        container_conflict_found=true # Set the flag
    fi
done

# After the loop, check the container name flag
if [ "$container_conflict_found" = true ]; then
    echo "‼️ One or more container name conflicts were found. Please resolve them before proceeding."
    exit 1 # Exit with an error code
fi
echo "✅ No conflicting container names found."

# Check if any listed image is already in use by a *running* container
echo "🔎 Checking for running containers using images from this compose file..."
EXISTING_RUNNING_CONTAINERS=$(docker ps --format '{{.Names}} {{.Image}}')
CONFLICTING_IMAGES=()
# Filter out images that are explicitly set to "none" or similar placeholders
FILTERED_IMAGES=()
for img in "${IMAGES[@]}"; do
    if [[ "$img" != "none" && "$img" != "" ]]; then
        FILTERED_IMAGES+=("$img")
    fi
done

if [ "${#FILTERED_IMAGES[@]}" -gt 0 ]; then
    for img in "${FILTERED_IMAGES[@]}"; do
        # Using grep -F for fixed string matching, -w for whole words (image name can be a whole word)
        if echo "$EXISTING_RUNNING_CONTAINERS" | grep -Fw -- "$img" > /dev/null; then
            # Find which running container(s) use this image
            CONTAINERS_USING_IMAGE=$(echo "$EXISTING_RUNNING_CONTAINERS" | grep -Fw -- "$img" | awk '{print $1}')
            echo "⚠️  WARNING: Image \"$img\" is already used by running container(s): $CONTAINERS_USING_IMAGE"
            CONFLICTING_IMAGES+=("$img") # Still add to this list if we want a final summary
        fi
    done
fi

# The image conflict is treated as a warning with an option to continue
if [ "${#CONFLICTING_IMAGES[@]}" -gt 0 ]; then
    read -p "Continue anyway? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || exit 1
fi
# If no image conflicts or user chose to continue, proceed.
if [ "${#CONFLICTING_IMAGES[@]}" -eq 0 ]; then
    echo "✅ No running containers found using these images."
fi


# Check for port conflicts
echo "🔎 Checking for port conflicts..."
port_conflict_found=false # Initialize a flag for ports

for port in "${PORTS[@]}"; do
    # Check if the port is in use (TCP or UDP, listening)
    if ss -tuln | grep -q ":$port "; then
        echo "❌ Port $port is already in use. Please stop the service using it or change the docker-compose config."
        port_conflict_found=true # Set the flag
    fi
done

# After the loop, check the port conflict flag
if [ "$port_conflict_found" = true ]; then
    echo "‼️ One or more port conflicts were found. Please resolve them before proceeding."
    exit 1 # Exit with an error code
fi
echo "✅ No conflicting ports found."

# --- If reach here, all critical checks passed, so proceed with system checks and startup ---
echo "✅ All conflict checks passed. Proceeding with system checks and setup..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "Docker not found. Installing..."
    # Add error handling for curl and sh script
    if curl -fsSL https://get.docker.com | sh; then
        sudo usermod -aG docker "$USER"
        echo "Docker installed successfully. Please log out and back in to apply group changes or run 'newgrp docker'."
        # We can't automatically apply the group change for the *current* shell session.
        # Exiting is often the safest way to ensure the user relogs or runs newgrp.
        exit 1
    else
        echo "❌ Failed to install Docker."
        exit 1
    fi
else
    echo "Docker is already installed."
fi

# Check Docker Compose plugin
if ! docker compose version &>/dev/null; then
    echo "Docker Compose plugin not found. Installing..."
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    mkdir -p "$DOCKER_CONFIG/cli-plugins" || { echo "❌ Failed to create Docker config directory."; exit 1; }
    # Fetch the latest release version dynamically (optional, but better than hardcoding)
    LATEST_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    # If fetching latest version is complex or adds failure points, hardcoding is okay too for stability
    # LATEST_COMPOSE_VERSION="v2.27.1" # Using your current hardcoded version for stability
    # Add error handling for curl and the file move/chmod
    if curl -SL "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-linux-$(uname -m)" \
      -o "$DOCKER_CONFIG/cli-plugins/docker-compose"; then
      chmod +x "$DOCKER_CONFIG/cli-plugins/docker-compose" || { echo "❌ Failed to set execute permissions on docker-compose plugin."; exit 1; }
      echo "Docker Compose plugin installed successfully."
    else
      echo "❌ Failed to download Docker Compose plugin."
      exit 1
    fi
fi

# Detect TimeZone
TZ=$(timedatectl show --value -p Timezone)

# Detect UID and GID
PUID=$(id -u)
PGID=$(id -g)

echo "Using UID=$PUID and GID=$PGID"

# --- Media Base Folder Setup ---
DEFAULT_SOURCE_PATH="/mnt/sdc1/Downloads" # Define the default here

# Prompt user for the source path with default
echo "--- Media Directory Setup ---"
read -p "Enter path to your actual media location (to bind to $BASE_MEDIA) [default: $DEFAULT_SOURCE_PATH]: " SOURCE_PATH_INPUT
SOURCE_PATH="${SOURCE_PATH_INPUT:-$DEFAULT_SOURCE_PATH}" # Use default if input is empty

echo "Using source path: $SOURCE_PATH"

# 1. Ensure the source path exists
if [ ! -d "$SOURCE_PATH" ]; then
    echo "Source path \"$SOURCE_PATH\" does not exist. Creating..."
    # Need sudo to create directories in /mnt/sdc1 if not owned by user
    sudo mkdir -p "$SOURCE_PATH" || { echo "❌ Error creating source path: $SOURCE_PATH"; exit 1; }
fi

# 2. Ensure the mount point ($BASE_MEDIA) exists
if [ ! -d "$BASE_MEDIA" ]; then
    echo "Mount point $BASE_MEDIA does not exist. Creating..."
    # Need sudo to create directories in /mnt if not owned by user
    sudo mkdir -p "$BASE_MEDIA" || { echo "❌ Error creating mount point: $BASE_MEDIA"; exit 1; }
fi

# 3. Check if the mount point is already mounted. If not, perform the bind mount.
if mountpoint -q "$BASE_MEDIA"; then
    echo "$BASE_MEDIA is already mounted."
    # Optional: Check if it's the *correct* source path mounted
    # MOUNT_SOURCE=$(findmnt -n -o SOURCE --target "$BASE_MEDIA")
    # if [ "$MOUNT_SOURCE" != "$SOURCE_PATH" ]; then
    #     echo "⚠️ Warning: $BASE_MEDIA is mounted, but not from the specified source $SOURCE_PATH. You may need to unmount it manually if this is incorrect."
    # fi
else
    echo "Mounting $SOURCE_PATH to $BASE_MEDIA..."
    # Need sudo for mounting
    if sudo mount --bind "$SOURCE_PATH" "$BASE_MEDIA"; then
        echo "Mounted $SOURCE_PATH to $BASE_MEDIA"
    else
        echo "❌ Error mounting $SOURCE_PATH to $BASE_MEDIA. Check permissions and if the source path exists."
        exit 1
    fi
fi

# 4. Create the required subdirectories WITHIN the SOURCE_PATH (which is now mounted to $BASE_MEDIA)
# These directories will appear directly under /mnt/media from the container's perspective.
echo "Ensuring required media subdirectories exist under $SOURCE_PATH (mounted at $BASE_MEDIA)..."
# Using sudo here because even though we are writing to SOURCE_PATH via the mount point,
# the mount point itself might require root permissions to operate on its contents depending on configuration.
# It's safer to use sudo for mkdir and chown operations touching directories under the mount point.
if sudo mkdir -p "$BASE_MEDIA/downloads" "$BASE_MEDIA/movies" "$BASE_MEDIA/tv"; then
    echo "Created directories: $BASE_MEDIA/{downloads,movies,tv}"
    # Also create subdirectories for downloads if needed by the compose file structure
    # If qbittorrent writes directly to /mnt/media/downloads, this is sufficient.
    # If qbittorrent expects /mnt/media/downloads/movies and /mnt/media/downloads/tv *within* downloads,
    # ensure your compose file or qbittorrent config reflects this, and uncomment/add mkdir calls here:
    # sudo mkdir -p "$BASE_MEDIA/downloads/movies" "$BASE_MEDIA/downloads/tv" || { echo "❌ Error creating download subdirectories under $BASE_MEDIA/downloads"; exit 1; }
else
    echo "❌ Error creating necessary media subdirectories under $BASE_MEDIA."
    echo "Please check permissions for the user $USER (or root if using sudo) on $SOURCE_PATH."
    exit 1
fi

# 5. Create config folders (these are separate from media)
echo "Creating necessary config directories..."
# Updated for WireGuard instead of Gluetun
mkdir -p "$CONFIG_ROOT"/{wireguard,qbittorrent,sonarr,radarr,jackett,filebrowser} || { echo "❌ Error creating config directories"; exit 1; }

# 6. Set ownership on the base media directory ($BASE_MEDIA) for the PUID/PGID
# This applies the ownership to the files/folders within the mounted SOURCE_PATH
echo "Setting ownership on $BASE_MEDIA to $PUID:$PGID..."
if ! sudo chown -R "$PUID:$PGID" "$BASE_MEDIA"; then
    echo "❌ Error setting ownership on $BASE_MEDIA. Make sure you have appropriate permissions (e.g., running with sudo)."
    # Decide if this is a fatal error or just a warning
    exit 1 # Uncomment this line if ownership setting is critical
fi

# --- End Media Base Folder Setup ---


# --- WireGuard VPN Configuration ---
echo
echo "--- WireGuard VPN Configuration ---"
echo -e "${RED}Important Note:${NC} This script uses a WireGuard Docker image (linuxserver/wireguard)"
echo "that expects a WireGuard configuration file (e.g., wg0.conf or no-osl.conf etc) in its mapped config volume."
echo
echo -e "You need to obtain this WireGuard configuration file from your VPN provider."
echo -e "This typically involves:"
echo -e "  1. Logging into your VPN provider's website."
echo -e "  2. Navigating to a 'Manual Setup', 'Router Setup', or 'WireGuard Configuration' section."
echo -e "  3. You might need to generate a new key pair (public/private key). Your provider will guide you if this is necessary."
echo -e "     If you generate a key pair, you'll usually provide your PUBLIC key to the VPN service, and they will incorporate it into the .conf file they provide you."
echo -e "  4. Download the generated .conf file to your system."
echo -e "  5. You ${RED}*must*${NC} add the following to the [Interface] section of the no-osl.conf file:"
echo -e "         PostUp = DBG_IP=\$(ip -4 route show default dev eth0 | awk '/default/ {print \$3}'); ip -4 route add 192.168.1.0/24 via \$DBG_IP dev eth0"
echo -e "     ${YELLOW}Change 192.168.1.0/24 to match your subnet.${NC}"
echo

echo "--- Wireguard Config File Setup ---"
# Prompt user for the source path with default
DEFAULT_CONFIG_FILE_PATH="/home/boss/no-osl.conf"   # Define the default here
while true; do
    read -p "Enter the FULL path to your WireGuard configuration file (default: $DEFAULT_CONFIG_FILE_PATH): " CONFIG_FILE_PATH_INPUT
    WIREGUARD_CONFIG_FILE_PATH="${CONFIG_FILE_PATH_INPUT:-$DEFAULT_CONFIG_FILE_PATH}"   # Use default if input is empty
    if [ -f "$WIREGUARD_CONFIG_FILE_PATH" ]; then
        echo "✅ WireGuard configuration file found at: $WIREGUARD_CONFIG_FILE_PATH"
        break
    else
        echo "❌ File not found at '$WIREGUARD_CONFIG_FILE_PATH'. Please enter a valid path."
    fi
done

# Ensure the WireGuard config directory exists within CONFIG_ROOT
WIREGUARD_HOST_CONFIG_DIR="$CONFIG_ROOT/wireguard"
mkdir -p "$WIREGUARD_HOST_CONFIG_DIR" || { echo "❌ Error creating WireGuard config directory: $WIREGUARD_HOST_CONFIG_DIR"; exit 1; }

# Copy the user's WireGuard config file to the designated location, naming it wg0.conf
# Most WireGuard Docker images look for wg0.conf by default.
TARGET_WG_CONF_FILE="$WIREGUARD_HOST_CONFIG_DIR/wg0.conf"
cp "$WIREGUARD_CONFIG_FILE_PATH" "$TARGET_WG_CONF_FILE" || { echo "❌ Error copying WireGuard config file to $TARGET_WG_CONF_FILE"; exit 1; }
echo "✅ WireGuard configuration file copied to $TARGET_WG_CONF_FILE"
echo "This file will be used by the WireGuard container."

# --- End WireGuard VPN Configuration ---


# Create .env file
echo "Creating .env file..."

# Start building the .env content
env_content=""
env_content+="TZ=$TZ"$'\n'
env_content+="PUID=$PUID"$'\n'
env_content+="PGID=$PGID"$'\n'
env_content+="CONFIG_ROOT=${CONFIG_ROOT}"$'\n'
# Add any other environment variables needed by your specific WireGuard image or other services, if any.
# For a simple WireGuard client setup using a .conf file, often no extra VPN env vars are needed here.

echo "$env_content" > "$ENV_FILE"

echo ".env file created with the following content:"
cat "$ENV_FILE"
echo # Add a newline

# Launch the stack
echo "Launching the Docker stack with docker compose..."
# Use --env-file explicitly and -f to specify the compose file
if docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" up -d; then  # <--- MODIFIED LINE
    echo "✅ Docker stack launched successfully!"
else
    echo "❌ Failed to launch Docker stack."
    # Keep the .env file for debugging if launch fails
    exit 1
fi

# Clean up the .env file if launch was successful (optional, useful for security)
# Commented out for now, often useful to keep for restarts/debugging
# rm -f "$ENV_FILE"

echo "✅ Media stack setup complete!"
# Attempt to get qbittorrent password from logs

echo
echo "To alter one container while leaving the rest up, first bring just that container down"
echo "and then make changes in docker-compose.yaml, and then create a new container:"
echo "    docker compose down radarr"
echo "    docker compose up -d radarr"
echo
echo "Attempting to find qbittorrent WebUI password in logs:"
sleep 5
echo "The WebUI username is 'admin'"
echo "The WebUI password is $(docker logs qbittorrent 2>/dev/null | grep temporary | awk '{print $16}')" # This awk field might need adjustment
echo
echo "I change this back to 'adminadmin' so that my PowerShell magnet script works from remote systems."
# docker logs qbittorrent | grep temporary 2>/dev/null | awk '{print $10}'
