#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# openSUSE Ultimate Remote Access Setup - V20
# Designed to be idempotent and interactive. Each option now explains what it gives
# you and any real downside before asking, rather than just doing it.

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
echo_info() { echo -e "    $@"; }
echo_warn() { echo -e "    ${C_RED}⚠ $@${C_NC}"; }

# --- macOS not supported ---
if [[ "$(uname)" == "Darwin" ]]; then
    echo_yellow "remote-access-opensuse.sh is an openSUSE-specific toolkit (Cockpit, x11vnc, Fail2Ban, zypper, etc.) — not applicable on macOS."
    echo_yellow "Use remote-access-mac.sh instead."
    exit 1
fi

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
echo "    openSUSE UNIVERSAL REMOTE ACCESS BUILDER V20"
echo "======================================================"
echo
echo_blue "This script will walk through an idempotent setup for:"
echo "  1. Hostname Configuration"
echo "  2. Network & WoL Diagnostics"
echo "  3. Tailscale Mesh VPN (Zero-config Access)"
echo "  4. Cockpit Web Dashboard & Navigator (Port 9090)"
echo "  5. Standalone FileBrowser (Port 9091)"
echo "  6. SFTPGo Advanced File Server (Port 9092)"
echo "  7. x11vnc Desktop Service (Auto-healing VNC)"
echo "  8. SSH Hardening & GitHub Key Import"
echo "  9. Fail2Ban (Active Brute-force Protection)"
echo " 10. Automatic Security Updates"
echo " 11. Samba Home Directory Sharing (Read-Write)"
echo " 12. Administrative Password Change"
echo " 13. Sleep/Suspend Hardening"
echo " 14. Other GUI Remote-Access Options (informational)"
echo
echo_yellow "Each option below explains what it does and any real downside before it asks."
echo_yellow "Nothing here is reversible-by-default — note what you enable so you can undo it later."
echo_yellow "Press ENTER to begin..."
read -r

# --- [1] HOSTNAME ---
echo_blue "--- [1] HOSTNAME ---"
echo_info "Sets the machine's network name (what 'ssh <name>' or '<name>.local' resolves to)."
echo_info "Downside: if other devices/scripts reference the old hostname, they'll need updating too."
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
echo_info "Read-only diagnostics: your primary IP and Wake-on-LAN NIC setting. Nothing is changed here."
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
echo_info "A mesh VPN: lets you reach this machine from anywhere by its Tailscale name, with no router"
echo_info "port-forwarding and traffic encrypted end-to-end. Generally the safest way to expose anything"
echo_info "below (Cockpit, FileBrowser, VNC) remotely, instead of opening them to the public internet."
echo_info "Downside: adds a background daemon and a dependency on Tailscale's own coordination service."
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
echo_info "A full web-based system admin panel: services, storage, logs, terminal, package updates - all"
echo_info "through a browser at port 9090, authenticated with your normal Linux login."
echo_warn "This is a PRIVILEGED admin interface. Opening it to the public internet (rather than only over"
echo_warn "Tailscale/VPN or your LAN) means anyone who can reach port 9090 gets a login prompt to a tool"
echo_warn "that can manage your whole system. Prefer restricting this firewall port to Tailscale's interface."
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
echo_info "A browser-based file manager for your home directory, with upload/download/rename/delete."
echo_warn "This setup bypasses FileBrowser's own 12-character minimum password length to force the"
echo_warn "default login to 'admin/admin' (4 chars). Until you change it, anyone who can reach port 9091"
echo_warn "has full read/write/delete access to everything under your home directory. Strongly consider"
echo_warn "the random-password option below instead, especially if this port will be reachable off your LAN."
FB_DB="/home/$ACTUAL_USER/filebrowser.db"
# If it was on 9998, we'll migrate it to 9091
if [[ -x /usr/bin/filebrowser ]]; then
    echo_green "✓ FileBrowser binary present."
    read -rp "Reset FileBrowser admin login? [a=admin/admin, r=random strong password, N=skip]: " FB_RESET
    if [[ "$FB_RESET" =~ ^[AaRr]$ ]]; then
        systemctl stop filebrowser
        if ! command -v sqlite3 &>/dev/null; then zypper install -y sqlite3; fi
        if [[ "$FB_RESET" =~ ^[Rr]$ ]]; then
            FB_PASS=$(openssl rand -base64 18)
            ADMIN_HASH=$(/usr/bin/filebrowser hash "$FB_PASS")
            sqlite3 "$FB_DB" "UPDATE users SET password = '$ADMIN_HASH' WHERE username = 'admin';" 2>/dev/null
            echo_green "✓ Password reset. Save this now, it will not be shown again: ${FB_PASS}"
        else
            sqlite3 "$FB_DB" "UPDATE settings SET password_min_length = 4; UPDATE settings SET min_password_length = 4;" 2>/dev/null
            ADMIN_HASH=$(/usr/bin/filebrowser hash admin)
            sqlite3 "$FB_DB" "UPDATE users SET password = '$ADMIN_HASH' WHERE username = 'admin';" 2>/dev/null
            echo_warn "Login is admin/admin. Change it immediately: filebrowser users update admin --password '<new-password>'"
        fi
    fi
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
    echo_green "✓ FileBrowser Active at http://$IP_ADDR:9091"
