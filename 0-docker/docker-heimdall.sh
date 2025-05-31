#!/bin/bash
# Author: Roy Wiseman 2025-05

# Heimdall Application Dashboard Setup in Docker (for Linux)
# ────────────────────────────────────────────────────────────

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

# ──[ Styling ]────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE_BOLD='\033[1;34m' # Used for default paths
BOLD='\033[1m'
NC='\033[0m' # No Color
UNDERLINE='\033[4m'

# ──[ Detect Host IP ]─────────────────────────────
HOST_IP_DETECTED=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP_DETECTED" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP. You might need to find it manually (e.g., using 'ip a').${NC}"
    DISPLAY_HOST_IP="localhost"
else
    DISPLAY_HOST_IP="$HOST_IP_DETECTED"
fi
echo -e "${CYAN}Detected local IP for access instructions: ${DISPLAY_HOST_IP}${NC}"


# ──[ Configuration ]──────────────────────────────
# --- Container Settings ---
CONTAINER_NAME="heimdall"
APP_IMAGE="lscr.io/linuxserver/heimdall:latest" # linuxserver.io image

# --- Default Host directory for Heimdall Configuration ---
DEFAULT_HOST_CONFIG_DIR="$HOME/.config/heimdall-docker"
APP_CONTAINER_CONFIG_DIR="/config" # Internal config path for linuxserver images

# --- Port Settings ---
DEFAULT_APP_HOST_PORT=8080    # Default host port to map to Heimdall's HTTP port
APP_CONTAINER_PORT=80         # Heimdall (linuxserver image) listens on port 80 (HTTP)

# --- Environment Variables for linuxserver/heimdall ---
# These will be used if installing fresh, and as fallback/comparison for existing
SCRIPT_PUID=$(id -u) # Current user's ID
SCRIPT_PGID=$(id -g) # Current user's group ID

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
    local target_puid="$2"
    local target_pgid="$3"
    if [ ! -d "$dir_path" ]; then
        echo -e "${CYAN}Ensuring directory exists on host: $dir_path${NC}"
        mkdir -p "$dir_path"
        if [ $? -ne 0 ]; then
            echo -e "${RED}✖ Error: Failed to create directory: $dir_path${NC}"
            echo -e "${YELLOW}Please check permissions or create it manually.${NC}"
            exit 1
        fi
        echo -e "${CYAN}Setting ownership of $dir_path to ${target_puid}:${target_pgid}...${NC}"
        sudo chown -R "${target_puid}:${target_pgid}" "$dir_path"
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}⚠️ Warning: Failed to set ownership of $dir_path. Manual permission adjustment might be needed.${NC}"
        fi
        echo -e "${GREEN}✅ Directory created or already exists.${NC}"
    else
        echo -e "${GREEN}✅ Directory already exists on host: $dir_path${NC}"
        CURRENT_OWNER=$(stat -c '%u:%g' "$dir_path")
        if [ "$CURRENT_OWNER" != "${target_puid}:${target_pgid}" ]; then
            echo -e "${CYAN}Updating ownership of $dir_path to ${target_puid}:${target_pgid}...${NC}"
            sudo chown -R "${target_puid}:${target_pgid}" "$dir_path"
            if [ $? -ne 0 ]; then
                echo -e "${YELLOW}⚠️ Warning: Failed to update ownership of $dir_path. Manual permission adjustment might be needed.${NC}"
            fi
        fi
    fi
}

