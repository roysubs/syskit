#!/usr/bin/env bash
# Author: Roy Wiseman 2025-04
set -euo pipefail

# === Helper Functions ===
is_wsl() {
    # Check for WSL-specific environment variables or /proc/version signature
    if [[ -n "${WSL_DISTRO_NAME}" || -n "${WSL_INTEROP}" ]] || grep -qiE "(microsoft|wsl)" /proc/version &>/dev/null; then
        return 0 # True, is WSL
    else
        return 1 # False, not WSL
    fi
}

prompt_install_pkg() {
    local pkg_name="$1"
    local install_cmd="$2"
    if ! command -v "$pkg_name" &>/dev/null; then
        read -p "$pkg_name command not found. Install it (y/N)? " -n 1 -r REPLY && echo
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            echo "Installing $pkg_name..."
            eval "$install_cmd" || { echo "Failed to install $pkg_name. Please install it manually and re-run the script."; exit 1; }
        else
            echo "$pkg_name not installed. It is required to proceed. Exiting."
            exit 1
        fi
    fi
}

# === Main Logic ===

echo "==> Docker Setup Script Initiated..."

# --- Check 1: Is Docker command already available? ---
if command -v docker &>/dev/null; then
    echo "==> Docker command is already available."
    DOCKER_VERSION_FULL=$(docker --version)
    echo "    $DOCKER_VERSION_FULL"

    if is_wsl; then
        echo "==> Running in WSL. Assuming Docker is provided by Docker Desktop on Windows."
        echo "    No installation or configuration needed from this script."
        
        # Optional: Check if user is in docker group (Docker Desktop might handle this, but good check)
        if ! groups "$USER" | grep -qw docker; then
            echo "==> Warning: User '$USER' is not in the 'docker' group in WSL."
            echo "    Docker Desktop typically manages Docker access."
            echo "    If you encounter permission issues with the Docker socket directly within WSL (less common),"
            echo "    you might need to be added. However, usually Docker Desktop handles CLI access."
            echo "    To add: sudo usermod -aG docker \"$USER\" (then newgrp docker or relogin)"
        else
            echo "==> User '$USER' is already in the 'docker' group in WSL."
        fi

        echo "==> Script finished. Docker Desktop is expected to manage Docker."
        exit 0
    else # Native Linux, Docker command found
        echo "==> Running on native Linux and Docker command is present."
        echo "    Assuming Docker is already installed and configured."
        # You could add user-to-group management here if desired for existing native installs
        if ! groups "$USER" | grep -qw docker; then
            echo "==> User '$USER' is NOT in the docker group. Adding now..."
            sudo usermod -aG docker "$USER"
            echo "==> User '$USER' has been added to the docker group."
            echo "    Please log out and log back in, or run 'newgrp docker', or reboot your system, to apply this change."
        else
            echo "==> User '$USER' is already in the docker group."
        fi
        echo "==> Script finished. Existing Docker installation detected."
        exit 0
    fi
fi

# --- Check 2: Docker command not found, proceed with installation logic ---
echo "==> Docker command not found. Attempting to determine installation strategy..."

if is_wsl; then
    echo "==> Running in WSL, but Docker command is not available."
    echo "==> The recommended way to use Docker in WSL2 is to:"
    echo "    1. Install Docker Desktop on your Windows host."
    echo "    2. Enable WSL2 integration in Docker Desktop settings for your distribution."
    echo "    This will make the 'docker' command available within your WSL2 environment automatically."
    echo "    Please visit: https://docs.docker.com/desktop/wsl/"
    echo "==> Script will not attempt to install Docker Engine directly into WSL when Docker Desktop is the preferred method."
    exit 1 # Exit with error as user expectation might be an install
fi

# --- Native Linux Installation (Docker command not found, not in WSL) ---
echo "==> Running on native Linux. Docker is not installed. Proceeding with installation..."

# Check for curl, which is needed for get.docker.com
# Try to detect package manager for installing curl
INSTALL_CURL_CMD=""
if command -v apt-get &>/dev/null; then
    INSTALL_CURL_CMD="sudo apt-get update && sudo apt-get install -y curl"
elif command -v dnf &>/dev/null; then
    INSTALL_CURL_CMD="sudo dnf install -y curl"
elif command -v yum &>/dev/null; then
    INSTALL_CURL_CMD="sudo yum install -y curl"
elif command -v zypper &>/dev/null; then
    INSTALL_CURL_CMD="sudo zypper install -y curl"
elif command -v pacman &>/dev/null; then
    INSTALL_CURL_CMD="sudo pacman -Syu --noconfirm curl"
else
    echo "Warning: Could not detect common package manager (apt, dnf, yum, zypper, pacman)."
    echo "Please ensure 'curl' is installed to download the Docker installation script."
fi

if [[ -n "$INSTALL_CURL_CMD" ]]; then
    prompt_install_pkg "curl" "$INSTALL_CURL_CMD"
else
    if ! command -v curl &>/dev/null; then
         echo "Error: 'curl' command not found and package manager unknown. Please install 'curl' manually and re-run."
         exit 1
    fi
fi


echo "==> Downloading and running Docker's official installation script (get.docker.com)..."
# Download the script
curl -fsSL https://get.docker.com -o get-docker.sh

# Run the script
# Note: The get.docker.com script typically handles adding the repo, GPG key, and installing packages.
sudo sh get-docker.sh

# Clean up the script
rm get-docker.sh

echo "==> Docker Engine installation attempted."

# --- Post-installation steps for native Linux ---
echo "==> Performing post-installation steps..."

# Add current user to the docker group
# The get.docker.com script usually does this, but it's good to ensure.
if ! groups "$USER" | grep -qw docker; then
    echo "==> Adding user '$USER' to the docker group..."
    sudo usermod -aG docker "$USER"
    echo "==> User '$USER' has been added to the docker group."
    echo "IMPORTANT: You need to log out and log back in, or run 'newgrp docker',"
    echo "           or reboot your system for the group changes to take full effect."
else
    echo "==> User '$USER' is already in the docker group."
fi

# Remind user to start/enable Docker service if systemd is present
if command -v systemctl &>/dev/null; then
    echo "==> You may need to start and enable the Docker service:"
    echo "    sudo systemctl start docker"
    echo "    sudo systemctl enable docker"
    # Optionally, try to start it if not running
    if ! sudo systemctl is-active --quiet docker; then
        echo "Attempting to start Docker service..."
        sudo systemctl start docker
        if sudo systemctl is-active --quiet docker; then
            echo "Docker service started."
        else
            echo "Failed to start Docker service. Please check 'sudo systemctl status docker' or 'journalctl -u docker'."
        fi
    fi
    if ! sudo systemctl is-enabled --quiet docker; then
         echo "Attempting to enable Docker service to start on boot..."
         sudo systemctl enable docker
         if sudo systemctl is-enabled --quiet docker; then
            echo "Docker service enabled."
        else
            echo "Failed to enable Docker service."
        fi
    fi
else
    echo "==> Could not detect systemctl. If Docker service is not running,"
    echo "    please consult your distribution's documentation on how to start services."
fi

echo "==> Docker setup script finished."
echo "Please verify your installation:"
echo "  1. (If group was added) Log out and log back in, or run 'newgrp docker', or reboot."
echo "  2. Check Docker version: docker --version"
echo "  3. Run test container: docker run hello-world"