else
    read -rp "Install Standalone FileBrowser? [a=admin/admin, r=random strong password, N=skip]: " INSTALL_FB
    if [[ "$INSTALL_FB" =~ ^[AaRr]$ ]]; then
        curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
        cp $(command -v filebrowser) /usr/bin/filebrowser
        /usr/bin/filebrowser -d "$FB_DB" config init 2>/dev/null
        if ! command -v sqlite3 &>/dev/null; then zypper install -y sqlite3; fi
        if [[ "$INSTALL_FB" =~ ^[Rr]$ ]]; then
            FB_PASS=$(openssl rand -base64 18)
            ADMIN_HASH=$(/usr/bin/filebrowser hash "$FB_PASS")
            echo_green "✓ Save this now, it will not be shown again: ${FB_PASS}"
        else
            sqlite3 "$FB_DB" "UPDATE settings SET password_min_length = 4; UPDATE settings SET min_password_length = 4;" 2>/dev/null
            ADMIN_HASH=$(/usr/bin/filebrowser hash admin)
            echo_warn "Login is admin/admin. Change it immediately: filebrowser users update admin --password '<new-password>'"
        fi
        sqlite3 "$FB_DB" "INSERT OR REPLACE INTO users (username, password, scope, locale, view_mode, single_click, perm_admin, perm_execute, perm_create, perm_rename, perm_modify, perm_delete, perm_share, perm_download, perm_copy) VALUES ('admin', '$ADMIN_HASH', '.', 'en', 'list', 0, 1, 1, 1, 1, 1, 1, 1, 1, 1);" 2>/dev/null
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
echo_info "A more modern file server than FileBrowser: per-user accounts, SFTP (port 2022) and a web UI,"
echo_info "with its own real auth system (no weak-default-password trap like FileBrowser above)."
echo_info "Downside: another two open ports (2022, 9092) and another service to keep updated."
if ! systemctl is-active --quiet sftpgo; then
    read -rp "Install SFTPGo Advanced File Server (SFTP/Web)? [y/N]: " INSTALL_SFTPGO
    if [[ "$INSTALL_SFTPGO" =~ ^[Yy]$ ]]; then
        echo "Installing SFTPGo..."
        rpm --import https://download.sftpgo.com/yum/gpg.key 2>/dev/null
        zypper addrepo -f "https://download.sftpgo.com/yum/$(uname -m)" sftpgo 2>/dev/null
        zypper refresh sftpgo
        zypper install -y libcap-progs sftpgo
    fi
fi

# Always re-seal configuration and restart to ensure port 9092 (ensures fix for existing installs)
if [[ -f /usr/lib/systemd/system/sftpgo.service || -f /etc/systemd/system/sftpgo.service ]]; then
    echo "Configuring SFTPGo Port 9092..."
    mkdir -p /etc/systemd/system/sftpgo.service.d
    cat <<EOF > /etc/systemd/system/sftpgo.service.d/override.conf
