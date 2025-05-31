#!/bin/bash
# Author: Roy Wiseman 2025-05

# Bastillion SSH Access Management Setup in Docker (for Linux)
# ────────────────────────────────────────────────────────────
# Bastillion provides web-based SSH console access and key management.

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
    echo "See instructions: https://docs.docker.com/engine/install/"
    exit 1
fi

# ──[ Styling ]────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE_BOLD='\033[1;34m' # Used for default paths
BOLD='\033[1m'
NC='\033[0m' # No Color
UNDERLINE='\033[4m'

# ──[ Detect Host IP for Access Instructions ]─────────────────────────────
# This IP is for accessing the Bastillion Web UI from your browser
HOST_IP_DETECTED=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP_DETECTED" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP for access instructions. You might need to find it manually (e.g., using 'ip a').${NC}"
    DISPLAY_HOST_IP="localhost"
else
    DISPLAY_HOST_IP="$HOST_IP_DETECTED"
fi
echo -e "${CYAN}Detected local IP for Bastillion Web UI access instructions: ${DISPLAY_HOST_IP}${NC}"


# ──[ Configuration ]──────────────────────────────
# --- Container Settings ---
CONTAINER_NAME="bastillion"
APP_IMAGE="bastillion/bastillion:latest" # Official Bastillion image

# --- Default Host directory for Bastillion Data (database, config, keys) ---
DEFAULT_HOST_DATA_DIR="$HOME/.config/bastillion-docker"
# Bastillion container expects its data in /bastillion_data
APP_CONTAINER_DATA_DIR="/bastillion_data"
# The bastillion/bastillion container runs as user 'bastillion' (UID 1000, GID 1000)
# So, the host directory should be owned by 1000:1000
BASTILLION_CONTAINER_UID=1000
BASTILLION_CONTAINER_GID=1000


# --- Port Settings ---
DEFAULT_APP_HOST_PORT=8443      # Default host port to map to Bastillion's HTTPS port
APP_CONTAINER_PORT=8443         # Bastillion listens on port 8443 (HTTPS) inside the container

# --- Environment Variables ---
# Attempt to detect system timezone for fresh install default
DEFAULT_TZ_FALLBACK="Etc/UTC" # A safe fallback
SYSTEM_TZ=$(timedatectl | grep "Time zone" | awk '{print $3}' | cut -d' ' -f1)
DEFAULT_INSTALL_TZ="$DEFAULT_TZ_FALLBACK"

if [ -n "$SYSTEM_TZ" ]; then
    DEFAULT_INSTALL_TZ="$SYSTEM_TZ"
    echo -e "${CYAN}Detected system timezone for new installs: ${SYSTEM_TZ}${NC}"
else
    echo -e "${YELLOW}Could not automatically detect system timezone for new installs. Defaulting to ${DEFAULT_INSTALL_TZ}.${NC}"
    echo -e "${YELLOW}You can find a list here: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones${NC}"
fi

# --- Flags ---
SHOULD_INSTALL=true # Assume we will install by default

