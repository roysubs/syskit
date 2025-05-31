#!/bin/bash
# Author: Roy Wiseman 2025-01

# Path to qBittorrent configuration file (adjust if needed)
CONFIG="$HOME/.config/qBittorrent/qBittorrent.conf"
BACKUP_CONFIG="${CONFIG}.$(date +%Y%m%d-%H%M%S)"

# Paths
TorrentExportDirectory="/mnt/sdc1/Downloads/0-torrents-incomplete"  # Where .torrent files are created when adding a magnet link
TempPath="/mnt/sdc1/Downloads/0-files-incomplete"  # Where incomplete files are stored while downloading
SavePath="/mnt/sdc1/Downloads"  # Where completed downloads are moved
FinishedTorrentExportDirectory="/mnt/sdc1/Downloads/0-torrents-complete"  # Where completed .torrent files are moved

# Parameters
Port=9147  # Listening port for incoming connections (6881)
UploadRateLimit=500  # Upload speed limit in KiB/s (0 = unlimited)
DownloadRateLimit=0  # Download speed limit in KiB/s (0 = unlimited)
MaxConnections=500  # Maximum number of connections
MaxActiveTorrents=50  # Maximum number of active torrents
RatioLimit=2.0  # Seeding ratio limit (0 = unlimited)

# Backup existing config
cp "$CONFIG" "$BACKUP_CONFIG"

# Ensure qBittorrent is not running before modifying the config
pkill -e -x qbittorrent 2>/dev/null

# Read current settings
Current_TorrentExportDirectory=$(grep -Po '(?<=Session\\TorrentExportDirectory=)[^\n]+' "$CONFIG" || echo "Not set")
Current_TempPath=$(grep -Po '(?<=Session\\TempPath=)[^\n]+' "$CONFIG" || echo "Not set")
Current_SavePath=$(grep -Po '(?<=Downloads\\SavePath=)[^\n]+' "$CONFIG" || echo "Not set")
Current_FinishedTorrentExportDirectory=$(grep -Po '(?<=Session\\FinishedTorrentExportDirectory=)[^\n]+' "$CONFIG" || echo "Not set")
Current_Port=$(grep -Po '(?<=Session\\Port=)[^\n]+' "$CONFIG" || echo "Not set")
Current_UploadRateLimit=$(grep -Po '(?<=Session\\UploadRateLimit=)[^\n]+' "$CONFIG" || echo "Not set")
Current_DownloadRateLimit=$(grep -Po '(?<=Session\\DownloadRateLimit=)[^\n]+' "$CONFIG" || echo "Not set")
Current_MaxConnections=$(grep -Po '(?<=Session\\MaxConnections=)[^\n]+' "$CONFIG" || echo "Not set")
Current_MaxActiveTorrents=$(grep -Po '(?<=Session\\MaxActiveTorrents=)[^\n]+' "$CONFIG" || echo "Not set")
Current_RatioLimit=$(grep -Po '(?<=Session\\RatioLimit=)[^\n]+' "$CONFIG" || echo "Not set")

# Display proposed changes
echo "The following changes will be made (current settings => new settings):"
echo
echo "TorrentExportDirectory:"
echo "   $Current_TorrentExportDirectory => $TorrentExportDirectory"
echo "TempPath:"
echo "   $Current_TempPath => $TempPath"
echo "SavePath:"
echo "   $Current_SavePath => $SavePath"
echo "FinishedTorrentExportDirectory:"
echo "   $Current_FinishedTorrentExportDirectory => $FinishedTorrentExportDirectory"
echo
echo "Port: $Current_Port => $Port"
echo "UploadRateLimit: $Current_UploadRateLimit => $UploadRateLimit"
echo "DownloadRateLimit: $Current_DownloadRateLimit => $DownloadRateLimit"
echo "MaxConnections: $Current_MaxConnections => $MaxConnections"
echo "MaxActiveTorrents: $Current_MaxActiveTorrents => $MaxActiveTorrents"
echo "RatioLimit: $Current_RatioLimit => $RatioLimit"
echo
echo "Do you want to make these changes? (y/N)"
read -r CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "No changes made. Exiting."
    exit 1
fi

