#!/usr/bin/env bash
if ((BASH_VERSINFO[0] < 4)); then echo "This script needs bash 4+. On macOS: brew install bash" >&2; return 1 2>/dev/null || exit 1; fi
# Author: Roy Wiseman 2025-04
pkg_install() {
    if command -v apt &>/dev/null; then sudo apt install "$@"
    elif command -v zypper &>/dev/null; then sudo zypper --non-interactive refresh && sudo zypper --non-interactive install -y "$@"
    else echo "No supported package manager found (need apt/zypper)." >&2; exit 1
    fi
}
pkg_install cockpit
echo "
sudo systemctl start cockpit.socket
sudo systemctl status cockpit.socket
sudo systemctl enable cockpit.socket   # Start at every reboot

Access cockpit at <serverip>:9090

For ufw:
sudo ufw allow 9090

For iptables:
sudo iptables -A INPUT -p tcp --dport 9090 -j ACCEPT

To install additional official and third-party modules:
https://cockpit-project.org/

e.g.
https://github.com/spotsnel/cockpit-tailscale  # Manage TailScale
https://github.com/45Drives/cockpit-benchmark  # Cockpit Benchmark
"
