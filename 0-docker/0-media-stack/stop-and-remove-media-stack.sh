#!/bin/bash
# Author: Roy Wiseman 2025-04

RED='\e[0;31m'
GREEN='\e[0;32m' # For the success message later on
NC='\033[0m'

set -e

# --- Default variables ---
CONFIG_ROOT="$HOME/.config/media-stack"
BASE_MEDIA="/mnt/media"
ENV_FILE=".env"
DOCKER_COMPOSE_FILE="docker-compose.yaml"

# Docker installation and status check (no changes)
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

# Informational messages (no changes)
echo "docker compose down will stop all containers defined in the ${DOCKER_COMPOSE_FILE} file."
echo "It will then remove the containers and their associated networks."
echo "Note: By default, named volumes are NOT removed to prevent data loss."

read -p "Stop and remove the containers (docker compose down) [y/N]: " del_env
if [[ "$del_env" =~ ^[Yy]$ ]]; then

  # --- NEW: Check if the stack is running before trying to stop it ---
  if [ -z "$(docker compose -f "$DOCKER_COMPOSE_FILE" ps -q 2>/dev/null)" ]; then
    echo -e "${GREEN}✅ Docker stack is already down. No containers to remove.${NC}"
  else
    # --- Stack is running, so proceed with a safe shutdown ---
    echo "Stack is running. Preparing for shutdown..."
    
    # Source the .env file if it exists to load its variables
    if [ -f "$ENV_FILE" ]; then
      echo "✅ Found .env file. Sourcing variables from it..."
      export $(grep -v '^#' "$ENV_FILE" | xargs)
    else
      echo "⚠️ .env file not found."
    fi

    # --- NEW: Set defaults for all common variables if they aren't set ---
    export CONFIG_PATH="${CONFIG_PATH:-$CONFIG_ROOT}"
    export MEDIA_PATH="${MEDIA_PATH:-$BASE_MEDIA}"
    export PUID="${PUID:-$(id -u)}"
    export PGID="${PGID:-$(id -g)}"
    export TZ="${TZ:-Etc/UTC}"

    echo "Attempting to stop the stack..."
    docker compose -f "$DOCKER_COMPOSE_FILE" down
    echo "✅ Docker stack stopped successfully."
  fi
fi

# Cleanup questions (no changes)
read -p "Delete the .env file? [y/N]: " del_env_file
if [[ "$del_env_file" =~ ^[Yy]$ ]]; then
  rm -f "$ENV_FILE"
  echo ".env file deleted."
fi

read -p "Delete all container config folders (all configuration will be lost!)? [y/N]: " del_configs
if [[ "$del_configs" =~ ^[Yy]$ ]]; then
  rm -rf "$CONFIG_ROOT"
  echo "Config folders deleted."
fi

echo "Removal complete."
