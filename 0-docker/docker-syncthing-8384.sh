#!/bin/bash
# Author: Roy Wiseman 2025-03

# Syncthing Server Docker automated deployment, with --network=host for full host network access
# https://github.com/syncthing/syncthing/blob/main/README-Docker.md
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
BOLD='\033[1m'
NC='\033[0m' # No Color

# ───[ Configuration ]───────────────────────────────────────────
# !! IMPORTANT: Define ALL host directories you might want Syncthing to access here !!
# Syncthing running inside Docker can ONLY see directories explicitly mounted using '-v'.
# Add more lines like the 'HOST_SYNC_SHARE' example if you need to sync other directories.
# --- Default Host directory for Syncthing's configuration files ---
# (contains database, keys, settings - KEEP THIS SAFE!)
ST_HOST_CONFIG_DIR="$HOME/.config/syncthing-docker" # Changed slightly to avoid conflict if native Syncthing is also used
# --- Host directory to be setup in web GUI to sync ---
DEFAULT_HOST_SYNC_SHARE="/mnt/media"
echo -e "${BOLD}Please enter the host folder to be used by Syncthing to sync.${NC}"
echo -e "Note: this is *not* neceissarily the folder that will sync, this is a shared volume."
echo -e "You can sync this folder or any subfolder by configuration in the syncthing web client."
echo -e "You can use 'tab' to autocomplete paths."
echo -e "Leave this empty to use the default path:  ${BLUE_BOLD}${DEFAULT_HOST_SYNC_SHARE}${NC}"
read -e -p "Enter host sync root path [${DEFAULT_HOST_SYNC_SHARE}]: " user_input   # -e enables tab completion, -p sets the prompt string.
if [ -z "$user_input" ]; then   # -z checks if string length is zero
  HOST_SYNC_SHARE="$DEFAULT_HOST_SYNC_SHARE"
  echo -e "Using default host sync path: ${BLUE_BOLD}${HOST_SYNC_SHARE}${NC}"
else
  HOST_SYNC_SHARE="$user_input"
  echo "Using entered host sync path: ${BLUE_BOLD}${HOST_SYNC_SHARE}${NC}"
fi
if [ ! -d "$HOST_SYNC_SHARE" ]; then
  echo -e "${RED}${BOLD}Warning: The path ${BLUE_BOLD}$HOST_SYNC_SHARE${RED}${BOLD} does not appear to be an existing directory.${NC}"
  echo "Please rerun the script with a valid path to continue."
  exit 1
fi

# By default, make the internal container folder that maps to the
# host folder have the same name, but under "/sync" internally.
ST_SYNC_SHARE="/sync/$(basename $HOST_SYNC_SHARE)"
echo "Container path to the above volume mount: $ST_SYNC_SHARE"
# You can add more directories here if needed, e.g.:
# PHOTOS_HOST_DIR="/path/to/my/photos"
# DOCUMENTS_HOST_DIR="/path/to/my/documents"

# --- Container Settings ---
CONTAINER_NAME="syncthing"
SYNCTHING_IMAGE="syncthing/syncthing:latest"

# ───[ Helper Functions ]────────────────────────────────────────
# Function to check if a directory exists
check_dir() {
  if [ ! -d "$1" ]; then
    echo -e "${RED}✖ Error: Directory not found: $1${NC}"
    echo -e "${YELLOW}Please ensure the directory exists and the script has permission to access it.${NC}"
    exit 1
  fi
}

# ───[ Preparations ]────────────────────────────────────────────
echo -e "${BOLD}Syncthing Docker Setup (Host Network Mode)${NC}"
echo "--------------------------------------------------"

# --- Detect Host IP (Best guess for UI link) ---
# Note: With host networking, Syncthing binds to 0.0.0.0 (all interfaces)
# We still try to find a primary local IP for easy access link.
HOST_IP=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP. You might need to find it manually (e.g., using 'ip a').${NC}"
    # Fallback if hostname -I fails
    HOST_IP="localhost"
fi
echo -e "${CYAN}ℹ️ Detected likely local IP: ${HOST_IP}${NC} (Syncthing UI will be accessible via this IP on port 8384)"

# --- Create Configuration Directory ---
echo -e "${CYAN}Ensuring Syncthing config directory exists on host: ${ST_HOST_CONFIG_DIR}${NC}"
mkdir -p "$ST_HOST_CONFIG_DIR"
if [ $? -ne 0 ]; then
  echo -e "${RED}✖ Error: Failed to create config directory: $ST_HOST_CONFIG_DIR${NC}"
  exit 1
