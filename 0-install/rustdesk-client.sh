#!/bin/bash
# Author: Gemini (based on template by Roy Wiseman) 2025-11
#
# RustDesk Client Installer for Debian (hp2)
# Installs and configures the RustDesk client to connect
# to a self-hosted server running on the SAME machine.
# IDEMPOTENT: Safe to run multiple times!
# ────────────────────────────────────────────────────────────────

set -e # Exit on error

# ───[ Styling ]───────────────────────────────────────────────────
RED='\033[1;31m'
GREEN='\033[1;32m'
CYAN='\033[1;36m'
YELLOW='\033[1;33m'
BLUE_BOLD='\033[1;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ───[ Global Variables ]──────────────────────────────────────────
PUBLIC_KEY=""
DEB_URL=""
DEB_FILE=""

# ───[ Helper Functions ]──────────────────────────────────────────

check_root() {
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}     RustDesk Client (for Self-Hosted) Setup${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}[1/7] Checking for root privileges...${NC}"
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ This script must be run as root (or with sudo).${NC}"
        echo -e "${YELLOW}Please run as: sudo $0${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Running as root.${NC}"
    echo
}

check_dependencies() {
    echo -e "${CYAN}[2/7] Checking dependencies (curl, wget)...${NC}"
    local missing_deps=()
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    if ! command -v wget &> /dev/null; then
        missing_deps+=("wget")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing missing dependencies: ${missing_deps[*]}...${NC}"
        apt-get update
        apt-get install -y "${missing_deps[@]}"
        echo -e "${GREEN}✅ Dependencies installed.${NC}"
    else
        echo -e "${GREEN}✅ All dependencies met.${NC}"
    fi
    echo
}

find_latest_deb_url() {
    echo -e "${CYAN}[3/7] Finding latest RustDesk client release...${NC}"
    local API_URL="https://api.github.com/repos/rustdesk/rustdesk/releases/latest"
    
    # Use curl to query GitHub API, grep for the x86_64.deb, and cut the URL
    DEB_URL=$(curl -s "$API_URL" \
        | grep "browser_download_url.*x86_64.deb" \
        | cut -d '"' -f 4 \
        | head -n 1)

    if [ -z "$DEB_URL" ]; then
        echo -e "${RED}❌ Could not automatically find the latest .deb URL.${NC}"
        echo -e "${YELLOW}Please find it manually from: https://github.com/rustdesk/rustdesk/releases${NC}"
        exit 1
    fi

    DEB_FILE="/tmp/$(basename "$DEB_URL")"
    echo -e "${GREEN}✅ Found latest package: $(basename "$DEB_URL")${NC}"
    echo
}

download_and_install() {
    echo -e "${CYAN}[4/7] Downloading and installing RustDesk client...${NC}"

    if [ -f "$DEB_FILE" ]; then
        echo -e "${YELLOW}⚠️  Previous download found. Removing to ensure freshness...${NC}"
        rm -f "$DEB_FILE"
    fi

    echo -e "${YELLOW}Downloading to $DEB_FILE...${NC}"
    wget -q -O "$DEB_FILE" "$DEB_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Download failed.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Download complete.${NC}"

    echo -e "${YELLOW}Installing package via dpkg...${NC}"
    # We expect this might fail with dependency errors
    dpkg -i "$DEB_FILE" 2>/dev/null || true

    echo -e "${YELLOW}Fixing any broken dependencies (this is normal)...${NC}"
    # 'apt-get -f install' fixes any dependency issues from the dpkg command
    if apt-get -f install -y; then
        echo -e "${GREEN}✅ RustDesk client installed successfully.${NC}"
    else
        echo -e "${RED}❌ Failed to install dependencies. Please check apt logs.${NC}"
        exit 1
    fi

    # Clean up the downloaded file
    rm -f "$DEB_FILE"
    echo
}

gather_server_info() {
    echo -e "${CYAN}[5/7] Locating self-hosted server key...${NC}"
    echo -e "This script needs to read the ${BOLD}public key${NC} from your RustDesk Docker server."
    echo -e "The server install script stored this in its 'data' directory."
    echo -e "Example: ${CYAN}/home/youruser/.config/rustdesk-server/data${NC}"
    echo

    local SERVER_DATA_DIR
    while true; do
        read -e -p "Enter the full path to your server's 'data' directory: " SERVER_DATA_DIR
        # Handle tilde expansion
        SERVER_DATA_DIR="${SERVER_DATA_DIR/#\~/$HOME}"
        
        local KEY_FILE_PUB="${SERVER_DATA_DIR}/id_ed25519.pub"

        if [ -f "$KEY_FILE_PUB" ]; then
            PUBLIC_KEY=$(cat "$KEY_FILE_PUB")
            echo -e "${GREEN}✅ Server key found and read successfully.${NC}"
            break
        else
            echo -e "${RED}❌ Key file not found at: ${KEY_FILE_PUB}${NC}"
            echo -e "${YELLOW}Please check the path and try again.${NC}"
        fi
    done
    echo
}

