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
  docker compose -f docker-compose.yaml down
  echo "docker media stack has been stopped."
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