fi

# --- Check if specified Host Data Directories exist ---
echo -e "${CYAN}Checking if specified host data directories exist...${NC}"
check_dir "$HOST_SYNC_SHARE"
# Add checks for other directories if you defined them above, e.g.:
# check_dir "$PHOTOS_HOST_DIR"
# check_dir "$DOCUMENTS_HOST_DIR"
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
    echo -e "${CYAN}Creating and starting Syncthing container '$CONTAINER_NAME'...${NC}"
    echo -e "${CYAN}Pulling latest Syncthing image ('${SYNCTHING_IMAGE}')...${NC}"
    docker pull ${SYNCTHING_IMAGE}
    if [ $? -ne 0 ]; then
      echo -e "${RED}✖ Error: Failed to pull Docker image. Check Docker installation and internet connection.${NC}"
      exit 1
    fi

    # --- Build the docker run command ---
    # Start with the basic command and options
    DOCKER_CMD="docker run -d --name \"$CONTAINER_NAME\""
    DOCKER_CMD+=" --network=host"
    # Use host network mode, without which performance will be slow.
    # To test, remove --network=host and use the below instead:
    # -p 8384:8384 -p 22000:22000/tcp -p 22000:22000/udp -p 21027:21027/udp
    DOCKER_CMD+=" --restart unless-stopped"
    # --- Mount Essential Syncthing Configuration Volume ---
    # This maps the host directory (where config is stored) to the container's internal path for config.
    DOCKER_CMD+=" -v \"$ST_HOST_CONFIG_DIR:/var/syncthing/config\"" # Syncthing expects its config here
    # --- Mount Data Volumes ---
    # IMPORTANT: For every host directory you want Syncthing to potentially access,
    # you MUST add a '-v' mount here. The container path (after the colon ':')
    # is what you will use when adding a folder inside the Syncthing Web UI.
    # We use a '/sync/' prefix inside the container for clarity.
    # --- Mount the Torrents directory ---
    DOCKER_CMD+=" -v \"$HOST_SYNC_SHARE:$ST_SYNC_SHARE\""
    # Add more mounts here if you defined more directories above, e.g.:
    # DOCKER_CMD+=" -v \"$PHOTOS_HOST_DIR:/sync/photos\""
    # DOCKER_CMD+=" -v \"$DOCUMENTS_HOST_DIR:/sync/documents\""
    # --- Add the Image Name ---
    DOCKER_CMD+=" ${SYNCTHING_IMAGE}"
    
    # --- Execute the command ---
    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD" # Use eval to correctly handle quotes in paths

    # --- Check for errors ---
    if [ $? -ne 0 ]; then
      echo -e "${RED}✖ Failed to start Syncthing container. Check Docker logs:${NC}"
      echo -e "  ${CYAN}docker logs $CONTAINER_NAME${NC}"
      exit 1
    fi
fi

# ───[ Post-Setup Information ]──────────────────────────────────
echo
echo -e "${GREEN}✅ Syncthing container '$CONTAINER_NAME' started successfully!${NC}"
echo
echo -e "${BOLD}📍 Key Information:${NC}"
echo -e "- Container Name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Network Mode: ${YELLOW}host${NC} (Uses host's network directly)"
echo -e "- Config stored on host: ${CYAN}$ST_HOST_CONFIG_DIR${NC}"
echo -e "- Syncthing Image: ${CYAN}${SYNCTHING_IMAGE}${NC}"

echo
echo -e "${BOLD}💾 Mounted Host Directories (accessible inside Syncthing UI):${NC}"
echo -e "  Host: ${CYAN}$HOST_SYNC_SHARE${NC} -> Container: ${YELLOW}/sync/torrents-complete${NC}"
# List other mounted directories here if added:
# echo -e "  Host: ${CYAN}$PHOTOS_HOST_DIR${NC} -> Container: ${YELLOW}/sync/photos${NC}"
# echo -e "  Host: ${CYAN}$DOCUMENTS_HOST_DIR${NC} -> Container: ${YELLOW}/sync/documents${NC}"
echo -e "${BOLD}IMPORTANT:${NC} When adding a folder in the Syncthing Web UI, use the ${YELLOW}Container Path${NC} (e.g., /sync/torrents-complete)."

