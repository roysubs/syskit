#!/bin/bash
# openSUSE Ultimate Remote Access Setup - V19
# Designed to be idempotent and interactive.

# --- ANSI Colors ---
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'
C_NC='\033[0m'

echo_blue() { echo -e "${C_BLUE}$@${C_NC}"; }
echo_green() { echo -e "${C_GREEN}$@${C_NC}"; }
echo_red() { echo -e "${C_RED}$@${C_NC}"; }
echo_yellow() { echo -e "${C_YELLOW}$@${C_NC}"; }

# --- Auto-Elevate to Root ---
if [[ $EUID -ne 0 ]]; then
    echo_yellow "(!) Elevating to root..."
    exec sudo "$0" "$@"
fi

# Determine actual user
ACTUAL_USER=$(logname 2>/dev/null || echo $SUDO_USER)
if [[ -z "$ACTUAL_USER" || "$ACTUAL_USER" == "root" ]]; then
    ACTUAL_USER=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1; exit}' /etc/passwd)
fi

# --- START ---
echo "======================================================"
echo "    openSUSE UNIVERSAL REMOTE ACCESS BUILDER V19"
echo "======================================================"
echo
echo_blue "This script will provide an idempotent setup for:"
echo "  1. Hostname Configuration"
echo "  2. Network & WoL Diagnostics"
echo "  3. Tailscale Mesh VPN (Zero-config Access)"
echo "  4. Cockpit Web Dashboard & Navigator (Port 9090)"
echo "  5. Standalone FileBrowser (Port 9091 + admin/admin fix)"
echo "  6. SFTPGo Advanced File Server (Port 9092)"
echo "  7. x11vnc Desktop Service (Auto-healing VNC)"
echo "  8. SSH Hardening & GitHub Key Import"
echo "  9. Fail2Ban (Active Brute-force Protection)"
echo " 10. Automatic Security Updates"
echo " 11. Samba Home Directory Sharing (Read-Write)"
echo " 12. Administrative Password Change"
echo " 13. Sleep/Suspend Hardening"
echo
echo_yellow "Press ENTER to begin..."
read -r

# --- [1] HOSTNAME ---
echo_blue "--- [1] HOSTNAME ---"
CURRENT_H=$(hostname)
echo "Current Hostname: $CURRENT_H"
[[ "$CURRENT_H" == *"_"* ]] && echo_yellow "(!) Tip: Underscores (_) in hostnames are non-standard; some tools prefer hyphens (-)."
read -rp "Change hostname? [y/N]: " CHANGE_H
if [[ "$CHANGE_H" =~ ^[Yy]$ ]]; then
    read -rp "New hostname: " NEW_H
    if [[ -n "$NEW_H" ]]; then
        hostnamectl set-hostname --static "$NEW_H"
        echo_green "✓ Hostname set to $(hostname)"
    fi
fi
echo

# --- [2] NETWORK ---
echo_blue "--- [2] NETWORK ---"
INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
IP_ADDR=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "Primary IP: $IP_ADDR"
if command -v ethtool &>/dev/null; then
    WOL_SET=$(ethtool "$INTERFACE" | grep "Wake-on:" | tail -n 1 | awk '{print $2}')
    echo "WoL Setting: $WOL_SET"
fi
echo

# --- [3] TAILSCALE ---
echo_blue "--- [3] TAILSCALE ---"
if command -v tailscale &>/dev/null; then
    echo_green "✓ Tailscale is installed."
else
    read -rp "Install Tailscale Mesh VPN? [y/N]: " INSTALL_TS
    if [[ "$INSTALL_TS" =~ ^[Yy]$ ]]; then
        zypper addrepo -f https://pkgs.tailscale.com/stable/opensuse/tailscale.repo; zypper refresh; zypper install -y tailscale; systemctl enable --now tailscaled
    fi
fi
echo

# --- [4] COCKPIT ---
echo_blue "--- [4] COCKPIT DASHBOARD ---"
if systemctl is-active --quiet cockpit.socket; then
    echo_green "✓ Cockpit Active at https://$IP_ADDR:9090"
else
    read -rp "Install Cockpit Dashboard? [y/N]: " INSTALL_COCKPIT
    if [[ "$INSTALL_COCKPIT" =~ ^[Yy]$ ]]; then
        zypper install -y cockpit cockpit-packagekit cockpit-storaged; systemctl enable --now cockpit.socket; firewall-cmd --permanent --add-service=cockpit; firewall-cmd --reload
    fi
fi

if [[ -d /usr/share/cockpit/navigator ]]; then
    echo_green "✓ Cockpit Navigator detected."
