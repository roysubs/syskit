#!/bin/bash
# Author: Roy Wiseman 2025-01

CURRENT_USER=${SUDO_USER:-$(whoami)}

if ! command -v ffmpeg &>/dev/null; then
    echo "ffmpeg is not installed. Installing..."
    sudo apt update && sudo apt install -y ffmpeg
fi

LATEST_VERSION=$(curl -s https://api.github.com/repos/navidrome/navidrome/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | sed 's/v//')
DOWNLOAD_URL="https://github.com/navidrome/navidrome/releases/download/v${LATEST_VERSION}/navidrome_${LATEST_VERSION}_linux_amd64.deb"
echo "DOWNLOAD_URL: $DOWNLOAD_URL"
echo "Downloading Navidrome $LATEST_VERSION..."
wget -O /tmp/navidrome.deb "$DOWNLOAD_URL"

echo "Installing Navidrome..."
sudo dpkg -i /tmp/navidrome.deb

# Modify configuration file
CONFIG_FILE="/etc/navidrome/navidrome.toml"
MUSIC_DIR="/srv/music"
DATA_DIR="/srv/navidrome"

sudo mkdir -p "$MUSIC_DIR" "$DATA_DIR"
sudo chown -R "$CURRENT_USER:$CURRENT_USER" "$MUSIC_DIR" "$DATA_DIR"
sudo chmod 777 "$MUSIC_DIR" "$DATA_DIR"

sudo sed -i "s|^MusicFolder = .*|MusicFolder = '$MUSIC_DIR'|" "$CONFIG_FILE"
sudo sed -i "s|^DataFolder = .*|DataFolder = '$DATA_DIR'|" "$CONFIG_FILE"

# Start the service
sudo systemctl restart navidrome
sleep 2  # Give it a moment to start

# Show service status
echo "\nNavidrome Service Status:"
sudo systemctl status navidrome --no-pager

# Display connection info
IP=$(hostname -I | awk '{print $1}')
PORT=4533

echo "Navidrome is running!"
echo "Access it at: http://$IP:$PORT"

echo "Important Locations:"
echo "  - Config File: $CONFIG_FILE"
echo "  - Music Folder: $MUSIC_DIR"
echo "  - Data Folder: $DATA_DIR"
echo "  - Logs: /var/log/navidrome.log"
echo
echo "Quick Start Guide:"
echo "1. Upload music to $MUSIC_DIR"
echo "   Example: scp -r my-music-folder user@$IP:$MUSIC_DIR"
echo "2. Add Podcasts: Go to Settings > Podcasts > Add Podcast URL"
echo "3. Add Radio Stations: Go to Settings > Radio and input the stream URL"
echo
echo "Troubleshooting:"
echo "- Check logs: sudo journalctl -u navidrome --no-pager | tail -50"
echo "- Restart service: sudo systemctl restart navidrome"
echo "- Ensure firewall allows port $PORT: sudo ufw allow $PORT/tcp"
echo "- Check running processes: ps aux | grep navidrome"

echo "\nInstallation complete! Enjoy your music with Navidrome!"