[Service]
Environment=SFTPGO_HTTPD__BINDINGS__0__PORT=9092
Environment=SFTPGO_HTTPD__BINDINGS__0__ADDRESS=0.0.0.0
EOF
    # Backup fix: modify JSON if it exists
    if [[ -f /etc/sftpgo/sftpgo.json ]]; then
        sed -i 's/"port": 8080/"port": 9092/g' /etc/sftpgo/sftpgo.json
    fi
    systemctl daemon-reload
    systemctl restart sftpgo
    firewall-cmd --permanent --add-port=9092/tcp; firewall-cmd --permanent --add-port=2022/tcp; firewall-cmd --reload
    echo_green "✓ SFTPGo active at http://$IP_ADDR:9092"
fi
echo

# --- [7] VNC ---
echo_blue "--- [7] VNC DESKTOP ---"
echo_info "Lets you see and control this machine's desktop remotely over VNC (port 5900)."
echo_warn "The VNC protocol's own password scheme (what you're about to set) is a weak, decades-old DES"
echo_warn "hash with an effective 8-character limit - not comparable to a modern password, and the video"
echo_warn "stream itself is unencrypted. Do not forward port 5900 through your router to the public"
echo_warn "internet; only reach it over Tailscale/VPN or an SSH tunnel."
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
echo_info "Imports your GitHub account's public SSH keys for passwordless login as $ACTUAL_USER."
echo_warn "Anyone holding the matching private key for ANY key currently listed on that GitHub account"
echo_warn "gets full SSH login as $ACTUAL_USER. Only do this for a GitHub account whose keys you fully trust."
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
echo_info "[9] Fail2Ban: watches auth logs and temporarily bans IPs after repeated failed login attempts"
echo_info "    (SSH, etc). Low downside - the main thing to know is it bans by IP, so a shared/dynamic IP"
echo_info "    you use yourself could get banned too if you mistype a password enough times."
if systemctl is-active --quiet fail2ban; then echo_green "✓ Fail2Ban Active."; else
read -rp "Install Fail2Ban? [y/N]: " I_F; [[ "$I_F" =~ ^[Yy]$ ]] && { zypper install -y fail2ban; systemctl enable --now fail2ban; }
fi

# Auto Update (transactional-update is the modern way for Tumbleweed/MicroOS)
echo_info "[10] Automatic Security Updates: keeps the system patched without you remembering to run"
echo_info "     'zypper update'. Reboot strategy is forced to MANUAL below so an update never reboots"
echo_info "     this machine out from under you unexpectedly."
if systemctl is-enabled --quiet transactional-update.timer 2>/dev/null; then echo_green "✓ Auto-updates Active."; else
read -rp "Enable Security Auto-Updates? [y/N]: " I_U; [[ "$I_U" =~ ^[Yy]$ ]] && {
    zypper install -y transactional-update
    # Set reboot strategy to manual to prevent unexpected reboots!
    if command -v rebootmgrctl &>/dev/null; then
        rebootmgrctl set-strategy manual
        echo_yellow "(!) Reboot strategy set to MANUAL (prevents auto-reboots)."
    fi
    systemctl enable --now transactional-update.timer 2>/dev/null || echo "(!) Note: transactional-update timer setup skipped."
}
fi

# Samba
echo_info "[11] Samba: shares your home directory read-write over SMB, so Windows/macOS/Linux machines"
echo_info "     on your network can mount it as a normal network drive. Scoped to $ACTUAL_USER only"
echo_info "     (not world-readable), but anyone with that Samba password has full read/write there."
if grep -q "\[$ACTUAL_USER-home\]" /etc/samba/smb.conf 2>/dev/null; then
    echo_green "✓ Samba Active."
