#!/bin/bash
# Author: Roy Wiseman 2025-01

# EmulatorJS Docker automated deployment using linuxserver/emulatorjs
# This script sets up the container with specified host paths, ports, and user IDs.
# Based on instructions from:
# https://medium.com/@irteza.asad/play-arcade-on-a-docker-container-49b56a19e576
# https://blog.devops.dev/play-arcade-on-docker-container-f9794a783d3c
# Official image documentation: https://fleet.linuxserver.io/image?name=emulatorjs
# https://archive.org/details/nes-hack-collection
# ───────────────────────────────────────────────────────────────

# Check if Docker is installed
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
CONTAINER_NAME="emulatorjs"
EMU_IMAGE="lscr.io/linuxserver/emulatorjs:latest"

# --- Default Host directories for EmulatorJS configuration and data ---
# Configuration directory (settings, logs etc - KEEP THIS SAFE!)
DEFAULT_HOST_CONFIG_DIR="$HOME/.config/emulatorjs-docker"
# Data directory (ROMs, BIOS files, save states)
DEFAULT_HOST_DATA_DIR="$HOME/emulatorjs-data"

EMU_CONTAINER_CONFIG_DIR="/config" # Internal config path inside the container (fixed by linuxserver image)
EMU_CONTAINER_DATA_DIR="/data"   # Internal data path inside the container (fixed by linuxserver image - for ROMs/BIOS/Saves)

# --- Default Port Settings ---
# You can change these if ports are already in use on your host.
# Format is HOST_PORT=CONTAINER_PORT for clarity.
# EmulatorJS by default wants to use port 80 for the frontend UI and 3000 for the backend manager.
WEBUI_HOST_PORT=3332         # Host port for the Web UI (uploading ROMs, config)
WEBUI_CONTAINER_PORT=3000    # Internal container port for WebUI

GAME_HOST_PORT=3333          # Host port for serving the emulator/game, it defaults to 80, so we map it elsewhere
GAME_CONTAINER_PORT=80       # Internal container port for Game Serving

OPTIONAL_HOST_PORT=3334      # An optional port is mentioned from the image homepage (e.g., for Netplay?), we won't use this by default
OPTIONAL_CONTAINER_PORT=4001 # Corresponding container port internal to container

# --- Environment Settings ---
# Specify a timezone to use. See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TZ="Etc/UTC" # Example: "America/New_York", "Europe/London"
# Subfolder for accessing the UI/Game (e.g., "/emujs" for http://your-ip/emujs) - leave "/" for root
SUBFOLDER="/"

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
echo -e "${BOLD}EmulatorJS Docker Setup${NC}"
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
    HOST_CONFIG_DIR=$DEFAULT_HOST_CONFIG_DIR
    HOST_DATA_DIR=$DEFAULT_HOST_DATA_DIR
else
    # --- Prompt for Host Configuration Directory ---
    echo -e "\n${BOLD}Please enter the host folder for EmulatorJS configuration files.${NC}"
    echo -e "This is where container settings and configuration will be stored persistently."
    echo -e "Leave this empty to use the default path: ${BLUE_BOLD}${DEFAULT_HOST_CONFIG_DIR}${NC}"
    read -e -p "Enter host config path [${DEFAULT_HOST_CONFIG_DIR}]: " user_config_input
    HOST_CONFIG_DIR="${user_config_input:-$DEFAULT_HOST_CONFIG_DIR}" # Use default if input is empty

    # --- Prompt for Host Data/ROMs Directory ---
    echo -e "\n${BOLD}Please enter the host folder for EmulatorJS data (ROMs, BIOS, Saves).${NC}"
    echo -e "This is the folder where you will place your game files."
    echo -e "Leave this empty to use the default path: ${BLUE_BOLD}${DEFAULT_HOST_DATA_DIR}${NC}"
    read -e -p "Enter host data path [${DEFAULT_HOST_DATA_DIR}]: " user_data_input
    HOST_DATA_DIR="${user_data_input:-$DEFAULT_HOST_DATA_DIR}" # Use default if input is empty

    # --- Ensure Host Directories Exist ---
    echo -e "\n${BOLD}Checking/Creating host directories...${NC}"
    ensure_dir "$HOST_CONFIG_DIR"
    ensure_dir "$HOST_DATA_DIR"
    echo -e "${GREEN}✅ Host directories checked/ensured.${NC}"
    echo

    # ───[ Docker Operations ]───────────────────────────────────────
    echo -e "${CYAN}Creating and starting EmulatorJS container '$CONTAINER_NAME'...${NC}"
    echo -e "${CYAN}Pulling latest EmulatorJS image ('${EMU_IMAGE}')...${NC}"
    docker pull ${EMU_IMAGE}
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
    DOCKER_CMD+=" -e SUBFOLDER=${SUBFOLDER}"

    # --- Port Mappings ---
    DOCKER_CMD+=" -p ${WEBUI_HOST_PORT}:${WEBUI_CONTAINER_PORT}" # WebUI/File Manager
    DOCKER_CMD+=" -p ${GAME_HOST_PORT}:${GAME_CONTAINER_PORT}"   # Game Serving

    # Add optional port mapping if OPTIONAL_HOST_PORT is not 0
    if [ "$OPTIONAL_HOST_PORT" -ne 0 ]; then
      DOCKER_CMD+=" -p ${OPTIONAL_HOST_PORT}:${OPTIONAL_CONTAINER_PORT}" # Optional Port
    fi

    # --- Volume Mappings ---
    # Config volume (MANDATORY)
    DOCKER_CMD+=" -v \"$HOST_CONFIG_DIR\":\"$EMU_CONTAINER_CONFIG_DIR\""
    # Data/ROMs volume (MANDATORY for games/saves)
    DOCKER_CMD+=" -v \"$HOST_DATA_DIR\":\"$EMU_CONTAINER_DATA_DIR\""

    # --- Add the Image Name ---
    DOCKER_CMD+=" ${EMU_IMAGE}"

    # --- Execute the command ---
    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD" # Use eval to correctly handle quotes in paths

    # --- Check for errors ---
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to start EmulatorJS container. Check Docker logs:${NC}"
        echo -e "  ${CYAN}docker logs $CONTAINER_NAME${NC}"
        exit 1
    fi
