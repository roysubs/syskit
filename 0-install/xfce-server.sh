#!/bin/bash
# Author: Gemini (based on template by Roy Wiseman) 2025-11
#
# Debian XFCE Desktop & Remote Access Installer
# Installs XFCE, XRDP (RDP), and TightVNCServer (VNC).
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

# ───[ Helper Functions ]──────────────────────────────────────────

check_root() {
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}     Debian XFCE & Remote Access Setup${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}[1/6] Checking for root privileges...${NC}"
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ This script must be run as root (or with sudo).${NC}"
        echo -e "${YELLOW}Please run as: sudo $0${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Running as root.${NC}"
    echo
}

update_packages() {
    echo -e "${CYAN}[2/6] Updating package lists...${NC}"
    if apt-get update; then
        echo -e "${GREEN}✅ Package lists updated successfully.${NC}"
    else
        echo -e "${RED}❌ Failed to update package lists. Check internet connection or apt sources.${NC}"
        exit 1
    fi
    echo
}

install_xfce() {
    echo -e "${CYAN}[3/6] Installing XFCE Desktop Environment...${NC}"
    
    # We check if the metapackage 'task-xfce-desktop' is already installed
    if dpkg -l | grep -q "^ii.*task-xfce-desktop"; then
        echo -e "${YELLOW}✅ XFCE metapackage 'task-xfce-desktop' is already installed.${NC}"
    else
        echo -e "${YELLOW}Installing XFCE (task-xfce-desktop)... This will take several minutes.${NC}"
        # Set frontend to noninteractive to avoid prompts (e.g., keyboard layout)
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y task-xfce-desktop
        echo -e "${GREEN}✅ XFCE Desktop Environment installed.${NC}"
    fi
    echo
}

