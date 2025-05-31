#!/bin/bash
# Author: Roy Wiseman 2025-05

# WeTTY (Web TTY) Setup in Docker (for Linux)
# ────────────────────────────────────────────────────────────
# Connect to an SSH server (e.g., your Docker host) via a web browser.

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

# ──[ Detect Host IP for Access Instructions ]─────────────────────────────
# This IP is for accessing the WeTTY Web UI from your browser
HOST_IP_DETECTED=$(hostname -I | awk '{print $1}')
if [ -z "$HOST_IP_DETECTED" ]; then
    echo -e "${YELLOW}⚠️ Could not automatically detect a primary local IP for access instructions. You might need to find it manually (e.g., using 'ip a').${NC}"
    DISPLAY_HOST_IP="localhost"
else
    DISPLAY_HOST_IP="$HOST_IP_DETECTED"
fi
echo -e "${CYAN}Detected local IP for WeTTY Web UI access instructions: ${DISPLAY_HOST_IP}${NC}"


# ──[ Configuration ]──────────────────────────────
# --- Container Settings ---
CONTAINER_NAME="wetty"
APP_IMAGE="wettyoss/wetty:latest" # Official WeTTY image

# --- Port Settings ---
DEFAULT_APP_HOST_PORT=3000      # Default host port to map to WeTTY's web UI
APP_CONTAINER_PORT=3000         # WeTTY listens on port 3000 inside the container by default

# --- WeTTY Specific SSH Connection Settings ---
DEFAULT_SSH_HOST="host.docker.internal" # Special Docker DNS name to connect to the host from container
                                        # Requires --add-host=host.docker.internal:host-gateway on Linux
DEFAULT_SSH_USER="$(whoami)"            # Default to current host user
DEFAULT_SSH_PORT=22                     # Default SSH port
DEFAULT_WETTY_BASE_PATH="/"             # Default base path for WeTTY web UI

# --- Flags ---
SHOULD_INSTALL=true # Assume we will install by default

