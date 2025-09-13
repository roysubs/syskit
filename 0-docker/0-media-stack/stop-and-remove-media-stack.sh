#!/bin/bash
# Author: Roy Wiseman 2025-04

RED='\e[0;31m'
GREEN='\e[0;32m' # For the success message later on
NC='\033[0m'

set -e

CONFIG_ROOT="$HOME/.config/media-stack"   # CONFIG_DIR="$(pwd)/config"
ENV_FILE=".env"
BASE_MEDIA="/mnt/media" # This is the mount point, seen by containers as the root of media

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

# Stop and remove containers
# docker rm -f wireguard qbittorrent sonarr radarr filebrowser jackett

echo "docker compose down will stop all containers defined in the docker-compose-media-stack.yml file."
echo "It will then remove the containers."
echo "It will then removes networks (the dedicated network created for your composed services)."
echo "By default, 'docker compose down' does not remove named volumes. This is to prevent data loss."
echo "To also remove named volumes, explicitly add the --volumes (or -v) flag:"
echo "    docker compose down --volumes.   # Anonymous volumes attached to containers are removed with the containers."



read -p "Stop and remove the containers (docker compose down) [y/N]: " del_env
if [[ "$del_env" =~ ^[Yy]$ ]]; then
  DOCKER_COMPOSE_FILE="docker-compose.yaml" # Define the compose file name

  if [ -f "$ENV_FILE" ]; then
    echo "✅ Found .env file. Using it for a clean shutdown..."
    docker compose -f "$DOCKER_COMPOSE_FILE" --env-file "$ENV_FILE" down
    echo "Docker stack stopped successfully."
  else
    echo "⚠️ .env file not found. Attempting a forceful removal of containers..."

    if ! command -v yq &> /dev/null; then
        echo -e "❌ ${RED}'yq' is not installed. Cannot parse container names for forceful removal.${NC}"
        echo "Please install yq (your start script can do this) or create an .env file manually."
        exit 1
    fi

    # Parse container names directly from the docker-compose file
    CONTAINER_NAMES=($(yq -r '.services | keys | .[]' "$DOCKER_COMPOSE_FILE"))

    if [ ${#CONTAINER_NAMES[@]} -gt 0 ]; then
        echo "Found containers to remove: ${CONTAINER_NAMES[*]}"
        docker rm -f "${CONTAINER_NAMES[@]}"
        echo "✅ All containers forcefully removed."
        echo "Note: Networks created by Docker Compose may still exist. Run 'docker network prune' to clean them up."
    else
        echo "Could not find any services defined in '$DOCKER_COMPOSE_FILE'."
    fi
  fi
fi


read -p "Delete the .env file with VPN credentials? [y/N]: " del_env
if [[ "$del_env" =~ ^[Yy]$ ]]; then
  rm -f "$ENV_FILE"
  echo ".env file deleted."
fi

read -p "Delete all container config folders (all configuration will be lost!)? [y/N]: " del_configs
if [[ "$del_configs" =~ ^[Yy]$ ]]; then
  # rm -rf "$CONFIG_DIR"/{gluetun,qbittorrent,sonarr,radarr,jackett,filebrowser}
  rm -rf "$CONFIG_ROOT"
  echo "Config folders deleted."
fi

echo "Removal complete."