install_remote_access() {
    echo -e "${CYAN}[4/6] Installing Remote Access Servers (XRDP & TightVNC)...${NC}"
    local packages_needed=()

    # Check for XRDP (RDP Server)
    if ! command -v xrdp &> /dev/null; then
        packages_needed+=("xrdp")
    else
        echo -e "${YELLOW}✅ XRDP (RDP Server) is already installed.${NC}"
    fi

    # Check for TightVNCServer (VNC Server)
    if ! command -v tightvncserver &> /dev/null; then
        packages_needed+=("tightvncserver")
    else
        echo -e "${YELLOW}✅ TightVNCServer (VNC Server) is already installed.${NC}"
    fi

    # Install any missing packages
    if [ ${#packages_needed[@]} -gt 0 ]; then
        echo -e "${YELLOW}Installing missing packages: ${packages_needed[*]}...${NC}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y "${packages_needed[@]}"
        echo -e "${GREEN}✅ Remote access packages installed.${NC}"
    else
        echo -e "${GREEN}✅ All remote access packages are already present.${NC}"
    fi
    echo
}

configure_remote_access() {
    echo -e "${CYAN}[5/6] Configuring Remote Access...${NC}"

    # --- Configure XRDP ---
    local STARTWM_SH="/etc/xrdp/startwm.sh"
    local STARTWM_BAK="/etc/xrdp/startwm.sh.bak"

    # 1. Add xrdp user to ssl-cert group (for certificate access)
    # This is a common requirement for XRDP to function correctly.
    if ! groups xrdp | grep -q "ssl-cert"; then
        echo -e "${YELLOW}Adding 'xrdp' user to 'ssl-cert' group...${NC}"
        usermod -a -G ssl-cert xrdp
        echo -e "${GREEN}✅ User 'xrdp' added to 'ssl-cert' group.${NC}"
    else
        echo -e "${YELLOW}✅ User 'xrdp' is already in 'ssl-cert' group.${NC}"
    fi

    # 2. Configure startwm.sh to launch XFCE
    # We back up the original file if we haven't already
    if [ -f "$STARTWM_SH" ] && [ ! -f "$STARTWM_BAK" ]; then
        echo -e "${YELLOW}Backing up original $STARTWM_SH to $STARTWM_BAK...${NC}"
        cp "$STARTWM_SH" "$STARTWM_BAK"
    fi
    
    # Check if our config is already present
    if grep -q "startxfce4" "$STARTWM_SH"; then
        echo -e "${YELLOW}✅ XRDP 'startwm.sh' already configured for XFCE.${NC}"
    else
        echo -e "${YELLOW}Configuring XRDP 'startwm.sh' for XFCE...${NC}"
        # Add 'startxfce4' just before the final 'exec' line
        sed -i '/^exec \/bin\/sh \/etc\/X11\/Xsession/i \
# Start XFCE\n\
startxfce4\n' "$STARTWM_SH"
        echo -e "${GREEN}✅ XRDP configured for XFCE.${NC}"
    fi

    # --- Configure VNC ---
    echo -e "${CYAN}VNC Server (tightvncserver):${NC}"
    echo -e "${YELLOW}⚠️  VNC requires per-user setup.${NC}"
    echo -e "A user must log in (e.g., via SSH) and run ${BOLD}'vncserver'${NC}."
    echo -e "This will create a config and ask them to set a password."
    echo -e "This step cannot be automated securely by this script."
    echo
}

restart_services() {
    echo -e "${CYAN}[6/6] Enabling and restarting services...${NC}"
    
    # --- XRDP ---
    if systemctl is-active --quiet xrdp; then
        echo -e "${YELLOW}Restarting XRDP service...${NC}"
        systemctl restart xrdp
    else
        echo -e "${YELLOW}XRDP service not running. Enabling and starting...${NC}"
    fi
    
    # Idempotent enable and start
    systemctl enable xrdp >/dev/null 2>&1
    systemctl start xrdp

    # Final check
    if systemctl is-active --quiet xrdp; then
        echo -e "${GREEN}✅ XRDP service is active.${NC}"
    else
        echo -e "${RED}❌ XRDP service failed to start. Check logs with 'journalctl -u xrdp'${NC}"
    fi
    
    # --- VNC ---
    echo -e "${CYAN}VNC service is user-managed. See notes below.${NC}"
    echo
}

show_final_instructions() {
    local SERVER_IP
    SERVER_IP=$(hostname -I | awk '{print $1}')
    
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}${BOLD}    🎉 XFCE Desktop Setup Complete! 🎉${NC}"
    echo -e "${BLUE_BOLD}═══════════════════════════════════════════════${NC}"
    echo
    echo -e "${BOLD}YOUR DEBIAN SERVER NOW HAS A FULL XFCE DESKTOP.${NC}"
    echo -e "Server IP Address: ${YELLOW}${SERVER_IP}${NC}"
    echo

    # --- RDP (XRDP) Instructions ---
    echo -e "## 🖥️ How to Connect via RDP (Recommended)"
    echo -e "This is the easiest method and works best with Windows."
    echo -e "The RDP server is running on port ${CYAN}3389${NC}."
    echo
    echo -e "${BOLD}From Windows:${NC}"
    echo -e "1. Open ${BOLD}Remote Desktop Connection${NC} (mstsc.exe)."
    echo -e "2. Enter the IP: ${YELLOW}${SERVER_IP}${NC}"
    echo -e "3. Click ${BOLD}Connect${NC}."
    echo -e "4. At the login screen, leave 'Session' as ${CYAN}Xorg${NC}."
    echo -e "5. Enter the ${BOLD}username and password${NC} for a user on this server."
    echo -e "   (Do NOT log in as root!)"
    echo
    echo -e "${BOLD}From Linux:${NC}"
    echo -e "1. Use an RDP client like ${BOLD}Remmina${NC}, ${BOLD}FreeRDP${NC}, or ${BOLD}rdesktop${NC}."
    echo -e "2. Connect to: ${YELLOW}${SERVER_IP}${NC}"
    echo -e "3. Log in with your server user credentials."
    echo

    # --- VNC Instructions ---
    echo -e "---"
    echo -e "## 📺 How to Connect via VNC (Alternative)"
    echo -e "VNC requires a one-time setup ${BOLD}for each user${NC} who wants to connect."
    echo
    echo -e "${BOLD}1. First-Time User Setup (on the server):${NC}"
    echo -e "   You must do this for the user you want to log in as (e.g., 'myuser')."
    echo -e "   a. SSH into the server: ${CYAN}ssh myuser@${SERVER_IP}${NC}"
    echo -e "   b. Run the VNC server setup command:"
    echo -e "      ${YELLOW}vncserver${NC}"
    echo -e "   c. You will be prompted to create a ${BOLD}VNC-specific password${NC}."
    echo -e "   d. It will start a session, usually on display ${CYAN}:1${NC}."
    echo -e "      (The server listens on port ${BOLD}5900 + display number${NC}, so: ${YELLOW}5901${NC})"
    echo
    echo -e "${BOLD}2. Connecting from Windows/Linux:${NC}"
    echo -e "   a. Use a VNC client like ${BOLD}TightVNC Viewer${NC}, ${BOLD}RealVNC${NC}, or ${BOLD}Remmina${NC}."
    echo -e "   b. Connect to: ${YELLOW}${SERVER_IP}:1${NC} (or ${YELLOW}${SERVER_IP}:5901${NC})"
    echo -e "   c. Enter the VNC-specific password you just created."
    echo

    # --- Firewall & Script Notes ---
    echo -e "---"
    echo -e "## 📓 How to Run This Script"
    echo
    echo -e "1. Save this script as (e.g.) ${CYAN}setup_xfce.sh${NC} on your server."
    echo -e "2. Make it executable:"
    echo -e "   ${CYAN}chmod +x setup_xfce.sh${NC}"
    echo -e "3. Run it with root privileges:"
    echo -e "   ${YELLOW}sudo ./setup_xfce.sh${NC}"
    echo
    echo -e "## ⚠️ Final Firewall Note"
    echo -e "If you have a firewall (like ${CYAN}ufw${NC}), you must open the ports:"
    echo -e " • RDP:   ${YELLOW}sudo ufw allow 3389/tcp${NC}"
    echo -e " • VNC:   ${YELLOW}sudo ufw allow 5901/tcp${NC} (and 5902, 5903, etc.)"
    echo
    echo -e "${GREEN}${BOLD}Enjoy your new remote desktop!${NC}"
    echo
}

# ───[ Main Execution ]────────────────────────────────────────────
main() {
    check_root
    update_packages
    install_xfce
    install_remote_access
    configure_remote_access
    restart_services
    show_final_instructions
}

main "$@"
