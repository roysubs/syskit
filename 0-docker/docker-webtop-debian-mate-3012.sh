#!/bin/bash
# Author: Roy Wiseman 2025-03

# Webtop Debian MATE Docker automated deployment using ghcr.io/linuxserver/webtop
# This script sets up the container with specified host paths, ports, and user IDs.
# It includes options for audio, network, and graphics passthrough.
# It uses the config volume for persistence and provides tips for interaction.
# Based on instructions from:
# https://fleet.linuxserver.io/image?name=webtop
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
CONTAINER_NAME="webtop-debian-mate" # Name for the new container
# The Docker image to use.
WEB_IMAGE="ghcr.io/linuxserver/webtop:debian-mate" # Using 'debian-mate' tag

# --- Default Host directory for Webtop ---
# Configuration directory (stores user profile, settings etc); critical to container functionality.
DEFAULT_HOST_CONFIG_DIR="$HOME/.config/${CONTAINER_NAME}-docker" # Default path using the container name
WEB_CONTAINER_CONFIG_DIR="/config" # Internal config path inside the container (fixed by linuxserver image)

# --- Default Port Settings ---
# Using the single port specified in the provided docker run command.
# Format is HOST_PORT:CONTAINER_PORT for clarity.
WEBUI_HOST_PORT=3012 # Port for the Web UI (noVNC)
WEBUI_CONTAINER_PORT=3000 # Internal container port for WebUI (standard LSIO webtop)

# --- Environment Settings ---
# By default, use the current host timezone.
HOST_TZ=$(timedatectl | grep "Time zone:" | awk '{print $3}')
# Specify a timezone to use. See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
# Check if HOST_TZ is not empty
if [ -n "$HOST_TZ" ]; then
    TZ="$HOST_TZ"
    echo "Setting container timezone to host timezone: $TZ"
else
    TZ="Europe/Amsterdam"
  echo "Could not detect host timezone, defaulting to: $TZ"
fi

# --- Hardware Passthrough Options ---
# Audio: Expose host sound device to the container for audio output/input.
ENABLE_AUDIO_PASSTHROUGH=true # Set to true to enable audio passthrough

# Graphics: Expose host GPU device to the container for hardware acceleration.
# This requires a compatible GPU and drivers on the host and may also need the NVIDIA Container Toolkit.
ENABLE_GRAPHICS_PASSTHROUGH=true # Set to true to enable graphics passthrough
GPU_DEVICE_PATH="/dev/dri" # Common path for graphics devices (or specific like /dev/dri/renderD128)
# For Nvidia, consider using the NVIDIA runtime instead/additionally.
# See: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

# Network: Give the container direct access to the host's network interface.
# !! WARNING: This bypasses network isolation and has SECURITY IMPLICATIONS. !!
# !! Only use if you understand the risks and it's absolutely necessary. !!
ENABLE_HOST_NETWORK=false # Set to true to use host network mode (usually not needed)

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
echo -e "${BOLD}Webtop Debian MATE Docker Setup${NC}"
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
echo -e "${CYAN}ℹ️ Using PUID=${PUID} and PGID=${PGID} 'id -u' and 'id -g' for container user mapping.${NC}"
echo -e "${YELLOW}Ensure the host directories you map below are owned by this user/group (${PUID}:${PGID}) for correct permissions inside the container.${NC}"

# Check if the container already exists
if docker ps -a --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
    echo -e "${GREEN}✅ Container '$CONTAINER_NAME' already exists. Skipping creation.${NC}"
    echo -e "${CYAN}To stop and remove the existing container to create a new one:${NC}"
    echo -e "  ${CYAN}docker stop \"$CONTAINER_NAME\" > /dev/null 2>&1${NC}"
    echo -e "  ${CYAN}docker rm \"$CONTAINER_NAME\" > /dev/null 2>&1${NC}"
    # Set variables to defaults for info output even if container wasn't recreated
    HOST_CONFIG_DIR=$DEFAULT_HOST_CONFIG_DIR
