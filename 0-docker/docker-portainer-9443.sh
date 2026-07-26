#!/usr/bin/env bash
# Author: Roy Wiseman 2025-02

# Portainer CE Setup in Docker (for Linux) automated deployment.
# ────────────────────────────────────────────────

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
# Note: This gets the *first* IP. Adjust if you have multiple network interfaces
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP. You might need to find it manually (e.g., using 'ip a').${NC}"
    HOST_IP="localhost" # Fallback
fi
echo -e "${CYAN}Detected local IP: ${HOST_IP}${NC}"


# ──[ Configuration ]──────────────────────────────
# --- Container Settings ---
CONTAINER_NAME="portainer"
PORTAINER_IMAGE="portainer/portainer-ce:latest" # Use latest tag for CE

# --- Default Host directory for Portainer Data ---
# This directory on your host will store all Portainer configuration,
# database, user settings, etc. Mapped to /data inside the container.
# Deleting this directory is required for a full reset, including admin password.
DEFAULT_HOST_DATA_DIR="$HOME/.config/portainer-docker"
PORTAINER_CONTAINER_DATA_DIR="/data" # Internal data path inside the container (fixed by image)

# --- Port Settings ---
# Portainer listens on 8000 for agent/HTTP and 9443 for HTTPS UI.
# We'll map both to the same ports on the host by default.
HTTP_HOST_PORT=8000
HTTP_CONTAINER_PORT=8000

HTTPS_HOST_PORT=9443
HTTPS_CONTAINER_PORT=9443

# ──[ Helper Functions ]─────────────────────────
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


# ──[ Check for Existing Container ]───────────────
EXISTS=$(docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME")

# ──[ Installation Logic ]─────────────────────────
if [ -z "$EXISTS" ]; then
    echo
    echo -e "${BOLD}Portainer container '$CONTAINER_NAME' not found. Proceeding with installation.${NC}"

    # ──[ Prompt for Host Data Directory ]─────────────
    echo -e "\n${BOLD}Please enter the host folder for Portainer data persistence.${NC}"
    echo -e "This directory will store Portainer's settings, users, etc."
    echo -e "Deleting this folder is the way to reset Portainer (including the admin password)."
    echo -e "You can use 'tab' to autocomplete paths."
    echo -e "Leave this empty to use the default path: ${BLUE_BOLD}${DEFAULT_HOST_DATA_DIR}${NC}"
    read -e -p "Enter Portainer data path [${DEFAULT_HOST_DATA_DIR}]: " user_data_input
    HOST_DATA_DIR="${user_data_input:-$DEFAULT_HOST_DATA_DIR}" # Use default if input is empty

    # ──[ Ensure Host Data Directory Exists ]──────────
    ensure_dir "$HOST_DATA_DIR"
    echo -e "${GREEN}✅ Host data directory checked/ensured: $HOST_DATA_DIR${NC}"
    echo

    # ──[ Pull Portainer Image ]─────────────────────
    echo -e "${CYAN}Pulling latest Portainer CE image ('${PORTAINER_IMAGE}')...${NC}"
    docker pull ${PORTAINER_IMAGE}

    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to pull Portainer image. Check your internet connection and Docker setup.${NC}"
        exit 1
    fi

    # ──[ Run Portainer Container ]──────────────────
    echo -e "${CYAN}Creating and starting Portainer container...${NC}"

    DOCKER_CMD="docker run -d"
    DOCKER_CMD+=" -p ${HTTP_HOST_PORT}:${HTTP_CONTAINER_PORT}"
    DOCKER_CMD+=" -p ${HTTPS_HOST_PORT}:${HTTPS_CONTAINER_PORT}"
    DOCKER_CMD+=" --name $CONTAINER_NAME"
    DOCKER_CMD+=" --restart unless-stopped"
    DOCKER_CMD+=" -v /var/run/docker.sock:/var/run/docker.sock" # Mount Docker socket
    DOCKER_CMD+=" -v \"$HOST_DATA_DIR\":\"$PORTAINER_CONTAINER_DATA_DIR\"" # Mount host data directory

    DOCKER_CMD+=" ${PORTAINER_IMAGE}"

    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD" # Use eval to correctly handle quotes in paths

    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to start Portainer container. Check Docker logs (${CYAN}docker logs $CONTAINER_NAME${RED}).${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Portainer container '$CONTAINER_NAME' started successfully!${NC}"

else
    # If container exists, use the default path for reporting,
    # as we don't know what path was used if it wasn't the default.
    HOST_DATA_DIR=$DEFAULT_HOST_DATA_DIR
    echo -e "${YELLOW}Portainer container '$CONTAINER_NAME' already exists.${NC}"
    echo -e "${YELLOW}Skipping installation steps.${NC}"
fi

# ──[ Post-Setup Info (Always Shown) ]─────────────
echo
echo -e "${BOLD}📍 Portainer Container Info:${NC}"
echo -e "- Container name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Host directory for data: ${CYAN}$HOST_DATA_DIR${NC}"
echo -e "  (Mapped to ${YELLOW}$PORTAINER_CONTAINER_DATA_DIR${NC} inside container)"
echo -e "- Portainer UI (HTTPS): ${CYAN}${HTTPS_HOST_PORT}${NC}"
echo -e "- Portainer Agent/HTTP: ${CYAN}${HTTP_HOST_PORT}${NC}"
echo -e "- Accesses host Docker socket: ${CYAN}/var/run/docker.sock${NC}"
echo
echo -e "${BOLD}🔑 Initial Setup / Resetting Password:${NC}"
echo -e "The ${UNDERLINE}first time${NC} you access Portainer, you will be prompted to create an administrator user and password."
echo -e "Make sure to choose a strong password."
echo
echo -e "If you want to reset all configuration:"
echo -e "1. ${RED}Stop the container:${NC} ${CYAN}docker stop $CONTAINER_NAME${NC}"
echo -e "2. ${RED}Remove the container:${NC} ${CYAN}docker rm $CONTAINER_NAME${NC}"
echo -e "3. ${RED}DELETE the host data directory:${NC} ${CYAN}rm -rf \"$HOST_DATA_DIR\"${NC}"
echo -e "4. ${GREEN}Re-run this script.${NC} It will prompt you for the data directory again (use the same path to recreate it) and start a fresh Portainer instance, allowing you to set up a new admin user."
echo
echo -e "${BOLD}🌐 Access Portainer Web UI:${NC}"
echo -e "  Open your web browser and go to: ${YELLOW}https://${HOST_IP}:${HTTPS_HOST_PORT}${NC}"
echo -e "  (Note: You might see a security warning about the self-signed certificate - this is normal for the initial setup.)"
echo
echo -e "${BOLD}🔧 Common Docker Commands:${NC}"
echo -e "  ${CYAN}docker start|stop|restart $CONTAINER_NAME${NC} - Start|Stop|Restart the Portainer container"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}      - View Portainer logs for troubleshooting"
echo -e "  ${CYAN}docker rm -f $CONTAINER_NAME${NC}   - Remove/delete the container (Data in ${HOST_DATA_DIR} is preserved)"
echo
echo -e "${BOLD}🚀 Next Steps After Login:${NC}"
echo -e "  1. Choose the environment you want to manage (e.g., your local Docker environment)."
echo -e "  2. Explore the dashboard to see your running containers, images, volumes, etc."
echo -e "  3. You can now manage your Docker environment through the intuitive web UI."
echo -e "  4. ${RED}Important:${NC} Remember that Portainer required a 12 char password (if you can't login, what 12 char password would you have used?)"
echo

exit 0