# Modify the configuration file
update_qbittorrent_conf() {
    local section="$1"
    local key="$2"
    local value="$3"
    local config_file="$HOME/.config/qBittorrent/qBittorrent.conf"

    # Escape slashes for sed
    local escaped_key=$(echo "$key" | sed 's|\\|\\\\|g')
    local escaped_value=$(echo "$value" | sed 's|/|\\/|g')

    # Check if the key exists in the correct section
    if grep -qE "^\[$section\]" "$config_file"; then
        if grep -qE "^${escaped_key}=" "$config_file"; then
            # Modify the existing key-value pair
            sed -i "/^\[$section\]/,/^\[/ s|^${escaped_key}=.*|${escaped_key}=${escaped_value}|" "$config_file"
        else
            # Append the new key-value pair inside the section
            sed -i "/^\[$section\]/a ${escaped_key}=${escaped_value}" "$config_file"
        fi
    else
        # If the section doesn't exist, append it at the end of the file
        echo -e "\n[$section]\n${escaped_key}=${escaped_value}" >> "$config_file"
    fi
}
update_qbittorrent_conf "BitTorrent" "Session\\DefaultSavePath" "/mnt/sdc1/Downloads"
update_qbittorrent_conf "BitTorrent" "Session\\FinishedTorrentExportDirectory" "/mnt/sdc1/Downloads/0-torrents-complete"
update_qbittorrent_conf "BitTorrent" "Session\\Port" "9147"
update_qbittorrent_conf "BitTorrent" "Session\\QueueingSystemEnabled" "false"
update_qbittorrent_conf "BitTorrent" "Session\\TempPath" "/mnt/sdc1/Downloads/0-files-incomplete"
update_qbittorrent_conf "BitTorrent" "Session\\TempPathEnabled" "true"
update_qbittorrent_conf "BitTorrent" "Session\\TorrentExportDirectory" "/mnt/sdc1/Downloads/0-torrents-incomplete"
update_qbittorrent_conf "BitTorrent" "Session\\UploadRateLimit" "500"
update_qbittorrent_conf "BitTorrent" "Session\\DownloadRateLimit" "0"
update_qbittorrent_conf "BitTorrent" "Session\\MaxConnections" "500"
update_qbittorrent_conf "BitTorrent" "Session\\MaxActiveTorrents" "50"
update_qbittorrent_conf "BitTorrent" "Session\\RatioLimit" "2.0"
# Some other settings:
# [General]
# Preferences\UseCustomUITheme=false
# Preferences\CustomUIThemePath=
# WebUI\Enabled=true
# WebUI\Port=8080

# Restart qBittorrent:
# qbittorrent-nox &   # Starts qBittorrent in the background.
# disown              # Detaches qBittorrent from the current terminal session
# This ensures that it won’t be killed when the terminal is closed. Very useful for long-running
# processes that you want to continue after the shell session ends.
qbittorrent-nox & disown
# sudo nohup qbittorrent-nox > /dev/null 2>&1 &
# sudo nohup qbittorrent-nox --profile=/home/boss/.config/qBittorrent > /dev/null 2>&1 &

# Ask if user wants to move files
echo "Would you like to move all files (recursively) from the old locations to the new locations? (y/N)"
read -r MOVE_CONFIRM
if [[ "$MOVE_CONFIRM" == "y" ]]; then
    echo "Moving files..."
    mkdir -p "$TorrentExportDirectory" "$TempPath" "$SavePath" "$FinishedTorrentExportDirectory"
    shopt -s nullglob
    [[ -d "$Current_TorrentExportDirectory" ]] && mv "$Current_TorrentExportDirectory"/* "$TorrentExportDirectory" 2>/dev/null
    [[ -d "$Current_TempPath" ]] && mv "$Current_TempPath"/* "$TempPath" 2>/dev/null
    [[ -d "$Current_SavePath" ]] && mv "$Current_SavePath"/* "$SavePath" 2>/dev/null
    [[ -d "$Current_FinishedTorrentExportDirectory" ]] && mv "$Current_FinishedTorrentExportDirectory"/* "$FinishedTorrentExportDirectory" 2>/dev/null
    shopt -u nullglob
    echo "File move complete."
else
    echo "Files not moved."
fi