else
    # --- Prompt for Host Configuration Directory ---
    echo -e "\n${BOLD}Please enter the host folder for Webtop configuration files.${NC}"
    echo -e "This is where container settings, your home directory files (including Downloads), etc., will be stored persistently."
    echo -e "Leave this empty to use the default path: ${BLUE_BOLD}${DEFAULT_HOST_CONFIG_DIR}${NC}"
    read -e -p "Enter host config path [${DEFAULT_HOST_CONFIG_DIR}]: " user_config_input
    HOST_CONFIG_DIR="${user_config_input:-$DEFAULT_HOST_CONFIG_DIR}" # Use default if input is empty

    # --- Prompt for Password ---
    echo -e "\n${BOLD}${RED}!! IMPORTANT: Set a secure password for accessing the Webtop desktop !!${NC}"
    echo -e "${BOLD}You will use this password to log in via the web browser.${NC}"
    read -s -p "Enter your secure password: " ACCESS_PASSWORD # -s hides input
    echo # Print a newline after silent read

    # --- Ensure Host Directory Exists ---
    echo -e "\n${BOLD}Checking/Creating host config directory...${NC}"
    ensure_dir "$HOST_CONFIG_DIR"
    echo -e "${GREEN}✅ Host directory checked/ensured.${NC}"
    echo

    # ───[ Docker Operations ]───────────────────────────────────────
    echo -e "${CYAN}Creating and starting Webtop Debian MATE container '$CONTAINER_NAME'...${NC}"
    echo -e "${CYAN}Pulling Webtop image ('${WEB_IMAGE}')...${NC}"
    echo
    echo -e "${CYAN}docker pull \"${WEB_IMAGE}\"${NC}"
    echo
    docker pull "${WEB_IMAGE}"
    echo
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Error: Failed to pull Docker image.${NC}"
        echo -e "${RED}  The image pull command failed for '${WEB_IMAGE}'. Ensure the image name and tag are correct and that you have network connectivity to ghcr.io.${NC}"
        exit 1
    fi

    # --- Build the docker run command string ---
    DOCKER_CMD="docker run -d"
    DOCKER_CMD+=" --name \"$CONTAINER_NAME\"" # Using quotes for robustness
    DOCKER_CMD+=" --restart unless-stopped"

    # --- Environment Variables ---
    DOCKER_CMD+=" -e PUID=${PUID}"
    DOCKER_CMD+=" -e PGID=${PGID}"
    DOCKER_CMD+=" -e TZ=${TZ}"
    DOCKER_CMD+=" -e PASSWORD=\"${ACCESS_PASSWORD}\"" # Password needs quotes if it might contain spaces or special characters

    # --- Port Mapping (Host:Container) ---
    # !! IMPORTANT: If using ENABLE_HOST_NETWORK=true below, port mapping will not be set
    if [ "$ENABLE_HOST_NETWORK" = false ]; then
        DOCKER_CMD+=" -p ${WEBUI_HOST_PORT}:${WEBUI_CONTAINER_PORT}" # WebUI/noVNC
    fi

    # --- Volume Mapping (Host:Container) ---
    DOCKER_CMD+=" -v \"$HOST_CONFIG_DIR\":\"$WEB_CONTAINER_CONFIG_DIR\"" # Config persistence

    # --- Resource Limits (Recommended) ---
    DOCKER_CMD+=" --shm-size=\"1gb\"" # Shared memory size

    # --- Hardware Passthrough Options ---
    # Audio Passthrough
    if [ "$ENABLE_AUDIO_PASSTHROUGH" = true ]; then
        echo -e "${CYAN}✅ Enabling audio passthrough (--device /dev/snd)${NC}"
        DOCKER_CMD+=" --device /dev/snd"
    else
       echo -e "${YELLOW}⚠️ Audio passthrough disabled. Set ENABLE_AUDIO_PASSTHROUGH=true in script config to enable.${NC}"
    fi

    # Graphics Passthrough (For NVIDIA, ensure that NVIDIA Container Toolkit is installed on host!)
    if [ "$ENABLE_GRAPHICS_PASSTHROUGH" = true ]; then
        echo -e "${CYAN}✅ Enabling graphics passthrough (--device ${GPU_DEVICE_PATH})${NC}"
        # For NVIDIA GPUs like RTX 3060, using --runtime=nvidia is often the correct approach
        # Make sure the NVIDIA Container Toolkit is installed on your host system.
        # See https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html
        DOCKER_CMD+=" --runtime=nvidia" # Use the nvidia container runtime
        DOCKER_CMD+=" --device ${GPU_DEVICE_PATH}:${GPU_DEVICE_PATH}" # Map the graphics device path
        # The seccomp unconfined option might be needed for some GPU setups, but reduces security
        echo -e "${YELLOW}⚠️ Adding --security-opt seccomp=unconfined for potential graphics compatibility. Use with caution.${NC}"
        DOCKER_CMD+=" --security-opt seccomp=unconfined" # Often needed for GUI/GPU apps
    else
       echo -e "${YELLOW}⚠️ Graphics passthrough disabled. Set ENABLE_GRAPHICS_PASSTHROUGH=true in script config to enable.${NC}"
    fi

    # Network Passthrough (!! SECURITY RISK !!)
    if [ "$ENABLE_HOST_NETWORK" = true ]; then
        echo -e "${RED}!! WARNING: Enabling host network mode (--network host) - SECURITY RISK !!${NC}"
        DOCKER_CMD+=" --network host"
        echo -e "${RED}!! Port mapping (-p) will be ignored when using host network mode. !!"
    else
       echo -e "${CYAN}✅ Using default bridge network mode (Recommended for security).${NC}"
    fi

    # --- Add the Image Name ---
    DOCKER_CMD+=" ${WEB_IMAGE}"

    # --- Execute the command ---
    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo
    echo -e "${CYAN}$DOCKER_CMD${NC}" # Print the command
    echo
    eval "$DOCKER_CMD" # Use eval to correctly handle quotes in paths

    # --- Check for errors ---
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Error: Failed to start Webtop container.${NC}"
        echo -e "${RED}  The 'eval' command exited with status $?.${NC}"
        echo -e "${RED}  Check Docker logs for more details if the container was partially created:${NC}"
        echo -e "  ${CYAN}docker logs $CONTAINER_NAME${NC}"
        exit 1
    fi
