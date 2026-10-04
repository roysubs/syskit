#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# macOS Remote Access Setup - V1
# Companion to remote-access-opensuse.sh, not a line-for-line port: several of that
# script's tools (Cockpit, x11vnc, Fail2Ban) have no real macOS equivalent and are
# replaced here with the native macOS way of doing the same underlying thing.
# Designed to be idempotent and interactive, and to explain what each option gives you
# and any real downside before asking - not just do it.

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

if [[ "$(uname)" != "Darwin" ]]; then
    echo_yellow "This is the macOS-specific remote access toolkit. Use remote-access-opensuse.sh on openSUSE."
    exit 1
fi

ACTUAL_USER="$(whoami)"
HOME_DIR="$HOME"

# Network info (ifconfig/netstat, not Linux's 'ip' - same pattern used elsewhere in this repo)
# Filter to a default route with a real IPv4 gateway - a bare 'grep ^default | head -1'
# would often match a VPN/system tunnel (utunN) default route instead of the real
# interface, since those get listed first on many Macs (confirmed live: this exact bug).
INTERFACE=$(netstat -rn | grep '^default' | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $NF}' | head -n 1)
IP_ADDR=$(ipconfig getifaddr "$INTERFACE" 2>/dev/null)

echo "======================================================"
echo "       macOS REMOTE ACCESS BUILDER V1"
echo "======================================================"
echo
echo_blue "This will walk through an idempotent setup for:"
echo "  1. Hostname Configuration"
echo "  2. Network & Wake-on-LAN Diagnostics"
echo "  3. Tailscale Mesh VPN (Zero-config Access)"
echo "  4. FileBrowser Web File Manager (Port 9091)"
echo "  5. SFTPGo Advanced File Server (Port 9092)"
echo "  6. Screen Sharing / Remote Management (built-in, replaces x11vnc)"
echo "  7. SSH Hardening & GitHub Key Import"
echo "  8. Automatic Security Updates"
echo "  9. File Sharing (SMB) - native vs Homebrew Samba"
echo " 10. Administrative Password Change"
echo " 11. Sleep Hardening (stay reachable on the network)"
echo " 12. Other GUI remote-access options (informational only)"
echo
echo_yellow "Each option explains what it does and any real downside before it asks."
echo_yellow "Several steps need an admin password via sudo - you'll be prompted when needed,"
echo_yellow "not all up front."
echo_yellow "Press ENTER to begin..."
read -r

# --- [1] HOSTNAME ---
echo_blue "--- [1] HOSTNAME ---"
echo_info "macOS actually has THREE separate name settings, unlike Linux's single hostname:"
echo_info "  HostName      - the network/DNS name (what SSH and most tools use)"
echo_info "  LocalHostName - the Bonjour/.local name (what AirDrop/Finder sidebar use)"
echo_info "  ComputerName  - the friendly name shown in System Settings and Finder"
echo_info "This sets all three to the same value for simplicity. Downside: if you rely on"
echo_info "a specific one differing (e.g. a fancy ComputerName with spaces/emoji), this"
echo_info "will flatten it to a single DNS-safe name."
if CURRENT_H=$(scutil --get HostName 2>/dev/null); then
    :
else
    # scutil --get HostName prints a stray "AuthorizationCreate() failed" line to stdout
    # (not stderr) when HostName isn't explicitly set, which is common and not a real
    # problem - most Macs only ever have ComputerName/LocalHostName set via the GUI.
    CURRENT_H="(not explicitly set - using ComputerName/Bonjour name: $(hostname))"
fi
echo "Current HostName: $CURRENT_H"
read -rp "Change hostname? [y/N]: " CHANGE_H
if [[ "$CHANGE_H" =~ ^[Yy]$ ]]; then
    read -rp "New hostname: " NEW_H
    if [[ -n "$NEW_H" ]]; then
        sudo scutil --set HostName "$NEW_H"
        sudo scutil --set LocalHostName "$NEW_H"
        sudo scutil --set ComputerName "$NEW_H"
        echo_green "✓ Hostname set to $(scutil --get HostName)"
    fi
fi
echo

