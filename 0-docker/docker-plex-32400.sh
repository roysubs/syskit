#!/bin/bash
# Author: Roy Wiseman 2025-04

# Plex Media Server in Docker automated deployment (web gui on port 32400)
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

DOCKER_IMAGE="pull plexinc/pms-docker"

# ──[ Styling ]────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
BLUE_BOLD='\033[1;34m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ──[ Detect Host IP ]─────────────────────────────
HOST_IP=$(hostname -I | awk '{print $1}')
echo -e "${CYAN}Detected local IP: ${HOST_IP}${NC}"

# ──[ Prompt for Media Directory ]─────────────────
DEFAULT_MEDIA_DIR="/mnt/sdc1/Downloads"
echo -e "${BOLD}Please enter the root folder where your media is stored.${NC}"
echo -e "You can use 'tab' to autocomplete paths."
echo -e "Leave this empty to use the default path:  ${BLUE_BOLD}${DEFAULT_MEDIA_DIR}${NC}"
read -e -p "Enter media root path [${DEFAULT_MEDIA_DIR}]: " user_input   # -e enables tab completion, -p sets the prompt string.
if [ -z "$user_input" ]; then   # -z checks if string length is zero
  MEDIA_DIR="$DEFAULT_MEDIA_DIR"
  echo -e "Using default media path: ${BLUE_BOLD}${MEDIA_DIR}${NC}"
else
  MEDIA_DIR="$user_input"
  echo "Using entered media path: ${BLUE_BOLD}${MEDIA_DIR}${NC}"
fi
if [ ! -d "$MEDIA_DIR" ]; then
  echo -e "${RED}${BOLD}Warning: The path ${BLUE_BOLD}$MEDIA_DIR${RED}${BOLD} does not appear to be an existing directory.${NC}"
  echo "Please rerun the script with a valid path to continue."
  exit 1
fi

# ──[ Validate Media Directory ]───────────────────
if [ ! -d "$MEDIA_DIR" ]; then
  echo -e "${RED}Error: Directory not found: $MEDIA_DIR${NC}"
  exit 1
fi

# ──[ Create Standard Media Folders ]──────────────
for folder in "0 Films" "0 TV" "0 Music"; do
  mkdir -p "$MEDIA_DIR/$folder"
done

# ──[ Show Folder Mapping Explanation ]────────────
echo
echo -e "${BOLD}📁 Folder Mapping Info:${NC}"
echo -e "The Docker container will map your media folder to: ${YELLOW}/mnt/plex/media${NC}"
echo -e "This means inside Plex you will use paths like:${NC}"
echo -e "  '/mnt/plex/media/0 Films'  => maps to '$MEDIA_DIR/0 Films'"
echo -e "  '/mnt/plex/media/0 TV'     => maps to '$MEDIA_DIR/0 TV'"
echo -e "  '/mnt/plex/media/0 Music'  => maps to '$MEDIA_DIR/0 Music'"

# ──[ Container Settings ]─────────────────────────
CONTAINER_NAME="plex-media-server"

# ──[ Check for Existing Container ]───────────────
EXISTS=$(docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME")

# ──[ Get Plex Claim Code If Needed ]──────────────
if [ -z "$EXISTS" ]; then
  echo
  echo -e "${BOLD}To link this server to your Plex account:${NC}"
  echo -e "  1. Visit ${YELLOW}https://account.plex.tv/claim${NC}"
  echo -e "  2. Sign in and copy your claim code (starts with 'claim-')"
  echo -e "  3. Paste it below. Code is valid for 5 minutes."
  echo
  read -p "Enter your Plex claim code: " PLEX_CLAIM

  echo -e "${CYAN}Pulling latest Plex image...${NC}"
  docker pull $DOCKER_IMAGE

  echo -e "${CYAN}Creating Plex container...${NC}"
  # Note: do not put any comments at the end of these lines as they cannot
  # be handled with the "\" line wraps. 
  docker run -d --name $CONTAINER_NAME \
    -e PLEX_CLAIM="$PLEX_CLAIM" \
    -e ADVERTISE_IP="http://$HOST_IP:32400" \
    -e PUID=1000 \
    -e PGID=1000 \
    -v "$MEDIA_DIR:/mnt/plex/media" \
    -v plex_data:/config \
    -p 32400:32400 \
    --restart unless-stopped \
    $DOCKER_IMAGE

  if [ $? -ne 0 ]; then
    echo -e "${RED}✖ Failed to start Plex container. Check Docker logs.${NC}"
    exit 1
  fi
else
  echo
  echo -e "${YELLOW}Container '$CONTAINER_NAME' already exists.${NC}"
fi

# ──[ Post-Setup Info (Always Shown) ]─────────────
echo
echo -e "${BOLD}📍 Plex Container Info:${NC}"
echo -e "- Container name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Media folder on host: ${CYAN}$MEDIA_DIR${NC}"
echo -e "- Mapped inside container to: ${CYAN}/mnt/plex/media${NC}"
echo -e "To add additional folders containing media to the running plex server, do"
echo -e "not use symlinks as they point to locations not accessible to the container."
echo -e "Instead, add additional -v 'hostPath:containerPath' options into the docker"
echo -e "command, though this will require destroying the container and creating a new"
echo -e "one, or mount additional folders directly into the media folder, or use bind"
echo -e "mounts for existing mounts on the system:"
echo -e "  sudo mount --bind '/mnt/mymount' '$MEDIA_DIR/mymount'"
echo
echo -e "${BOLD}📁 Suggested Plex Library Setup:${NC}"
for folder in "${SUBFOLDERS[@]}"; do
  type=$(echo "$folder" | sed 's/^0 //')
  echo "  Library Type: $type -> /mnt/plex/media/$folder"
done
echo
echo -e "${BOLD}🔧 Container Management:${NC}"
echo -e "  ${CYAN}docker stop|start|restart|logs $CONTAINER_NAME${NC} - Stop|Start|Restart|View logs"
echo -e "  ${CYAN}docker exec -it $CONTAINER_NAME bash${NC}           - Enter the container shell"
echo
echo -e "${BOLD}🌐 Access Plex Web UI:${NC} http://${HOST_IP}:32400/web"
echo