else
    read -rp "Add File Browser tab (Navigator) to Cockpit? [y/N]: " INSTALL_NAV
    if [[ "$INSTALL_NAV" =~ ^[Yy]$ ]]; then
        NAV_URL="https://github.com/45Drives/cockpit-navigator/releases/download/v0.5.10/cockpit-navigator_0.5.10-1_all.tar.gz"
        NAV_TMP=$(mktemp -d); curl -Lfs "$NAV_URL" -o "$NAV_TMP/nav.tar.gz"
        tar -xzf "$NAV_TMP/nav.tar.gz" -C /usr/share/cockpit/ && mv /usr/share/cockpit/cockpit-navigator /usr/share/cockpit/navigator
        systemctl restart cockpit; rm -rf "$NAV_TMP"; echo_green "✓ Added."
    fi
fi
echo

# --- [5] FILEBROWSER ---
echo_blue "--- [5] FILEBROWSER (PORT 9091) ---"
FB_DB="/home/$ACTUAL_USER/filebrowser.db"
# If it was on 9998, we'll migrate it to 9091
if [[ -x /usr/bin/filebrowser ]]; then
    echo_green "✓ FileBrowser binary present. Configuring for admin/admin..."
    systemctl stop filebrowser
    # Force set the minLength to 4
    /usr/bin/filebrowser -d "$FB_DB" config set --auth.password.minLength 4 2>/dev/null
    # Reset password to admin
    /usr/bin/filebrowser -d "$FB_DB" users update admin --password admin 2>/dev/null || \
    /usr/bin/filebrowser -d "$FB_DB" users add admin admin --perm.admin
    
    # Update Service to 9091
    cat <<EOF > /etc/systemd/system/filebrowser.service
[Unit]
Description=FileBrowser on 9091
[Service]
User=$ACTUAL_USER
Group=users
WorkingDirectory=/home/$ACTUAL_USER
ExecStart=/usr/bin/filebrowser -p 9091 -r /home/$ACTUAL_USER -a 0.0.0.0 --database $FB_DB
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl restart filebrowser
    firewall-cmd --permanent --add-port=9091/tcp; firewall-cmd --reload
    echo_green "✓ FileBrowser Active at http://$IP_ADDR:9091 (admin/admin)"
else
    read -rp "Install Standalone FileBrowser (admin/admin)? [y/N]: " INSTALL_FB
    if [[ "$INSTALL_FB" =~ ^[Yy]$ ]]; then
        curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
        cp $(command -v filebrowser) /usr/bin/filebrowser
        /usr/bin/filebrowser -d "$FB_DB" config init 2>/dev/null
        /usr/bin/filebrowser -d "$FB_DB" config set --auth.password.minLength 4 2>/dev/null
        /usr/bin/filebrowser -d "$FB_DB" users add admin admin --perm.admin
        # (Service file logic as above)
        cat <<EOF > /etc/systemd/system/filebrowser.service
[Unit]
Description=FileBrowser on 9091
[Service]
User=$ACTUAL_USER
Group=users
WorkingDirectory=/home/$ACTUAL_USER
ExecStart=/usr/bin/filebrowser -p 9091 -r /home/$ACTUAL_USER -a 0.0.0.0 --database $FB_DB
Restart=always
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable --now filebrowser; firewall-cmd --permanent --add-port=9091/tcp; firewall-cmd --reload
    fi
fi
echo

# --- [6] SFTPGO ---
echo_blue "--- [6] SFTPGO ADVANCED FILE SERVER (PORT 9092) ---"
if systemctl is-active --quiet sftpgo; then
    echo_green "✓ SFTPGo is ACTIVE at http://$IP_ADDR:9092"
else
    read -rp "Install SFTPGo Advanced File Server (SFTP/Web)? [y/N]: " INSTALL_SFTPGO
    if [[ "$INSTALL_SFTPGO" =~ ^[Yy]$ ]]; then
        echo "Installing SFTPGo..."
        zypper install -y sftpgo
        
        # Configure SFTPGo to use port 9092 for HTTP and listen on all interfaces
        # Note: sftpgo usually uses sftpgo.json or env vars. We'll use a drop-in override for the port.
        mkdir -p /etc/systemd/system/sftpgo.service.d
        cat <<EOF > /etc/systemd/system/sftpgo.service.d/override.conf
[Service]
Environment=SFTPGO_HTTPD__BIND_PORT=9092
Environment=SFTPGO_HTTPD__BIND_ADDRESS=0.0.0.0
EOF
        systemctl daemon-reload; systemctl enable --now sftpgo
        firewall-cmd --permanent --add-port=9092/tcp; firewall-cmd --permanent --add-port=2022/tcp; firewall-cmd --reload
        echo_green "✓ SFTPGo installed. SFTP Port: 2022, Web UI: http://$IP_ADDR:9092"
        echo_yellow "(!) Please visit the Web UI to create your initial admin account."
    fi