# --- [2] NETWORK ---
echo_blue "--- [2] NETWORK ---"
echo_info "Read-only diagnostics: your primary IP and Wake-on-LAN ('Wake for network access')"
echo_info "setting. Nothing is changed here. Note: WoL support on Mac is genuinely less"
echo_info "reliable than on typical Linux/Windows PCs - it generally works over wired"
echo_info "Ethernet, is inconsistent over Wi-Fi, and behaves differently model to model."
echo "Primary interface: ${INTERFACE:-unknown}"
echo "Primary IP: ${IP_ADDR:-unknown}"
WOL_SET=$(pmset -g custom 2>/dev/null | awk '/womp/{print $2; exit}')
if [[ "$WOL_SET" == "1" ]]; then
    echo_green "Wake-on-LAN (womp): enabled"
else
    echo_yellow "Wake-on-LAN (womp): disabled or unknown"
fi
echo

# --- [3] TAILSCALE ---
echo_blue "--- [3] TAILSCALE ---"
echo_info "A mesh VPN: lets you reach this Mac from anywhere by its Tailscale name, with no"
echo_info "router port-forwarding and traffic encrypted end-to-end. The safest way to reach"
echo_info "anything below (FileBrowser, Screen Sharing) remotely instead of opening it to"
echo_info "the public internet."
echo_info "Downside: adds a background daemon and a dependency on Tailscale's coordination service."
if command -v tailscale &>/dev/null; then
    echo_green "✓ Tailscale is installed."
else
    read -rp "Install Tailscale Mesh VPN via Homebrew? [y/N]: " INSTALL_TS
    if [[ "$INSTALL_TS" =~ ^[Yy]$ ]]; then
        if command -v brew &>/dev/null; then
            brew install tailscale
            echo_yellow "Start it with: sudo tailscaled install-system-daemon   (then: tailscale up)"
        else
            echo_red "Homebrew not found. Install it from https://brew.sh first, or get the macOS app from https://tailscale.com/download"
        fi
    fi
fi
echo

# --- [4] FILEBROWSER ---
echo_blue "--- [4] FILEBROWSER (PORT 9091) ---"
echo_info "A browser-based file manager for your home directory, with upload/download/rename/delete."
echo_warn "The default login this offers is 'admin/admin'. Until you change it, anyone who can"
echo_warn "reach port 9091 has full read/write/delete access to your home directory. Strongly"
echo_warn "prefer the random-password option, especially if this port is reachable off your LAN."
if command -v filebrowser &>/dev/null; then
    echo_green "✓ FileBrowser binary present."
else
    read -rp "Install FileBrowser via Homebrew? [y/N]: " INSTALL_FB
    if [[ "$INSTALL_FB" =~ ^[Yy]$ ]] && command -v brew &>/dev/null; then
        brew install filebrowser
    fi
fi
if command -v filebrowser &>/dev/null; then
    FB_DB="$HOME_DIR/filebrowser.db"
    read -rp "(Re)configure FileBrowser on port 9091? [a=admin/admin, r=random strong password, N=skip]: " FB_SET
    if [[ "$FB_SET" =~ ^[AaRr]$ ]]; then
        filebrowser -d "$FB_DB" config init 2>/dev/null
        if [[ "$FB_SET" =~ ^[Rr]$ ]]; then
            FB_PASS=$(openssl rand -base64 18)
            filebrowser -d "$FB_DB" users add admin "$FB_PASS" --perm.admin 2>/dev/null \
                || filebrowser -d "$FB_DB" users update admin --password "$FB_PASS" 2>/dev/null
            echo_green "✓ Save this now, it will not be shown again: ${FB_PASS}"
        else
            filebrowser -d "$FB_DB" users add admin admin --perm.admin 2>/dev/null \
                || filebrowser -d "$FB_DB" users update admin --password admin 2>/dev/null
            echo_warn "Login is admin/admin. Change it immediately: filebrowser -d '$FB_DB' users update admin --password '<new-password>'"
        fi
        echo_info "Run it with: filebrowser -d '$FB_DB' -p 9091 -r '$HOME_DIR' -a 0.0.0.0"
        echo_info "To keep it running in the background permanently, ask me to set up a launchd agent for it."
    fi
fi
echo

# --- [5] SFTPGO ---
echo_blue "--- [5] SFTPGO ADVANCED FILE SERVER (PORT 9092) ---"
echo_info "A more modern file server than FileBrowser: per-user accounts, SFTP (port 2022) and"
echo_info "a web UI, with its own real auth system (no weak-default-password trap like above)."
echo_info "Downside: another two open ports and another service to keep updated."
if command -v sftpgo &>/dev/null; then
    echo_green "✓ SFTPGo already installed."
