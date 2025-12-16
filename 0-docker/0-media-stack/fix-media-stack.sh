#!/bin/bash
# A definitive script to safely stop qBittorrent, set a fixed password,
# correctly configure all necessary download paths on the host, and restart the container.

# --- Style & Color Configuration ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Script Configuration ---
# --- STEP 1: VERIFY THESE SETTINGS ---

# The name of the qBittorrent container as defined in your docker-compose.yaml
CONTAINER_NAME="qbittorrent"

# The full path to the qBittorrent config file on the HOST machine.
CONFIG_FILE="$HOME/.config/media-stack/qbittorrent/qBittorrent/config/qBittorrent.conf"

# The FIXED WebUI password you want to use. qBittorrent stores the SHA-1 hash.
# The hash for the plain text "password" is:
FIXED_PASSWORD_HASH="@ByteArray(e3c23e800d922a6119f8dd0e17610444390623a9)"
NEW_PASSWORD_PLAINTEXT="password" # For display only

# This is the root directory on your HOST machine where your media is stored.
HOST_DATA_ROOT="$HOME/Downloads"

# The subdirectories on the HOST machine you want to use for the structured downloads.
HOST_MEDIA_LIBRARY_PATH="$HOST_DATA_ROOT/media-library"
HOST_TEMP_DOWNLOAD_PATH="$HOST_MEDIA_LIBRARY_PATH/0-downloading"
HOST_INCOMPLETE_TORRENTS_PATH="$HOST_MEDIA_LIBRARY_PATH/0-torrents-incomplete"
HOST_COMPLETE_TORRENTS_PATH="$HOST_MEDIA_LIBRARY_PATH/0-torrents-complete"

# --- These are the corresponding paths from the CONTAINER's perspective ---
CONTAINER_MEDIA_LIBRARY_PATH="/data/media-library"
CONTAINER_TEMP_DOWNLOAD_PATH="/data/media-library/0-downloading"
CONTAINER_INCOMPLETE_TORRENTS_PATH="/data/media-library/0-torrents-incomplete"
CONTAINER_COMPLETE_TORRENTS_PATH="/data/media-library/0-torrents-complete"
# --- END OF CONFIGURATION ---

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper Function for Config Modification ---
update_or_add_setting() {
    local section=$1
    local key=$2
    local value=$3
    local full_line="$key=$value"
    local escaped_key_for_grep=$(echo "$key" | sed 's/\\/\\\\/g')
    # Escape slashes and backslashes for sed substitution
    local escaped_line_for_sed=$(echo "$full_line" | sed 's/\\/\\\\/g; s/\//\\\//g')

    echo "     - Ensuring '$key' is set..."
    if grep -q "^$escaped_key_for_grep=" "$CONFIG_FILE"; then
        # Found, so substitute the line
        sed -i "s#^$escaped_key_for_grep=.*#$escaped_line_for_sed#" "$CONFIG_FILE"
    else
        # Not found, so add it under the correct section
        sed -i "/^\[$section\]/a $escaped_line_for_sed" "$CONFIG_FILE"
    fi
}

# --- Main Script ---
echo -e "${BLUE}--- Safely Updating qBittorrent Configuration and Setting Fixed Password ---${NC}"

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
    echo -e "    ${RED}Error: Container '$CONTAINER_NAME' is not running. Starting it first...${NC}"
    docker compose start "$CONTAINER_NAME"
    sleep 5 # Give it a moment to stabilize
fi
echo -e "    ${GREEN}✓ All checks passed. Container is running.${NC}"

# 2. Prepare Host Directories and Set Permissions
echo "2. Preparing host directories and setting permissions..."

# Debug check to ensure variables aren't empty
if [ -z "$HOST_MEDIA_LIBRARY_PATH" ]; then
    echo -e "${RED}CRITICAL ERROR: Variables failed to load. Please check script formatting.${NC}"
    exit 1
fi

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

# 4. Modify Configuration File (Password and Paths)
echo "4. Modifying config file directly on the host..."

# --- 4a. Path Fix ---
echo -e "${YELLOW}--- Fixing Paths to use $HOST_MEDIA_LIBRARY_PATH ---${NC}"
update_or_add_setting "Preferences" "Downloads\\DefaultSavePath" "$CONTAINER_MEDIA_LIBRARY_PATH"
update_or_add_setting "BitTorrent" "Session\\DefaultSavePath" "$CONTAINER_MEDIA_LIBRARY_PATH"
update_or_add_setting "BitTorrent" "Session\\TempPath" "$CONTAINER_TEMP_DOWNLOAD_PATH"
update_or_add_setting "BitTorrent" "Session\\TorrentExportDirectory" "$CONTAINER_INCOMPLETE_TORRENTS_PATH"
update_or_add_setting "BitTorrent" "Session\\FinishedTorrentExportDirectory" "$CONTAINER_COMPLETE_TORRENTS_PATH"
update_or_add_setting "BitTorrent" "Session\\TempPathEnabled" "true"

# Cleanup old incorrect settings
sed -i "/^DownloadsDefaultSavePath=/d" "$CONFIG_FILE"

# --- 4b. Password Fix ---
echo -e "${YELLOW}--- Setting Fixed Password to: $NEW_PASSWORD_PLAINTEXT ---${NC}"
update_or_add_setting "WebUI" "Password" "$FIXED_PASSWORD_HASH"
update_or_add_setting "WebUI" "UseUPnP" "false"
update_or_add_setting "WebUI" "Port" "8080"
update_or_add_setting "WebUI" "Host" "0.0.0.0"

echo -e "    ${GREEN}✓ Configuration file updated.${NC}"

# 5. Restart Container
echo "5. Starting container '$CONTAINER_NAME'..."
docker compose start "$CONTAINER_NAME"

echo -e "\n${GREEN}✅ Configuration, Paths, and Fixed Password applied successfully.${NC}"
echo -e "🔒 Your new **fixed password** for the WebUI (http://localhost:8080) is: **${NEW_PASSWORD_PLAINTEXT}**"
