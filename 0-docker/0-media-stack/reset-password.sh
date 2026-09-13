<<<<<<< Updated upstream
#!/usr/bin/env bash
# Script to wipe qBittorrent password and retrieve the temporary one

=======
#!/bin/bash
>>>>>>> Stashed changes
CONTAINER_NAME="qbittorrent"
CONFIG_FILE="$HOME/.config/media-stack/qbittorrent/qBittorrent/config/qBittorrent.conf"

echo "--- Resetting qBittorrent Password ---"

echo "1. Stopping container..."
docker compose stop "$CONTAINER_NAME"

echo "2. Wiping old password settings from config..."
if [ ! -w "$CONFIG_FILE" ]; then
    echo "⚠️  No write permission on $CONFIG_FILE — trying with sudo"
    sudo sed -i '/^WebUI\\Password/d' "$CONFIG_FILE"
else
    sed -i '/^WebUI\\Password/d' "$CONFIG_FILE"
fi

# Verify it actually got removed
if grep -q "^WebUI\\\\Password" "$CONFIG_FILE"; then
    echo "❌ Password line still present — the edit failed. Aborting."
    exit 1
fi

echo "3. Starting container..."
docker compose start "$CONTAINER_NAME"

echo "4. Waiting for qBittorrent to generate a temporary password..."
PASSWORD=""
for i in {1..15}; do
    sleep 2
    PASSWORD=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -iA 1 "temporary password" | tail -n 1)
    [ -n "$PASSWORD" ] && break
done

echo -e "\n--- 🔑 YOUR TEMPORARY PASSWORD ---"
if [ -n "$PASSWORD" ]; then
    echo "$PASSWORD"
else
    echo "❌ Not found in logs. Dumping recent logs for manual inspection:"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -n 40
fi
echo -e "----------------------------------\n"
