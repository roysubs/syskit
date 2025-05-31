#!/bin/bash
# Author: Roy Wiseman 2025-04

# Serve a web page that displays various basic information
# If 8081 is in use, 'sudo lsof -i :8081' and kill that process then rerun this
# To make it run independently and in the background:
# nohup ./web-system-info-8081.sh > output.log 2>&1 &
#    nohup "no hang up" ensures the script keeps running after the terminal session is closed.
#    > output.log redirects standard output to a log file (output.log).
#    2>&1 ensures that both stdout and stderr are directed to the same log file.
#    & puts the script in the background.
# Process will then run independently of the currently open terminal session.

# To start on every reboot, edit the users crontab
#    crontab -e
# Add this line:
#    @reboot /path/to/your/web-page.sh &
# Note that this is user level crontab, so will not start until the user has logged on.
# Other methods:
# - systemd Service (for system reboot)
#   The service will run the script as soon as the system has finished booting and the network is available.
#   This is ideal if you need the script to run independently of any user logging in.
# - Cron @reboot (for system reboot)
#   Use this if you don't want to create a full systemd service but want the script to run easily.
# - rc.local (for system reboot)
#   Like systemd, it does not depend on user login. Legacy method.
# - init.d (for system reboot)
#   Also a legacy method, effective for older Linux systems or distributions that still use the init system.
# - For user logon (session start), you can use ~/.bashrc (console logins) or ~/.profile (for graphical logins).

# Set to dynamically refresh every 30 seconds, but only when a user is on the page:
# while true; do
#     echo -e "HTTP/1.1 200 OK\nContent-Type: text/html\n\n$(get_system_info)" | nc -l -p "$PORT" -q 1
# done
# nc -l -p "$PORT":   nc (Netcat) listens on the specified port ($PORT), waiting for a connection from a client (such as a browser).
# This only triggers when a user opens the page or refreshes it.
# $(get_system_info):   When a request comes in, the script calls get_system_info to dynamically generate the HTML content.
# Wait for Next Request:   The -q 1 option ensures nc closes the connection after sending the response, so it can immediately wait for the next incoming request.

# Old jq duf output, not good:  <pre>$(duf --json | jq '.[] | {device: .device, mount_point: .mount_point}')</pre>


# Only update if at least 2 days have passed since the last update
if [ $(find /var/cache/apt/pkgcache.bin -mtime +2 -print) ]; then sudo apt update; fi
# Install tools if not already installed
install-if-missing() { if ! dpkg-query -l "$1" >/dev/null; then sudo apt install -y $1; fi; }
install-if-missing python3
install-if-missing curl
install-if-missing neofetch
install-if-missing inxi
install-if-missing duf
install-if-missing jq

# Define the port and address
PORT=8081
ADDRESS=0.0.0.0

# Function to get the system stats
get_system_info() {
    cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="refresh" content="30"> <!-- Refresh every 30 seconds -->
    <title>System Information</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; line-height: 1.6; }
        h1, h2 { color: #2E86C1; }
        pre { background-color: #f4f4f4; padding: 10px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>System Information</h1>

    <h2>System Info (neofetch --stdout)</h2>
    <pre>$(neofetch --stdout)</pre>
    
    <h2>System Info (inxi)</h2>
    <pre>$(inxi)</pre>
    
    <h2>Sensors</h2>
    <pre>$(sensors)</pre>
    
    <h2>Disk Usage (duf)</h2>
    <pre>$(duf)</pre>
    
    <h2>Disk Info (lsblk)</h2>
    <pre>$(lsblk)</pre>

    <h2>Logged-in Users</h2>
    <pre>$(who)</pre>
    
    <h2>Memory Info (free -h)</h2>
    <pre>$(free -h)</pre>

    <h2>CPU Info</h2>
    <pre>$(lscpu | grep -v "Not affected")</pre>

</body>
</html>
EOF
}

# Serve dynamic content directly
serve() {
    echo "Server running at http://$ADDRESS:$PORT. Press Ctrl+C to stop."
    trap "exit" INT TERM
    while true; do
        echo -e "HTTP/1.1 200 OK\nContent-Type: text/html\n\n$(get_system_info)" | nc -l -p "$PORT" -q 1
    done
}

# Run the server
serve