else
    read -rp "Install SFTPGo? [y/N]: " INSTALL_SFTPGO
    if [[ "$INSTALL_SFTPGO" =~ ^[Yy]$ ]]; then
        if command -v brew &>/dev/null; then
            echo_info "No official Homebrew formula for SFTPGo as of writing - install the macOS binary"
            echo_info "directly from: https://github.com/drakkan/sftpgo/releases (look for the darwin build)"
        fi
    fi
fi
echo

# --- [6] SCREEN SHARING / REMOTE MANAGEMENT ---
echo_blue "--- [6] SCREEN SHARING / REMOTE MANAGEMENT ---"
echo_info "macOS has a built-in remote-desktop server - no third-party VNC server needed like"
echo_info "x11vnc on Linux. Two levels:"
echo_info "  Screen Sharing   - basic remote control, also speaks standard VNC (any VNC viewer"
echo_info "                     can connect, same weak-password VNC protocol caveat as Linux's"
echo_info "                     x11vnc - don't forward this port to the public internet)."
echo_info "  Remote Management (Apple Remote Desktop) - adds file transfer, observe-only mode,"
echo_info "                     per-user permission control. Overkill for one machine, useful"
echo_info "                     for managing several."
# A non-privileged signal of current state, so we don't need to sudo just to look:
# the screensharingd process is only running while Screen Sharing is actually active.
if pgrep -x ScreenSharingAgent &>/dev/null || pgrep -x screensharingd &>/dev/null; then
    echo "Screen Sharing looks currently: on"
else
    echo "Screen Sharing looks currently: off (or idle until a connection arrives)"
fi
read -rp "Enable basic Screen Sharing? [y/N]: " ENABLE_SS
if [[ "$ENABLE_SS" =~ ^[Yy]$ ]]; then
    sudo launchctl enable system/com.apple.screensharing 2>/dev/null
    sudo launchctl kickstart -k system/com.apple.screensharing 2>/dev/null
    sleep 1
    if sudo launchctl print system/com.apple.screensharing &>/dev/null; then
        echo_green "✓ Screen Sharing is running."
    else
        echo_warn "Could not confirm Screen Sharing started. Verify manually:"
        echo_warn "System Settings > General > Sharing > Screen Sharing"
    fi
fi
echo

# --- [7] SSH ---
echo_blue "--- [7] SSH & KEYS ---"
echo_info "Enables Remote Login (SSH) and imports your GitHub account's public keys for"
echo_info "passwordless login as $ACTUAL_USER."
echo_warn "Anyone holding the matching private key for ANY key currently listed on that GitHub"
echo_warn "account gets full SSH login as $ACTUAL_USER. Only do this for an account whose keys"
echo_warn "you fully trust."
# systemsetup needs sudo even just to query - rather than force a password prompt just
# to look, use launchd's own (non-sudo) listing, which is a decent proxy signal.
if launchctl list 2>/dev/null | grep -q com.openssh.sshd; then
    echo "Remote Login (SSH) looks currently: on"
else
    echo "Remote Login (SSH) looks currently: off"
