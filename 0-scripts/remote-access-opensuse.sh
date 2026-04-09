#!/bin/bash
# openSUSE Ultimate Remote Access Setup
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

# --- Check Root ---
if [[ $EUID -ne 0 ]]; then
    echo_red "Please run as root (sudo $0)"
    exit 1
fi

# Determine actual user for Samba/SSH/Password bits
ACTUAL_USER=$(logname 2>/dev/null || echo $SUDO_USER)
if [[ -z "$ACTUAL_USER" || "$ACTUAL_USER" == "root" ]]; then
    # Fallback to the first non-system user (UID >= 1000)
    ACTUAL_USER=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1; exit}' /etc/passwd)
fi

# --- START ---
# (Removed CLEAR to keep terminal history)
echo "======================================================"
echo "    openSUSE UNIVERSAL REMOTE ACCESS BUILDER V9"
echo "======================================================"
echo
echo_blue "This script will provide an idempotent setup for:"
echo "  1. Hostname Configuration"
echo "  2. Network & WoL Diagnostics"
echo "  3. Tailscale Mesh VPN (Zero-config Access)"
echo "  4. Cockpit Web Dashboard (Browser Admin)"
echo "  5. x11vnc Desktop Service (Auto-healing VNC)"
echo "  6. SSH Hardening & GitHub Key Import"
echo "  7. Fail2Ban (Active Brute-force Protection)"
echo "  8. Automatic Security Updates"
echo "  9. Samba Home Directory Sharing (Read-Write)"
echo " 10. Administrative Password Change"
echo " 11. Sleep/Suspend Hardening"
echo
echo_yellow "Press ENTER to begin the interactive summary..."
read -r

# --- [1] HOSTNAME ---
echo_blue "--- [1] HOSTNAME CONFIGURATION ---"
CURRENT_H=$(hostname)
echo "Current Hostname: $CURRENT_H"
read -rp "Change hostname? [y/N]: " CHANGE_H
if [[ "$CHANGE_H" =~ ^[Yy]$ ]]; then
    read -rp "Enter new hostname: " NEW_H
    if [[ -n "$NEW_H" ]]; then
        # Force the name (some systems sanitize underscores)
        hostnamectl set-hostname --static "$NEW_H"
        echo_green "✓ Hostname set to $(hostname)"
    fi
else
    echo_green "✓ Keeping hostname: $CURRENT_H"
fi
echo

# --- [2] NETWORK & WOL ---
echo_blue "--- [2] NETWORK DIAGNOSTICS ---"
INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
IP_ADDR=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "Primary Interface: $INTERFACE"
echo "Local IP Address: $IP_ADDR"

if command -v nmcli &>/dev/null; then
    IS_DHCP=$(nmcli dev show "$INTERFACE" | grep -iE 'IP4.METHOD|ipv4.method' | awk '{print $2}')
    echo "Network Method: ${IS_DHCP:-Unknown}"
fi

if command -v ethtool &>/dev/null; then
    WOL_STATUS=$(ethtool "$INTERFACE" | grep "Wake-on")
    echo "WoL Capabilities: $(echo "$WOL_STATUS" | grep 'Supports' | awk '{print $2}')"
    echo "WoL Setting:      $(echo "$WOL_STATUS" | grep 'Wake-on:' | tail -n 1 | awk '{print $2}')"
else
    echo_yellow "(!) installing network tools..."
    zypper install -y ethtool net-tools-deprecated
fi
echo

# --- [3] TAILSCALE ---
echo_blue "--- [3] TAILSCALE MESH VPN ---"
if command -v tailscale &>/dev/null; then
    echo_green "✓ Tailscale is installed."
    tailscale status | head -n 1
else
    read -rp "Install Tailscale (VPN)? [y/N]: " INSTALL_TS
    if [[ "$INSTALL_TS" =~ ^[Yy]$ ]]; then
        zypper addrepo -f https://pkgs.tailscale.com/stable/opensuse/tailscale.repo
        zypper --gpg-auto-import-keys refresh
        zypper install -y tailscale
        systemctl enable --now tailscaled
        echo_yellow "(!) Run 'tailscale up' later to authenticate."
    fi
fi
echo