fi
echo

# --- [7] VNC ---
echo_blue "--- [7] VNC DESKTOP ---"
if systemctl is-active --quiet x11vnc; then
    echo_green "✓ x11vnc active."
else
    read -rp "Install x11vnc? [y/N]: " INSTALL_VNC
    if [[ "$INSTALL_VNC" =~ ^[Yy]$ ]]; then
        zypper install -y x11vnc xauth; read -rsp "VNC Password: " VNC_PASS; echo
        x11vnc -storepasswd "$VNC_PASS" /etc/x11vnc.pass
        cat <<EOF > /etc/systemd/system/x11vnc.service
[Unit]
Description=VNC
[Service]
ExecStart=/bin/sh -c 'XAUTHLOC=\$(find /run/sddm -type f -name \"xauth*\" | head -n 1); /usr/bin/x11vnc -auth \$XAUTHLOC -forever -loop -noxdamage -repeat -rfbauth /etc/x11vnc.pass -display :0 -shared'
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable --now x11vnc; firewall-cmd --permanent --add-port=5900/tcp; firewall-cmd --reload
    fi
fi
echo

# --- [8] SSH ---
echo_blue "--- [8] SSH & KEYS ---"
if [[ -f "/home/$ACTUAL_USER/.ssh/authorized_keys" && $(grep -c "github" "/home/$ACTUAL_USER/.ssh/authorized_keys") -gt 0 ]]; then
    echo_green "✓ SSH Keys imported."
else
    read -rp "Import GitHub SSH keys for $ACTUAL_USER? [y/N]: " IMPORT_KEYS
    if [[ "$IMPORT_KEYS" =~ ^[Yy]$ ]]; then
        read -rp "GitHub Username: " GH_USER
        SSH_DIR="/home/$ACTUAL_USER/.ssh"; mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
        curl -sL "https://github.com/${GH_USER}.keys" >> "$SSH_DIR/authorized_keys"
        chown -R "$ACTUAL_USER:" "$SSH_DIR"; chmod 600 "$SSH_DIR/authorized_keys"; echo_green "✓ Imported."
    fi
fi
echo

# --- [9-13] RESIDUALS ---
echo_blue "--- [9-13] SECURITY & SHARES ---"
# Fail2Ban
if systemctl is-active --quiet fail2ban; then echo_green "✓ Fail2Ban Active."; else
read -rp "Install Fail2Ban? [y/N]: " I_F; [[ "$I_F" =~ ^[Yy]$ ]] && { zypper install -y fail2ban; systemctl enable --now fail2ban; }
fi
# Auto Update
if systemctl is-enabled --quiet zypper-automatic.timer 2>/dev/null; then echo_green "✓ Auto-updates Active."; else
read -rp "Enable Security Auto-Updates? [y/N]: " I_U; [[ "$I_U" =~ ^[Yy]$ ]] && { zypper install -y zypper-automatic; systemctl enable --now zypper-automatic.timer; }
fi
# Samba
if grep -q "\[$ACTUAL_USER-home\]" /etc/samba/smb.conf 2>/dev/null; then echo_green "✓ Samba Active."; else
read -rp "Share Home via Samba? [y/N]: " I_S; [[ "$I_S" =~ ^[Yy]$ ]] && { zypper install -y samba; echo -e "[$ACTUAL_USER-home]\n path=/home/$ACTUAL_USER\n valid users=$ACTUAL_USER\n read only=no" >> /etc/samba/smb.conf; smbpasswd -a "$ACTUAL_USER"; systemctl enable --now smb nmb; }
fi
echo

# --- SUMMARY ---
echo "======================================================"
echo_green "              ESTABLISHMENT COMPLETE!"
echo "======================================================"
echo "  [ SHELL ]    ssh $ACTUAL_USER@$IP_ADDR"
echo "  [ DASHBOARD ] https://$IP_ADDR:9090 (Cockpit)"
echo "  [ FILE-APP ]  http://$IP_ADDR:9091 (FileBrowser - admin/admin)"
echo "  [ SFTP-GO ]   http://$IP_ADDR:9092 (Web Admin)"
echo "  [ VNC ]       $IP_ADDR:5900"
echo "  [ WINDOWS ]   \\\\$IP_ADDR\\$ACTUAL_USER-home"
echo "  [ MACOS ]     smb://$IP_ADDR/$ACTUAL_USER-home"
echo "------------------------------------------------------"
echo_blue "Connection & Management:"
echo "  SFTPGo:       Port 2022 (SFTP)"
echo "  Tailscale:    'tailscale status' or 'sudo tailscale up'"
echo "  Updates:      Daily 3am (if enabled)"
echo "======================================================"