fi
read -rp "Enable Remote Login (SSH)? [y/N]: " ENABLE_SSH
[[ "$ENABLE_SSH" =~ ^[Yy]$ ]] && sudo systemsetup -setremotelogin on
if [[ -f "$HOME_DIR/.ssh/authorized_keys" && $(grep -c "github" "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null) -gt 0 ]]; then
    echo_green "✓ SSH Keys already imported."
else
    read -rp "Import GitHub SSH keys for $ACTUAL_USER? [y/N]: " IMPORT_KEYS
    if [[ "$IMPORT_KEYS" =~ ^[Yy]$ ]]; then
        read -rp "GitHub Username: " GH_USER
        SSH_DIR="$HOME_DIR/.ssh"; mkdir -p "$SSH_DIR"; chmod 700 "$SSH_DIR"
        curl -sL "https://github.com/${GH_USER}.keys" >> "$SSH_DIR/authorized_keys"
        chmod 600 "$SSH_DIR/authorized_keys"; echo_green "✓ Imported."
    fi
fi
echo_info "No direct macOS equivalent to Fail2Ban's log-watching auto-ban exists. The practical"
echo_info "mitigation is the same shape though: rely on key-only auth (above) rather than"
echo_info "passwords, and reach SSH over Tailscale rather than exposing port 22 to the internet."
echo

# --- [8] AUTOMATIC SECURITY UPDATES ---
echo_blue "--- [8] AUTOMATIC SECURITY UPDATES ---"
echo_info "Keeps macOS patched without remembering to check System Settings > General > Software"
echo_info "Update manually. Unlike the openSUSE script's 'manual reboot strategy' safeguard,"
echo_info "macOS security updates do NOT force a reboot by default - app updates install"
echo_info "live, OS updates typically prompt you to restart on your own schedule."
echo_info "(Checking the current setting also needs sudo on macOS, so skipping an eager check -"
echo_info "the command below will tell you the result once you've answered.)"
read -rp "Enable automatic update checks? [y/N]: " ENABLE_AUTOUPDATE
[[ "$ENABLE_AUTOUPDATE" =~ ^[Yy]$ ]] && sudo softwareupdate --schedule on
echo

# --- [9] FILE SHARING (SMB) ---
echo_blue "--- [9] FILE SHARING (SMB) ---"
echo_info "Two real options here, worth knowing the actual tradeoff rather than picking blind:"
echo
echo_info "${C_GREEN}Native macOS File Sharing (sharing -a)${C_NC}"
echo_info "  + Zero extra install, deeply integrated with your Mac user accounts"
echo_info "  + Apple patches it as part of the OS - no separate service to keep updated"
echo_info "  + Properly handles macOS-specific metadata (resource forks, extended attrs) for"
echo_info "    other Mac clients, and is what Time Machine network backups expect"
echo_info "  - Configuration is limited from the command line - no smb.conf-level per-share"
echo_info "    ACL tuning, just basic read/write + guest toggles"
echo
echo_info "${C_YELLOW}Homebrew Samba${C_NC}"
echo_info "  + Full smb.conf control - identical configuration language to your Linux boxes,"
echo_info "    useful if you want this Mac's share config to genuinely match an openSUSE/Linux"
echo_info "    server's setup"
echo_info "  + Finer-grained per-share options than Apple's own tool exposes"
echo_info "  - A second SMB server on the same machine - only one can bind port 445, so you'd"
echo_info "    need to disable Apple's own File Sharing first to avoid a conflict"
echo_info "  - Doesn't integrate with macOS account management or Time Machine-over-network"
echo_info "    the way Apple's own implementation does"
echo_info "  - One more service you personally patch/secure, vs. Apple handling it via OS updates"
echo
echo_info "Recommendation: use native sharing for a normal 'share my folder with other machines'"
echo_info "case (simpler, zero maintenance). Reach for Homebrew Samba only if you specifically"
echo_info "need smb.conf-level config parity with a Linux box, or a Samba feature Apple's"
echo_info "implementation doesn't expose."
echo
read -rp "Set up sharing? [1=native sharing -a, 2=Homebrew Samba, Enter=skip]: " SMB_CHOICE
if [[ "$SMB_CHOICE" == "1" ]]; then
    SHARE_DIR="$HOME_DIR"
    sudo sharing -a "$SHARE_DIR" -S "${ACTUAL_USER}-home" -s 001 -g 000 -R 0
    echo_green "✓ Sharepoint created. Now enable File Sharing itself if it isn't already on:"
    echo_info "System Settings > General > Sharing > File Sharing (toggle on, ensure SMB is checked)"
    echo_info "Or: sudo launchctl enable system/com.apple.smbd && sudo launchctl kickstart -k system/com.apple.smbd"
elif [[ "$SMB_CHOICE" == "2" ]]; then
    echo_warn "Remember to turn OFF native File Sharing first (System Settings > General > Sharing)"
    echo_warn "to avoid both servers fighting over port 445."
    if command -v brew &>/dev/null; then
        read -rp "Install Samba via Homebrew now? [y/N]: " I_SAMBA
        [[ "$I_SAMBA" =~ ^[Yy]$ ]] && brew install samba
        echo_info "Then configure /opt/homebrew/etc/smb.conf (or /usr/local/etc/smb.conf on Intel) same as the openSUSE script's [$ACTUAL_USER-home] stanza."
    else
        echo_red "Homebrew not found. Install it from https://brew.sh first."
    fi
fi
echo

# --- [10] ADMIN PASSWORD ---
echo_blue "--- [10] ADMINISTRATIVE PASSWORD CHANGE ---"
echo_info "Changes the login/admin password for $ACTUAL_USER. Affects local login, sudo, and"
echo_info "(if FileVault is on) your disk encryption unlock password too - double check you'll"
echo_info "remember it before confirming."
read -rp "Change password for $ACTUAL_USER now? [y/N]: " I_PW
[[ "$I_PW" =~ ^[Yy]$ ]] && passwd "$ACTUAL_USER"
echo

# --- [11] SLEEP HARDENING ---
echo_blue "--- [11] SLEEP HARDENING ---"
echo_info "Disables automatic sleep, so this Mac stays reachable over the network instead of"
echo_info "going to sleep and dropping off until someone wakes it locally."
echo_warn "On a laptop, this means it'll also stay awake (and warm, and draining battery) on"
echo_warn "battery power unless you scope it to AC only - this script scopes it to AC power"
echo_warn "only for that reason. On a desktop (no battery) this distinction doesn't matter."
read -rp "Disable sleep while on AC power (keep this Mac always reachable)? [y/N]: " I_SLEEP
if [[ "$I_SLEEP" =~ ^[Yy]$ ]]; then
    sudo pmset -c sleep 0 disksleep 0 displaysleep 0
    echo_green "✓ Sleep disabled while on AC power. (Battery-power sleep settings untouched.)"
fi
echo

# --- [12] OTHER GUI REMOTE-ACCESS OPTIONS ---
echo_blue "--- [12] OTHER GUI REMOTE-ACCESS OPTIONS (informational only - not installed here) ---"
echo_info "These are full GUI apps best installed directly from their own site/App Store rather"
echo_info "than piped through a shell script, but worth knowing the landscape:"
echo
echo_info "${C_BLUE}Cross-platform commercial tools (all have a free personal-use tier):${C_NC}"
echo_info "  TeamViewer      - very widely used, relay-based so no port-forwarding needed;"
echo_info "                    some users report its free tier flagging 'commercial use'"
echo_info "                    even for personal sessions if used heavily"
echo_info "  AnyDesk         - similar to TeamViewer, generally lighter-weight"
echo_info "  Chrome Remote Desktop - genuinely free, Google-account based, browser + small"
echo_info "                    host app, no port-forwarding, good low-friction cross-platform pick"
echo_info "  RealVNC         - free tier for a handful of personal devices, VNC-based with"
echo_info "                    their own relay option so it also avoids port-forwarding"
echo
echo_info "${C_BLUE}Jump Desktop (Mac-focused, unusual pricing split):${C_NC}"
echo_info "  Free, unlimited Mac connections FROM non-Mac clients (Windows, Android, iOS,"
echo_info "  Chromebook, web) via the free 'Jump Desktop Connect' host app on the Mac being"
echo_info "  controlled. Connecting FROM a Mac to another Mac needs the paid Jump Desktop"
echo_info "  app (Mac App Store). Worth knowing if most of your remote sessions originate"
echo_info "  from a non-Mac device."
echo
echo_info "${C_BLUE}Free, built-in, same-LAN only:${C_NC}"
echo_info "  If both Macs are signed into the SAME Apple ID and on the same LAN, Finder's"
echo_info "  sidebar 'Shared' section lists your other Macs with a one-click 'Share Screen' -"
echo_info "  free, but LAN-only, not a remote/internet option."
echo

# --- SUMMARY ---
echo "======================================================"
echo_green "              SETUP COMPLETE!"
echo "======================================================"
echo "  [ SHELL ]       ssh $ACTUAL_USER@${IP_ADDR:-<this-machine>}"
echo "  [ FILE-APP ]    http://${IP_ADDR:-<this-machine>}:9091 (FileBrowser, if configured)"
echo "  [ SFTP-GO ]     http://${IP_ADDR:-<this-machine>}:9092 (if installed)"
echo "  [ SCREEN SHARE ] vnc://${IP_ADDR:-<this-machine>} (if enabled)"
echo "  [ SMB SHARE ]   smb://${IP_ADDR:-<this-machine>}/${ACTUAL_USER}-home (if configured)"
echo "------------------------------------------------------"
echo_yellow "Anything above reachable from outside your LAN is safer reached only over Tailscale"
echo_yellow "than opened directly to the internet via router port-forwarding - these toggles only"
echo_yellow "enable the service on this machine, they don't by themselves expose it beyond your"
echo_yellow "router/NAT."
echo "======================================================"