fi # End if container already exists check

# ───[ Post-Setup Information ]──────────────────────────────────
echo
echo -e "${GREEN}✅ Webtop container '$CONTAINER_NAME' started successfully!${NC}"
echo
echo -e "${BOLD}📍 Key Information:${NC}"
echo -e "- Container Name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Webtop Image: ${CYAN}${WEB_IMAGE}${NC}"
echo -e "- Host IP detected: ${CYAN}${HOST_IP}${NC}"
echo -e "- PUID/PGID used: ${CYAN}${PUID}/${PGID}${NC}"
echo -e "- Timezone set to: ${CYAN}${TZ}${NC}"
echo -e "- Shared memory size: ${CYAN}1gb${NC}"

if [ "$ENABLE_AUDIO_PASSTHROUGH" = true ]; then
  echo -e "- Audio Passthrough: ${GREEN}Enabled${NC} (--device /dev/snd)"
else
  echo -e "- Audio Passthrough: ${RED}Disabled${NC}"
fi

if [ "$ENABLE_GRAPHICS_PASSTHROUGH" = true ]; then
  echo -e "- Graphics Passthrough: ${GREEN}Enabled${NC} (--device ${GPU_DEVICE_PATH}, --runtime=nvidia, --security-opt seccomp=unconfined)"
  echo -e "  ${YELLOW}Note: Graphics acceleration requires NVIDIA Container Toolkit and compatible drivers on your host.${NC}"
else
  echo -e "- Graphics Passthrough: ${RED}Disabled${NC}"
fi

echo
echo -e "${BOLD}📡 Networking Notes:${NC}"
if [ "$ENABLE_HOST_NETWORK" = true ]; then
    echo -e "- Network Mode: ${RED}Host (SECURITY RISK!)${NC} (--network host)"
    echo -e "  ${RED}Access via host IP and container port ${WEBUI_CONTAINER_PORT} directly (e.g., http://${HOST_IP}:${WEBUI_CONTAINER_PORT})${NC}"
    echo -e "  ${RED}Port mapping (-p) is ignored in this mode.${NC}"
else
    echo -e "- Network Mode: ${GREEN}Bridge (Recommended)${NC}"
    echo -e "- Web UI (noVNC) port mapped: ${CYAN}${WEBUI_HOST_PORT} (Host) -> ${WEBUI_CONTAINER_PORT} (Container)${NC}"
    echo -e "  Access via: ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}${NC}"
    # echo -e "  Or from host: ${YELLOW}http://localhost:${WEBUI_HOST_PORT}${NC} or ${YELLOW}http://127.0.0.1:${WEBUI_HOST_PORT}${NC}"
fi

echo -e "- If accessing from outside your LAN, ensure your ${BOLD}host machine's firewall${NC} allows the relevant port (${WEBUI_HOST_PORT} or ${WEBUI_CONTAINER_PORT} if host network)."
echo -e "- Port forwarding on your router would need to point to ${BOLD}your host machine's IP${NC} (${HOST_IP})."

echo
echo -e "${BOLD}🛠 Basic Docker Commands:${NC}"
echo -e "  ${CYAN}docker ps|stop|start|restart $CONTAINER_NAME${NC} - List|Stop|Start|Restart the container"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}           - View live container logs"
echo -e "  ${CYAN}docker rm -f $CONTAINER_NAME${NC}          - Force remove container (config/data ${BOLD}preserved${NC} in host paths!)"
echo -e "  ${CYAN}docker exec -it $CONTAINER_NAME bash${NC}    - Enter container (or 'sh'/'ash' if bash is not default)"

