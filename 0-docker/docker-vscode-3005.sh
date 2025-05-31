#!/bin/bash
# Author: Roy Wiseman 2025-05

# VS Code Server Docker automated deployment using linuxserver/openvscode-server
# This script sets up the container with specified host paths, ports, and user IDs.
# Based on instructions from:
# https://fleet.linuxserver.io/image?name=openvscode-server
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
CONTAINER_NAME="vscode-server"
VSCODE_IMAGE="lscr.io/linuxserver/openvscode-server:latest"

# --- Default Host directory for VS Code Server configuration ---
# Configuration directory (settings, extensions, etc.)
# This will be mapped to /config inside the container.
DEFAULT_HOST_CONFIG_DIR="$HOME/.config/vscode-server-docker"
VSCODE_CONTAINER_CONFIG_DIR="/config" # Internal config path inside the container (fixed by linuxserver image)

# --- Default Host directory for User's Project Files / Code ---
# This is the main directory on your host where your code/projects are.
# This will be mapped to the default user's home directory (/home/coder) inside the container.
DEFAULT_HOST_PROJECTS_DIR="$HOME" # Default to the current user's home directory on the host
VSCODE_CONTAINER_PROJECTS_DIR="/home/coder" # Internal path for user home/projects inside the container

# --- Port Settings ---
# Note: The container listens on 3000 internally.
# The user requested the external/host port to be 3005.
# Format is HOST_PORT=CONTAINER_PORT
WEBUI_HOST_PORT=3005      # Host port for accessing the VS Code Web UI (User requested 3005)
WEBUI_CONTAINER_PORT=3000 # Internal container port for WebUI (Fixed by image)

# --- Environment Settings ---
# Specify a timezone to use. See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ="Etc/UTC" # Example: "America/New_York", "Europe/London"

# Optional security token for accessing the Web UI (ie. supersecrettoken).
# If set, access is http://<your-ip>:<WEBUI_HOST_PORT>/?tkn=supersecrettoken
# Leave empty ("") to disable token requirement.
CONNECTION_TOKEN=""

# Optional path to a file inside the container that contains the security token.
# Overrides CONNECTION_TOKEN if set.
# CONNECTION_SECRET="/path/to/file/inside/container" # Uncomment and set if using a secret file
CONNECTION_SECRET="" # Leave empty ("") to not use a secret file

# If set, user will have sudo access in the VS Code terminal with the specified password.
SUDO_PASSWORD="" # Example: "your_sudo_password"

# Optionally set sudo password via hash (takes priority over SUDO_PASSWORD var).
# Format is $type$salt$hashed.
SUDO_PASSWORD_HASH="" # Example: "$type$salt$hashed"

# ───[ Helper Functions ]────────────────────────────────────────
# Function to check if a directory exists or create it
ensure_dir() {
    if [ ! -d "$1" ]; then
        echo -e "${CYAN}Ensuring directory exists on host: $1${NC}"
        mkdir -p "$1"
        if [ $? -ne 0 ]; then
            echo -e "${RED}✖ Error: Failed to create directory: $1${NC}"
            echo -e "${YELLOW}Please check permissions or create it manually.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✅ Directory created or already exists.${NC}"
    else
        echo -e "${GREEN}✅ Directory already exists on host: $1${NC}"
    fi
}

# Function to get PUID and PGID of the current user
get_user_ids() {
    local user_id=$(id -u)
    local group_id=$(id -g)
    echo "$user_id:$group_id"
}

# ───[ Preparations ]────────────────────────────────────────────
echo -e "${BOLD}VS Code Server Docker Setup${NC}"
echo "--------------------------------------------------"

# --- Detect Host IP (Best guess for UI link) ---
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP. You might need to find it manually (e.g., using 'ip a').${NC}"
    # Fallback if hostname -I fails
    HOST_IP="localhost"
fi
echo -e "${CYAN}ℹ️ Detected likely local IP: ${HOST_IP}${NC}"

