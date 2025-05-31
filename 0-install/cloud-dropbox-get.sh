#!/bin/bash
# Author: Roy Wiseman 2025-04

# Install dependencies
echo "Installing Dropbox dependencies..."
sudo apt update
sudo apt install -y python3-gpg

# Download and install Dropbox
echo "Downloading Dropbox..."
cd ~ && wget -O dropbox.tar.gz "https://www.dropbox.com/download?plat=lnx.x86_64"
tar -xzf dropbox.tar.gz
rm dropbox.tar.gz

# Start Dropbox daemon
echo "Starting Dropbox..."
~/.dropbox-dist/dropboxd &

# Wait for user authentication
echo "Please follow the authentication process in your browser."
read -p "Press Enter once authentication is complete."

# Install Dropbox CLI for additional management
echo "Installing Dropbox CLI..."
wget -O ~/.dropbox-cli.py "https://www.dropbox.com/download?dl=packages/dropbox.py"
chmod +x ~/.dropbox-cli.py
ln -s ~/.dropbox-cli.py ~/bin/dropbox

# Enable Dropbox autostart
echo "Enabling Dropbox autostart..."
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/dropbox.desktop <<EOF
[Desktop Entry]
Name=Dropbox
Exec=$HOME/.dropbox-dist/dropboxd
Type=Application
StartupNotify=false
X-GNOME-Autostart-enabled=true
EOF

echo "Dropbox installation complete. It will start automatically on login."
echo "Your Dropbox folder is located in ~/Dropbox."