# ──[ Helper Functions ]─────────────────────────
ensure_dir() {
    local dir_path="$1"
    local target_uid="$2" # UID for ownership
    local target_gid="$3" # GID for ownership
    if [ ! -d "$dir_path" ]; then
        echo -e "${CYAN}Ensuring directory exists on host: $dir_path${NC}"
        mkdir -p "$dir_path"
        if [ $? -ne 0 ]; then
            echo -e "${RED}✖ Error: Failed to create directory: $dir_path${NC}"
            echo -e "${YELLOW}Please check permissions or create it manually.${NC}"
            exit 1
        fi
        echo -e "${CYAN}Setting ownership of $dir_path to ${target_uid}:${target_gid}...${NC}"
        sudo chown -R "${target_uid}:${target_gid}" "$dir_path"
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}⚠️ Warning: Failed to set ownership of $dir_path. Manual permission adjustment might be needed.${NC}"
            echo -e "${YELLOW}   The directory should be writable by UID ${target_uid} and GID ${target_gid}.${NC}"
        fi
        echo -e "${GREEN}✅ Directory created.${NC}"
    else
        echo -e "${GREEN}✅ Directory already exists on host: $dir_path${NC}"
        CURRENT_OWNER_UID=$(stat -c '%u' "$dir_path")
        CURRENT_OWNER_GID=$(stat -c '%g' "$dir_path")
        # Check if top-level directory ownership is correct
        if [ "$CURRENT_OWNER_UID" != "$target_uid" ] || [ "$CURRENT_OWNER_GID" != "$target_gid" ]; then
            echo -e "${CYAN}Updating ownership of $dir_path to ${target_uid}:${target_gid}...${NC}"
            sudo chown -R "${target_uid}:${target_gid}" "$dir_path"
            if [ $? -ne 0 ]; then
                echo -e "${YELLOW}⚠️ Warning: Failed to update ownership of $dir_path. Manual permission adjustment might be needed.${NC}"
                echo -e "${YELLOW}   The directory should be writable by UID ${target_uid} and GID ${target_gid}.${NC}"
            fi
        fi
    fi
}

