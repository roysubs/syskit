#!/bin/bash

# --- CONFIGURATION ---
VNC_PASS="YourSecurePassword" # CHANGE THIS
VNC_RES="1920x1080"
ZONE_LIST=("public" "home")

# --- HELPER FUNCTIONS ---
run_cmd() {
    echo ">> Running: $1"
    eval "$1"
}

# --- START ---
if [ "$EUID" -ne 0 ]; then echo "Please run as root"; exit; fi

echo "======================================================"
echo "  openSUSE GUARANTEED REMOTE ACCESS (V5 - AUTO-COOKIE)"
echo "======================================================"

# 1. FORCE X11
mkdir -p /etc/sddm.conf.d
echo -e "[General]\nDisplayServer=x11" > /etc/sddm.conf.d/force-x11.conf

# 2. INSTALL TOOLS
zypper install -y openssh x11vnc ethtool net-tools-deprecated xauth xhost xf86-video-dummy

# 3. FIREWALL
systemctl enable --now sshd
for zone in "${ZONE_LIST[@]}"; do
    firewall-cmd --permanent --zone=$zone --add-service=ssh >/dev/null 2>&1
    firewall-cmd --permanent --zone=$zone --add-port=5900/tcp >/dev/null 2>&1
done
firewall-cmd --reload

# 4. VNC PASSWORD
x11vnc -storepasswd "$VNC_PASS" /etc/x11vnc.pass

# 5. THE AUTO-LOOKUP SERVICE
# We use a subshell in ExecStart to find the cookie dynamically at runtime.
cat <<EOF > /etc/systemd/system/x11vnc.service
[Unit]
Description=Dynamic x11vnc Service
After=display-manager.service

[Service]
Type=simple
ExecStartPre=/bin/sh -c 'sleep 10'
ExecStart=/bin/sh -c 'XAUTHLOC=\$(find /run/sddm -type f -name "xauth*" | head -n 1); /usr/bin/x11vnc -auth \$XAUTHLOC -forever -loop -noxdamage -repeat -rfbauth /etc/x11vnc.pass -display :0 -shared'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

run_cmd "systemctl daemon-reload"
run_cmd "systemctl enable --now x11vnc"
run_cmd "systemctl restart x11vnc"

# 6. NO SLEEP HARDENING
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

echo -e "\n======================================================"
echo "SUCCESS: The VNC service is now self-healing."
echo "It will dynamically find the SDDM cookie on every boot."
echo "Connect to 192.168.68.61:5900"
echo "======================================================"
