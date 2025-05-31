#!/bin/bash
# Author: Roy Wiseman 2025-05

# This script installs AnyDesk on Debian-based systems (e.g., Debian, Ubuntu, Mint).
# It automatically downloads the latest GPG key and sets up the AnyDesk repository.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
ANYDESK_GPG_KEY_URL="https://keys.anydesk.com/repos/DEB-GPG-KEY"
ANYDESK_GPG_KEY_PATH="/etc/apt/keyrings/anydesk-stable-keyring.gpg"
ANYDESK_REPO_FILE="/etc/apt/sources.list.d/anydesk-stable.list"

# --- Helper Functions ---
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
    exit 1
}

# --- Pre-flight Checks ---
if [ "$(id -u)" -ne 0 ]; then
  log_error "This script must be run as root or with sudo."
fi

# Check for necessary tools
for cmd in wget gpg dpkg apt; do
  if ! command -v "$cmd" &> /dev/null; then
    log_error "$cmd is not installed. Please install it first."
  fi
done

# --- Main Installation Logic ---

# Step 1: Update package lists
log_info "Updating package lists..."
sudo apt update

# Step 2: Install dependencies (if any are strictly needed beyond what's usually present)
# For this script, wget and gpg are checked above.
# ca-certificates should generally be present.
# sudo apt install -y ca-certificates # Uncomment if issues with HTTPS downloads

# Step 3: Add AnyDesk GPG Key
log_info "Adding AnyDesk GPG key..."
# Download the GPG key and dearmor it directly to the keyrings directory
if wget -qO- "$ANYDESK_GPG_KEY_URL" | sudo gpg --dearmor -o "$ANYDESK_GPG_KEY_PATH"; then
    log_info "AnyDesk GPG key added successfully to $ANYDESK_GPG_KEY_PATH."
else
    log_error "Failed to download or import AnyDesk GPG key."
fi

# Step 4: Add AnyDesk Repository
log_info "Adding AnyDesk repository..."
# Determine system architecture
ARCH=$(dpkg --print-architecture)
if [ -z "$ARCH" ]; then
    log_error "Could not determine system architecture."
fi
log_info "System architecture detected: $ARCH"

# Create the repository file
echo "deb [arch=$ARCH signed-by=$ANYDESK_GPG_KEY_PATH] http://deb.anydesk.com/ all main" | sudo tee "$ANYDESK_REPO_FILE" > /dev/null
log_info "AnyDesk repository added to $ANYDESK_REPO_FILE."

# Step 5: Update Apt Repository Cache (after adding new repo)
log_info "Updating apt repository cache with new AnyDesk repository..."
sudo apt update

# Step 6: Install AnyDesk
log_info "Installing AnyDesk..."
# The "-y" flag automatically confirms the installation.
if sudo apt install -y anydesk; then
    log_info "AnyDesk installed successfully."
else
    # Attempt to fix broken installs, which can sometimes happen
    log_warn "Initial AnyDesk installation failed. Attempting to fix broken dependencies..."
    if sudo apt --fix-broken install -y && sudo apt install -y anydesk; then
        log_info "AnyDesk installed successfully after fixing dependencies."
    else
        log_error "Failed to install AnyDesk. Please check the output above for errors."
    fi
fi

# Step 7: Ensure AnyDesk service is enabled and started
log_info "Ensuring AnyDesk service is enabled and started..."
# Use systemctl to enable (start on boot) and start the service now
# The '|| true' prevents the script from exiting if the service is already running or masked (less likely for a new install)
sudo systemctl enable anydesk.service || true
sudo systemctl start anydesk.service || true
sudo systemctl daemon-reload # Ensure systemd recognizes the new service state

# Check service status
if systemctl is-active --quiet anydesk.service; then
    log_info "AnyDesk service is active and running."
else
    log_warn "AnyDesk service may not be running. Check status with: sudo systemctl status anydesk.service"
fi

log_info "AnyDesk installation and setup complete!"
log_info "You can typically find AnyDesk in your applications menu or run 'anydesk' from the terminal."

# --- Optional Uninstall Instructions ---
# To uninstall AnyDesk and remove its repository:
#
# log_info "To uninstall AnyDesk, you can run the following commands:"
# echo "sudo apt remove --purge -y anydesk"
# echo "sudo rm -f $ANYDESK_REPO_FILE"
# echo "sudo rm -f $ANYDESK_GPG_KEY_PATH"
# echo "sudo apt update"
# echo "sudo systemctl disable anydesk.service || true" # To prevent errors if already removed
# echo "sudo systemctl stop anydesk.service || true"
# echo "sudo systemctl daemon-reload"

exit 0