fi

# ───[ Post-Setup Information ]──────────────────────────────────
echo
echo -e "${GREEN}✅ EmulatorJS container '$CONTAINER_NAME' started successfully!${NC}"
echo
echo -e "${BOLD}📍 Key Information:${NC}"
echo -e "- Container Name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- EmulatorJS Image: ${CYAN}${EMU_IMAGE}${NC}"
echo -e "- Host IP detected: ${CYAN}${HOST_IP}${NC}"
echo -e "- PUID/PGID used: ${CYAN}${PUID}/${PGID}${NC}"
echo -e "- Timezone set to: ${CYAN}${TZ}${NC}"
echo -e "- Subfolder configured: ${CYAN}${SUBFOLDER}${NC}"

echo
echo -e "${BOLD}📡 Networking Notes:${NC}"
echo -e "- Web UI port mapped: ${CYAN}${WEBUI_HOST_PORT} (Host) -> ${WEBUI_CONTAINER_PORT} (Container)${NC}"
echo -e "- Game serving port mapped: ${CYAN}${GAME_HOST_PORT} (Host) -> ${GAME_CONTAINER_PORT} (Container)${NC}"
if [ "$OPTIONAL_HOST_PORT" -ne 0 ]; then
  echo -e "- Optional port mapped: ${CYAN}${OPTIONAL_HOST_PORT} (Host) -> ${OPTIONAL_CONTAINER_PORT} (Container)${NC}"
fi
echo -e "- If accessing from outside your LAN, ensure your ${BOLD}host machine's firewall${NC} allows these ports (${WEBUI_HOST_PORT} and ${GAME_HOST_PORT}, plus ${OPTIONAL_HOST_PORT} if mapped)."
echo -e "- Port forwarding on your router would need to point to ${BOLD}your host machine's IP${NC} (${HOST_IP}) for these ports."
echo -e "${BOLD}Note:${NC} If accessing from the host machine, you can also use ${YELLOW}http://localhost:${WEBUI_HOST_PORT}${SUBFOLDER}${NC} or ${YELLOW}http://127.0.0.1:${WEBUI_HOST_PORT}${SUBFOLDER}${NC} for the UI."

echo
echo -e "${BOLD}🛠 Common Docker Commands:${NC}"
echo -e "  ${CYAN}docker stop|start|restart $CONTAINER_NAME${NC} - Stop|Start|Restart the container"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}     - View live container logs"
echo -e "  ${CYAN}docker ps -a${NC}                 - Check if container is running"
echo -e "  ${CYAN}docker rm -f $CONTAINER_NAME${NC}       - Force remove container (config/data ${BOLD}preserved${NC} in host paths)"
echo -e "  ${CYAN}docker exec -it $CONTAINER_NAME bash${NC} - Enter container shell (if bash is available, often uses 'sh')"

