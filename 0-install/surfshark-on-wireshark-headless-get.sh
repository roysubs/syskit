#!/usr/bin/env bash
# Author: Roy Wiseman 2025-02
set -euo pipefail

# =============== CONFIGURATION ================
CONFIG_DIR="$HOME/.config/surfshark"
WG_CONF="$CONFIG_DIR/wg0.conf"
WG_INTERFACE="wg0"
ENDPOINT_NAME="Norway"
ENDPOINT_INDEX=80  # Norway #80
HELPERS_FILE="$HOME/.local/bin/vpn-helpers.sh"
SYSTEMD_SERVICE="surfshark-wireguard"
# ==============================================

# Ensure required directories
mkdir -p "$CONFIG_DIR" "$HOME/.local/bin"

# Install WireGuard and curl if needed
echo "🔧 Installing dependencies..."
sudo apt-get update -qq
sudo apt-get install -y wireguard curl unzip

# Prompt for credentials if not already saved
CRED_FILE="$CONFIG_DIR/credentials"
if [[ ! -f "$CRED_FILE" ]]; then
  echo "🔐 Enter your Surfshark credentials."
  read -rp "Username: " USERNAME
  read -rsp "Password: " PASSWORD
  echo
  echo "Storing credentials..."
  echo "USER=$USERNAME" > "$CRED_FILE"
  echo "PASS=$PASSWORD" >> "$CRED_FILE"
  chmod 600 "$CRED_FILE"
else
  source "$CRED_FILE"
fi

# Download the WireGuard config zip and extract Norway #80
if [[ ! -f "$WG_CONF" ]]; then
  echo "🌍 Fetching Surfshark WireGuard config for $ENDPOINT_NAME #$ENDPOINT_INDEX..."
  TMPDIR=$(mktemp -d)
  pushd "$TMPDIR" >/dev/null
  curl -u "$USER:$PASS" -O https://my.surfshark.com/vpn/api/v1/server/configurations
  unzip configurations
  CONF_FILE=$(find . -iname "*$ENDPOINT_NAME*.conf" | sort | sed -n "${ENDPOINT_INDEX}p")
  if [[ -z "$CONF_FILE" ]]; then
    echo "❌ Could not find $ENDPOINT_NAME #$ENDPOINT_INDEX in the config list."
    exit 1
  fi
  mv "$CONF_FILE" "$WG_CONF"
  chmod 600 "$WG_CONF"
  popd >/dev/null
  rm -rf "$TMPDIR"
  echo "✅ WireGuard config saved to $WG_CONF"
fi

# Create systemd service
echo "⚙️ Setting up systemd service: $SYSTEMD_SERVICE"
sudo tee "/etc/systemd/system/$SYSTEMD_SERVICE.service" >/dev/null <<EOF
[Unit]
Description=Surfshark VPN via WireGuard
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/wg-quick up $WG_CONF
ExecStop=/usr/bin/wg-quick down $WG_CONF
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable --now "$SYSTEMD_SERVICE"

# Add helper commands
cat > "$HELPERS_FILE" <<'EOS'
#!/usr/bin/env bash
WG_CONF="$HOME/.config/surfshark/wg0.conf"
SERVICE=surfshark-wireguard

vpn-start()   { sudo systemctl start "$SERVICE"; }
vpn-stop()    { sudo systemctl stop "$SERVICE"; }
vpn-status()  { sudo systemctl status "$SERVICE"; }
vpn-restart() { sudo systemctl restart "$SERVICE"; }
vpn-change() {
  echo "🧭 To change location, edit or replace $WG_CONF"
  echo "Then run: vpn-restart"
}
EOS

chmod +x "$HELPERS_FILE"
for cmd in vpn-start vpn-stop vpn-status vpn-restart vpn-change; do
  ln -sf "$HELPERS_FILE" "$HOME/.local/bin/$cmd"
done

echo "🎉 Done! VPN is now connected."
echo "Use the following commands:"
echo "  vpn-start   → Connect"
echo "  vpn-stop    → Disconnect"
echo "  vpn-status  → Show status"
echo "  vpn-restart → Reconnect"
echo "  vpn-change  → Change endpoint"

