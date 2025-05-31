#!/bin/bash
# Author: Roy Wiseman 2025-05

# qBittorrent Docker automated deployment using linuxserver/qbittorrent
# This script sets up the container with specified host paths, ports, and user IDs.
# https://fleet.linuxserver.io/image?name=qbittorrent
# ───────────────────────────────────────────────────────────────

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

# ───[ Styling ]─────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE_BOLD='\033[1;34m' # Used for default paths
BOLD='\033[1m'
NC='\033[0m' # No Color
UNDERLINE='\033[4m'

# ───[ Configuration ]───────────────────────────────────────────
# --- Container Settings ---
CONTAINER_NAME="qbittorrent"
QB_IMAGE="lscr.io/linuxserver/qbittorrent:latest"

# --- Default Host directory for qBittorrent's configuration files ---
# (Contains database, settings, logs etc - KEEP THIS SAFE!)
QB_HOST_CONFIG_DIR="$HOME/.config/qbittorrent-docker"

# --- Default Host directory for qBittorrent downloads ---
# (This is where your downloaded files will appear on the host)
DEFAULT_HOST_DOWNLOADS_DIR="/mnt/sdc1/Downloads"
QB_CONTAINER_DOWNLOADS_DIR="/downloads" # Internal path inside the container (fixed by linuxserver image)
QB_CONTAINER_CONFIG_DIR="/config" # Internal path inside the container (fixed by linuxserver image)

# --- Default Port Settings ---
# You can change these if 8080 or 6881 are already in use on your host
WEBUI_HOST_PORT=8080
TORRENTING_HOST_PORT=6881

# --- Timezone Setting ---
# Specify a timezone to use. See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ="Etc/UTC" # Example: "America/New_York", "Europe/London"

# ───[ Helper Functions ]────────────────────────────────────────
# Function to check if a directory exists
check_dir() {
  if [ ! -d "$1" ]; then
    echo -e "${RED}✖ Error: Directory not found: $1${NC}"
    echo -e "${YELLOW}Please ensure the directory exists and the script has permission to access it.${NC}"
    exit 1
  fi
}

# Function to get PUID and PGID of the current user
get_user_ids() {
  local user_id=$(id -u)
  local group_id=$(id -g)
  echo "$user_id:$group_id"
}

# ───[ Preparations ]────────────────────────────────────────────
echo -e "${BOLD}qBittorrent Docker Setup${NC}"
echo "--------------------------------------------------"

# --- Detect Host IP (Best guess for UI link) ---
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP. You might need to find it manually (e.g., using 'ip a').${NC}"
    # Fallback if hostname -I fails
    HOST_IP="localhost"
fi
echo -e "${CYAN}ℹ️ Detected likely local IP: ${HOST_IP}${NC} (qBittorrent UI will be accessible via this IP on port ${WEBUI_HOST_PORT})"

