#!/bin/bash
# Script to fix qBittorrent paths/permissions WITHOUT touching the password.

# --- Style & Color Configuration ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Script Configuration ---
CONTAINER_NAME="qbittorrent"
CONFIG_FILE="$HOME/.config/media-stack/qbittorrent/qBittorrent/config/qBittorrent.conf"

# --- Host Paths (Where files live on your computer) ---
HOST_DATA_ROOT="$HOME/Downloads"
HOST_MEDIA_LIBRARY_PATH="$HOST_DATA_ROOT/media-library"
HOST_TEMP_DOWNLOAD_PATH="$HOST_MEDIA_LIBRARY_PATH/0-downloading"
HOST_INCOMPLETE_TORRENTS_PATH="$HOST_MEDIA_LIBRARY_PATH/0-torrents-incomplete"
HOST_COMPLETE_TORRENTS_PATH="$HOST_MEDIA_LIBRARY_PATH/0-torrents-complete"

# --- Container Paths (Where qBittorrent thinks files live) ---
CONTAINER_MEDIA_LIBRARY_PATH="/data/media-library"
CONTAINER_TEMP_DOWNLOAD_PATH="/data/media-library/0-downloading"
CONTAINER_INCOMPLETE_TORRENTS_PATH="/data/media-library/0-torrents-incomplete"
CONTAINER_COMPLETE_TORRENTS_PATH="/data/media-library/0-torrents-complete"

set -e # Exit immediately on error

# --- Helper Function ---
update_or_add_setting() {
    local section=$1
    local key=$2
    local value=$3
    local full_line="$key=$value"
    local escaped_key=$(echo "$key" | sed 's/\\/\\\\/g')
    local escaped_line=$(echo "$full_line" | sed 's/\\/\\\\/g; s/\//\\\//g')

    echo "     - Setting '$key' to '$value'..."
    if grep -q "^$escaped_key=" "$CONFIG_FILE"; then
        sed -i "s#^$escaped_key=.*#$escaped_line#" "$CONFIG_FILE"
    else
        sed -i "/^\[$section\]/a $escaped_line" "$CONFIG_FILE"
    fi
}

# --- Execution ---
echo -e "${BLUE}--- Fixing qBittorrent Paths & Permissions ---${NC}"

# 1. Checks
echo "1. Checking environment..."
if [ ! -f "$CONFIG_FILE" ]; then echo -e "${RED}Error: Config not found at $CONFIG_FILE${NC}"; exit 1; fi
source .env 2>/dev/null || { echo -e "${RED}Error: .env file missing.${NC}"; exit 1; }

# 2. Host Directories
echo "2. creating host directories and setting permissions..."
if [ -z "$HOST_MEDIA_LIBRARY_PATH" ]; then echo "Error: Variables empty."; exit 1; fi

mkdir -p "$HOST_MEDIA_LIBRARY_PATH" "$HOST_TEMP_DOWNLOAD_PATH" "$HOST_INCOMPLETE_TORRENTS_PATH" "$HOST_COMPLETE_TORRENTS_PATH" "$HOST_MEDIA_LIBRARY_PATH/movies" "$HOST_MEDIA_LIBRARY_PATH/tv"

echo "    - Setting ownership to $PUID:$PGID..."
sudo chown -R "$PUID:$PGID" "$HOST_DATA_ROOT"

# 3. Stop Container
echo "3. Stopping container to modify config..."
docker compose stop "$CONTAINER_NAME"

# 4. Modify Config (Paths Only)
echo "4. Updating configuration file..."
# Set the specific download paths
update_or_add_setting "Preferences" "Downloads\\DefaultSavePath" "$CONTAINER_MEDIA_LIBRARY_PATH"
update_or_add_setting "BitTorrent" "Session\\DefaultSavePath" "$CONTAINER_MEDIA_LIBRARY_PATH"
update_or_add_setting "BitTorrent" "Session\\TempPath" "$CONTAINER_TEMP_DOWNLOAD_PATH"
update_or_add_setting "BitTorrent" "Session\\TorrentExportDirectory" "$CONTAINER_INCOMPLETE_TORRENTS_PATH"
update_or_add_setting "BitTorrent" "Session\\FinishedTorrentExportDirectory" "$CONTAINER_COMPLETE_TORRENTS_PATH"
update_or_add_setting "BitTorrent" "Session\\TempPathEnabled" "true"

# Clean up old/conflicting lines
sed -i "/^DownloadsDefaultSavePath=/d" "$CONFIG_FILE"

# 5. Start Container
echo "5. Starting container..."
docker compose start "$CONTAINER_NAME"

# --- THE EXPLAINER ---
echo -e "\n${GREEN}✅ Success! Folder paths and permissions are fixed.${NC}"
echo -e "${YELLOW}-------------------------------------------------------${NC}"
echo -e "${YELLOW}               HOW TO FIX THE LOGIN PERMANENTLY        ${NC}"
echo -e "${YELLOW}-------------------------------------------------------${NC}"
echo -e "Since we didn't touch the password, qBittorrent generated a random one."
echo -e "Follow these steps to set it permanently:"
echo -e ""
echo -e "1. Run this command to see the temporary password:"
echo -e "   ${GREEN}docker exec -it $CONTAINER_NAME grep -i \"temporary password\" /config/supervisord.log${NC}"
echo -e ""
echo -e "2. Log in at: ${BLUE}http://localhost:8080${NC}"
echo -e "   Username: ${BLUE}admin${NC}"
echo -e "   Password: ${BLUE}(The code you found in step 1)${NC}"
echo -e ""
echo -e "3. Once logged in, go to: ${BLUE}Tools -> Options -> Web UI${NC}"
echo -e "4. Change the password to 'password' (or whatever you like) and click Save."
echo -e ""
echo -e "🎉 Because we fixed the paths, this setting will now stay saved forever!"