echo
echo -e "${BOLD}📂 Mounted Host Directory (for Persistence & File Transfer):${NC}"
echo -e "  Host Config: ${CYAN}$HOST_CONFIG_DIR${NC}         -> Container: ${YELLOW}$WEB_CONTAINER_CONFIG_DIR${NC}"
echo -e "${BOLD}Note:${NC} The Downloads folder inside the container is typically located within the mounted config directory (e.g., ${YELLOW}$WEB_CONTAINER_CONFIG_DIR/home/abc/Downloads${NC}). You can access it on your host at ${CYAN}$HOST_CONFIG_DIR/home/abc/Downloads${NC} after the container has initialized and created the 'abc' user's home structure.${NC}"

echo
echo -e "${BOLD}🚀 First Time Access & Interaction Tips:${NC}"
echo -e "- 🌐 Go to the Webtop desktop in your browser: ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}${NC}"
echo -e "- 🔑 You will be prompted for a password. Use the secure password you entered when running this script."
echo -e "- 📁 ${UNDERLINE}Accessing Shared Files:${NC} Files you put in the host directory ${CYAN}$HOST_CONFIG_DIR/home/abc/Downloads${NC} will appear inside the container at ${YELLOW}$WEB_CONTAINER_CONFIG_DIR/home/abc/Downloads${NC}. Use the file manager inside Webtop to access them."
echo -e "- 📦 ${UNDERLINE}Installing Software:${NC} Open the Terminal Emulator within the Webtop desktop. Use ${CYAN}sudo apt update${NC} followed by ${CYAN}sudo apt install <package_name>${NC} to add applications (since this is a Debian image)."
echo -e "- ⌨️ ${UNDERLINE}Copy/Paste & Input:${NC} Look for a sidebar or top bar toolbar in your web client for clipboard, file transfer, special keys, and fullscreen."
echo -e "- 📈 ${UNDERLINE}Performance:${NC} Performance depends on your server's resources, network, and whether hardware acceleration is correctly configured and utilized by the applications."
echo -e "- 🚪 ${UNDERLINE}Logging Out/Disconnecting:${NC} Closing the browser tab disconnects the VNC session. To stop the desktop session, log out from the desktop menu or stop the container via docker stop $CONTAINER_NAME."
echo -e "- 🩺 ${UNDERLINE}Troubleshooting:${NC} If the web page doesn't load, use ${CYAN}docker logs $CONTAINER_NAME${NC} to check for errors during startup."
echo -e "- 🔊 ${UNDERLINE}Audio:${NC} This is NOT controlled by the OS directly (under System -> Preferences -> Hardware, no audio hardware is listed), the hardware is controlled by KasmVNC. Open up the KasmVNC panel and a second panel at the top should appear with audio and mic settings. Press on the audio icon to enable audio."
echo -e "- 🖼️ ${UNDERLINE}GPU Acceleration:${NC} This requires the Nvidia Cotainer Toolkit to be installed (see script in this folder). Set ENABLE_GRAPHICS_PASSTHROUGH=true to increase the Webtop graphics performance."
echo -e "- 🌐 ${UNDERLINE}KasmVNC Control Panel Help:${NC} ${YELLOW}https://kasmweb.com/docs/latest/user_guide/control_panel.html${NC}"
# Upload Files: Send files from your local machine into the Webtop environment. This is useful for getting documents, images, or other files you need to work with into your remote Linux desktop session.
# Download Files: Retrieve files from the Webtop session to save them onto your local computer. This is essential for accessing any files you create or modify within the Webtop.
# Essentially, the File Manager acts as a bridge for simple file transfers, integrating directly into the KasmVNC web interface to streamline the process without needing separate file transfer protocols or applications. Files you upload are usually placed in a designated upload directory within the Webtop session (often a specific folder in the user's home directory, such as /home/kasm-user/Uploads), and similarly, there's typically a designated download folder (/home/kasm-user/Downloads) from which you can initiate downloads to your local machine. 1 

echo
echo -e "${GREEN}🚀 Webtop setup script finished.${NC}"
if [ "$ENABLE_HOST_NETWORK" = true ]; then
  echo -e "${GREEN}  Access your Debian MATE Webtop at ${YELLOW}http://${HOST_IP}:${WEBUI_CONTAINER_PORT}${NC}${NC}"
else
  echo -e "${GREEN}  Access your Debian MATE Webtop at ${YELLOW}http://${HOST_IP}:${WEBUI_HOST_PORT}${NC}${NC}"
fi
