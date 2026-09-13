#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-02

# Ensure email argument is provided

pkg_install() {
    if command -v apt &>/dev/null; then sudo DEBIAN_FRONTEND=noninteractive apt update -qq && sudo DEBIAN_FRONTEND=noninteractive apt install -y "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper install -y "$@"
    elif command -v dnf &>/dev/null; then sudo dnf install -y "$@"
    else echo "No supported package manager found (need apt/zypper/dnf)." >&2; exit 1
    fi
}

if [[ -z "$1" ]]; then
    echo "Usage: $0 your-email@gmail.com"
    exit 1
fi

EMAIL="$1"
MOUNT_POINT="$HOME/GoogleDrive"
CONFIG_NAME="gdrive"

# Install rclone if not installed
if ! command -v rclone &>/dev/null; then
    echo "Installing rclone..."
    sudo apt update
    pkg_install rclone
fi

# Configure rclone
echo "Starting rclone configuration for $EMAIL..."
rclone config create "$CONFIG_NAME" drive scope full config_is_local true

echo "Google Drive has been configured."
read -p "Press Enter to continue."

# Create mount directory
mkdir -p "$MOUNT_POINT"

# Create systemd service
SYSTEMD_SERVICE="$HOME/.config/systemd/user/rclone-gdrive.service"
mkdir -p "$(dirname "$SYSTEMD_SERVICE")"

cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Mount Google Drive using rclone
After=network-online.target

[Service]
ExecStart=/usr/bin/rclone mount --vfs-cache-mode writes "$CONFIG_NAME": "$MOUNT_POINT"
ExecStop=/bin/fusermount -u "$MOUNT_POINT"
Restart=always
User=$USER
Group=$USER

[Install]
WantedBy=default.target
EOF

# Enable and start the service
echo "Enabling Google Drive systemd service..."
systemctl --user enable rclone-gdrive
systemctl --user start rclone-gdrive

echo "Google Drive is now mounted at $MOUNT_POINT."
echo "It will mount automatically on login."

