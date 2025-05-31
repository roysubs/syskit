#!/bin/bash
# Author: Roy Wiseman 2025-04

# Variables
PORT=61208      # You can change this port number as needed
# USER=glances  # User for running Glances service
# GROUP=glances # Group for running Glances service
# USER=boss     # No need to set this, use current user to run the service
GROUP=users     # Group for running Glances service, use basic 'users'

# Install pipx if it's not already installed
if ! command -v pipx &> /dev/null; then
    echo "Installing pipx..."
    sudo apt update
    sudo apt install -y pipx
    python3 -m pip install --user pipx
    sudo ln -s ~/.local/bin/pipx /usr/local/bin/pipx  # Ensure pipx is available globally
fi

# Install Glances using pipx
echo "Installing Glances using pipx..."
pipx install --force "glances[web]"   # Use glances[web] instead of:   pipx install glances
pipx inject glances "glances[web]"
# pipx runpip glances list | grep fastapi   # Check fastapi is available
# This ensures fastapi and other web-related dependencies are installed inside the pipx environment.
# Without this, it will not be possible to connect to the service remotely.

# Create a user for Glances if it doesn't exist
if ! id -u "$USER" > /dev/null 2>&1; then
    echo "Creating user $USER..."
    sudo useradd -r -m -s /bin/bash "$USER"
fi

# Create a systemd service file for Glances
echo "Creating systemd service file..."
sudo tee /etc/systemd/system/glances.service > /dev/null <<EOF
[Unit]
Description=Glances system monitoring tool
After=network.target

[Service]
User=$USER
Group=$GROUP
ExecStart=/home/$USER/.local/bin/glances -w -B 0.0.0.0 -p $PORT
Restart=always
Environment="PATH=/home/$USER/.local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd, enable and start the service
echo "Reloading systemd and starting Glances service..."
sudo systemctl daemon-reload
sudo systemctl enable glances
sudo systemctl start glances

# Check if the service is running
echo "Checking if Glances is running..."
sudo systemctl status glances

echo "Glances is set up and accessible on port $PORT."
echo "You can access the web interface remotely at: http://<your-server-ip>:$PORT"