# --- [4] COCKPIT ---
echo_blue "--- [4] COCKPIT WEB DASHBOARD ---"
if systemctl is-active --quiet cockpit.socket; then
    echo_green "✓ Cockpit is ACTIVE at https://$IP_ADDR:9090"
else
    read -rp "Install Cockpit Web Dashboard? [y/N]: " INSTALL_COCKPIT
    if [[ "$INSTALL_COCKPIT" =~ ^[Yy]$ ]]; then
        zypper install -y cockpit cockpit-packagekit cockpit-storaged cockpit-networkmanager
        systemctl enable --now cockpit.socket
        firewall-cmd --permanent --add-service=cockpit
        firewall-cmd --reload
        echo_green "✓ Cockpit installed. Access at https://$IP_ADDR:9090"
    fi
fi
echo

# --- [5] VNC ---
echo_blue "--- [5] VNC DESKTOP ACCESS (x11vnc) ---"
if systemctl is-active --quiet x11vnc; then
    echo_green "✓ x11vnc service is ACTIVE."
else
    read -rp "Install self-healing VNC service? [y/N]: " INSTALL_VNC
    if [[ "$INSTALL_VNC" =~ ^[Yy]$ ]]; then
        zypper install -y x11vnc xauth xhost xf86-video-dummy
        read -rsp "Enter VNC Password: " VNC_PASS
        echo
        x11vnc -storepasswd "$VNC_PASS" /etc/x11vnc.pass
        mkdir -p /etc/sddm.conf.d
        echo -e "[General]\nDisplayServer=x11" > /etc/sddm.conf.d/force-x11.conf
        cat <<EOF > /etc/systemd/system/x11vnc.service
[Unit]
Description=Dynamic x11vnc Service
After=display-manager.service
[Service]
Type=simple
ExecStartPre=/bin/sh -c 'sleep 10'
ExecStart=/bin/sh -c 'XAUTHLOC=\$(find /run/sddm -type f -name "xauth*" | head -n 1); /usr/bin/x11vnc -auth \$XAUTHLOC -forever -loop -noxdamage -repeat -rfbauth /etc/x11vnc.pass -display :0 -shared'
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now x11vnc
        firewall-cmd --permanent --add-port=5900/tcp
        firewall-cmd --reload
    fi
fi
echo

# --- [6] SSH & KEY IMPORT ---
echo_blue "--- [6] OPENSSH & KEY IMPORT ---"
SSH_DIR="/home/$ACTUAL_USER/.ssh"
if [[ -f "$SSH_DIR/authorized_keys" && $(grep -c "github.com" "$SSH_DIR/authorized_keys") -gt 0 ]]; then
    echo_green "✓ GitHub Public keys already imported for $ACTUAL_USER."
else
    zypper install -y openssh
    systemctl enable --now sshd
    firewall-cmd --permanent --add-service=ssh
    firewall-cmd --reload
    
    read -rp "Import public keys from GitHub for $ACTUAL_USER? [y/N]: " IMPORT_KEYS
    if [[ "$IMPORT_KEYS" =~ ^[Yy]$ ]]; then
        read -rp "Enter GitHub username: " GH_USER
        if [[ -n "$GH_USER" ]]; then
            mkdir -p "$SSH_DIR"
            chmod 700 "$SSH_DIR"
            echo "# Imported from github.com/$GH_USER" >> "$SSH_DIR/authorized_keys"
            curl -s -L "https://github.com/${GH_USER}.keys" >> "$SSH_DIR/authorized_keys"
            chown -R "$ACTUAL_USER:" "$SSH_DIR"
            chmod 600 "$SSH_DIR/authorized_keys"
            echo_green "✓ Keys imported."
        fi
    fi
fi
echo

# --- [7] FAIL2BAN ---
echo_blue "--- [7] FAIL2BAN BRUTE-FORCE PROTECTION ---"
if systemctl is-active --quiet fail2ban; then
    echo_green "✓ Fail2Ban is ACTIVE."
else
    read -rp "Install Fail2Ban protection? [y/N]: " INSTALL_F2B
    if [[ "$INSTALL_F2B" =~ ^[Yy]$ ]]; then
        zypper install -y fail2ban
        systemctl enable --now fail2ban
        echo_green "✓ Fail2Ban monitoring SSH."
    fi
fi
echo

