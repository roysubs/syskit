#!/bin/bash
# Author: Roy Wiseman 2025-05

# Script to install Bastillion on Debian

# --- Configuration ---
INSTALL_DIR="/opt/bastillion"
BASTILLION_USER="bastillion" # Optional: run Bastillion under a dedicated user
DOWNLOAD_DIR="/tmp/bastillion_download"

# --- Helper Functions ---
echoinfo() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

echowarn() {
    echo -e "\033[1;33m[WARN]\033[0m $1"
}

echoerror() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

check_command_success() {
    if [ $? -ne 0 ]; then
        echoerror "$1 failed. Exiting."
        exit 1
    fi
}

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
  echoerror "This script must be run as root or with sudo privileges."
  exit 1
fi

# --- Start Installation ---
echoinfo "Starting Bastillion installation process..."

# 1. Update system and install dependencies
echoinfo "Updating package lists and upgrading existing packages..."
sudo apt update -y && sudo apt upgrade -y
check_command_success "System update/upgrade"

echoinfo "Installing prerequisites: default-jdk, wget, tar, curl, jq..."
sudo apt install -y default-jdk wget tar curl jq
check_command_success "Prerequisite installation"

# Verify Java installation
echoinfo "Verifying Java installation..."
if ! command -v java &> /dev/null; then
    echoerror "Java could not be installed or found. Please install Java manually and try again."
    exit 1
fi
java -version
JAVA_HOME_PATH=$(dirname $(dirname $(readlink -f $(which java))))
echoinfo "Detected JAVA_HOME should be around: $JAVA_HOME_PATH"
echoinfo "You will need to set the JAVA_HOME environment variable."

# 2. Create Bastillion User (Optional, but recommended for security)
if id "$BASTILLION_USER" &>/dev/null; then
    echoinfo "User '$BASTILLION_USER' already exists."
else
    echoinfo "Creating user '$BASTILLION_USER' to run Bastillion..."
    sudo useradd -r -m -d "$INSTALL_DIR" -s /bin/bash "$BASTILLION_USER"
    check_command_success "Bastillion user creation"
    echoinfo "Bastillion will be installed in $INSTALL_DIR, owned by $BASTILLION_USER."
fi

# 3. Download Bastillion
echoinfo "Fetching the latest Bastillion release information from GitHub..."
LATEST_RELEASE_INFO_URL="https://api.github.com/repos/bastillion-io/Bastillion/releases/latest"
LATEST_TAG=$(curl -s $LATEST_RELEASE_INFO_URL | jq -r '.tag_name')

if [ -z "$LATEST_TAG" ] || [ "$LATEST_TAG" == "null" ]; then
    echoerror "Could not automatically fetch the latest Bastillion release tag."
    echoerror "Please visit https://github.com/bastillion-io/Bastillion/releases manually to find the latest version."
    read -p "Enter the latest version tag (e.g., v3.15.00): " LATEST_TAG
    if [ -z "$LATEST_TAG" ]; then
        echoerror "No version tag provided. Exiting."
        exit 1
    fi
fi
# Remove 'v' prefix if present for constructing the filename
VERSION_NUMBER=${LATEST_TAG#v}

BASTILLION_TARBALL="bastillion-jetty-$VERSION_NUMBER.tar.gz"
BASTILLION_DOWNLOAD_URL="https://github.com/bastillion-io/Bastillion/releases/download/$LATEST_TAG/$BASTILLION_TARBALL"

echoinfo "Latest Bastillion version identified: $LATEST_TAG"
echoinfo "Downloading $BASTILLION_TARBALL from $BASTILLION_DOWNLOAD_URL..."

mkdir -p "$DOWNLOAD_DIR"
check_command_success "Creating download directory $DOWNLOAD_DIR"
wget -O "$DOWNLOAD_DIR/$BASTILLION_TARBALL" "$BASTILLION_DOWNLOAD_URL"
check_command_success "Bastillion download"

# 4. Extract Bastillion
echoinfo "Extracting Bastillion to $INSTALL_DIR..."
sudo mkdir -p "$INSTALL_DIR"
check_command_success "Creating installation directory $INSTALL_DIR"
sudo tar -xzf "$DOWNLOAD_DIR/$BASTILLION_TARBALL" -C "$INSTALL_DIR" --strip-components=1
check_command_success "Bastillion extraction"

# 5. Set Permissions
echoinfo "Setting permissions for $INSTALL_DIR..."
# If you created a dedicated user:
sudo chown -R "$BASTILLION_USER":"$BASTILLION_USER" "$INSTALL_DIR"
check_command_success "Setting ownership for $INSTALL_DIR"
sudo chmod +x "$INSTALL_DIR/startBastillion.sh"
sudo chmod +x "$INSTALL_DIR/stopBastillion.sh"
check_command_success "Setting execute permissions on scripts"


# 6. Cleanup
echoinfo "Cleaning up downloaded files..."
rm -rf "$DOWNLOAD_DIR"
check_command_success "Cleanup"

# --- Post-Installation Instructions ---
echoinfo "Bastillion installation complete!"
echowarn "---------------------------------------------------------------------"
echowarn "IMPORTANT NEXT STEPS:"
echowarn "---------------------------------------------------------------------"
echo ""
echoinfo "1. Set JAVA_HOME environment variable:"
echo "   For the current session (replace path if different):"
echo "     export JAVA_HOME=$JAVA_HOME_PATH"
echo "     export PATH=\$JAVA_HOME/bin:\$PATH"
echo "   To set it permanently, add the lines above to your shell profile"
echo "   (e.g., ~/.bashrc for the current user, or /etc/profile for system-wide)."
echo "   Then source the file (e.g., source ~/.bashrc)."
echo ""
echoinfo "2. Start Bastillion:"
echo "   Navigate to the installation directory: cd $INSTALL_DIR"
echo "   If you created the '$BASTILLION_USER', switch to that user first (recommended for running):"
echo "     sudo -u $BASTILLION_USER -H bash"
echo "     cd $INSTALL_DIR"
echo "     export JAVA_HOME=$JAVA_HOME_PATH # Make sure JAVA_HOME is set in this user's session too"
echo "     export PATH=\$JAVA_HOME/bin:\$PATH"
echo "     ./startBastillion.sh"
echo ""
echo "   If running as root (not recommended for long-term use):"
echo "     cd $INSTALL_DIR"
echo "     export JAVA_HOME=$JAVA_HOME_PATH"
echo "     export PATH=\$JAVA_HOME/bin:\$PATH"
echo "     ./startBastillion.sh"
echo ""
echoinfo "3. Access Bastillion:"
echo "   Open your web browser and go to: https://YOUR_SERVER_IP:8443"
echo "   The default login credentials are usually admin / changeme (Change this immediately!)"
echo ""
echoinfo "4. Firewall:"
echo "   If you have a firewall (like ufw), allow port 8443:"
echo "     sudo ufw allow 8443/tcp"
echo ""
echoinfo "5. Review Configuration:"
echo "   Bastillion's configuration can be found in:"
echo "   $INSTALL_DIR/jetty/bastillion/WEB-INF/classes/BastillionConfig.properties"
echo "   You might want to review and customize settings, especially for production."
echo ""
echoinfo "6. For production, consider running Bastillion as a systemd service."
echowarn "---------------------------------------------------------------------"

exit 0
