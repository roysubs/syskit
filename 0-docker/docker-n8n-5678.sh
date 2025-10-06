#!/bin/bash
# Author: Roy Wiseman (template), Gemini (adaptation) 2025-10
#
# n8n Docker automated deployment script.
# n8n is a self-hostable, open-source workflow automation tool.
# https://docs.n8n.io/hosting/installation/docker/
# ────────────────────────────────────────────────────────────────

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker not found. Please install Docker to continue.${NC}"
    echo "You can usually install it with: curl -fsSL https://get.docker.com | sh"
    exit 1
fi

if ! docker info &>/dev/null; then
    echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
    exit 1
fi

# ───[ Styling ]───────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE_BOLD='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ───[ Configuration ]─────────────────────────────────────────────
# --- Host directory for n8n's persistent data ---
# (contains database, credentials, settings - KEEP THIS SAFE!)
N8N_HOST_CONFIG_DIR="$HOME/.n8n-docker"

# --- Optional host directory to make available to workflows ---
# This is useful if you want workflows to read/write files on the host system.
# For example, saving downloaded receipt PDFs.
DEFAULT_HOST_DATA_DIR="$HOME/n8n-data"

echo -e "${BOLD}Please enter the host folder for n8n's persistent data.${NC}"
echo -e "This is where workflows, credentials, and the database will be stored."
read -e -p "Enter n8n config path [${N8N_HOST_CONFIG_DIR}]: " user_config_input
if [ -n "$user_config_input" ]; then
    N8N_HOST_CONFIG_DIR="$user_config_input"
fi
echo -e "Using config path: ${BLUE_BOLD}${N8N_HOST_CONFIG_DIR}${NC}"
echo

echo -e "${BOLD}Please enter an optional host folder to share with n8n workflows.${NC}"
echo -e "This allows workflows to save or read files. It will be available at '/data' inside the container."
read -e -p "Enter shared data path (or leave empty to skip) [${DEFAULT_HOST_DATA_DIR}]: " user_data_input
if [ -z "$user_data_input" ]; then
    HOST_DATA_DIR=""
    echo -e "${YELLOW}Skipping shared data volume mount.${NC}"
else
    # If user entered something, use it. If they just hit enter, use default.
    HOST_DATA_DIR="${user_data_input:-$DEFAULT_HOST_DATA_DIR}"
    echo -e "Using shared data path: ${BLUE_BOLD}${HOST_DATA_DIR}${NC}"
fi

# --- Container Settings ---
CONTAINER_NAME="n8n"
N8N_IMAGE="n8nio/n8n:latest"
# Set your timezone to ensure schedules run at the correct time.
# Full list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TIMEZONE="Europe/Amsterdam"   # Europe/London

# ───[ Helper Functions ]─────────────────────────────────────────
check_and_create_dir() {
    if [ ! -d "$1" ]; then
        echo -e "${CYAN}Directory not found. Creating: $1${NC}"
        mkdir -p "$1"
        if [ $? -ne 0 ]; then
            echo -e "${RED}✖ Error: Failed to create directory: $1${NC}"
            exit 1
        fi
    fi
}

# ───[ Preparations ]─────────────────────────────────────────────
echo
echo -e "${BOLD}n8n Docker Setup${NC}"
echo "--------------------------------------------------"

# --- Detect Host IP (Best guess for UI link) ---
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP. Using 'localhost'.${NC}"
    HOST_IP="localhost"
fi
echo -e "${CYAN}ℹ️  Detected likely local IP: ${HOST_IP}${NC} (n8n UI will be on port 5678)"

# --- Create Configuration & Data Directories ---
echo -e "${CYAN}Ensuring n8n config directory exists: ${N8N_HOST_CONFIG_DIR}${NC}"
check_and_create_dir "$N8N_HOST_CONFIG_DIR"

if [ -n "$HOST_DATA_DIR" ]; then
    echo -e "${CYAN}Ensuring shared data directory exists: ${HOST_DATA_DIR}${NC}"
    check_and_create_dir "$HOST_DATA_DIR"
fi
echo -e "${GREEN}✅ Host directories checked.${NC}"
echo

# ───[ Docker Operations ]────────────────────────────────────────
# Check if container exists
if docker ps -a --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
    echo -e "${GREEN}✅ Container '$CONTAINER_NAME' already exists. Skipping creation.${NC}"
    echo -e "${CYAN}If you need to recreate it, first run:${NC}"
    echo -e "   docker stop \"$CONTAINER_NAME\" && docker rm \"$CONTAINER_NAME\""