# --- [8] AUTO UPDATES ---
echo_blue "--- [8] AUTOMATIC SECURITY UPDATES ---"
if [[ -f /etc/cron.d/auto-patch ]] || systemctl is-enabled --quiet zypper-automatic.timer 2>/dev/null; then
    echo_green "✓ Automatic updates are ACTIVE."
else
    read -rp "Configure automatic security patches? [y/N]: " AUTO_UPD
    if [[ "$AUTO_UPD" =~ ^[Yy]$ ]]; then
        if zypper install -y zypper-automatic 2>/dev/null; then
             sed -i 's/apply_updates = no/apply_updates = yes/' /etc/zypp/automatic.conf 2>/dev/null
             systemctl enable --now zypper-automatic.timer
             echo_green "✓ Automatic updates scheduled via zypper-automatic."
        else
             echo "0 3 * * * root zypper --non-interactive patch --no-reboot" > /etc/cron.d/auto-patch
             echo_green "✓ Manual security patch cron job created (daily at 3am)."
        fi
    fi
fi
echo

# --- [9] SAMBA ---
echo_blue "--- [9] SAMBA HOME SHARING ---"
if [[ -f /etc/samba/smb.conf && $(grep -c "\[$ACTUAL_USER-home\]" /etc/samba/smb.conf) -gt 0 ]]; then
    echo_green "✓ Samba share for $ACTUAL_USER is active."
else
    read -rp "Share $ACTUAL_USER home directory (Read-Write)? [y/N]: " INSTALL_SAMBA
    if [[ "$INSTALL_SAMBA" =~ ^[Yy]$ ]]; then
        zypper install -y samba
        [[ ! -s /etc/samba/smb.conf ]] && echo -e "[global]\nworkgroup=WORKGROUP\nsecurity=user\npassdb backend=tdbsam" > /etc/samba/smb.conf
        cat <<EOF >> /etc/samba/smb.conf

[$ACTUAL_USER-home]
    comment = Remote Administration for $ACTUAL_USER
    path = /home/$ACTUAL_USER
    valid users = $ACTUAL_USER
    read only = no
    browsable = yes
    guest ok = no
    create mask = 0644
    directory mask = 0755
EOF
        echo_yellow "(!) Enter SAMBA password for $ACTUAL_USER: "
        smbpasswd -a "$ACTUAL_USER"
        firewall-cmd --permanent --add-service=samba
        firewall-cmd --reload
        systemctl enable --now smb nmb
        echo_green "✓ Samba configured."
    fi
fi
echo

# --- [10] PASSWORD ---
echo_blue "--- [10] PASSWORD MANAGEMENT ---"
read -rp "Change password for $ACTUAL_USER? [y/N]: " CHANGE_PW
if [[ "$CHANGE_PW" =~ ^[Yy]$ ]]; then passwd "$ACTUAL_USER"; fi
echo

# --- [11] STABILITY ---
echo_blue "--- [11] STABILITY (NO SLEEP) ---"
if systemctl is-active --quiet sleep.target 2>/dev/null; then
    read -rp "Prevent machine from sleeping? [y/N]: " NO_SLEEP
    if [[ "$NO_SLEEP" =~ ^[Yy]$ ]]; then
        systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
        echo_green "✓ Sleep targets masked."
    fi
else
    echo_green "✓ Sleep targets are already masked."
fi

# --- SUMMARY ---
echo
echo "======================================================"
echo_green "              ESTABLISHMENT COMPLETE!"
echo "======================================================"
echo
echo_blue "Connection Strings for your Remote Client:"
echo
echo_yellow "  [ SHELL ] (Terminal)"
echo "  ssh $ACTUAL_USER@$IP_ADDR"
echo
echo_yellow "  [ DASHBOARD ] (Web Browser)"
echo "  https://$IP_ADDR:9090"
echo
echo_yellow "  [ DESKTOP ] (VNC Viewer)"
echo "  $IP_ADDR:5900"
echo
echo_yellow "  [ FILES ] (Samba/SMB)"
echo "  Windows:  \\\\$IP_ADDR\\$ACTUAL_USER-home"
echo "  macOS:    smb://$IP_ADDR/$ACTUAL_USER-home"
echo
echo "------------------------------------------------------"
echo_blue "Hostname:    $(hostname)"
echo "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo 'Not Connected')"
echo "------------------------------------------------------"
echo_green "The machine is now mission-ready."
echo "======================================================"