echo
echo -e "${BOLD}🌐 Access Syncthing Web UI:${NC} ${YELLOW}http://${HOST_IP}:8384${NC}"
echo -e "${BOLD}Note:${NC} If you are accessing this from the host machine itself, you can also use ${YELLOW}http://localhost:8384${NC} or ${YELLOW}http://127.0.0.1:8384${NC}."
echo -e "Initial setup might require creating an admin username/password in the UI (Settings -> GUI)."

echo
echo -e "${BOLD}✨ How to Add Your Sync Folders (via Web UI):${NC}"
echo -e "1. Open the Syncthing Web UI (${YELLOW}http://${HOST_IP}:8384${NC})."
echo -e "2. Click the ${GREEN}'+ Add Folder'${NC} button."
echo -e "3. ${BOLD}Folder Label:${NC} Give it a descriptive name."
echo -e "4. ${BOLD}Folder Path:${NC} Enter the path ${UNDERLINE}inside the container${NC} that you mounted earlier."
echo -e "   - For an added volume mount, find these under: ${YELLOW}/sync/name-of-mount${NC} (i.e., not the path as it is on the host)."
echo -e "5. Go to the ${BOLD}'Sharing'${NC} tab to select which devices should sync this folder."
echo -e "6. Configure other options (Versioning, Ignore Patterns) as needed."
echo -e "7. Click ${GREEN}'Save'${NC}."
echo -e "8. Repeat for any other folders you mounted and want to sync."

echo
echo -e "${BOLD}📡 Networking Notes (Host Mode):${NC}"
echo -e "- Syncthing directly uses the host's network interfaces."
echo -e "- Ports used on the host: ${CYAN}8384${NC} (Web UI), ${CYAN}22000/TCP${NC} (Sync Protocol), ${CYAN}22000/UDP${NC} (Sync Protocol), ${CYAN}21027/UDP${NC} (Discovery)."
echo -e "- Local device discovery should work reliably now."
echo -e "- If accessing from outside your LAN, ensure your ${BOLD}host machine's firewall${NC} allows these ports (especially 22000 TCP/UDP)."
echo -e "- Port forwarding on your router would need to point to ${BOLD}your host machine's IP${NC} (${HOST_IP}) for these ports."

echo
echo -e "${BOLD}🛠 Common Syncthing Docker Commands:${NC}"
echo -e "  ${CYAN}docker stop|start|restart $CONTAINER_NAME${NC} - Stop|Start|Restart the container"
echo -e "  ${CYAN}docker exec -it $CONTAINER_NAME sh${NC} - Enter container shell (uses 'sh', not 'bash', and running Alpine)"
echo -e "  ${CYAN}docker ps -a${NC}                 - Check if container is running"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}     - View live Syncthing logs"
echo -e "  ${CYAN}docker rm -f $CONTAINER_NAME${NC}       - Force remove container (config ${BOLD}preserved${NC} in ${ST_HOST_CONFIG_DIR})"

echo
echo -e "${BOLD}🔮 Adding NEW Host Folders Later:${NC}"
echo -e "If you want Syncthing to access a host folder that wasn't mounted initially:"
echo -e "1. ${RED}STOP${NC} the container: ${CYAN}docker stop $CONTAINER_NAME${NC}"
echo -e "2. ${RED}REMOVE${NC} the container: ${CYAN}docker rm $CONTAINER_NAME${NC} (Your config in ${ST_HOST_CONFIG_DIR} is safe!)"
echo -e "3. Edit ${BOLD}this script${NC}:"
echo -e "   - Add a new variable for the host path (e.g., ${CYAN}NEW_FOLDER_HOST_DIR=\"/path/to/new/folder\"${NC})."
echo -e "   - Add a new ${CYAN}check_dir \"\$NEW_FOLDER_HOST_DIR\"${NC} line."
echo -e "   - Add a new mount line to the ${CYAN}DOCKER_CMD${NC} string: ${CYAN}-v \"\$NEW_FOLDER_HOST_DIR:/sync/new-folder-name\"${NC}"
echo -e "   - Update the '${BOLD}Mounted Host Directories'${NC} output section."
echo -e "4. ${GREEN}Re-run this script${NC}. It will recreate the container with the new mount."
echo -e "5. Go to the Web UI and add the new folder using its container path (e.g., ${YELLOW}/sync/new-folder-name${NC})."

echo
echo -e "${GREEN}🚀 Setup complete. Configure your folders and devices via the Web UI: ${YELLOW}http://${HOST_IP}:8384${NC}"