# --- Get User and Group IDs ---
USER_IDS=$(get_user_ids)
PUID=${USER_IDS%:*}
PGID=${USER_IDS#*:}
echo -e "${CYAN}ℹ️ Using PUID=${PUID} and PGID=${PGID} for container user mapping.${NC}"
echo -e "${YELLOW}Ensure the host directories below are owned by this user/group for correct permissions.${NC}"

# Check if the container already exists
if docker ps -a --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
    echo -e "${GREEN}✅ Container '$CONTAINER_NAME' already exists. Skipping creation.${NC}"
    echo -e "${CYAN}To stop and remove existing container named '$CONTAINER_NAME' to allow a new one to be created:${NC}"
    echo -e "${CYAN}docker stop \"$CONTAINER_NAME\" > /dev/null 2>&1${NC}"
    echo -e "${CYAN}docker rm \"$CONTAINER_NAME\" > /dev/null 2>&1${NC}"
    # When container exists, we can't reliably get the original prompted paths,
    # but config path is fixed default and projects path will be the default $HOME
    # for reporting purposes. The running container already has its mounts.
    HOST_CONFIG_DIR=$DEFAULT_HOST_CONFIG_DIR
    HOST_PROJECTS_DIR=$DEFAULT_HOST_PROJECTS_DIR
else
    # --- Prompt for Host Configuration Directory ---
    echo -e "\n${BOLD}Please enter the host folder for VS Code Server configuration files.${NC}"
    echo -e "This is where container settings, extensions, and user data will be stored persistently."
    echo -e "Leave this empty to use the default path: ${BLUE_BOLD}${DEFAULT_HOST_CONFIG_DIR}${NC}"
    read -e -p "Enter host config path [${DEFAULT_HOST_CONFIG_DIR}]: " user_config_input
    HOST_CONFIG_DIR="${user_config_input:-$DEFAULT_HOST_CONFIG_DIR}" # Use default if input is empty

    # --- Prompt for Host Projects/Code Directory ---
    echo -e "\n${BOLD}Please enter the host folder where your code projects are located.${NC}"
    echo -e "This directory will be accessible inside the container at ${YELLOW}${VSCODE_CONTAINER_PROJECTS_DIR}${NC}."
    echo -e "You can use 'tab' to autocomplete paths."
    echo -e "Leave this empty to use the default path (your home directory): ${BLUE_BOLD}${DEFAULT_HOST_PROJECTS_DIR}${NC}"
    read -e -p "Enter host projects path [${DEFAULT_HOST_PROJECTS_DIR}]: " user_projects_input
    HOST_PROJECTS_DIR="${user_projects_input:-$DEFAULT_HOST_PROJECTS_DIR}" # Use default if input is empty

    # --- Ensure Host Directories Exist ---
    echo -e "\n${BOLD}Checking/Creating host directories...${NC}"
    # Ensure config directory exists
    ensure_dir "$HOST_CONFIG_DIR"
    # Validate projects directory exists (do not create, as user provides it)
    echo -e "${CYAN}Validating projects directory exists on host: $HOST_PROJECTS_DIR${NC}"
    if [ ! -d "$HOST_PROJECTS_DIR" ]; then
        echo -e "${RED}${BOLD}✖ Error: The path ${BLUE_BOLD}$HOST_PROJECTS_DIR${RED}${BOLD} does not appear to be an existing directory.${NC}"
        echo "Please rerun the script with a valid path to continue."
        exit 1
    fi
    echo -e "${GREEN}✅ Projects directory exists.${NC}"
    echo -e "${GREEN}✅ Host directories checked/ensured.${NC}"
    echo

    # ───[ Docker Operations ]───────────────────────────────────────
    echo -e "${CYAN}Creating and starting VS Code Server container '$CONTAINER_NAME'...${NC}"
    echo -e "${CYAN}Pulling latest VS Code Server image ('${VSCODE_IMAGE}')...${NC}"
    docker pull ${VSCODE_IMAGE}
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

    if [ -n "$CONNECTION_TOKEN" ]; then
        DOCKER_CMD+=" -e CONNECTION_TOKEN=\"${CONNECTION_TOKEN}\""
    fi

    if [ -n "$CONNECTION_SECRET" ]; then
        # Using FILE__ prefix for secrets from files is a common pattern, but the docs show CONNECTION_SECRET directly.
        # We'll use CONNECTION_SECRET directly as per docs, assuming the file exists inside the container.
        # If the user intends to mount a secret file from the host, they'd need to add another volume mount
        # and adjust CONNECTION_SECRET to point to that mounted file path inside the container.
        # For simplicity based *only* on the provided docs' syntax, we add it directly if set.
        echo -e "${YELLOW}Note: CONNECTION_SECRET requires the token file to exist INSIDE the container at the specified path.${NC}"
        DOCKER_CMD+=" -e CONNECTION_SECRET=\"${CONNECTION_SECRET}\""
    fi

    if [ -n "$SUDO_PASSWORD" ]; then
        DOCKER_CMD+=" -e SUDO_PASSWORD=\"${SUDO_PASSWORD}\""
    fi

     if [ -n "$SUDO_PASSWORD_HASH" ]; then
        DOCKER_CMD+=" -e SUDO_PASSWORD_HASH=\"${SUDO_PASSWORD_HASH}\""
    fi

    # --- Port Mappings ---
    # Mapping HOST_PORT:CONTAINER_PORT (3005:3000 as requested)
    DOCKER_CMD+=" -p ${WEBUI_HOST_PORT}:${WEBUI_CONTAINER_PORT}"

    # --- Volume Mappings ---
    # Config volume (MANDATORY for persistence)
    DOCKER_CMD+=" -v \"$HOST_CONFIG_DIR\":\"$VSCODE_CONTAINER_CONFIG_DIR\""
    # Projects/Code volume (Mapped to /home/coder)
    DOCKER_CMD+=" -v \"$HOST_PROJECTS_DIR\":\"$VSCODE_CONTAINER_PROJECTS_DIR\""


    # --- Add the Image Name ---
    DOCKER_CMD+=" ${VSCODE_IMAGE}"

    # --- Execute the command ---
    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD" # Use eval to correctly handle quotes in paths

    # --- Check for errors ---
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to start VS Code Server container. Check Docker logs:${NC}"
        echo -e "  ${CYAN}docker logs $CONTAINER_NAME${NC}"
        exit 1
    fi
fi

# ───[ Post-Setup Information ]──────────────────────────────────
echo
echo -e "${GREEN}✅ VS Code Server container '$CONTAINER_NAME' started successfully!${NC}"
echo
echo -e "${BOLD}📍 Key Information:${NC}"
echo -e "- Container Name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- VS Code Server Image: ${CYAN}${VSCODE_IMAGE}${NC}"
echo -e "- Host IP detected: ${CYAN}${HOST_IP}${NC}"
echo -e "- PUID/PGID used: ${CYAN}${PUID}/${PGID}${NC}"
echo -e "- Timezone set to: ${CYAN}${TZ}${NC}"
if [ -n "$CONNECTION_TOKEN" ]; then
    echo -e "- Connection Token SET: ${CYAN}$CONNECTION_TOKEN${NC} (Access via ?tkn=...)"
elif [ -n "$CONNECTION_SECRET" ]; then
    echo -e "- Connection Secret File SET: ${CYAN}$CONNECTION_SECRET${NC} (Access via ?tkn=...)"
else
    echo -e "- Connection Token/Secret NOT set (Access directly)."
fi
if [ -n "$SUDO_PASSWORD" ] || [ -n "$SUDO_PASSWORD_HASH" ]; then
     echo -e "- Sudo access enabled in terminal.${NC}"
else
    echo -e "- Sudo access NOT enabled in terminal.${NC}"
fi

echo
echo -e "${BOLD}📡 Networking Notes:${NC}"
echo -e "- Web UI port mapped: ${CYAN}${WEBUI_HOST_PORT} (Host) -> ${WEBUI_CONTAINER_PORT} (Container)${NC}"
echo -e "- If accessing from outside your LAN, ensure your ${BOLD}host machine's firewall${NC} allows port ${WEBUI_HOST_PORT}."
echo -e "- Port forwarding on your router would need to point to ${BOLD}your host machine's IP${NC} (${HOST_IP}) for port ${WEBUI_HOST_PORT}."
echo -e "${BOLD}Note:${NC} If accessing from the host machine, you can also use ${YELLOW}http://localhost:${WEBUI_HOST_PORT}${NC} or ${YELLOW}http://127.0.0.1:${WEBUI_HOST_PORT}${NC}."

echo
echo -e "${BOLD}🛠 Common Docker Commands:${NC}"
echo -e "  ${CYAN}docker stop|start|restart $CONTAINER_NAME${NC} - Stop|Start|Restart the container"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}     - View live container logs"
echo -e "  ${CYAN}docker ps -a${NC}                 - Check if container is running"
echo -e "  ${CYAN}docker rm -f $CONTAINER_NAME${NC}       - Force remove container (config/data ${BOLD}preserved${NC} in host paths)"
echo -e "  ${CYAN}docker exec -it $CONTAINER_NAME bash${NC} - Enter container shell (if bash is available, often uses 'sh')"