else
    echo -e "${CYAN}Pulling latest n8n image ('${N8N_IMAGE}')...${NC}"
    docker pull ${N8N_IMAGE}
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Error: Failed to pull Docker image. Check Docker installation and internet connection.${NC}"
        exit 1
    fi

    echo -e "${CYAN}Creating and starting n8n container '$CONTAINER_NAME'...${NC}"
    
    # --- Build the docker run command ---
    DOCKER_CMD="docker run -d --name \"$CONTAINER_NAME\""
    DOCKER_CMD+=" --restart unless-stopped"
    DOCKER_CMD+=" -p 5678:5678"
    
    # --- Add Environment Variables ---
    DOCKER_CMD+=" -e GENERIC_TIMEZONE=\"$TIMEZONE\""
    DOCKER_CMD+=" -e N8N_SECURE_COOKIE=false"
    
    # --- Mount Essential n8n Configuration Volume ---
    DOCKER_CMD+=" -v \"$N8N_HOST_CONFIG_DIR:/root/.n8n\""
    
    # --- Mount Optional Shared Data Volume ---
    if [ -n "$HOST_DATA_DIR" ]; then
        DOCKER_CMD+=" -v \"$HOST_DATA_DIR:/data\""
    fi
    
    # --- Add the Image Name ---
    DOCKER_CMD+=" ${N8N_IMAGE}"

    # --- Execute the command ---
    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD" # Use eval to correctly handle quotes in paths

    # --- Check for errors ---
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to start n8n container. Check Docker logs:${NC}"
        echo -e "   ${CYAN}docker logs $CONTAINER_NAME${NC}"
        exit 1
    fi
    echo -e "${CYAN}Waiting a few seconds for the container to initialize...${NC}"
    sleep 5
fi

# ───[ Post-Setup Information ]───────────────────────────────────
echo
echo -e "${GREEN}✅ n8n container '$CONTAINER_NAME' is running!${NC}"
echo
echo -e "${BOLD}📍 Key Information:${NC}"
echo -e "- Container Name:        ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Config stored on host: ${CYAN}$N8N_HOST_CONFIG_DIR${NC}"
if [ -n "$HOST_DATA_DIR" ]; then
echo -e "- Shared data on host:   ${CYAN}$HOST_DATA_DIR${NC} -> ${YELLOW}(inside container at /data)${NC}"
fi
echo -e "- Timezone set to:       ${CYAN}$TIMEZONE${NC}"

echo
echo -e "${BOLD}🌐 Access n8n Web UI:${NC} ${YELLOW}http://${HOST_IP}:5678${NC}"
echo -e "   (You can also use ${YELLOW}http://localhost:5678${NC} from the host machine)"
echo
echo -e "${BOLD}✨ Next Steps - Getting Started:${NC}"
echo -e "1. Open the UI. The first time you visit, you'll be asked to set up an ${BOLD}owner account${NC}. Do this!"
echo -e "2. To scan your receipts, you need to connect your Google account:"
echo -e "   - In the n8n UI, go to the ${BOLD}'Credentials'${NC} section on the left."
echo -e "   - Click 'Add credential', search for ${GREEN}'Gmail'${NC}, and follow the authentication steps."
echo -e "   - This process will guide you through the correct OAuth consent screen flow."
echo -e "3. Create your first workflow:"
echo -e "   - Start with a ${CYAN}'Schedule'${NC} node to run the workflow automatically."
echo -e "   - Add a ${CYAN}'Gmail'${NC} node, choose your new credential, set the operation to 'Search',"
echo -e "     and use a search query like: ${YELLOW}subject:(receipt OR invoice) is:unread${NC}"
echo -e "   - Connect other nodes (like Google Sheets, Code, etc.) to process the results."
echo
echo -e "${BOLD}🛠 Common n8n Docker Commands:${NC}"
echo -e "  Stop/Start/Restart: ${CYAN}docker stop|start|restart $CONTAINER_NAME${NC}"
echo -e "  View live logs:     ${CYAN}docker logs -f $CONTAINER_NAME${NC}"
echo -e "  Remove container:   ${CYAN}docker rm -f $CONTAINER_NAME${NC} (config is preserved in ${N8N_HOST_CONFIG_DIR})"
echo
echo -e "${GREEN}🚀 Setup complete. Time to start automating! Visit: ${YELLOW}http://${HOST_IP}:5678${NC}"