# --- Get User and Group IDs ---
USER_IDS=$(get_user_ids)
PUID=${USER_IDS%:*}
PGID=${USER_IDS#*:}
echo -e "${CYAN}ℹ️ Using PUID=${PUID} and PGID=${PGID} for container user mapping.${NC}"
echo -e "${YELLOW}Ensure the host directories (${QB_HOST_CONFIG_DIR} and the chosen downloads directory) are owned by this user/group for correct permissions.${NC}"

# --- Prompt for Downloads Directory ---
echo -e "\n${BOLD}Please enter the host folder to be used by qBittorrent for downloads.${NC}"
echo -e "This is the folder on your Linux machine where completed (and incomplete) downloads will be stored."
echo -e "You can use 'tab' to autocomplete paths."
echo -e "Leave this empty to use the default path: ${BLUE_BOLD}${DEFAULT_HOST_DOWNLOADS_DIR}${NC}"
read -e -p "Enter host downloads path [${DEFAULT_HOST_DOWNLOADS_DIR}]: " user_input   # -e enables tab completion, -p sets the prompt string.
if [ -z "$user_input" ]; then   # -z checks if string length is zero
  HOST_DOWNLOADS_DIR="$DEFAULT_HOST_DOWNLOADS_DIR"
  echo -e "Using default host downloads path: ${BLUE_BOLD}${HOST_DOWNLOADS_DIR}${NC}"
else
  HOST_DOWNLOADS_DIR="$user_input"
  echo "Using entered host downloads path: ${BLUE_BOLD}${HOST_DOWNLOADS_DIR}${NC}"
fi

# --- Create Configuration Directory on Host ---
echo -e "\n${CYAN}Ensuring qBittorrent config directory exists on host: ${QB_HOST_CONFIG_DIR}${NC}"
mkdir -p "$QB_HOST_CONFIG_DIR"
if [ $? -ne 0 ]; then
  echo -e "${RED}✖ Error: Failed to create config directory: $QB_HOST_CONFIG_DIR${NC}"
  exit 1
fi

# --- Check if specified Host Downloads Directory exists ---
echo -e "${CYAN}Checking if specified host downloads directory exists: ${HOST_DOWNLOADS_DIR}${NC}"
check_dir "$HOST_DOWNLOADS_DIR"
echo -e "${GREEN}✅ Host directories checked.${NC}"
echo

# ───[ Docker Operations ]───────────────────────────────────────

# Check if container exists
if docker ps -a --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
    echo -e "${GREEN}✅ Container '$CONTAINER_NAME' already exists. Skipping creation.${NC}"
    echo -e "${CYAN}To stop and remove existing container named '$CONTAINER_NAME' to allow a new one to be created:${NC}"
    echo -e "${CYAN}docker stop \"$CONTAINER_NAME\" > /dev/null 2>&1${NC}"
    echo -e "${CYAN}docker rm \"$CONTAINER_NAME\" > /dev/null 2>&1${NC}"
else
    echo -e "${CYAN}Creating and starting qBittorrent container '$CONTAINER_NAME'...${NC}"
    echo -e "${CYAN}Pulling latest qBittorrent image ('${QB_IMAGE}')...${NC}"
    docker pull ${QB_IMAGE}
    if [ $? -ne 0 ]; then
      echo -e "${RED}✖ Error: Failed to pull Docker image. Check Docker installation and internet connection.${NC}"
      exit 1
    fi

    # --- Build the docker run command ---
    DOCKER_CMD="docker run -d"
    DOCKER_CMD+=" --name \"$CONTAINER_NAME\""
    DOCKER_CMD+=" --restart unless-stopped"

    # --- Environment Variables ---
    DOCKER_CMD+=" -e PUID=${PUID}"
    DOCKER_CMD+=" -e PGID=${PGID}"
    DOCKER_CMD+=" -e TZ=${TZ}"
    DOCKER_CMD+=" -e WEBUI_PORT=${WEBUI_HOST_PORT}" # Pass host port to container for CSRF
    DOCKER_CMD+=" -e TORRENTING_PORT=${TORRENTING_HOST_PORT}" # Pass host port to container

    # --- Port Mappings ---
    DOCKER_CMD+=" -p ${WEBUI_HOST_PORT}:${WEBUI_HOST_PORT}" # WebUI (Host:Container)
    DOCKER_CMD+=" -p ${TORRENTING_HOST_PORT}:${TORRENTING_HOST_PORT}" # Torrenting TCP (Host:Container)
    DOCKER_CMD+=" -p ${TORRENTING_HOST_PORT}:${TORRENTING_HOST_PORT}/udp" # Torrenting UDP (Host:Container)

    # --- Volume Mappings ---
    # Config volume (MANDATORY)
    DOCKER_CMD+=" -v \"$QB_HOST_CONFIG_DIR\":\"$QB_CONTAINER_CONFIG_DIR\""
    # Downloads volume (MANDATORY for downloads)
    DOCKER_CMD+=" -v \"$HOST_DOWNLOADS_DIR\":\"$QB_CONTAINER_DOWNLOADS_DIR\""

    # --- Add the Image Name ---
    DOCKER_CMD+=" ${QB_IMAGE}"

    # --- Execute the command ---
    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD" # Use eval to correctly handle quotes in paths

    # --- Check for errors ---
    if [ $? -ne 0 ]; then
      echo -e "${RED}✖ Failed to start qBittorrent container. Check Docker logs:${NC}"
      echo -e "  ${CYAN}docker logs $CONTAINER_NAME${NC}"
      exit 1
    fi
fi

# ───[ Post-Setup Information ]──────────────────────────────────
echo
echo -e "${GREEN}✅ qBittorrent container '$CONTAINER_NAME' started successfully!${NC}"
echo
echo -e "${BOLD}📍 Key Information:${NC}"
echo -e "- Container Name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- qBittorrent Image: ${CYAN}${QB_IMAGE}${NC}"
echo -e "- Host IP detected: ${CYAN}${HOST_IP}${NC}"
echo -e "- PUID/PGID used: ${CYAN}${PUID}/${PGID}${NC}"
echo -e "- Timezone set to: ${CYAN}${TZ}${NC}"

echo
echo -e "${BOLD}💾 Mounted Host Directories:${NC}"
echo -e "  Config: ${CYAN}$QB_HOST_CONFIG_DIR${NC} -> Container: ${YELLOW}$QB_CONTAINER_CONFIG_DIR${NC}"
echo -e "  Downloads: ${CYAN}$HOST_DOWNLOADS_DIR${NC} -> Container: ${YELLOW}$QB_CONTAINER_DOWNLOADS_DIR${NC}"

echo
echo -e "${BOLD}🌐 Access qBittorrent Web UI:${NC} ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}${NC}"
echo -e "${BOLD}Note:${NC} If you are accessing this from the host machine itself, you can also use ${YELLOW}http://localhost:${WEBUI_HOST_PORT}${NC} or ${YELLOW}http://127.0.0.1:${WEBUI_HOST_PORT}${NC}."

echo
echo -e "${BOLD}🔒 Initial Password & Login:${NC}"
echo -e "The ${UNDERLINE}temporary password${NC} for the 'admin' user is printed to the container logs on the ${BOLD}first startup${NC}."
echo -e "1. Go to the Web UI: ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}${NC}"
echo -e "2. The username is '${BOLD}admin${NC}'."
echo -e "3. To get the password, open a new terminal and run: ${CYAN}docker logs ${CONTAINER_NAME} | grep 'password'${NC}"
echo -e "4. Use the printed password to log in."
echo -e "${RED}${BOLD}5. IMPORTANT: Immediately go to 'Tools -> Options -> Web UI' and change the username and password!${NC}"
echo -e "   If you do not change the password, a new one will be generated every time the container restarts."

echo
echo -e "${BOLD}⬇️ Configuring Download Locations in Web UI:${NC}"
echo -e "When setting the default download location or specific locations for torrents in the qBittorrent Web UI (Tools -> Options -> Downloads), you MUST use the ${UNDERLINE}container path${NC}."
echo -e "Set your default download location in the Web UI to: ${YELLOW}$QB_CONTAINER_DOWNLOADS_DIR${NC}"
echo -e "This path corresponds to the host directory ${CYAN}$HOST_DOWNLOADS_DIR${NC} you specified."

echo
echo -e "${BOLD}📡 Networking Notes:${NC}"
echo -e "- qBittorrent Web UI port mapped: ${CYAN}${WEBUI_HOST_PORT} (Host) -> ${WEBUI_HOST_PORT} (Container)${NC}"
echo -e "- Torrenting ports mapped: ${CYAN}${TORRENTING_HOST_PORT}/tcp, ${TORRENTING_HOST_PORT}/udp (Host) -> ${TORRENTING_HOST_PORT}/tcp, ${TORRENTING_HOST_PORT}/udp (Container)${NC}"
echo -e "- If accessing from outside your LAN, ensure your ${BOLD}host machine's firewall${NC} allows these ports (especially ${TORRENTING_HOST_PORT} TCP/UDP)."
echo -e "- Port forwarding on your router would need to point to ${BOLD}your host machine's IP${NC} (${HOST_IP}) for these ports (${WEBUI_HOST_PORT} and ${TORRENTING_HOST_PORT})."

echo
echo -e "${BOLD}🛠 Common Docker Commands:${NC}"
echo -e "  ${CYAN}docker stop|start|restart $CONTAINER_NAME${NC} - Stop|Start|Restart the container"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}     - View live qBittorrent logs (useful for initial password)"
echo -e "  ${CYAN}docker ps -a${NC}                 - Check if container is running"
echo -e "  ${CYAN}docker rm -f $CONTAINER_NAME${NC}       - Force remove container (config ${BOLD}preserved${NC} in ${QB_HOST_CONFIG_DIR})"
echo -e "  ${CYAN}docker exec -it $CONTAINER_NAME bash${NC} - Enter container shell (if bash is available, often uses 'sh')"