echo
echo -e "${BOLD}📂 Mounted Host Directories:${NC}"
echo -e "  Host Config: ${CYAN}$HOST_CONFIG_DIR${NC}       -> Container: ${YELLOW}$VSCODE_CONTAINER_CONFIG_DIR${NC}"
echo -e "  Host Projects/Code: ${CYAN}$HOST_PROJECTS_DIR${NC} -> Container: ${YELLOW}$VSCODE_CONTAINER_PROJECTS_DIR${NC}"


echo
echo -e "🚀${BOLD} Accessing VS Code Server:${NC}"
if [ -n "$CONNECTION_TOKEN" ]; then
    echo -e "🌐 Go to: ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}/?tkn=${CONNECTION_TOKEN}${NC}"
elif [ -n "$CONNECTION_SECRET" ]; then
    echo -e "🌐 Go to: ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}/${NC} (Token from file ${CONNECTION_SECRET} required)"
else
    echo -e "🌐 Go to: ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}/${NC}"
fi
echo -e "Once connected, you can open folders and files within the ${YELLOW}${VSCODE_CONTAINER_PROJECTS_DIR}${NC} directory inside VS Code, which corresponds to the host path ${CYAN}${HOST_PROJECTS_DIR}${NC}."


echo
echo -e "${GREEN}🚀 VS Code Server setup script finished.${NC}"
echo -e "${GREEN}   Access the VS Code Server Web UI at  ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}/${NC}${NC}"
