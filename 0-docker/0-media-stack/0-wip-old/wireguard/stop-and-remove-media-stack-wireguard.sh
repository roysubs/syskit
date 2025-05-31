#!/bin/bash
# Author: Roy Wiseman 2025-05

set -e

CONFIG_ROOT="$HOME/.config/media-stack"   # CONFIG_DIR="$(pwd)/config"
ENV_FILE=".env"
BASE_MEDIA="/mnt/media" # This is the mount point, seen by containers as the root of media

rm -rf ~/.config/media-stack

# Stop and remove containers
# docker rm -f wireguard qbittorrent sonarr radarr filebrowser jackett
docker compose -f docker-compose-wireguard.yaml down

read -p "Delete the .env file with VPN credentials? [y/N]: " del_env
if [[ "$del_env" =~ ^[Yy]$ ]]; then
  rm -f "$ENV_FILE"
  echo ".env file deleted."
fi

read -p "Delete all container config folders? [y/N]: " del_configs
if [[ "$del_configs" =~ ^[Yy]$ ]]; then
  # rm -rf "$CONFIG_DIR"/{gluetun,qbittorrent,sonarr,radarr,jackett,filebrowser}
  rm -rf "$CONFIG_ROOT"
  echo "Config folders deleted."
fi

# read -p "Delete media folders in $BASE_MEDIA? [y/N]: " del_media
# if [[ "$del_media" =~ ^[Yy]$ ]]; then
#   rm -rf "$BASE_MEDIA"/downloads "$BASE_MEDIA"/movies "$BASE_MEDIA"/tv
#   echo "Media folders deleted."
# fi

echo "Removal complete."