echo
echo -e "${BOLD}🔮 Adding NEW Download Folders Later:${NC}"
echo -e "If you want qBittorrent to download to a host folder that wasn't mounted initially:"
echo -e "1. ${RED}STOP${NC} the container: ${CYAN}docker stop $CONTAINER_NAME${NC}"
echo -e "2. ${RED}REMOVE${NC} the container: ${CYAN}docker rm $CONTAINER_NAME${NC} (Your config in ${QB_HOST_CONFIG_DIR} is safe!)"
echo -e "3. Edit ${BOLD}this script${NC}:"
echo -e "   - Define a new variable for the host path (e.g., ${CYAN}NEW_FOLDER_HOST_DIR=\"/path/to/new/folder\"${NC})."
echo -e "   - Add a new ${CYAN}check_dir \"\$NEW_FOLDER_HOST_DIR\"${NC} line in the Preparations section."
echo -e "   - Add a new mount line to the ${CYAN}DOCKER_CMD${NC} string in the Docker Operations section:"
echo -e "     ${CYAN}+= \" -v \\\"\$NEW_FOLDER_HOST_DIR\\\":/new-folder-name-in-container\\\"\"${NC}"
echo -e "     (Choose a meaningful name after the colon, e.g., '/my-movies')."
echo -e "   - Update the '${BOLD}Mounted Host Directories'${NC} output section to list the new mount."
echo -e "4. ${GREEN}Re-run this script${NC}. It will recreate the container with the new mount."
echo -e "5. In the qBittorrent Web UI, you can now use this new container path (e.g., ${YELLOW}/new-folder-name-in-container${NC}) for specific downloads or move finished ones there."

echo
echo -e "${GREEN}🚀 Setup complete. Access the Web UI at ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}${NC}"
echo -e "${GREEN}   Remember to get the initial password from the container log:${NC}   ${CYAN}docker logs ${CONTAINER_NAME} | grep 'password'${NC}"
echo -e "${GREEN}   Note! This password can expire or lock out. To regenerate a new one:   ${CYAN}docker restart ${CONTAINER_NAME}${NC}"
echo
