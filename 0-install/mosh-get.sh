#!/bin/bash
# Author: Roy Wiseman 2025-01

# Use MOSH as an alternative to SSH access as backup in case SSH service crashes.

# First line checks running as root or with sudo (exit 1 if not). Second line auto-elevates the script as sudo.
# if [ "$(id -u)" -ne 0 ]; then echo "This script must be run as root or with sudo" 1>&2; exit 1; fi
if [ "$(id -u)" -ne 0 ]; then echo "Elevation required; rerunning as sudo..."; sudo "$0" "$@"; exit 0; fi

# Only update if it has been more than 2 days since the last update (to avoid constant updates)
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update && sudo apt upgrade; fi

# Install tools if not already installed
PACKAGES=("mosh")
install-if-missing() { if ! dpkg-query -W "$1" > /dev/null 2>&1; then sudo apt install -y $1; fi; }
for package in "${PACKAGES[@]}"; do install-if-missing $package; done

echo "
Mosh (Mobile Shell) Operation
==========
https://ideawrights.com/mosh-windows-wsl/
Mosh (mobile shell) is a shell client optimized for poor or intermittent internet
connections, so is useful when working on a poor mobile connection or a high-latency
satellite connections.

Mosh uses SSH only for the initial setup—to authenticate and start a
process on the remote host. Once that's done, Mosh switches to its own
protocol, which runs over UDP. After the switch:
- Mosh no longer relies on the SSH connection.
- The ongoing communication between the client and the remote host happens
  via Mosh's custom UDP-based protocol, completely independent of SSH.
- This design makes Mosh much more resilient than SSH to network disruptions,
  changes in IP addresses, or server-side SSH issues after the initial connection.

Connect to Mosh from Windows
==========
Install Windows Subsystem for Linux (WSL) if you don't already have it.
Mosh requires a Unix-like environment.
Install a Linux distribution via the Microsoft Store (e.g., Ubuntu or Debian)
Open your WSL terminal and install Mosh
   sudo apt update && sudo apt install mosh
Install Mosh Server on the Remote Host
Ensure the remote host has the Mosh server installed. Run the following on the
remote host:
   sudo apt update && sudo apt install mosh
Use Mosh via WSL
After setup, connect to the remote host using the Mosh client in your WSL
terminal. For example:
   mosh username@remote-host
Optional: Integrate Mosh with PowerShell
To use Mosh more seamlessly from PowerShell:
Install a terminal like Windows Terminal that integrates both PowerShell
and WSL. Add WSL to your terminal profile for easy access.
Alternative via Native Windows. If you prefer to avoid WSL, you can use
mosh-client-win, a native Windows port of Mosh. However, its functionality
and reliability may vary.

Check if the port is open on the server with netstat or ss:
sudo netstat -uln | grep 60001   # Check if mosh is listening
sudo ss -uln | grep 60001        # Using ss
A result like 0.0.0.0:60001 or *:60001 means that the server is listening on the port.
If there's no output, mosh might not be running properly; make sure a mosh-server session is started.

Test connectivity to the UDP port:
echo "test" | nc -u <server_ip> 60001  # Test from a remote machine if a server has port 60001 open
If the server responds, the port is accessible, otherwise it might be blocked by a firewall.

UFW:
sudo ufw status verbose   # Check for a rule allowing UDP traffic on port 60001
sudo ufw allow 60001/udp  # Add a rule for mosh
sudo ufw reload           # Reload ufw to apply changes

"