else
read -rp "Share Home via Samba? [y/N]: " I_S
if [[ "$I_S" =~ ^[Yy]$ ]]; then
    zypper install -y samba
    echo -e "[$ACTUAL_USER-home]\n path=/home/$ACTUAL_USER\n valid users=$ACTUAL_USER\n read only=no" >> /etc/samba/smb.conf
    smbpasswd -a "$ACTUAL_USER"
    systemctl enable --now smb nmb
    # Previous versions of this script never opened the firewall for Samba, so the
    # share would exist but not actually be reachable - fixed here.
    firewall-cmd --permanent --add-service=samba; firewall-cmd --reload
    echo_green "✓ Samba share active and firewall opened (service: samba)."
fi
fi

# Administrative Password Change
echo_info "[12] Change the login/sudo password for $ACTUAL_USER. Affects local login, sudo, and anything"
echo_info "     else authenticating against this account (e.g. Samba login is separate, set above)."
read -rp "Change administrative password for $ACTUAL_USER now? [y/N]: " I_PW
[[ "$I_PW" =~ ^[Yy]$ ]] && passwd "$ACTUAL_USER"

# Sleep/Suspend Hardening
echo_info "[13] Disables automatic sleep/suspend, so this machine stays reachable over the network at"
echo_info "     all times instead of going to sleep and dropping off until someone wakes it locally."
echo_warn "On a laptop, this means it'll also stay awake (and draining battery) even unplugged -"
echo_warn "this masks sleep.target system-wide rather than only while on AC power. Fine for a"
echo_warn "desktop/server; think twice before enabling on a laptop you also run on battery."
read -rp "Disable sleep/suspend (keep this machine always reachable)? [y/N]: " I_SLEEP
if [[ "$I_SLEEP" =~ ^[Yy]$ ]]; then
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
    echo_green "✓ Sleep/suspend disabled."
fi
echo

# --- [14] OTHER GUI REMOTE-ACCESS OPTIONS ---
echo_blue "--- [14] OTHER GUI REMOTE-ACCESS OPTIONS (informational only - not installed here) ---"
echo_info "Everything above is self-hosted. If you'd rather not run/maintain your own services,"
echo_info "these cross-platform commercial tools all support Linux and have a free personal tier:"
echo_info "  TeamViewer      - very widely used, relay-based so no port-forwarding needed;"
echo_info "                    some users report its free tier flagging 'commercial use'"
echo_info "                    even for personal sessions if used heavily"
echo_info "  AnyDesk         - similar to TeamViewer, generally lighter-weight"
echo_info "  Chrome Remote Desktop - genuinely free, Google-account based, browser + small"
echo_info "                    host app, no port-forwarding, good low-friction cross-platform pick"
echo_info "  RealVNC         - free tier for a handful of personal devices, VNC-based with"
echo_info "                    their own relay option so it also avoids port-forwarding"
echo_info "These are full GUI apps best installed directly from their own site rather than piped"
echo_info "through this script - not automated here."
echo

# --- SUMMARY ---
echo "======================================================"
echo_green "              ESTABLISHMENT COMPLETE!"
echo "======================================================"
echo "  [ SHELL ]    ssh $ACTUAL_USER@$IP_ADDR"
echo "  [ DASHBOARD ] https://$IP_ADDR:9090 (Cockpit)"
echo "  [ FILE-APP ]  http://$IP_ADDR:9091 (FileBrowser)"
echo "  [ SFTP-GO ]   http://$IP_ADDR:9092 (Web Admin)"
echo "  [ VNC ]       $IP_ADDR:5900"
echo "  [ WINDOWS ]   \\\\$IP_ADDR\\$ACTUAL_USER-home"
echo "  [ MACOS ]     smb://$IP_ADDR/$ACTUAL_USER-home"
echo "------------------------------------------------------"
echo_blue "Connection & Management:"
echo "  SFTPGo:       Port 2022 (SFTP)"
echo "  Tailscale:    'tailscale status' or 'sudo tailscale up'"
echo "  Updates:      Daily 3am (if enabled)"
echo "------------------------------------------------------"
echo_yellow "Anything above reachable from outside your LAN is safer reached only over Tailscale than"
echo_yellow "opened directly to the internet via router port-forwarding - these firewall rules only open"
echo_yellow "the port on this machine, they don't by themselves expose it beyond your router/NAT."
echo "======================================================"
