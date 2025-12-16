#!/bin/bash
# A definitive script to safely stop qBittorrent, correctly configure all
# necessary download paths on the host, and restart the container.
# This refactored version centralizes path configuration and adds
# pre-flight checks and a critical permissions-setting step.

# --- Style & Color Configuration ---
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[1;33m'
RED='\e[0;31m'
NC='\033[0m' # No Color

# --- Script Configuration ---
# --- STEP 1: VERIFY THESE SETTINGS ---

# The name of the qBittorrent container as defined in your docker-compose.yaml
CONTAINER_NAME="qbittorrent"

# The full path to the qBittorrent config file on the HOST machine.
CONFIG_FILE="$HOME/.config/media-stack/qbittorrent/qBittorrent/config/qBittorrent.conf"

# This is the root directory on your HOST machine where your media is stored.
# IMPORTANT: This MUST match the MEDIA_PATH you set in the main start script.
HOST_DATA_ROOT="$HOME/Downloads" # <-- PLEASE VERIFY THIS PATH

# These are the subdirectories on the HOST the script will create.
HOST_MEDIA_LIBRARY_PATH="$HOST_DATA_ROOT/media-library"
HOST_TEMP_DOWNLOAD_PATH="$HOST_MEDIA_LIBRARY_PATH/0-downloading"
HOST_INCOMPLETE_TORRENTS_PATH="$HOST_MEDIA_LIBRARY_PATH/0-torrents-incomplete"
HOST_COMPLETE_TORRENTS_PATH="$HOST_MEDIA_LIBRARY_PATH/0-torrents-complete"

# These are the corresponding paths from the CONTAINER's perspective.
CONTAINER_MEDIA_LIBRARY_PATH="/data/media-library"
CONTAINER_TEMP_DOWNLOAD_PATH="/data/media-library/0-downloading"
CONTAINER_INCOMPLETE_TORRENTS_PATH="/data/media-library/0-torrents-incomplete"
CONTAINER_COMPLETE_TORRENTS_PATH="/data/media-library/0-torrents-complete"
# --- END OF CONFIGURATION ---

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper Function ---
update_or_add_setting() {
    local section=$1
    local key=$2
    local value=$3
    local full_line="$key=$value"
    local escaped_key_for_grep=$(echo "$key" | sed 's/\\/\\\\/g')
    local escaped_line_for_sed=$(echo "$full_line" | sed 's/\\/\\\\/g')
    echo "     - Ensuring '$key' is set to '$value'..."
    if grep -q "^$escaped_key_for_grep=" "$CONFIG_FILE"; then
        sed -i "s#^$escaped_key_for_grep=.*#$escaped_line_for_sed#" "$CONFIG_FILE"
    else
        sed -i "/^\[$section\]/a $escaped_line_for_sed" "$CONFIG_FILE"
    fi
}

# --- Main Script ---
echo -e "${BLUE}--- Safely Updating qBittorrent Configuration ---${NC}"

# 1. Pre-flight Checks
echo "1. Running pre-flight checks..."
if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "    ${RED}Error: Config file not found at: $CONFIG_FILE${NC}"
    exit 1
fi
if [ ! -f ".env" ]; then
    echo -e "    ${RED}Error: .env file not found. Please run the main start script first.${NC}"
    exit 1
fi
source .env # Load PUID and PGID from .env file
if ! docker ps --format '{{.Names}}' | grep -wq "$CONTAINER_NAME"; then
    echo -e "    ${RED}Error: Container '$CONTAINER_NAME' is not running.${NC}"
    exit 1
fi
echo -e "    ${GREEN}✓ All checks passed.${NC}"

# 2. Prepare Host Directories and Set Permissions
echo "2. Preparing host directories and setting permissions..."
mkdir -p \
    "$HOST_MEDIA_LIBRARY_PATH" \
    "$HOST_TEMP_DOWNLOAD_PATH" \
    "$HOST_INCOMPLETE_TORRENTS_PATH" \
    "$HOST_COMPLETE_TORRENTS_PATH"
echo "    - Setting ownership for user $PUID:$PGID on '$HOST_DATA_ROOT'..."
sudo chown -R "$PUID:$PGID" "$HOST_DATA_ROOT"
echo -e "    ${GREEN}✓ Host directories and permissions are ready.${NC}"

# 3. Stop Container
echo "3. Stopping container '$CONTAINER_NAME' to prevent config overwrites..."
docker compose stop "$CONTAINER_NAME"
sleep 3

# 4. Modify Configuration File
echo "4. Modifying config file directly on the host..."
update_or_add_setting "Preferences" "Downloads\\DefaultSavePath" "$CONTAINER_MEDIA_LIBRARY_PATH"
update_or_add_setting "BitTorrent" "Session\\DefaultSavePath" "$CONTAINER_MEDIA_LIBRARY_PATH"
update_or_add_setting "BitTorrent" "Session\\TempPath" "$CONTAINER_TEMP_DOWNLOAD_PATH"
update_or_add_setting "BitTorrent" "Session\\TorrentExportDirectory" "$CONTAINER_INCOMPLETE_TORRENTS_PATH"
update_or_add_setting "BitTorrent" "Session\\FinishedTorrentExportDirectory" "$CONTAINER_COMPLETE_TORRENTS_PATH"
update_or_add_setting "BitTorrent" "Session\\TempPathEnabled" "true"
echo -e "    - ${YELLOW}Cleaning up old incorrect settings...${NC}"
sed -i "/^DownloadsDefaultSavePath=/d" "$CONFIG_FILE"

# 5. Restart Container
echo "5. Starting container '$CONTAINER_NAME'..."
docker compose start "$CONTAINER_NAME"

echo -e "\n${GREEN}✅ Configuration and permissions applied successfully.${NC}"
echo -e "${YELLOW}The container has been restarted and is now using the correct settings.${NC}"

