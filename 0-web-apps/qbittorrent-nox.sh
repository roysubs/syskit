#!/bin/bash
# Author: Roy Wiseman 2025-02

# Check if qBittorrent-nox is installed
if ! command -v qbittorrent-nox &> /dev/null; then
    echo "qBittorrent-nox is not installed. Installing..."
    sudo apt update
    sudo apt install -y qbittorrent-nox
else
    echo "qBittorrent-nox is already installed."
fi

# Create a config directory if it doesn't exist
CONFIG_DIR="$HOME/.config/qBittorrent"
if [ ! -d "$CONFIG_DIR" ]; then
    mkdir -p "$CONFIG_DIR"
    echo "Config directory created at $CONFIG_DIR"
fi

# Create a config file for qBittorrent-nox (first-time setup)
if [ ! -f "$CONFIG_DIR/qBittorrent.conf" ]; then
    echo "Setting up first-time configuration for qBittorrent-nox..."
    cat <<EOL > "$CONFIG_DIR/qBittorrent.conf"
[General]
WebUI\Enabled=true
WebUI\Port=8080  # Port for the web interface
WebUI\Host=0.0.0.0  # Allow all hosts to access it remotely
WebUI\Username=admin
WebUI\Password=adminadmin  # Change the password to something secure after first use
SavePath=$HOME/Torrents
EOL
    echo "First-time configuration file created at $CONFIG_DIR/qBittorrent.conf"
else
    echo "qBittorrent configuration already exists."
fi

# Set up cron job to start qBittorrent-nox on boot
if ! crontab -l | grep -q "@reboot /usr/bin/qbittorrent-nox"; then
    echo "Setting up cron job to start qBittorrent-nox on boot..."
    (crontab -l 2>/dev/null; echo "@reboot /usr/bin/qbittorrent-nox > /dev/null 2>&1 &") | crontab -
    echo "Cron job to start qBittorrent-nox on boot is set up."
else
    echo "Cron job for qBittorrent-nox already exists."
fi

# Check if UFW is installed and configure firewall
if command -v ufw &> /dev/null; then
    echo "UFW is installed. Opening port 8080 for web UI access..."
    sudo ufw allow 8080
    sudo ufw reload
    echo "Port 8080 opened for web UI access."
else
    echo "UFW is not installed. Skipping firewall configuration."
fi

# Start qBittorrent-nox manually if not running
if ! pgrep -x "qbittorrent-nox" > /dev/null; then
    echo "Starting qBittorrent-nox manually..."
    nohup qbittorrent-nox > /dev/null 2>&1 &
    echo "qBittorrent-nox started manually."
else
    echo "qBittorrent-nox is already running."
fi

# Display Web UI and console usage tips
echo
echo "qBittorrent-nox setup completed!"
echo "Web UI is accessible at http://<your_ip>:8080"
echo "  Username: admin"
echo "  Password: adminadmin (please change after first login)"
echo
echo "Console usage tips:"
echo "- To add a magnet link: qbittorrent-nox --add-magnet '<magnet_link>'"
echo "- To add a .torrent file: qbittorrent-nox <file.torrent>"
echo
echo "To view/kill/restart the process:"
echo "pgrep -a qbittorrent            # process-grep"
echo "ps aux | grep qbittorrent-nox   # check qbittorrent-nox process"
echo "killall qbittorrent-nox"
echo "kill -9 qbittorrent-nox"
echo
echo "qBittorrent-nox is now set up and ready for use!"