# ──[ Check for Existing Container ]───────────────
EXISTS=$(docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME")
if [ ! -z "$EXISTS" ]; then
    echo -e "${YELLOW}An existing Heimdall container named '$CONTAINER_NAME' was found.${NC}"
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
INFO_HOST_CONFIG_DIR=""
INFO_SELECTED_HOST_PORT=""
INFO_SELECTED_TZ=""
INFO_PUID=""
INFO_PGID=""

if $SHOULD_INSTALL ; then
    echo
    echo -e "${BOLD}Heimdall container '$CONTAINER_NAME' will be installed.${NC}"

    echo -e "\n${BOLD}Please enter the host folder for Heimdall configuration files.${NC}"
    read -e -p "Enter Heimdall config path [${DEFAULT_HOST_CONFIG_DIR}]: " user_config_input
    HOST_CONFIG_DIR_INPUT="${user_config_input:-$DEFAULT_HOST_CONFIG_DIR}"
    
    # ensure_dir will use SCRIPT_PUID and SCRIPT_PGID for new directory
    ensure_dir "$HOST_CONFIG_DIR_INPUT" "$SCRIPT_PUID" "$SCRIPT_PGID"
    echo -e "${GREEN}✅ Host config directory for Heimdall: $HOST_CONFIG_DIR_INPUT${NC}"
    echo

    echo -e "\n${BOLD}Please enter the host port for Heimdall Web UI (HTTP).${NC}"
    read -e -p "Enter Host Port for Heimdall [${DEFAULT_APP_HOST_PORT}]: " user_host_port_input
    SELECTED_HOST_PORT_INPUT="${user_host_port_input:-$DEFAULT_APP_HOST_PORT}"
    echo -e "${GREEN}✅ Heimdall will be accessible on host port: $SELECTED_HOST_PORT_INPUT${NC}"
    echo

    echo -e "\n${BOLD}Please enter the Timezone for Heimdall (e.g., Europe/Oslo, America/New_York).${NC}"
    read -e -p "Enter Timezone [${DEFAULT_INSTALL_TZ}]: " user_tz_input
    SELECTED_TZ_INPUT="${user_tz_input:-$DEFAULT_INSTALL_TZ}"
    echo -e "${GREEN}✅ Timezone set to: $SELECTED_TZ_INPUT${NC}"
    echo

    echo -e "${CYAN}Pulling Heimdall image ('${APP_IMAGE}')...${NC}"
    docker pull ${APP_IMAGE}
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to pull Heimdall image. Check Docker and internet.${NC}"
        exit 1
    fi

    echo -e "${CYAN}Creating and starting Heimdall container...${NC}"
    DOCKER_CMD="docker run -d"
    DOCKER_CMD+=" -p ${SELECTED_HOST_PORT_INPUT}:${APP_CONTAINER_PORT}"
    DOCKER_CMD+=" --name $CONTAINER_NAME"
    DOCKER_CMD+=" --restart unless-stopped"
    DOCKER_CMD+=" -e PUID=${SCRIPT_PUID}"
    DOCKER_CMD+=" -e PGID=${SCRIPT_PGID}"
    DOCKER_CMD+=" -e TZ=\"${SELECTED_TZ_INPUT}\""
    DOCKER_CMD+=" -v \"$HOST_CONFIG_DIR_INPUT\":\"$APP_CONTAINER_CONFIG_DIR\""
    DOCKER_CMD+=" ${APP_IMAGE}"

    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD"

    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to start Heimdall container. Check Docker logs (${CYAN}docker logs $CONTAINER_NAME${RED}).${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Heimdall container '$CONTAINER_NAME' started successfully!${NC}"

    # Set INFO_ variables from the installation
    INFO_HOST_CONFIG_DIR="$HOST_CONFIG_DIR_INPUT"
    INFO_SELECTED_HOST_PORT="$SELECTED_HOST_PORT_INPUT"
    INFO_SELECTED_TZ="$SELECTED_TZ_INPUT"
    INFO_PUID="$SCRIPT_PUID"
    INFO_PGID="$SCRIPT_PGID"
else
    # Container exists, and we are not reinstalling. Gather info.
    echo -e "\n${CYAN}Attempting to retrieve information for existing container '$CONTAINER_NAME'...${NC}"

    INFO_HOST_CONFIG_DIR=$(docker inspect --format='{{range .Mounts}}{{if eq .Destination "'"$APP_CONTAINER_CONFIG_DIR"'"}}{{.Source}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
    if [ -z "$INFO_HOST_CONFIG_DIR" ]; then INFO_HOST_CONFIG_DIR="<unknown or not mapped to $APP_CONTAINER_CONFIG_DIR>"; fi

    # More reliable port parsing
    INFO_SELECTED_HOST_PORT=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if eq $p "'"$APP_CONTAINER_PORT/tcp"'"}}{{(index $conf 0).HostPort}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
    if [ -z "$INFO_SELECTED_HOST_PORT" ]; then INFO_SELECTED_HOST_PORT="<unknown or not exposed>"; fi

    ALL_ENVS=$(docker inspect --format='{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
    INFO_PUID=$(echo "$ALL_ENVS" | grep -E '^PUID=' | cut -d'=' -f2)
    if [ -z "$INFO_PUID" ]; then INFO_PUID="<not set or unknown>"; fi
    INFO_PGID=$(echo "$ALL_ENVS" | grep -E '^PGID=' | cut -d'=' -f2)
    if [ -z "$INFO_PGID" ]; then INFO_PGID="<not set or unknown>"; fi
    INFO_SELECTED_TZ=$(echo "$ALL_ENVS" | grep -E '^TZ=' | cut -d'=' -f2)
    if [ -z "$INFO_SELECTED_TZ" ]; then INFO_SELECTED_TZ="<not set or unknown>"; fi
fi

# ──[ Post-Setup Info ]─────────────
echo
echo -e "${BOLD}📍 Heimdall Container Info:${NC}"
echo -e "- Container name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Image: ${CYAN}$APP_IMAGE${NC}"
echo -e "- Host directory for config: ${CYAN}$INFO_HOST_CONFIG_DIR${NC}"
echo -e "  (Mapped to ${YELLOW}$APP_CONTAINER_CONFIG_DIR${NC} inside container)"
echo -e "- Heimdall Web UI (HTTP): Port ${CYAN}$INFO_SELECTED_HOST_PORT${NC}"
echo -e "- Running with PUID=${CYAN}${INFO_PUID}${NC}, PGID=${CYAN}${INFO_PGID}${NC}, TZ=${CYAN}${INFO_SELECTED_TZ}${NC}"
echo
echo -e "${BOLD}🔧 Configuration:${NC}"
echo -e "Heimdall configuration (adding applications, etc.) is done via its web interface."
echo
echo -e "If you need to ${UNDERLINE}reset Heimdall's configuration${NC} or start completely fresh:"
echo -e "1. ${RED}Stop the container:${NC} ${CYAN}docker stop $CONTAINER_NAME${NC}"
echo -e "2. ${RED}Remove the container:${NC} ${CYAN}docker rm $CONTAINER_NAME${NC}"
echo -e "3. ${RED}DELETE the host config directory:${NC} ${CYAN}rm -rf \"$INFO_HOST_CONFIG_DIR\"${NC}"
echo -e "   ${YELLOW}Warning: This will delete all your Heimdall settings and application links.${NC}"
echo -e "4. ${GREEN}Re-run this script.${NC}"
echo
echo -e "${BOLD}🌐 Access Heimdall Web UI:${NC}"
echo -e "  Open your browser: ${YELLOW}http://${DISPLAY_HOST_IP}:${INFO_SELECTED_HOST_PORT}${NC}"
echo -e "  (Allow a minute for Heimdall to initialize fully on first run if newly installed.)"
echo
echo -e "${BOLD}⚙️ Common Docker Commands:${NC}"
echo -e "  ${CYAN}docker start|stop|restart $CONTAINER_NAME${NC}"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}"
echo -e "  ${CYAN}docker rm $CONTAINER_NAME${NC} (config in ${INFO_HOST_CONFIG_DIR} is preserved unless you manually delete it)"
echo
echo -e "${BOLD}🚀 Next Steps After Accessing Heimdall:${NC}"
echo -e "  1. Access the web UI."
echo -e "  2. Start adding your application links using the '+' button or by going to 'Application List' -> 'Add'."
echo -e "  3. Explore 'Settings' for any further customization."
echo

exit 0
