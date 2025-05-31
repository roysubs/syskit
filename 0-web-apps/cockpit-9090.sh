#!/bin/bash
# Author: Roy Wiseman 2025-04
sudo apt install cockpit
echo "
sudo systemctl start cockpit
sudo systemctl status cockpit
sudo systemctl enable cockpit   # Start at every reboot

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