# ──[ Check for Existing Container ]───────────────
EXISTS=$(docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME")
if [ ! -z "$EXISTS" ]; then
    echo -e "${YELLOW}An existing WeTTY container named '$CONTAINER_NAME' was found.${NC}"
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
INFO_SELECTED_HOST_PORT=""
INFO_SSH_HOST=""
INFO_SSH_USER=""
INFO_SSH_PORT=""
INFO_WETTY_BASE_PATH=""

if $SHOULD_INSTALL ; then
    echo
    echo -e "${BOLD}WeTTY container '$CONTAINER_NAME' will be installed.${NC}"

    echo -e "\n${BOLD}Please enter the host port for WeTTY Web UI.${NC}"
    read -e -p "Enter Host Port for WeTTY [${DEFAULT_APP_HOST_PORT}]: " user_host_port_input
    SELECTED_HOST_PORT_INPUT="${user_host_port_input:-$DEFAULT_APP_HOST_PORT}"
    echo -e "${GREEN}✅ WeTTY will be accessible on host port: $SELECTED_HOST_PORT_INPUT${NC}"
    echo

    echo -e "\n${BOLD}Configure Target SSH Connection Details:${NC}"
    read -e -p "Enter SSH Host (e.g., IP, hostname, or 'host.docker.internal' for Docker host) [${DEFAULT_SSH_HOST}]: " user_ssh_host_input
    SELECTED_SSH_HOST_INPUT="${user_ssh_host_input:-$DEFAULT_SSH_HOST}"
    echo -e "${GREEN}✅ Target SSH Host: $SELECTED_SSH_HOST_INPUT${NC}"

    read -e -p "Enter SSH User [${DEFAULT_SSH_USER}]: " user_ssh_user_input
    SELECTED_SSH_USER_INPUT="${user_ssh_user_input:-$DEFAULT_SSH_USER}"
    echo -e "${GREEN}✅ Target SSH User: $SELECTED_SSH_USER_INPUT${NC}"

    read -e -p "Enter SSH Port [${DEFAULT_SSH_PORT}]: " user_ssh_port_input
    SELECTED_SSH_PORT_INPUT="${user_ssh_port_input:-$DEFAULT_SSH_PORT}"
    echo -e "${GREEN}✅ Target SSH Port: $SELECTED_SSH_PORT_INPUT${NC}"
    echo

    read -e -p "Enter WeTTY Base URL Path (e.g., /wetty or / for root) [${DEFAULT_WETTY_BASE_PATH}]: " user_wetty_base_path_input
    SELECTED_WETTY_BASE_PATH_INPUT="${user_wetty_base_path_input:-$DEFAULT_WETTY_BASE_PATH}"
    # Ensure base path starts with a slash if not empty
    if [[ -n "$SELECTED_WETTY_BASE_PATH_INPUT" && ! "$SELECTED_WETTY_BASE_PATH_INPUT" == "/" && ! "$SELECTED_WETTY_BASE_PATH_INPUT" == /* ]]; then
        SELECTED_WETTY_BASE_PATH_INPUT="/$SELECTED_WETTY_BASE_PATH_INPUT"
    fi
    echo -e "${GREEN}✅ WeTTY Base Path: $SELECTED_WETTY_BASE_PATH_INPUT${NC}"
    echo

    echo -e "${CYAN}Pulling WeTTY image ('${APP_IMAGE}')...${NC}"
    docker pull ${APP_IMAGE}
    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to pull WeTTY image. Check Docker and internet.${NC}"
        exit 1
    fi

    echo -e "${CYAN}Creating and starting WeTTY container...${NC}"
    DOCKER_CMD="docker run -d"
    DOCKER_CMD+=" -p ${SELECTED_HOST_PORT_INPUT}:${APP_CONTAINER_PORT}"
    DOCKER_CMD+=" --name $CONTAINER_NAME"
    DOCKER_CMD+=" --restart unless-stopped"

    # Add host.docker.internal mapping for Linux hosts.
    # This allows using 'host.docker.internal' as SSH_HOST to connect to the Docker host.
    # For Docker Desktop on Mac/Windows, this is usually handled automatically.
    if [[ "$(uname -s)" == "Linux" ]]; then
      DOCKER_CMD+=" --add-host=host.docker.internal:host-gateway"
    fi

    # WeTTY command line arguments go AFTER the image name
    WETTY_ARGS="--ssh-host \"${SELECTED_SSH_HOST_INPUT}\""
    WETTY_ARGS+=" --ssh-user \"${SELECTED_SSH_USER_INPUT}\""
    WETTY_ARGS+=" --ssh-port \"${SELECTED_SSH_PORT_INPUT}\""
    WETTY_ARGS+=" --base \"${SELECTED_WETTY_BASE_PATH_INPUT}\""
    # Wetty listens on 0.0.0.0:3000 inside the container by default,
    # so no need to specify --host or --port for wetty itself unless changing its internal listen port.

    DOCKER_CMD+=" ${APP_IMAGE} ${WETTY_ARGS}"

    echo -e "${YELLOW}Executing Docker command:${NC}"
    echo "$DOCKER_CMD"
    eval "$DOCKER_CMD"

    if [ $? -ne 0 ]; then
        echo -e "${RED}✖ Failed to start WeTTY container. Check Docker logs (${CYAN}docker logs $CONTAINER_NAME${RED}).${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ WeTTY container '$CONTAINER_NAME' started successfully!${NC}"

    # Set INFO_ variables from the installation
    INFO_SELECTED_HOST_PORT="$SELECTED_HOST_PORT_INPUT"
    INFO_SSH_HOST="$SELECTED_SSH_HOST_INPUT"
    INFO_SSH_USER="$SELECTED_SSH_USER_INPUT"
    INFO_SSH_PORT="$SELECTED_SSH_PORT_INPUT"
    INFO_WETTY_BASE_PATH="$SELECTED_WETTY_BASE_PATH_INPUT"
else
    # Container exists, and we are not reinstalling. Gather info.
    echo -e "\n${CYAN}Attempting to retrieve information for existing container '$CONTAINER_NAME'...${NC}"

    INFO_SELECTED_HOST_PORT=$(docker inspect --format='{{range $p, $conf := .NetworkSettings.Ports}}{{if eq $p "'"$APP_CONTAINER_PORT/tcp"'"}}{{(index $conf 0).HostPort}}{{end}}{{end}}' "$CONTAINER_NAME" 2>/dev/null)
    if [ -z "$INFO_SELECTED_HOST_PORT" ]; then INFO_SELECTED_HOST_PORT="<unknown or not exposed>"; fi

    # Attempt to parse command for existing container (can be fragile)
    CMD_ARGS=$(docker inspect --format='{{range .Args}}{{.}} {{end}}' "$CONTAINER_NAME" 2>/dev/null)
    if [ -n "$CMD_ARGS" ]; then
        INFO_SSH_HOST=$(echo "$CMD_ARGS" | grep -o -E -- '--ssh-host "?([^"]*|[^ ]*)"?' | sed -E 's/--ssh-host "?//;s/"?$//' | tail -n1)
        INFO_SSH_USER=$(echo "$CMD_ARGS" | grep -o -E -- '--ssh-user "?([^"]*|[^ ]*)"?' | sed -E 's/--ssh-user "?//;s/"?$//' | tail -n1)
        INFO_SSH_PORT=$(echo "$CMD_ARGS" | grep -o -E -- '--ssh-port "?([^"]*|[^ ]*)"?' | sed -E 's/--ssh-port "?//;s/"?$//' | tail -n1)
        INFO_WETTY_BASE_PATH=$(echo "$CMD_ARGS" | grep -o -E -- '--base "?([^"]*|[^ ]*)"?' | sed -E 's/--base "?//;s/"?$//' | tail -n1)
    fi
    if [ -z "$INFO_SSH_HOST" ]; then INFO_SSH_HOST="<unknown from cmd args>"; fi
    if [ -z "$INFO_SSH_USER" ]; then INFO_SSH_USER="<unknown from cmd args>"; fi
    if [ -z "$INFO_SSH_PORT" ]; then INFO_SSH_PORT="<unknown from cmd args>"; fi
    if [ -z "$INFO_WETTY_BASE_PATH" ]; then INFO_WETTY_BASE_PATH="/"; fi # Default if not found
fi

# Ensure base path for URL construction always starts with a slash if not empty
URL_BASE_PATH="$INFO_WETTY_BASE_PATH"
if [[ -n "$URL_BASE_PATH" && ! "$URL_BASE_PATH" == "/" && ! "$URL_BASE_PATH" == /* ]]; then
    URL_BASE_PATH="/$URL_BASE_PATH"
elif [[ "$URL_BASE_PATH" == "/" ]]; then
    URL_BASE_PATH="" # Avoid double slash in URL if base is just "/"
fi


# ──[ Post-Setup Info ]─────────────
echo
echo -e "${BOLD}📍 WeTTY Container Info:${NC}"
echo -e "- Container name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Image: ${CYAN}$APP_IMAGE${NC}"
echo -e "- WeTTY Web UI (HTTP): Port ${CYAN}$INFO_SELECTED_HOST_PORT${NC} on host"
echo -e "- WeTTY Base Path: ${CYAN}$INFO_WETTY_BASE_PATH${NC}"
echo
echo -e "${BOLD}🔧 Target SSH Configuration:${NC}"
echo -e "- SSH Host: ${CYAN}$INFO_SSH_HOST${NC}"
echo -e "- SSH User: ${CYAN}$INFO_SSH_USER${NC}"
echo -e "- SSH Port: ${CYAN}$INFO_SSH_PORT${NC}"
echo
echo -e "${YELLOW}Note on SSH Authentication:${NC}"
echo -e "WeTTY will attempt to connect using the specified user. You will typically be prompted for a password in the browser."
echo -e "If the target SSH server (e.g., your Docker host) is configured for key-based authentication for that user,"
echo -e "and an SSH agent is correctly configured and accessible, key-based auth might work automatically."
echo -e "Forcing a specific private key requires mounting the key into the container and using the '--ssh-key' WeTTY option (not implemented in this basic script)."
echo
echo -e "If you need to ${UNDERLINE}change WeTTY's target SSH configuration${NC} or port:"
echo -e "1. ${RED}Stop the container:${NC} ${CYAN}docker stop $CONTAINER_NAME${NC}"
echo -e "2. ${RED}Remove the container:${NC} ${CYAN}docker rm $CONTAINER_NAME${NC}"
echo -e "3. ${GREEN}Re-run this script${NC} with the new desired settings."
echo
echo -e "${BOLD}🌐 Access WeTTY Web UI:${NC}"
echo -e "  Open your browser: ${YELLOW}http://${DISPLAY_HOST_IP}:${INFO_SELECTED_HOST_PORT}${URL_BASE_PATH}${NC}"
echo -e "  (Allow a moment for WeTTY to initialize fully on first run if newly installed.)"
echo
echo -e "${BOLD}⚙️ Common Docker Commands:${NC}"
echo -e "  ${CYAN}docker start|stop|restart $CONTAINER_NAME${NC}"
echo -e "  ${CYAN}docker logs -f $CONTAINER_NAME${NC}"
echo -e "  ${CYAN}docker rm $CONTAINER_NAME${NC}"
echo
echo -e "${BOLD}🚀 Next Steps After Accessing WeTTY:${NC}"
echo -e "  1. Access the web UI at the URL above."
echo -e "  2. You should be prompted to log in with the credentials for '${BOLD}${INFO_SSH_USER}${NC}' on host '${BOLD}${INFO_SSH_HOST}${NC}'."
echo -e "  3. Consider setting up HTTPS using a reverse proxy (e.g., Nginx, Traefik) for secure connections."
echo

exit 0