configure_client() {
    echo -e "${CYAN}[6/7] Configuring system-wide client settings...${NC}"
    local CONFIG_DIR="/etc/rustdesk"
    local CONFIG_FILE="${CONFIG_DIR}/RustDesk.toml"

    mkdir -p "$CONFIG_DIR"
    
    # Check if config file already exists and is configured
    if [ -f "$CONFIG_FILE" ] && grep -q "server = '127.0.0.1'" "$CONFIG_FILE"; then
        echo -e "${YELLOW}✅ System-wide config file ($CONFIG_FILE) is already configured.${NC}"
    else
        echo -e "${YELLOW}Writing config to $CONFIG_FILE...${NC}"
        # Create the system-wide config file.
        # This forces the client (and service) to use these settings.
        cat > "$CONFIG_FILE" << EOF
# System-wide RustDesk Client Configuration
# Generated: $(date)
# This forces the client to use the self-hosted server.

[options]
# Connect to the server on the *same machine*
server = '127.0.0.1'

# Use the public key from your server
key = '${PUBLIC_KEY}'

# Disable auto-updates (handled by apt)
update-url = ''

# Prevent users from changing server settings in the GUI
allow-remote-config = 'false'
EOF
        echo -e "${GREEN}✅ Client configured to use local server (127.0.0.1).${NC}"
    fi
    echo
}

restart_service() {
    echo -e "${CYAN}[7/7] Enabling and restarting RustDesk service...${NC}"
    echo -e "This allows for unattended access after reboots."
    
    # Enable the service to start on boot
    systemctl enable rustdesk >/dev/null 2>&1
    
    # Restart it to apply the new configuration
    systemctl restart rustdesk
    
    echo -e "${CYAN}Waiting 3 seconds for service to initialize...${NC}"
    sleep 3

    if systemctl is-active --quiet rustdesk; then
        echo -e "${GREEN}✅ RustDesk service is active and running.${NC}"
    else
        echo -e "${RED}❌ RustDesk service failed to start.${NC}"
        echo -e "${YELLOW}Run 'journalctl -u rustdesk -f' for logs.${NC}"
    fi
    echo
}

show_final_instructions() {
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}    🎉 Client Setup Complete! 🎉${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "The RustDesk client is now ${BOLD}installed and running as a service${NC} on this server (hp2)."
    echo -e "It is configured to connect to your RustDesk Docker server at ${CYAN}127.0.0.1${NC}."
    echo
    echo -e "## 🖥️ How to Connect from your Windows PC"
    echo
    echo -e "1. Open your RustDesk client on ${BOLD}Windows${NC}."
    echo -e "   (This client must also be configured to use your self-hosted server)."
    echo -e "2. In your address book / recent sessions, you should see the new ID for this server."
    echo -e "   (It may take up to 30 seconds to appear for the first time)."
    echo -e "3. Click ${BOLD}Connect${NC}."
    echo -e "4. You will be prompted for the login credentials ${BOLD}for the XFCE desktop${NC}."
    echo -e "   Enter the username and password for a user on this Debian server."
    echo
    echo -e "## 🛠️ Troubleshooting"
    echo
    echo -e "* ${BOLD}If the new ID does not appear on your Windows client:${NC}"
    echo -e "    1.  Ensure your Docker server is running: ${CYAN}docker ps${NC}"
    echo -e "    2.  Check the client service status on this server: ${CYAN}systemctl status rustdesk${NC}"
    echo -e "    3.  Check the client logs: ${CYAN}journalctl -u rustdesk -f${NC}"
    echo
    echo -e "${GREEN}${BOLD}You can now remotely access your XFCE desktop!${NC}"
    echo
}

# ───[ Main Execution ]────────────────────────────────────────────
main() {
    check_root
    check_dependencies
    find_latest_deb_url
    download_and_install
    gather_server_info
    configure_client
    restart_service
    show_final_instructions
}

main "$@"