# ──[ Check for Existing Container ]───────────────
EXISTS=$(docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME")
if [ ! -z "$EXISTS" ]; then
    echo -e "${YELLOW}An existing Bastillion container named '$CONTAINER_NAME' was found.${NC}"
    read -p "Do you want to remove it to allow the script to (re)install it? (y/N): " remove_existing
    if [[ "$remove_existing" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Stopping and removing existing container '$CONTAINER_NAME'...${NC}"
        docker stop "$CONTAINER_NAME" >/dev/null 2>&1
        docker rm "$CONTAINER_NAME" >/dev/null 2>&1
        echo -e "${GREEN}✅ Existing container removed. Proceeding with fresh installation.${NC}"
        SHOULD_INSTALL=true
    else
        echo -e "${CYAN}Skipping installation. Will display information about the existing container.${NC}"
        SHOULD_INSTALL=false
    fi
fi

# Variables for Post-Setup Info section
INFO_HOST_DATA_DIR=""
INFO_SELECTED_HOST_PORT=""
INFO_SELECTED_TZ=""

if $SHOULD_INSTALL ; then
    echo
    echo -e "${BOLD}Bastillion container '$CONTAINER_NAME' will be installed.${NC}"

    echo -e "\n${BOLD}Please enter the host folder for Bastillion persistent data (database, configs, keys).${NC}"
    read -e -p "Enter Bastillion data path [${DEFAULT_HOST_DATA_DIR}]: " user_data_dir_input
    HOST_DATA_DIR_INPUT="${user_data_dir_input:-$DEFAULT_HOST_DATA_DIR}"

    # ensure_dir will use BASTILLION_CONTAINER_UID and BASTILLION_CONTAINER_GID for new directory
    ensure_dir "$HOST_DATA_DIR_INPUT" "$BASTILLION_CONTAINER_UID" "$BASTILLION_CONTAINER_GID"
    echo -e "${GREEN}✅ Host data directory for Bastillion: $HOST_DATA_DIR_INPUT${NC}"
    echo

    echo -e "\n${BOLD}Please enter the host port for Bastillion Web UI (HTTPS).${NC}"
    read -e -p "Enter Host Port for Bastillion [${DEFAULT_APP_HOST_PORT}]: " user_host_port_input
    SELECTED_HOST_PORT_INPUT="${user_host_port_input:-$DEFAULT_APP_HOST_PORT}"
    echo -e "${GREEN}✅ Bastillion will be accessible on host port: $SELECTED_HOST_PORT_INPUT (HTTPS)${NC}"
    echo

    echo -e "\n${BOLD}Please enter the Timezone for Bastillion (e.g., Europe/Oslo, America/New_York).${NC}"
    echo -e "${YELLOW}(This sets the TZ environment variable; its usage depends on the Bastillion image.)${NC}"
    read -e -p "Enter Timezone [${DEFAULT_INSTALL_TZ}]: " user_tz_input
    SELECTED_TZ_INPUT="${user_tz_input:-$DEFAULT_INSTALL_TZ}"
    echo -e "${GREEN}✅ Timezone set to: $SELECTED_TZ_INPUT${NC}"
    echo

    echo -e "${CYAN}Pulling Bastillion image ('${APP_IMAGE}')...${NC}"
    docker pull ${APP_IMAGE}
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to pull Bastillion image. Check Docker and internet.${NC}"
        exit 1
    fi

    echo -e "${CYAN}Creating and starting Bastillion container...${NC}"
    DOCKER_CMD="docker run -d"
    DOCKER_CMD+=" -p ${SELECTED_HOST_PORT_INPUT}:${APP_CONTAINER_PORT}"
    DOCKER_CMD+=" --name $CONTAINER_NAME"
    DOCKER_CMD+=" --restart unless-stopped"
    # Mount the persistent data directory
    DOCKER_CMD+=" -v \"$HOST_DATA_DIR_INPUT\":\"$APP_CONTAINER_DATA_DIR\""
    # Set Timezone environment variable (its effect depends on the image internals)
    DOCKER_CMD+=" -e TZ=\"${SELECTED_TZ_INPUT}\""

    # Add host.docker.internal mapping for Linux hosts.
    # This allows Bastillion to connect to 'host.docker.internal' if you configure it as a system.
    if [[ "$(uname -s)" == "Linux" ]]; then
      DOCKER_CMD+=" --add-host=host.docker.internal:host-gateway"
    fi
    # The bastillion/bastillion image does not seem to use PUID/PGID env vars.
    # It runs internally as user 'bastillion' (1000:1000).
    # The ensure_dir function handles host directory permissions.

    DOCKER_CMD+=" ${APP_IMAGE}"

    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD"

    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to start Bastillion container. Check Docker logs (${CYAN}docker logs $CONTAINER_NAME${RED}).${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Bastillion container '$CONTAINER_NAME' started successfully!${NC}"

    # Set INFO_ variables from the installation
    INFO_HOST_DATA_DIR="$HOST_DATA_DIR_INPUT"
    INFO_SELECTED_HOST_PORT="$SELECTED_HOST_PORT_INPUT"
    INFO_SELECTED_TZ="$SELECTED_TZ_INPUT"
else
    # Container exists, and we are not reinstalling. Gather info.
    echo -e "\n${CYAN}Attempting to retrieve information for existing container '$CONTAINER_NAME'...${NC}"

    INFO_HOST_DATA_DIR=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "'"$APP_CONTAINER_DATA_DIR"'"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
    if [ -z "$INFO_HOST_DATA_DIR" ]; then INFO_HOST_DATA_DIR="<unknown or not mapped to $APP_CONTAINER_DATA_DIR>"; fi

    INFO_SELECTED_HOST_PORT=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if eq $p "'"$APP_CONTAINER_PORT/tcp"'"}}{{(index $conf 0).HostPort}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
    if [ -z "$INFO_SELECTED_HOST_PORT" ]; then INFO_SELECTED_HOST_PORT="<unknown or not exposed>"; fi

    ALL_ENVS=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
    INFO_SELECTED_TZ=$(echo "$ALL_ENVS" | grep -E '^TZ=' | cut -d'=' -f2)
    if [ -z "$INFO_SELECTED_TZ" ]; then INFO_SELECTED_TZ="<not set or unknown>"; fi
fi

# ──[ Post-Setup Info ]─────────────
echo
echo -e "${BOLD}📍 Bastillion Container Info:${NC}"
echo -e "- Container name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Image: ${CYAN}$APP_IMAGE${NC}"
echo -e "- Host directory for data: ${CYAN}$INFO_HOST_DATA_DIR${NC}"
echo -e "  (Mapped to ${YELLOW}$APP_CONTAINER_DATA_DIR${NC} inside container)"
echo -e "- Bastillion Web UI (HTTPS): Port ${CYAN}$INFO_SELECTED_HOST_PORT${NC}"
echo -e "- Timezone set in container env: ${CYAN}${INFO_SELECTED_TZ}${NC}"
echo
echo -e "${RED}${BOLD}⚠️ IMPORTANT FIRST STEPS:${NC}"
echo -e "1. Bastillion uses a ${UNDERLINE}self-signed certificate${NC} by default. Your browser will show a security warning."
echo -e "   You will need to accept the risk to proceed."
echo -e "2. Default credentials: user: ${YELLOW}admin${NC} / password: ${YELLOW}changeme${NC}"
echo -e "3. ${RED}YOU MUST CHANGE THE DEFAULT ADMIN PASSWORD IMMEDIATELY AFTER FIRST LOGIN!${NC}"
echo -e "   Go to 'Profile' (top right) -> 'Change Password'."
echo
echo -e "${BOLD}🌐 Access Bastillion Web UI:${NC}"
echo -e "  Open your browser: ${YELLOW}https://${DISPLAY_HOST_IP}:${INFO_SELECTED_HOST_PORT}${NC}"
echo -e "  (Allow a minute or two for Bastillion to initialize fully on first run if newly installed.)"
echo
echo -e "${BOLD}🔧 Configuring SSH Access to Your Docker Host (or other servers) via Bastillion:${NC}"
echo -e "1. Log in to Bastillion using the admin credentials (and change password!)."
echo -e "2. Go to ${CYAN}Systems${NC} from the side menu."
echo -e "3. Click ${CYAN}Add System${NC}."
echo -e "4. Fill in the details:"
echo -e "   - ${BOLD}System Name:${NC} e.g., 'Docker Host' or a descriptive name."
echo -e "   - ${BOLD}Host:${NC} To connect to your Docker host from the container, use ${YELLOW}host.docker.internal${NC}"
echo -e "     (Requires Docker 18.03+ on Linux with --add-host, or Docker Desktop. Otherwise, use your host's LAN IP accessible by the container)."
echo -e "   - ${BOLD}Port:${NC} Usually ${YELLOW}22${NC} for SSH."
echo -e "   - ${BOLD}Login User:${NC} The username on your Docker host you want to SSH as (e.g., $(whoami))."
echo -e "   - ${BOLD}Authentication Type:${NC} Choose 'Password' (Bastillion will prompt) or 'Key'."
echo -e "     If 'Key', you'll typically manage keys within Bastillion profiles later."
echo -e "5. Click ${CYAN}Save${NC}."
echo -e "6. To connect, go to ${CYAN}My Connections${NC}, find your newly added system, and click ${CYAN}Connect${NC}."
echo
echo -e "If you need to ${UNDERLINE}reset Bastillion's data and configuration${NC} or start completely fresh:"
echo -e "1. ${RED}Stop the container:${NC} ${CYAN}docker stop $CONTAINER_NAME${NC}"
echo -e "2. ${RED}Remove the container:${NC} ${CYAN}docker rm $CONTAINER_NAME${NC}"
echo -e "3. ${RED}DELETE the host data directory:${NC} ${CYAN}rm -rf \"$INFO_HOST_DATA_DIR\"${NC}"
echo -e "   ${YELLOW}Warning: This will delete all your Bastillion users, systems, keys, and settings.${NC}"
echo -e "4. ${GREEN}Re-run this script.${NC}"
echo
echo -e "${BOLD}⚙️ Common Docker Commands:${NC}"
echo -e "  ${CYAN}docker start|stop|restart $CONTAINER_NAME${NC}"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}"
echo -e "  ${CYAN}docker rm $CONTAINER_NAME${NC} (data in ${INFO_HOST_DATA_DIR} is preserved unless you manually delete it)"
echo

exit 0
