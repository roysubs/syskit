#!/bin/bash
# Author: Roy Wiseman 2025-05

# Watchtower (automatic container updates) Docker automated deployment
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
BOLD='\033[1m'
NC='\033[0m' # No Color

# ──[ Detect Host IP ]─────────────────────────────
# Note: IP detection is not strictly necessary for Watchtower function,
# but kept for template consistency. Watchtower doesn't have a web UI.
HOST_IP=$(hostname -I | awk '{print $1}')
echo -e "${CYAN}Detected local IP: ${HOST_IP}${NC}"

# ──[ Container Settings ]─────────────────────────
CONTAINER_NAME="watchtower"
IMAGE_NAME="containrrr/watchtower"

# ──[ Check for Existing Container ]───────────────
EXISTS=$(docker ps -a --format '{{.Names}}' | grep -w "$CONTAINER_NAME")

# ──[ Installation Logic ]─────────────────────────
if [ -z "$EXISTS" ]; then
	echo
	echo -e "${BOLD}Watchtower container '$CONTAINER_NAME' not found. Proceeding with installation.${NC}"

	# ──[ Pull Watchtower Image ]────────────────────
	echo -e "${CYAN}Pulling latest Watchtower image...${NC}"
	docker pull $IMAGE_NAME

	if [ $? -ne 0 ]; then
		echo -e "${RED}✖ Failed to pull Watchtower image. Check your internet connection and Docker setup.${NC}"
		exit 1
	fi

	# ──[ Run Watchtower Container ]─────────────────
	# Translates the provided docker-compose.yml into a docker run command
	echo -e "${CYAN}Creating and starting Watchtower container...${NC}"
	docker run -d \
		--name $CONTAINER_NAME \
		--restart always \
		-v /var/run/docker.sock:/var/run/docker.sock \
		$IMAGE_NAME \
		--cleanup --interval 3600

	if [ $? -ne 0 ]; then
		echo -e "${RED}✖ Failed to start Watchtower container. Check Docker logs (${CYAN}docker logs $CONTAINER_NAME${RED}).${NC}"
		exit 1
	fi

	echo -e "${GREEN}✓ Watchtower container '$CONTAINER_NAME' started successfully!${NC}"

else
	echo -e "${YELLOW}Watchtower container '$CONTAINER_NAME' already exists.${NC}"
	echo -e "${YELLOW}Skipping installation steps.${NC}"
fi

# ──[ Post-Setup Info (Always Shown) ]─────────────
echo
echo -e "${BOLD}📍 Watchtower Container Info:${NC}"
echo -e "- Container name: ${CYAN}$CONTAINER_NAME${NC}"
echo -e "- Image: ${CYAN}$IMAGE_NAME${NC}"
echo -e "- Restart policy: ${CYAN}always${NC}"
echo -e "- Accesses host Docker socket: ${CYAN}/var/run/docker.sock${NC}"
echo -e "- Update check interval: ${CYAN}3600 seconds (1 hour)${NC}"
echo -e "- Cleans up old images: ${CYAN}Yes${NC}"
echo
echo -e "${BOLD}ℹ️ About Watchtower:${NC}"
echo    "Watchtower is a service that automatically updates your running Docker containers."
echo    "It monitors your containers and checks Docker Hub (or other registries) for new image versions."
echo    "When a new version is found, it stops the old container, pulls the new image,"
echo    "and restarts the container with the same options (volumes, networks, environment variables, etc.)"
echo    "that you used to initially run it."
echo
echo -e "${BOLD}Configuration Used in this Script:${NC}"
echo -e "- ${CYAN}--cleanup${NC}: This tells Watchtower to remove the old image after the new container starts successfully."
echo -e "- ${CYAN}--interval 3600${NC}: This sets the check interval to 3600 seconds (1 hour). Watchtower will check for updates every hour."
echo
echo -e "${BOLD}🔧 Container Management Commands:${NC}"
echo -e "  ${CYAN}docker start|stop|restart $CONTAINER_NAME${NC}   - Start|Stop|Restart the Watchtower container"
echo -e "  ${CYAN}docker logs $CONTAINER_NAME${NC}    - View Watchtower logs to see update activity"
echo -e "  ${CYAN}docker rm -f $CONTAINER_NAME${NC}   - Remove the container (this will stop Watchtower container auto-updates!)"
echo
echo -e "${BOLD}📝 Notes:${NC}"
echo    "By default, Watchtower will monitor ALL running containers on the host."
echo    "You can tell Watchtower to ignore specific containers by adding the label"
echo -e "${CYAN}com.centurylinklabs.watchtower.enable=false${NC} when you run those containers."
echo    "See the Watchtower documentation for more advanced options (e.g., updating only specific containers, notifications)."
echo

exit 0
