#!/bin/bash
# A script to forcefully set the correct download path inside the running container.

# --- Configuration and Colors ---
GREEN='\e[0;32m'
BLUE='\e[0;34m'
YELLOW='\e[1;33m'
NC='\033[0m'

set -e

CONTAINER_NAME=$(yq -r '.services.*.container_name' docker-compose.yaml)

echo -e "${BLUE}--- Forcefully Setting Save Path for Container: $CONTAINER_NAME ---${NC}"

echo "1. Terminating qBittorrent process inside the container..."
docker exec "$CONTAINER_NAME" pkill -f "qbittorrent-nox" || true
sleep 3 # Give it a moment to terminate and for the config file to be writable

echo "2. Modifying config file (brute force method)..."
# This entire command block is wrapped in single quotes to pass it literally.
docker exec "$CONTAINER_NAME" /bin/bash -c '
CONF_FILE="/config/qBittorrent/config/qBittorrent.conf"

# Step 1: Forcefully replace any existing line. The double backslash is needed for sed.
# This command does nothing if the line does not exist.
echo "--> Attempting to replace existing save path..."
sed -i "s#^Downloads\\\\DefaultSavePath=.*#Downloads\\\\DefaultSavePath=/data/downloads#" "$CONF_FILE"

# Step 2: Verify the line now exists correctly. If not, add it.
# We use grep -F for a literal, non-regex search. A single backslash is correct here.
if ! grep -Fq "Downloads\DefaultSavePath=/data/downloads" "$CONF_FILE"; then
    echo "--> Save path key was not found or not set correctly, adding it..."
    # Add the line after the [Preferences] header. Double backslash for sed to write correctly.
    sed -i "/^\[Preferences\]/a Downloads\\\\DefaultSavePath=/data/downloads" "$CONF_FILE"
else
    echo "--> Save path is now correctly configured."
fi
'

echo -e "\n${YELLOW}Change applied. The container's watchdog will automatically restart the qBittorrent process.${NC}"
echo -e "${GREEN}✅ Please refresh the Web UI in about 15-30 seconds to see the change.${NC}"


