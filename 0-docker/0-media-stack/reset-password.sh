#!/bin/bash
# Script to wipe qBittorrent password and retrieve the temporary one

CONTAINER_NAME="qbittorrent"
CONFIG_FILE="$HOME/.config/media-stack/qbittorrent/qBittorrent/config/qBittorrent.conf"

echo "--- Resetting qBittorrent Password ---"

# 1. Stop the container to safely edit the file
echo "1. Stopping container..."
docker compose stop "$CONTAINER_NAME"

# 2. Wipe the password lines (both legacy and new formats)
echo "2. Wiping old password settings from config..."
# Removes lines starting with WebUI\Password= or WebUI\Password_PBKDF2=
sed -i '/^WebUI\\Password/d' "$CONFIG_FILE"

# 3. Start the container
echo "3. Starting container..."
docker compose start "$CONTAINER_NAME"

# 4. Wait for the logs to generate the password
echo "4. Waiting 10 seconds for qBittorrent to generate a temporary password..."
sleep 10

# 5. Extract the password from the logs
echo -e "\n--- 🔑 YOUR TEMPORARY PASSWORD ---"
# We look for the specific line in the logs
docker logs "$CONTAINER_NAME" 2>&1 | grep -A 1 "temporary password" | tail -n 1
echo -e "----------------------------------\n"

echo "👉 ACTION REQUIRED:"
echo "1. Go to http://localhost:8080"
echo "2. Login with Username: admin"
echo "3. Password: (Use the random code shown above)"
echo "4. Go to Tools > Options > Web UI and change the password to 'password' immediately."
echo "   (Since your config file is now fixed on the host, this change will stick forever!)"