echo
echo -e "${BOLD}📂 Adding NEW Host Volumes Later:${NC}"
echo -e "If you need to add another directory from your host to the container (e.g., for more ROM storage segregated from the main data volume):"
echo -e "1. ${RED}STOP${NC} the container: ${CYAN}docker stop $CONTAINER_NAME${NC}"
echo -e "2. ${RED}REMOVE${NC} the container: ${CYAN}docker rm $CONTAINER_NAME${NC} (Your data in ${HOST_CONFIG_DIR} and ${HOST_DATA_DIR} is safe!)"
echo -e "3. Edit ${BOLD}this script${NC}:"
echo -e "   - Define a new variable for the new host path (e.g., ${CYAN}NEW_ROMS_HOST_DIR=\"/path/to/more/roms\"${NC})."
echo -e "   - Add a new ${CYAN}ensure_dir \"\$NEW_ROMS_HOST_DIR\"${NC} line in the Preparations section."
echo -e "   - Add a new mount line to the ${CYAN}DOCKER_CMD${NC} string in the Docker Operations section:"
echo -e "     ${CYAN}+= \" -v \\\"\$NEW_ROMS_HOST_DIR\\\":/new-container-path\\\"\"${NC}"
echo -e "     (Choose a meaningful path inside the container after the colon, e.g., '/mnt/more-roms')."
echo -e "   - Update the '${BOLD}Mounted Host Directories'${NC} output section to list the new mount."
echo -e "4. ${GREEN}Re-run this script${NC}. It will recreate the container with the new mount."
echo -e "5. Place files in the new host directory (${CYAN}\$NEW_ROMS_HOST_DIR${NC}) and access them inside the container"
echo -e "   via the new container path (${YELLOW}/new-container-path${NC})."

echo
echo -e "${BOLD}💾 Mounted Host Directories:${NC}"
echo -e "  Host Config: ${CYAN}$HOST_CONFIG_DIR${NC}       -> Container: ${YELLOW}$EMU_CONTAINER_CONFIG_DIR${NC}"
echo -e "  Host Data (ROMs/Saves/BIOS): ${CYAN}$HOST_DATA_DIR${NC} -> Container: ${YELLOW}$EMU_CONTAINER_DATA_DIR${NC}"

echo
echo -e "🚀${BOLD} First Time Access - Initial Setup (follow this carefully!):${NC}"
echo -e "- 🌐 Go to the ${BOLD}EmulatorJS Manager:${NC} ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}${SUBFOLDER}${NC}"
echo -e "- 📂 In File Management (3rd tab), drag files in (can be native ROMs or zip files with ROMs inside)."
echo -e "     e.g., 248 homebrew games here: ${YELLOW}https://archive.org/details/nes-hack-collection${NC}"
echo -e "- 🛠  In ROM Management (1st tab), select nes (or whatever ROMs you added), then press \"Scan\"."
echo -e "     ${RED}Very important!${NC} Also press \"DL/Update\" on this page to pull the UI images and videos."
echo -e "- 🛠  in Config Manamagnet (2nd tab), the section should have updated with the ROMs (no need to do anything)."
echo -e "- 🌐 Go to ${BOLD}EmulatorJS:${NC} ${YELLOW}http://${HOST_IP}:${GAME_HOST_PORT}${SUBFOLDER}${NC}"
echo -e "     ${RED}Very important!${NC} Press Ctrl+F5 or Ctrl+Shift+R to clear the cache so that it can read the config!"
echo -e "     Without this, the frontend Game Interface will just say that you have no games loaded."
echo -e "- 🎮 Don't use F11 to go Fullscreen as that will retain the window, do that with the fullscreen button top right."
echo -e "     To change game controls or add a hand controller, press F1 when in-game (doesn't work on home screen)."
echo -e "- 🛠  Add more games by dragging or copying in, press the \"Scan\" button to update config, and Ctrl+F5 on frontend."

echo
echo -e "${BOLD}🎮 Adding ROMs and BIOS Files:${NC}"
echo -e "Add ROM files (e.g., homebrew .nes, .smc, .gba) and any necessary BIOS files into the corresponding subfolders within the host directory mapped to ${YELLOW}/data${NC} (or drag files remotely into the EmulatorJS Manager web page in the File Management section as before)."
echo -e "If copying files in via a file manager or console, the host directory is: ${CYAN}$HOST_DATA_DIR${NC}"
echo -e "e.g., for Nintendo ROMs, put them in ${CYAN}$HOST_DATA_DIR/roms/nes${NC}, ${CYAN}$HOST_DATA_DIR/roms/snes${NC}, ${CYAN}$HOST_DATA_DIR/roms/gba${NC}, ${CYAN}$HOST_DATA_DIR/bios${NC}, etc."
echo -e "The container is configured to scan these host locations for games."


echo
echo -e "${GREEN}🚀 EmulatorJS setup script finished.${NC}"
echo -e "${GREEN}   Access the EmulatorJS Manager at   ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}${SUBFOLDER}${NC}${NC}"
echo -e "${GREEN}   Access the EmulatorJS Interface at ${YELLOW}http://${HOST_IP}:${GAME_HOST_PORT}${SUBFOLDER}${NC}${NC}"
echo
